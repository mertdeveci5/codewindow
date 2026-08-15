import CryptoKit
import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case pi

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .pi: "Pi"
        }
    }
}

public enum Activity: String, Codable, Sendable {
    case starting
    case working
    case needsAttention
    case idle
    case ended

    public var priority: Int {
        switch self {
        case .needsAttention: 0
        case .working: 1
        case .starting: 2
        case .idle: 3
        case .ended: 4
        }
    }
}

public enum SafeAction: String, Codable, Sendable {
    case waiting
    case thinking
    case runningCommand
    case editingFile
    case readingFile
    case searching
    case usingTool
    case awaitingPermission
    case failed

    public var label: String {
        switch self {
        case .waiting: "waiting"
        case .thinking: "thinking"
        case .runningCommand: "running command"
        case .editingFile: "editing file"
        case .readingFile: "reading file"
        case .searching: "searching"
        case .usingTool: "using tool"
        case .awaitingPermission: "needs permission"
        case .failed: "action failed"
        }
    }
}

public struct ProcessStamp: Codable, Equatable, Hashable, Sendable {
    public let pid: Int32
    public let startedAtSeconds: UInt64
    public let startedAtMicroseconds: UInt64

    public init(pid: Int32, startedAtSeconds: UInt64, startedAtMicroseconds: UInt64) {
        self.pid = pid
        self.startedAtSeconds = startedAtSeconds
        self.startedAtMicroseconds = startedAtMicroseconds
    }
}

public struct SessionState: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sessionKey: String
    public let agent: AgentKind
    public let activity: Activity
    public let projectLabel: String
    public let action: SafeAction
    /// A short, sanitized excerpt of the task that started the current turn.
    public let taskPreview: String?
    /// A short, sanitized subject for the tool that is currently running.
    public let actionPreview: String?
    /// The latest sanitized event, retained in memory by the app while it runs.
    public let feedEvent: SessionFeedEvent?
    public let process: ProcessStamp
    public let updatedAt: Date

    public var id: String { sessionKey }

    public init(
        sessionKey: String,
        agent: AgentKind,
        activity: Activity,
        projectLabel: String,
        action: SafeAction,
        taskPreview: String? = nil,
        actionPreview: String? = nil,
        feedEvent: SessionFeedEvent? = nil,
        process: ProcessStamp,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionKey = sessionKey
        self.agent = agent
        self.activity = activity
        self.projectLabel = projectLabel
        self.action = action
        self.taskPreview = taskPreview
        self.actionPreview = actionPreview
        self.feedEvent = feedEvent
        self.process = process
        self.updatedAt = updatedAt
    }

    public static func key(agent: AgentKind, externalSessionID: String) -> String {
        let digest = SHA256.hash(data: Data("\(agent.rawValue)\u{0}\(externalSessionID)".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public static func projectLabel(cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        let clean = name.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
        return String((clean.isEmpty ? "Terminal" : clean).prefix(60))
    }
}
