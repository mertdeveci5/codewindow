import CryptoKit
import Foundation

private enum CloudComputerName {
    static let prefix = "meatproxy"

    static func slug(for generation: Int) -> String {
        "\(prefix)\(generation)"
    }

    static func generation(from slug: String) -> Int? {
        guard slug.hasPrefix(prefix),
              let generation = Int(slug.dropFirst(prefix.count)),
              generation > 0,
              slug == self.slug(for: generation)
        else { return nil }
        return generation
    }
}

public enum CloudViewVisibility: String, Codable, Equatable, Sendable {
    case publicAccess = "public"
    case privateAccess = "private"
}

public struct CloudProvisioningIntent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generation: Int
    public let slug: String
    public let visibility: CloudViewVisibility
    public let ownershipMarker: String
    public let remoteIDSeed: String

    public init(
        generation: Int,
        visibility: CloudViewVisibility = .publicAccess,
        ownershipMarker: String,
        remoteIDSeed: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generation = generation
        self.slug = CloudComputerName.slug(for: generation)
        self.visibility = visibility
        self.ownershipMarker = ownershipMarker
        self.remoteIDSeed = remoteIDSeed
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generation
        case slug
        case visibility
        case ownershipMarker
        case remoteIDSeed
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == 1 || decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported Cloud provisioning receipt schema"
            )
        }
        schemaVersion = Self.currentSchemaVersion
        generation = try values.decode(Int.self, forKey: .generation)
        slug = try values.decode(String.self, forKey: .slug)
        visibility = decodedSchemaVersion == 1
            ? .privateAccess
            : try values.decode(CloudViewVisibility.self, forKey: .visibility)
        ownershipMarker = try values.decode(String.self, forKey: .ownershipMarker)
        remoteIDSeed = try values.decode(String.self, forKey: .remoteIDSeed)
        guard generation > 0,
              slug == CloudComputerName.slug(for: generation),
              CloudMirrorHandle.is256BitHex(ownershipMarker),
              CloudMirrorHandle.is256BitHex(remoteIDSeed)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Invalid Cloud provisioning receipt"
            )
        }
    }
}

public struct CloudMirrorHandle: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let computerID: String
    public let slug: String
    public let generation: Int
    public let visibility: CloudViewVisibility
    public let ownershipMarker: String
    public let remoteIDSeed: String
    public var ownershipEstablished: Bool
    public var publicURL: URL?

    public init(
        computerID: String,
        slug: String,
        generation: Int,
        visibility: CloudViewVisibility = .publicAccess,
        ownershipMarker: String,
        remoteIDSeed: String,
        ownershipEstablished: Bool = false,
        publicURL: URL? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.computerID = computerID
        self.slug = slug
        self.generation = generation
        self.visibility = visibility
        self.ownershipMarker = ownershipMarker
        self.remoteIDSeed = remoteIDSeed
        self.ownershipEstablished = ownershipEstablished
        self.publicURL = publicURL
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case computerID
        case slug
        case generation
        case visibility
        case ownershipMarker
        case remoteIDSeed
        case ownershipEstablished
        case publicURL
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == 1 || decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported CloudMirrorHandle schema"
            )
        }
        schemaVersion = Self.currentSchemaVersion
        computerID = try values.decode(String.self, forKey: .computerID)
        slug = try values.decode(String.self, forKey: .slug)
        generation = try values.decode(Int.self, forKey: .generation)
        visibility = decodedSchemaVersion == 1
            ? .privateAccess
            : try values.decode(CloudViewVisibility.self, forKey: .visibility)
        ownershipMarker = try values.decode(String.self, forKey: .ownershipMarker)
        remoteIDSeed = try values.decode(String.self, forKey: .remoteIDSeed)
        ownershipEstablished = try values.decodeIfPresent(
            Bool.self,
            forKey: .ownershipEstablished
        ) ?? false
        publicURL = try values.decodeIfPresent(URL.self, forKey: .publicURL)
        guard !computerID.isEmpty,
              computerID != "pending",
              generation > 0,
              slug == CloudComputerName.slug(for: generation),
              Self.is256BitHex(ownershipMarker),
              Self.is256BitHex(remoteIDSeed),
              publicURL == nil || Self.isExpectedCoolURL(publicURL, slug: slug)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .computerID,
                in: values,
                debugDescription: "Invalid Cloud mirror handle"
            )
        }
    }

    fileprivate static func is256BitHex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    fileprivate static func isExpectedCoolURL(_ url: URL?, slug: String) -> Bool {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "\(slug).cool.computer",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { return false }
        return true
    }
}

