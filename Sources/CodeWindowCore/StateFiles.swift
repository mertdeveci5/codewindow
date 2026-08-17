import Darwin
import Foundation

public enum StateFiles {
    /// Room for a short run of sanitized events. Every field that reaches this file is length
    /// bounded before it is written, so this stays a backstop rather than a working limit.
    public static let maximumStateBytes = 4_096

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

    public static func all(in directory: URL) -> [(url: URL, state: SessionState)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", let state = read(from: file) else { return nil }
            return (file, state)
        }
    }
}

public enum StateFileError: Error {
    case tooLarge
    case renameFailed(Int32)
}
