import Darwin
import Foundation

/// What a waiting session needs from the user.
public enum InboxRequest: Codable, Equatable, Sendable {
    /// The agent finished its turn and is waiting for the next instruction.
    case reply
    /// The agent wants to run something and is waiting for approval. `detail` is the command,
    /// path, or other subject the tool will act on.
    case permission(tool: String, detail: String?)

    public var isPermission: Bool {
        if case .permission = self { true } else { false }
    }
}

/// The user's answer to one inbox item.
public enum InboxResponse: Codable, Equatable, Sendable {
    case reply(String)
    case allow
    case deny(reason: String?)
    /// Return the decision to the terminal: the agent shows its own prompt there.
    case answerInTerminal

    // A flat shape, because CodeWindow's Pi extension reads these files from JavaScript.
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decodeIfPresent(String.self, forKey: .text)
        switch try container.decode(String.self, forKey: .kind) {
        case "reply": self = .reply(text ?? "")
        case "allow": self = .allow
        case "deny": self = .deny(reason: text)
        case "terminal": self = .answerInTerminal
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown inbox response"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .reply(text):
            try container.encode("reply", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .allow:
            try container.encode("allow", forKey: .kind)
        case let .deny(reason):
            try container.encode("deny", forKey: .kind)
            try container.encodeIfPresent(reason, forKey: .text)
        case .answerInTerminal:
            try container.encode("terminal", forKey: .kind)
        }
    }
}

/// One session waiting on the user. Unlike session state, an item keeps the agent's whole latest
/// message and the request that started the turn, because the inbox exists to answer them. Items
/// stay on this Mac, readable only by the user, and are deleted once answered or superseded.
public struct InboxItem: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumMessageLength = 16_000
    public static let maximumTaskLength = 4_000
    public static let maximumDetailLength = 2_000

    public let schemaVersion: Int
    public let id: String
    public let sessionKey: String
    /// The agent's own session ID. Codex replies are queued against it.
    public let externalSessionID: String
    public let agent: AgentKind
    public let projectLabel: String
    public let request: InboxRequest
    public let message: String?
    public let task: String?
    public let process: ProcessStamp
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionKey: String,
        externalSessionID: String,
        agent: AgentKind,
        projectLabel: String,
        request: InboxRequest,
        message: String?,
        task: String?,
        process: ProcessStamp,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.sessionKey = sessionKey
        self.externalSessionID = externalSessionID
        self.agent = agent
        self.projectLabel = projectLabel
        self.request = switch request {
        case .reply: .reply
        case let .permission(tool, detail):
            .permission(
                tool: InboxText.clean(tool, limit: 80) ?? "tool",
                detail: InboxText.clean(detail, limit: Self.maximumDetailLength)
            )
        }
        self.message = InboxText.clean(message, limit: Self.maximumMessageLength)
        self.task = InboxText.clean(task, limit: Self.maximumTaskLength)
        self.process = process
        self.createdAt = createdAt
    }

    /// How a reply reaches this agent. Permission answers always go back through the hook that
    /// is waiting for them.
    public var replyDelivery: InboxReplyDelivery {
        switch agent {
        case .claude: .waitingHook
        case .codex: .codexQueue
        case .pi: .piExtension
        }
    }
}

public enum InboxReplyDelivery: Equatable, Sendable {
    /// A hook started when the turn ended is still running and hands the reply back to the agent.
    case waitingHook
    /// Codex accepts queued messages for a live thread through its local app server.
    case codexQueue
    /// CodeWindow's Pi extension watches for replies addressed to its session.
    case piExtension
}

enum InboxText {
    /// Keeps line structure, drops every other control character, and trims the far end. The
    /// text comes from the agent and from the user, both of whom this Mac already trusts, so it
    /// is bounded rather than redacted.
    static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let scalars = value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        var text = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > limit {
            text = String(text.prefix(limit - 1)) + "…"
        }
        return text
    }
}

