import Darwin
import Foundation

public struct CoolCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CoolCommandRunning: Sendable {
    func run(
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> CoolCommandResult
    func cancelAll()
}

public extension CoolCommandRunning {
    func cancelAll() {}
}

public enum CoolCLIError: Error, Equatable, Sendable {
    case missing
    case unsupportedVersion(String)
    case authenticationRequired
    case timedOut
    case outputTooLarge
    case invalidResponse(String)
    case commandFailed(code: String, message: String, exitCode: Int32)

    public var userMessage: String {
        switch self {
        case .missing:
            "Cloud View needs the cool CLI in ~/.local/bin, /opt/homebrew/bin, or /usr/local/bin."
        case let .unsupportedVersion(version):
            "Cloud View needs cool 0.9.0 or newer; found \(version)."
        case .authenticationRequired:
            "Cloud View needs Cool login. Run cool login in Terminal, then retry."
        case .timedOut:
            "Cool did not respond in time."
        case .outputTooLarge:
            "Cool returned more data than CodeWindow can safely read."
        case .invalidResponse:
            "Cool returned an unexpected response."
        case let .commandFailed(_, message, _):
            CloudText.message(message)
        }
    }
}

public struct CoolVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ output: String) {
        guard let match = output.firstMatch(of: /(?:cool\s+)?(\d+)\.(\d+)\.(\d+)/),
              let major = Int(match.1),
              let minor = Int(match.2),
              let patch = Int(match.3)
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: CoolVersion, rhs: CoolVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct CoolCLIClient: CoolCommandRunning, Sendable {
    public static let minimumVersion = CoolVersion(major: 0, minor: 9, patch: 0)
    public static let maximumOutputBytes = 2_097_152

    public let executableURL: URL
    private let registry: CoolProcessRegistry

    public init(executableURL: URL) {
        self.executableURL = executableURL
        registry = CoolProcessRegistry()
    }

    public static func discovered(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CoolCLIClient? {
        var candidates = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/cool"),
            URL(fileURLWithPath: "/opt/homebrew/bin/cool"),
            URL(fileURLWithPath: "/usr/local/bin/cool"),
        ]
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").compactMap {
                let directory = String($0)
                guard directory.hasPrefix("/") else { return nil }
                return URL(fileURLWithPath: directory).appendingPathComponent("cool")
            })
        }

        var seen = Set<String>()
        for candidate in candidates {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let path = resolved.path
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard seen.insert(path).inserted,
                  fileManager.fileExists(atPath: path),
                  fileManager.isExecutableFile(atPath: path),
                  values?.isRegularFile == true
            else { continue }
            return CoolCLIClient(executableURL: resolved)
        }
        return nil
    }

    public func checkedVersion() async throws -> CoolVersion {
        let result = try await run(arguments: ["--version"], stdin: nil, timeout: 10)
        let output = String(decoding: result.stdout + result.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, let version = CoolVersion(output) else {
            throw CoolCLIError.invalidResponse("version")
        }
        guard version >= Self.minimumVersion else {
            throw CoolCLIError.unsupportedVersion(output)
        }
        return version
    }

    public func run(
        arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval
    ) async throws -> CoolCommandResult {
        let executableURL = self.executableURL
        let operation = CoolProcessOperation()
        registry.insert(operation)
        defer { registry.remove(operation) }
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Self.runSynchronously(
                    executableURL: executableURL,
                    arguments: arguments,
                    stdin: stdin,
                    timeout: timeout,
                    operation: operation
                )
            }.value
        } onCancel: {
            operation.requestStop(.cancelled)
        }
    }

    public func cancelAll() {
        registry.cancelAll()
    }

    private static func runSynchronously(
        executableURL: URL,
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval,
        operation: CoolProcessOperation
    ) throws -> CoolCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = standardInput

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }

        guard operation.install(process) else { throw CancellationError() }
        do {
            try process.run()
        } catch {
            if operation.stopReason == .cancelled { throw CancellationError() }
            throw CoolCLIError.missing
        }
        operation.terminateIfStopped()

        let readGroup = DispatchGroup()
        let capturedOutput = CoolCapturedOutput()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(
                standardOutput.fileHandleForReading,
                stream: .standardOutput,
                capturedOutput: capturedOutput,
                operation: operation
            )
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(
                standardError.fileHandleForReading,
                stream: .standardError,
                capturedOutput: capturedOutput,
                operation: operation
            )
            readGroup.leave()
        }

        // Write concurrently so a CLI that stops consuming stdin cannot prevent the
        // timeout below from terminating it. Snapshot writes can exceed pipe capacity.
        _ = fcntl(standardInput.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let inputGroup = DispatchGroup()
        inputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { inputGroup.leave() }
            do {
                if let stdin, !stdin.isEmpty {
                    try standardInput.fileHandleForWriting.write(contentsOf: stdin)
                }
                try standardInput.fileHandleForWriting.close()
            } catch {
                // The process result below remains authoritative. Broken input commonly
                // means the child exited early and already supplied a structured error.
            }
        }

        if termination.wait(timeout: .now() + timeout) != .success {
            operation.requestStop(.timedOut)
            if termination.wait(timeout: .now() + 1) != .success {
                operation.forceKill()
                _ = termination.wait(timeout: .now() + 1)
            }
        }
        inputGroup.wait()
        readGroup.wait()

        switch operation.stopReason {
        case .cancelled:
            throw CancellationError()
        case .outputTooLarge:
            throw CoolCLIError.outputTooLarge
        case .timedOut:
            throw CoolCLIError.timedOut
        case nil:
            break
        }
        let captured = capturedOutput.snapshot()
        return CoolCommandResult(
            exitCode: process.terminationStatus,
            stdout: captured.0,
            stderr: captured.1
        )
    }

    private static func drain(
        _ handle: FileHandle,
        stream: CoolOutputStream,
        capturedOutput: CoolCapturedOutput,
        operation: CoolProcessOperation
    ) {
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            guard capturedOutput.append(
                chunk,
                to: stream,
                maximumBytes: maximumOutputBytes
            ) else {
                operation.requestStop(.outputTooLarge)
                return
            }
        }
    }
}

