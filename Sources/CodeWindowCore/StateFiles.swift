import Darwin
import Foundation

public enum StateFiles {
    /// Room for a short run of sanitized events. Every field that reaches this file is length
    /// bounded before it is written, so this stays a backstop rather than a working limit.
    public static let maximumStateBytes = 8_192

    private static let reportingFailureFileName = ".reporting-failure"

    public static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let url: URL
        if let override = environment["CODEWINDOW_STATE_DIR"], !override.isEmpty {
            url = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            url = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("CodeWindow", isDirectory: true)
            .appendingPathComponent("State", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// A parallel tool turn starts several hook processes for one session at the same moment,
    /// and each of them reads the session file, folds its event in, and writes the whole file
    /// back. Without this they overwrite each other and every event but the last is lost. The
    /// kernel drops the lock when the process exits, so a crashed hook cannot wedge a session.
    public static func withSessionLock<Result>(
        _ sessionKey: String,
        in directory: URL,
        perform body: () throws -> Result
    ) throws -> Result {
        let lock = directory.appendingPathComponent(".\(sessionKey).lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw StateFileError.lockFailed(errno) }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StateFileError.lockFailed(errno) }
        return try body()
    }

    public static func lockFile(for sessionKey: String, in directory: URL) -> URL {
        directory.appendingPathComponent(".\(sessionKey).lock")
    }

    public static func write(_ state: SessionState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= maximumStateBytes else { throw StateFileError.tooLarge }

        let destination = directory.appendingPathComponent("\(state.sessionKey).json")
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        let result = temporary.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw StateFileError.renameFailed(code)
        }
    }

    /// The panel reads this to tell the user that activity stopped being recorded, and clears it
    /// once shown. Best effort by definition: the failure being reported may be the very thing
    /// that stops this write from landing.
    public static func recordReportingFailure(_ reason: String) {
        guard let directory = try? directory() else { return }
        let summary = reason
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .prefix(160)
        try? Data("\(summary ?? "unknown error")\n".utf8).write(
            to: directory.appendingPathComponent(reportingFailureFileName),
            options: .atomic
        )
    }

    public static func reportingFailure(in directory: URL) -> String? {
        let file = directory.appendingPathComponent(reportingFailureFileName)
        guard let data = try? Data(contentsOf: file), data.count <= maximumStateBytes else {
            return nil
        }
        let reason = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }

    public static func clearReportingFailure(in directory: URL) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(reportingFailureFileName)
        )
    }

    public static func read(from file: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              data.count <= maximumStateBytes
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let state = try? decoder.decode(SessionState.self, from: data),
              state.schemaVersion == SessionState.currentSchemaVersion,
              file.deletingPathExtension().lastPathComponent == state.sessionKey
        else { return nil }
        return state
    }

    /// Reports every state file, including the ones that no longer decode, so the app can clear
    /// them out. Skipping them silently leaves litter nothing is able to see, let alone remove.
    public static func all(in directory: URL) -> [(url: URL, state: SessionState?)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json" else { return nil }
            return (file, read(from: file))
        }
    }
}

public enum StateFileError: Error {
    case tooLarge
    case renameFailed(Int32)
    case lockFailed(Int32)
}