/// The inbox lives beside session state, inside the same user-only directory, so uninstalling
/// CodeWindow removes it along with everything else.
public enum InboxFiles {
    public static let maximumFileBytes = 96_000

    private static let enabledMarker = ".enabled"

    /// The inbox's location, without creating anything. Hooks check the mode through this on
    /// every event, so a user who never turns the inbox on never gets the directory either.
    public static func root(stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    public static func directory(stateDirectory: URL) throws -> URL {
        let root = root(stateDirectory: stateDirectory)
        for url in [root, items(in: root), responses(in: root), tasks(in: root)] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        return root
    }

    static func items(in root: URL) -> URL { root.appendingPathComponent("Items", isDirectory: true) }
    static func responses(in root: URL) -> URL { root.appendingPathComponent("Responses", isDirectory: true) }
    static func tasks(in root: URL) -> URL { root.appendingPathComponent("Tasks", isDirectory: true) }

    public static func itemsDirectory(in root: URL) -> URL { items(in: root) }

    // MARK: Mode

    /// Inbox mode is off unless the user turns it on. Hooks check it on every event, so turning
    /// it off takes effect at once and leaves every agent behaving exactly as before.
    public static func isEnabled(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(enabledMarker).path)
    }

    public static func setEnabled(_ enabled: Bool, in root: URL) throws {
        let marker = root.appendingPathComponent(enabledMarker)
        if enabled {
            try write(Data(), to: marker)
        } else {
            try? FileManager.default.removeItem(at: marker)
            // Waiting hooks see their items disappear and hand control back to the terminal.
            for item in all(in: root) { remove(itemID: item.id, in: root) }
            removeAll(in: tasks(in: root))
        }
    }

    // MARK: Items

    /// Writes a new item and retires every older one for the same session: an agent can only be
    /// waiting on one thing at a time, and the newest is the one that is current.
    public static func add(_ item: InboxItem, in root: URL) throws {
        retire(sessionKey: item.sessionKey, in: root)
        try write(encode(item), to: items(in: root).appendingPathComponent("\(item.id).json"))
    }

    public static func item(id: String, in root: URL) -> InboxItem? {
        read(items(in: root).appendingPathComponent("\(id).json"))
    }

    public static func all(in root: URL) -> [InboxItem] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: items(in: root),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(read)
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The session moved on — the user typed in the terminal, a tool ran, or the session ended —
    /// so whatever it was waiting on is no longer a question.
    public static func retire(sessionKey: String, in root: URL) {
        for item in all(in: root) where item.sessionKey == sessionKey {
            remove(itemID: item.id, in: root)
        }
    }

    public static func remove(itemID: String, in root: URL) {
        try? FileManager.default.removeItem(at: items(in: root).appendingPathComponent("\(itemID).json"))
        try? FileManager.default.removeItem(at: responses(in: root).appendingPathComponent("\(itemID).json"))
    }

    // MARK: Responses

    public static func respond(_ response: InboxResponse, to itemID: String, in root: URL) throws {
        try write(encode(response), to: responses(in: root).appendingPathComponent("\(itemID).json"))
    }

