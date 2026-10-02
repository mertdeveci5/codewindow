import Darwin
import Foundation

/// Uses the same hooks/list → config/batchWrite flow as Codex's /hooks UI.
/// Codex owns the hook keys, hashes, and TOML edits; we select only our installed commands.
public struct CodexHookTrust {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public static func discovered(home: URL) -> CodexHookTrust? {
        let environment = ProcessInfo.processInfo.environment
        var candidates = (environment["PATH"] ?? "").split(separator: ":").compactMap { directory -> URL? in
            guard directory.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: String(directory)).appendingPathComponent("codex")
        }
        candidates += [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return CodexHookTrust(executableURL: executable)
        }
        // Finder launches don't inherit an nvm/asdf shell's PATH. A running native
        // Codex process gives us its actual executable without evaluating shell startup files.
        for agent in ProcessInspector.terminalAgentProcesses() where agent.agent == .codex {
            guard ProcessInspector.isCurrent(agent.process) else { continue }
            let path = ProcessInspector.executablePath(pid: agent.process.pid)
            if FileManager.default.isExecutableFile(atPath: path) {
                return CodexHookTrust(executableURL: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    public func trust(at locations: InstallLocations) throws {
        for home in locations.codexHomes {
            let connection = try CodexHookConnection(executable: executableURL, home: home)
            defer { connection.close() }
            let hooks = try installedHooks(connection, home: home, locations: locations)
            var updates: [String: [String: String]] = [:]
            for hook in hooks where hook.trustStatus != "trusted" {
                updates[hook.key] = ["trusted_hash": hook.currentHash]
            }
            if !updates.isEmpty {
                try connection.write(edits: [["keyPath": "hooks.state", "value": updates, "mergeStrategy": "upsert"]])
            }
            guard try installedHooks(connection, home: home, locations: locations).allSatisfy({ $0.trustStatus == "trusted" }) else {
                throw CodexHookTrustError.failed("Codex did not save CodeWindow hook permissions.")
            }
        }
    }

    public func isTrusted(at locations: InstallLocations) throws -> Bool {
        for home in locations.codexHomes {
            let connection = try CodexHookConnection(executable: executableURL, home: home)
            defer { connection.close() }
            if try !installedHooks(connection, home: home, locations: locations).allSatisfy({ $0.trustStatus == "trusted" }) {
                return false
            }
        }
        return true
    }

    /// Remove trust before removing the commands, while Codex can still identify their keys.
    public func remove(at locations: InstallLocations) throws {
        for home in locations.codexHomes where FileManager.default.fileExists(atPath: home.appendingPathComponent("hooks.json").path) {
            let connection = try CodexHookConnection(executable: executableURL, home: home)
            defer { connection.close() }
            let hooks = try connection.hooks()
                .filter { owns($0, home: home, locations: locations) && $0.trustStatus != "untrusted" }
            let edits: [[String: Any]] = try hooks.map { hook in
                // JSON basic-string escaping is also valid for these TOML key segments.
                let key = String(decoding: try JSONEncoder().encode(hook.key), as: UTF8.self)
                return ["keyPath": "hooks.state.\(key)", "value": NSNull(), "mergeStrategy": "replace"]
            }
            if !edits.isEmpty { try connection.write(edits: edits) }
        }
    }

    private func installedHooks(_ connection: CodexHookConnection, home: URL, locations: InstallLocations) throws -> [CodexConfiguredHook] {
        let hooks = try connection.hooks().filter { owns($0, home: home, locations: locations) }
        let expected = Set(HookInstaller.codexEvents.map { $0.prefix(1).lowercased() + $0.dropFirst() })
        guard Set(hooks.map(\.eventName)) == expected else {
            throw CodexHookTrustError.failed("Codex could not load CodeWindow's hooks. Update Codex and reconnect your agents.")
        }
        return hooks
    }

    private func owns(_ hook: CodexConfiguredHook, home: URL, locations: InstallLocations) -> Bool {
        hook.source == "user"
            && hook.handlerType == "command"
            && hook.command == "\(HookInstaller.shellQuote(locations.installedReporter.path)) --agent codex"
            && URL(fileURLWithPath: hook.sourcePath).resolvingSymlinksInPath().standardizedFileURL
                == home.appendingPathComponent("hooks.json").resolvingSymlinksInPath().standardizedFileURL
    }
}

private struct CodexConfiguredHook: Decodable {
    let key: String
    let eventName: String
    let handlerType: String
    let command: String?
    let source: String
    let sourcePath: String
    let currentHash: String
    let trustStatus: String
}

enum CodexHookTrustError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self { case let .failed(message): message }
    }
}

/// Short-lived, local configuration connection. No thread or model session is started.
private final class CodexHookConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let home: URL
    private let deadline = ProcessInfo.processInfo.systemUptime + 15
    private var buffer = Data()
    private var requestID = 0
    private var closed = false

    init(executable: URL, home: URL) throws {
        self.home = home
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw invalidResponse
            }
            try process.run()
            output.fileHandleForWriting.closeFile()
            input.fileHandleForReading.closeFile()
            _ = try request("initialize", params: [
                "clientInfo": ["name": "codewindow_installer", "version": "1"],
                "capabilities": ["experimentalApi": true],
            ])
            try input.fileHandleForWriting.write(contentsOf: Data("{\"method\":\"initialized\"}\n".utf8))
        } catch {
            close()
            throw error
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            // This helper only serves configuration RPCs; don't wait on a wedged server.
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        try? output.fileHandleForReading.close()
    }

    func hooks() throws -> [CodexConfiguredHook] {
        let result = try request("hooks/list", params: ["cwds": [home.path]])
        struct Entry: Decodable {
            let hooks: [CodexConfiguredHook]
        }
        struct Response: Decodable {
            let data: [Entry]
        }
        let response = try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: result))
        guard response.data.count == 1 else { throw invalidResponse }
        return response.data[0].hooks
    }

    func write(edits: [[String: Any]]) throws {
        let result = try request("config/batchWrite", params: ["edits": edits, "reloadUserConfig": true])
        guard result["status"] as? String == "ok" else {
            throw CodexHookTrustError.failed("Codex policy prevented saving CodeWindow hook permissions.")
        }
    }

    private var invalidResponse: CodexHookTrustError {
        .failed("Codex setup failed. Update Codex and reconnect your agents.")
    }

    private func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        requestID += 1
        var data = try JSONSerialization.data(withJSONObject: ["id": requestID, "method": method, "params": params])
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
        while true {
            let line = try readLine()
            guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw invalidResponse }
            guard response["id"] as? Int == requestID else { continue }
            guard response["error"] == nil, let result = response["result"] as? [String: Any] else { throw invalidResponse }
            return result
        }
    }

    private func readLine() throws -> Data {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw CodexHookTrustError.failed("Codex setup timed out. Reconnect your agents to retry.")
            }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(remaining * 1_000))
            if ready < 0, errno == EINTR { continue }
            guard ready >= 0 else { throw invalidResponse }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw invalidResponse }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 2_097_152 else { throw invalidResponse }
        }
    }
}