public enum CoolJSON {
    public static func object(from result: CoolCommandResult) throws -> [String: Any] {
        guard result.exitCode == 0 else { throw failure(from: result) }
        guard let object = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              object["success"] as? Bool == true
        else { throw CoolCLIError.invalidResponse("success JSON") }
        return object
    }

    public static func requireSuccess(_ result: CoolCommandResult) throws {
        _ = try object(from: result)
    }

    public static func failure(from result: CoolCommandResult) -> CoolCLIError {
        let objects = [result.stderr, result.stdout].compactMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        if objects.contains(where: { $0["code"] as? String == "authentication_required" }) {
            return .authenticationRequired
        }
        let object = objects.first
        let code = object?["code"] as? String ?? "command_failed"
        let message = object?["error"] as? String ?? "cool exited with status \(result.exitCode)"
        return .commandFailed(code: code, message: message, exitCode: result.exitCode)
    }

    public static func dictionary(_ object: [String: Any], key: String) throws -> [String: Any] {
        guard let value = object[key] as? [String: Any] else {
            throw CoolCLIError.invalidResponse(key)
        }
        return value
    }

    public static func string(_ object: [String: Any], key: String) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else {
            throw CoolCLIError.invalidResponse(key)
        }
        return value
    }
}

private enum CoolOutputStream {
    case standardOutput
    case standardError
}

private enum CoolProcessStopReason: Equatable {
    case cancelled
    case outputTooLarge
    case timedOut
}

private final class CoolProcessOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var reason: CoolProcessStopReason?

    var stopReason: CoolProcessStopReason? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }

    func install(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        return reason == nil
    }

    func requestStop(_ requestedReason: CoolProcessStopReason) {
        lock.lock()
        if reason == nil { reason = requestedReason }
        let process = self.process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    func terminateIfStopped() {
        lock.lock()
        let shouldStop = reason != nil
        let process = self.process
        lock.unlock()
        if shouldStop, process?.isRunning == true { process?.terminate() }
    }

    func forceKill() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

private final class CoolProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [ObjectIdentifier: CoolProcessOperation] = [:]

    func insert(_ operation: CoolProcessOperation) {
        lock.lock()
        operations[ObjectIdentifier(operation)] = operation
        lock.unlock()
    }

    func remove(_ operation: CoolProcessOperation) {
        lock.lock()
        operations.removeValue(forKey: ObjectIdentifier(operation))
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let active = Array(operations.values)
        lock.unlock()
        for operation in active { operation.requestStop(.cancelled) }
    }
}

private final class CoolCapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func append(
        _ data: Data,
        to stream: CoolOutputStream,
        maximumBytes: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard standardOutput.count + standardError.count + data.count <= maximumBytes else {
            return false
        }
        switch stream {
        case .standardOutput:
            standardOutput.append(data)
        case .standardError:
            standardError.append(data)
        }
        return true
    }

    func snapshot() -> (Data, Data) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}