    /// Reads and consumes a response, so each answer is delivered exactly once.
    public static func takeResponse(for itemID: String, in root: URL) -> InboxResponse? {
        let url = responses(in: root).appendingPathComponent("\(itemID).json")
        guard let response: InboxResponse = decode(url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return response
    }

    // MARK: Tasks

    /// The prompt that started the current turn, kept in full while inbox mode is on so an item
    /// can say what the session is about.
    public static func rememberTask(_ task: String?, sessionKey: String, in root: URL) {
        guard let task = InboxText.clean(task, limit: InboxItem.maximumTaskLength) else { return }
        try? write(Data(task.utf8), to: tasks(in: root).appendingPathComponent("\(sessionKey).txt"))
    }

    public static func task(sessionKey: String, in root: URL) -> String? {
        let url = tasks(in: root).appendingPathComponent("\(sessionKey).txt")
        guard let data = try? Data(contentsOf: url), data.count <= maximumFileBytes else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func forgetTask(sessionKey: String, in root: URL) {
        try? FileManager.default.removeItem(at: tasks(in: root).appendingPathComponent("\(sessionKey).txt"))
    }

    // MARK: Storage

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumFileBytes else { throw StateFileError.tooLarge }
        return data
    }

    private static func decode<Value: Decodable>(_ url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url), data.count <= maximumFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Value.self, from: data)
    }

    private static func read(_ url: URL) -> InboxItem? {
        guard let item: InboxItem = decode(url),
              item.schemaVersion == InboxItem.currentSchemaVersion,
              url.deletingPathExtension().lastPathComponent == item.id
        else { return nil }
        return item
    }

    /// Readers see either the old file or the new one, never half of either.
    private static func write(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                Darwin.rename(source, target)
            }
        }
        guard result == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw StateFileError.renameFailed(code)
        }
    }

    private static func removeAll(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

/// What a waiting hook prints and returns once the user answers. Pure, so every agent's exact
/// contract is covered by tests rather than discovered in a live session.
public struct InboxHookOutput: Equatable, Sendable {
    /// Introduces a reply in the text that wakes a Claude session. Claude feeds that text back
    /// through its prompt hook, where this marker lets CodeWindow recover the user's own words.
    public static let replyPreamble = "The user replied from the CodeWindow inbox:"

    public let standardOutput: String?
    public let standardError: String?
    public let exitCode: Int32

    public static let nothing = InboxHookOutput(standardOutput: nil, standardError: nil, exitCode: 0)

    public static func output(
        for response: InboxResponse?,
        agent: AgentKind,
        request: InboxRequest
    ) -> InboxHookOutput {
        guard let response else { return .nothing }
        switch (request, response) {
        case let (.reply, .reply(text)):
            // Claude's background Stop hook wakes the session on exit code 2 and shows stderr to
            // the model. Saying where the words came from keeps them from reading as tool noise.
            guard agent == .claude, let text = InboxText.clean(text, limit: InboxItem.maximumTaskLength) else {
                return .nothing
            }
            return InboxHookOutput(
                standardOutput: nil,
                standardError: "\(replyPreamble)\n\n\(text)",
                exitCode: 2
            )
        case (.permission, .allow):
            return permission(["behavior": "allow"])
        case let (.permission, .deny(reason)):
            var decision: [String: Any] = ["behavior": "deny"]
            decision["message"] = InboxText.clean(reason, limit: InboxItem.maximumDetailLength)
                ?? "The user denied this from the CodeWindow inbox."
            return permission(decision)
        default:
            // Answering in the terminal, or an answer that does not fit the question: print
            // nothing, and the agent falls back to its own prompt.
            return .nothing
        }
    }

    private static func permission(_ decision: [String: Any]) -> InboxHookOutput {
        let object: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return InboxHookOutput(
            standardOutput: String(decoding: data, as: UTF8.self),
            standardError: nil,
            exitCode: 0
        )
    }
}

/// Holds a hook open until the user answers its item, the item is retired, or the agent exits.
public enum InboxWaiter {
    public static func wait(
        for item: InboxItem,
        in root: URL,
        pollInterval: TimeInterval = 0.25,
        deadline: Date = .distantFuture,
        isAgentAlive: () -> Bool
    ) -> InboxResponse? {
        var nextLivenessCheck = Date()
        while Date() < deadline {
            if let response = InboxFiles.takeResponse(for: item.id, in: root) {
                InboxFiles.remove(itemID: item.id, in: root)
                return response
            }
            // Retired: the session moved on, a newer item replaced this one, or the mode was
            // turned off. Whatever happened, the terminal now owns the answer.
            guard InboxFiles.item(id: item.id, in: root) != nil else { return nil }
            if Date() >= nextLivenessCheck {
                guard isAgentAlive() else {
                    InboxFiles.remove(itemID: item.id, in: root)
                    return nil
                }
                nextLivenessCheck = Date().addingTimeInterval(5)
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        InboxFiles.remove(itemID: item.id, in: root)
        return nil
    }
}