public enum CloudMirrorError: Error, Equatable, Sendable {
    case ownershipMismatch
    case unexpectedService
    case unsafeComputerConfiguration
    case computerMissing
    case invalidCloudURL
    case computerNotReady(String)

    public var userMessage: String {
        switch self {
        case .ownershipMismatch:
            "Cloud View could not verify its dedicated Cool Computer. Nothing was changed."
        case .unexpectedService:
            "The saved Cool Computer is running an unexpected service. Nothing was changed."
        case .unsafeComputerConfiguration:
            "The saved Cool Computer no longer has its required visibility and network-disabled configuration. Nothing was changed."
        case .computerMissing:
            "The saved Cool Computer no longer exists. Set up a new Cloud View explicitly."
        case .invalidCloudURL:
            "Cool did not return the expected Cloud View URL."
        case let .computerNotReady(status):
            "The Cool Computer is not ready (\(CloudText.message(status)))."
        }
    }
}

public actor CloudMirrorEngine {
    public static let remoteDirectory = "/home/runtime/codewindow"
    public static let viewerPath = "/home/runtime/codewindow/index.html"
    public static let statePath = "/home/runtime/codewindow/state.json"
    public static let markerPath = "/home/runtime/.codewindow-owner.json"
    public static let servicePort = 8000
    public static let serviceCommand = "python3 -m http.server 8000 --directory /home/runtime/codewindow"

    private let runner: any CoolCommandRunning
    private let viewerHTML: Data

    public init(runner: any CoolCommandRunning, viewerHTML: Data) {
        self.runner = runner
        self.viewerHTML = viewerHTML
    }

    public nonisolated func cancelAllCommands() {
        runner.cancelAll()
    }

    @discardableResult
    public func preflight() async throws -> CoolVersion {
        let versionResult = try await runner.run(
            arguments: ["--version"],
            stdin: nil,
            timeout: 10
        )
        let versionOutput = String(
            decoding: versionResult.stdout + versionResult.stderr,
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard versionResult.exitCode == 0, let version = CoolVersion(versionOutput) else {
            throw CoolCLIError.invalidResponse("version")
        }
        guard version >= CoolCLIClient.minimumVersion else {
            throw CoolCLIError.unsupportedVersion(versionOutput)
        }

        _ = try await json(["whoami", "--json"], timeout: 10)
        return version
    }

    public func nextGeneration(localMinimum: Int) async throws -> Int {
        guard localMinimum > 0, localMinimum < Int.max else {
            throw CoolCLIError.invalidResponse("computer generation")
        }
        let response = try await json(["list", "--json"], timeout: 15)
        let computers = response["computers"] as? [[String: Any]] ?? []
        let remoteMaximum = computers.compactMap { computer -> Int? in
            guard let slug = computer["slug"] as? String,
                  let generation = CloudComputerName.generation(from: slug)
            else { return nil }
            return generation
        }.max() ?? 0
        guard remoteMaximum < Int.max else {
            throw CoolCLIError.invalidResponse("computer generation")
        }
        return max(localMinimum, remoteMaximum + 1)
    }

    public func createHandle(
        generation: Int,
        ownershipMarker: String,
        remoteIDSeed: String
    ) async throws -> CloudMirrorHandle {
        try await createHandle(intent: CloudProvisioningIntent(
            generation: generation,
            ownershipMarker: ownershipMarker,
            remoteIDSeed: remoteIDSeed
        ))
    }

    public func createHandle(intent: CloudProvisioningIntent) async throws -> CloudMirrorHandle {
        let provisional = CloudMirrorHandle(
            computerID: "pending",
            slug: intent.slug,
            generation: intent.generation,
            visibility: intent.visibility,
            ownershipMarker: intent.ownershipMarker,
            remoteIDSeed: intent.remoteIDSeed
        )
        let bootstrap = try bootstrapCommand(for: provisional)
        let response = try await json([
            "create", intent.slug,
            "--visibility", intent.visibility.rawValue,
            "--network", "none",
            "--command", bootstrap,
            "--port", String(Self.servicePort),
            "--json",
        ], timeout: 60)
        let computer = try CoolJSON.dictionary(response, key: "computer")
        let computerID = try CoolJSON.string(computer, key: "id")
        let returnedSlug = try CoolJSON.string(computer, key: "slug")
        guard returnedSlug == intent.slug else {
            throw CoolCLIError.invalidResponse("computer.slug")
        }
        guard computer["visibility"] as? String == intent.visibility.rawValue,
              (computer["network_policy"] as? [String: Any])?["mode"] as? String == "none"
        else { throw CoolCLIError.invalidResponse("Cloud View computer configuration") }

        return CloudMirrorHandle(
            computerID: computerID,
            slug: intent.slug,
            generation: intent.generation,
            visibility: intent.visibility,
            ownershipMarker: intent.ownershipMarker,
            remoteIDSeed: intent.remoteIDSeed
        )
    }

    /// Finds only the exact generation reserved by this app and then requires its
    /// random remote marker. A matching name alone is never enough to claim a computer.
    public func recoverProvisioning(_ intent: CloudProvisioningIntent) async throws -> CloudMirrorHandle? {
        let response = try await json(["list", "--json"], timeout: 15)
        let matches = (response["computers"] as? [[String: Any]] ?? []).filter {
            $0["slug"] as? String == intent.slug
        }
        guard matches.count <= 1 else { throw CoolCLIError.invalidResponse("duplicate computer slug") }
        guard let match = matches.first else { return nil }
        let computerID = try CoolJSON.string(match, key: "id")
        var handle = CloudMirrorHandle(
            computerID: computerID,
            slug: intent.slug,
            generation: intent.generation,
            visibility: intent.visibility,
            ownershipMarker: intent.ownershipMarker,
            remoteIDSeed: intent.remoteIDSeed
        )
        let computer = try await computerDetails(computerID)
        try validateComputer(computer, for: handle)
        try await ensureRunning(computer, for: handle)
        try await verifyOwnershipEventually(handle)
        handle.ownershipEstablished = true
        return handle
    }

    public func configureNew(
        handle: CloudMirrorHandle,
        initialSnapshot: Data
    ) async throws -> CloudMirrorHandle {
        let computer = try await computerDetails(handle.computerID)
        try validateComputer(computer, for: handle)
        try await ensureRunning(computer, for: handle)
        try await verifyOwnershipEventually(handle)
        try await requireSuccess([
            "share", handle.visibility.rawValue, handle.computerID, "--json",
        ], timeout: 15)
        try await requireSuccess([
            "files", "mkdir", handle.computerID, Self.remoteDirectory,
            "--parents", "--mode", "0755", "--json",
        ], timeout: 30)
        var configured = handle
        configured.ownershipEstablished = true
        try await writeFile(
            computerID: handle.computerID,
            path: Self.viewerPath,
            data: viewerHTML,
            mode: "0644"
        )
        try await writeFile(
            computerID: handle.computerID,
            path: Self.statePath,
            data: initialSnapshot,
            mode: "0644"
        )
        try await replaceBootstrapService(for: handle)
        let url = try await cloudURL(for: handle)
        configured.publicURL = url
        return configured
    }

    public func resume(_ handle: CloudMirrorHandle) async throws -> CloudMirrorHandle {
        let computer = try await computerDetails(handle.computerID)
        try validateComputer(computer, for: handle)
        try await ensureRunning(computer, for: handle)
        var resumed = handle
        // The remote marker is authoritative even if the app quit before persisting
        // `ownershipEstablished`. A missing marker is never recreated on a saved ID.
        try await verifyOwnership(handle)
        resumed.ownershipEstablished = true
        try await requireSuccess([
            "share", handle.visibility.rawValue, handle.computerID, "--json",
        ], timeout: 15)
        try await writeFile(
            computerID: handle.computerID,
            path: Self.viewerPath,
            data: viewerHTML,
            mode: "0644"
        )
        try await ensureExpectedService(handle.computerID)
        let url = try await cloudURL(for: handle)
        resumed.publicURL = url
        return resumed
    }

    public func publish(_ snapshot: Data, to handle: CloudMirrorHandle) async throws {
        do {
            try await writeFile(
                computerID: handle.computerID,
                path: Self.statePath,
                data: snapshot,
                mode: "0644"
            )
        } catch let error as CoolCLIError where error != .authenticationRequired {
            let computer = try await computerDetails(handle.computerID)
            try validateComputer(computer, for: handle)
            let status = try CoolJSON.string(computer, key: "status")
            guard status == "cold" else { throw error }
            try await requireSuccess([
                "start", handle.computerID, "--json",
            ], timeout: 60)
            try await verifyOwnership(handle)
            try await writeFile(
                computerID: handle.computerID,
                path: Self.statePath,
                data: snapshot,
                mode: "0644"
            )
        }
    }

    public func deleteVerified(_ handle: CloudMirrorHandle) async throws {
        do {
            let computer = try await computerDetails(handle.computerID)
            try validateIdentity(computer, for: handle)
            try await ensureRunning(computer, for: handle)
        } catch CloudMirrorError.computerMissing {
            // Deletion is idempotent: if Cool confirms the saved ID is gone, local
            // cleanup can finish instead of trapping the user in a retry loop.
            return
        }
        if handle.ownershipEstablished {
            try await verifyOwnership(handle)
        } else {
            try await verifyOwnershipEventually(handle)
        }
        try await requireSuccess([
            "delete", handle.computerID, "--force", "--json",
        ], timeout: 60)
    }

    private func markerData(_ handle: CloudMirrorHandle) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "slug": handle.slug,
            "markerDigest": ownershipDigest(handle.ownershipMarker),
        ], options: [.sortedKeys])
    }

    private func ownershipDigest(_ marker: String) -> String {
        SHA256.hash(data: Data(marker.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func bootstrapCommand(for handle: CloudMirrorHandle) throws -> String {
        let marker = try markerData(handle).base64EncodedString()
        return "/bin/bash -lc 'umask 077; install -d -m 0755 \(Self.remoteDirectory); printf %s \(marker) | base64 --decode > \(Self.markerPath); chmod 0600 \(Self.markerPath); exec \(Self.serviceCommand)'"
    }

    private func verifyOwnership(_ handle: CloudMirrorHandle) async throws {
        let result = try await runner.run(
            arguments: ["files", "read", handle.computerID, Self.markerPath],
            stdin: nil,
            timeout: 30
        )
        guard result.exitCode == 0 else {
            let error = CoolJSON.failure(from: result)
            if error == .authenticationRequired { throw error }
            if isNotFound(error) { throw CloudMirrorError.ownershipMismatch }
            throw error
        }
        guard let object = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              object["schemaVersion"] as? Int == 1,
              object["slug"] as? String == handle.slug,
              object["markerDigest"] as? String == ownershipDigest(handle.ownershipMarker)
        else { throw CloudMirrorError.ownershipMismatch }
    }

    private func isNotFound(_ error: Error) -> Bool {
        guard case let CoolCLIError.commandFailed(code, message, _) = error else { return false }
        return code == "api_error" && (
            message.localizedCaseInsensitiveContains("404")
                || message.localizedCaseInsensitiveContains("not found")
        )
    }

    private func ensureRunning(
        _ computer: [String: Any],
        for handle: CloudMirrorHandle
    ) async throws {
        let status = try CoolJSON.string(computer, key: "status")
        switch status {
        case "running", "creating":
            return
        case "cold", "archived":
            try await requireSuccess(["start", handle.computerID, "--json"], timeout: 60)
        default:
            throw CloudMirrorError.computerNotReady(status)
        }
    }

    private func computerDetails(_ computerID: String) async throws -> [String: Any] {
        do {
            let response = try await json(["info", computerID, "--json"], timeout: 15)
            return try CoolJSON.dictionary(response, key: "computer")
        } catch where isNotFound(error) {
            throw CloudMirrorError.computerMissing
        }
    }

    private func validateComputer(
        _ computer: [String: Any],
        for handle: CloudMirrorHandle
    ) throws {
        try validateIdentity(computer, for: handle)
        guard computer["visibility"] as? String == handle.visibility.rawValue,
              (computer["network_policy"] as? [String: Any])?["mode"] as? String == "none"
        else { throw CloudMirrorError.unsafeComputerConfiguration }
    }

    private func validateIdentity(
        _ computer: [String: Any],
        for handle: CloudMirrorHandle
    ) throws {
        guard computer["id"] as? String == handle.computerID,
              computer["slug"] as? String == handle.slug
        else { throw CloudMirrorError.ownershipMismatch }
    }

    private func verifyOwnershipEventually(_ handle: CloudMirrorHandle) async throws {
        var lastError: Error = CloudMirrorError.ownershipMismatch
        for attempt in 0..<10 {
            do {
                try await verifyOwnership(handle)
                return
            } catch {
                if error is CancellationError { throw error }
                if case CoolCLIError.authenticationRequired = error {
                    throw error
                }
                lastError = error
                guard attempt < 9 else { break }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw lastError
    }

    private func ensureExpectedService(_ computerID: String) async throws {
        let response = try await json(["service", "show", computerID, "--json"], timeout: 15)
        let service = try CoolJSON.dictionary(response, key: "service")
        guard service["configured"] as? Bool == true else {
            _ = try await runService(computerID)
            return
        }
        guard service["port"] as? Int == Self.servicePort,
              service["command"] as? String == Self.serviceCommand
        else { throw CloudMirrorError.unexpectedService }

        if let status = service["status"] as? String,
           !["running", "starting"].contains(status)
        {
            try await requireSuccess([
                "service", "restart", computerID, "--json",
            ], timeout: 60)
        }
    }

    private func replaceBootstrapService(for handle: CloudMirrorHandle) async throws {
        let response = try await json([
            "service", "show", handle.computerID, "--json",
        ], timeout: 15)
        let service = try CoolJSON.dictionary(response, key: "service")
        guard service["configured"] as? Bool == true else {
            _ = try await runService(handle.computerID)
            return
        }
        guard service["port"] as? Int == Self.servicePort,
              let command = service["command"] as? String
        else { throw CloudMirrorError.unexpectedService }

        let bootstrap = try bootstrapCommand(for: handle)
        if command == bootstrap {
            _ = try await runService(handle.computerID)
            return
        }
        guard command == Self.serviceCommand else { throw CloudMirrorError.unexpectedService }
        if let status = service["status"] as? String,
           !["running", "starting"].contains(status)
        {
            try await requireSuccess([
                "service", "restart", handle.computerID, "--json",
            ], timeout: 60)
        }
    }

    private func runService(_ computerID: String) async throws -> [String: Any] {
        try await json([
            "service", "run", "--json", computerID,
            "--port", String(Self.servicePort), "--",
            "python3", "-m", "http.server", String(Self.servicePort),
            "--directory", Self.remoteDirectory,
        ], timeout: 60)
    }

    private func cloudURL(for handle: CloudMirrorHandle) async throws -> URL {
        let response = try await json(["url", handle.computerID, "--json"], timeout: 15)
        guard response["visibility"] as? String == handle.visibility.rawValue,
              response["slug"] as? String == handle.slug,
              let value = response["public_url"] as? String,
              let url = URL(string: value),
              CloudMirrorHandle.isExpectedCoolURL(url, slug: handle.slug)
        else { throw CloudMirrorError.invalidCloudURL }
        return url
    }

    private func writeFile(
        computerID: String,
        path: String,
        data: Data,
        mode: String
    ) async throws {
        try await requireSuccess([
            "files", "write", computerID, path,
            "--mode", mode, "--json",
        ], stdin: data, timeout: 30)
    }

    private func requireSuccess(
        _ arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval
    ) async throws {
        _ = try await json(arguments, stdin: stdin, timeout: timeout)
    }

    private func json(
        _ arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let result = try await runner.run(
            arguments: arguments,
            stdin: stdin,
            timeout: timeout
        )
        return try CoolJSON.object(from: result)
    }
}
