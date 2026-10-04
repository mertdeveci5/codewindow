import Darwin
import Foundation

/// A registration for one running app instance, scoped to its state directory. A file alone
/// never means "running": readers verify the PID and its start time with the kernel. A crash
/// can leave a file, but cannot keep hooks active or make a reused PID look like CodeWindow.
public final class AppPresence {
    private let file: URL

    public init(in directory: URL) throws {
        guard let process = ProcessInspector.stamp(pid: getpid()) else {
            throw CocoaError(.fileReadUnknown)
        }
        let root = Self.root(in: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        for candidate in Self.files(in: directory) {
            if !Self.isLive(candidate) { try? FileManager.default.removeItem(at: candidate) }
        }
        file = root.appendingPathComponent("\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(process).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: file)
    }

    /// Read-only and fail-open for the agent: no app, unreadable state, or stale registrations
    /// make reporting a no-op. Separate registrations support installed and development apps
    /// running together; quitting one does not disable the other.
    public static func isRunning(in directory: URL) -> Bool {
        files(in: directory).contains(where: isLive)
    }

    static func root(in directory: URL) -> URL {
        directory.appendingPathComponent(".apps", isDirectory: true)
    }

    private static func files(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root(in: directory), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.pathExtension == "json" }
    }

    private static func isLive(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1_025), data.count <= 1_024,
              let process = try? JSONDecoder().decode(ProcessStamp.self, from: data)
        else { return false }
        return ProcessInspector.isCurrent(process)
    }
}
