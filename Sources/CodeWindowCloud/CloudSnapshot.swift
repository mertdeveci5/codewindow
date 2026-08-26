import CodeWindowCore
import CryptoKit
import Foundation

public struct CloudSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let revision: UInt64
    public let generatedAt: Date
    public var sessions: [CloudSessionSnapshot]

    public init(
        revision: UInt64,
        generatedAt: Date = Date(),
        sessions: [CloudSessionSnapshot]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.sessions = sessions
    }
}

public struct CloudSessionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let agent: AgentKind
    public let activity: Activity
    public let projectLabel: String
    public let action: SafeAction
    public let taskPreview: String?
    public let actionPreview: String?
    public let updatedAt: Date
    public var events: [CloudEventSnapshot]

    public init(
        id: String,
        agent: AgentKind,
        activity: Activity,
        projectLabel: String,
        action: SafeAction,
        taskPreview: String?,
        actionPreview: String?,
        updatedAt: Date,
        events: [CloudEventSnapshot]
    ) {
        self.id = id
        self.agent = agent
        self.activity = activity
        self.projectLabel = CloudText.project(projectLabel)
        self.action = action
        self.taskPreview = CloudText.preview(taskPreview)
        self.actionPreview = CloudText.preview(actionPreview)
        self.updatedAt = updatedAt
        self.events = Array(events.suffix(SessionFeed.maximumEvents))
    }
}

public struct CloudEventSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: SessionFeedEventKind
    public let text: String
    public let detail: String?
    public let succeeded: Bool?

    public init(
        id: String,
        kind: SessionFeedEventKind,
        text: String,
        detail: String?,
        succeeded: Bool?
    ) {
        self.id = id
        self.kind = kind
        self.text = CloudText.message(text)
        self.detail = CloudText.message(detail)
        self.succeeded = succeeded
    }
}

public enum CloudSnapshotEncodingError: Error, Equatable, Sendable {
    case summariesExceedLimit
}

public enum CloudSnapshotEncoder {
    public static let maximumBytes = 1_048_576

    public static func encode(_ snapshot: CloudSnapshot) throws -> Data {
        var candidate = snapshot
        var data = try encoder.encode(candidate)

        while data.count > maximumBytes {
            guard let index = candidate.sessions.indices
                .filter({ !candidate.sessions[$0].events.isEmpty })
                .max(by: {
                    candidate.sessions[$0].events.count < candidate.sessions[$1].events.count
                })
            else {
                throw CloudSnapshotEncodingError.summariesExceedLimit
            }
            candidate.sessions[index].events.removeFirst()
            data = try encoder.encode(candidate)
        }
        return data
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public enum CloudIdentifier {
    public static func derived(seed: String, localID: String) -> String {
        let digest = SHA256.hash(data: Data("\(seed)\u{0}\(localID)".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public static func random256BitHex() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }
}

public enum CloudText {
    public static func project(_ value: String) -> String {
        limited(redacted(clean(value)), characters: 60, bytes: 192)
    }

    public static func preview(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = limited(redacted(clean(value)), characters: 96, bytes: 192)
        return result.isEmpty ? nil : result
    }

    public static func message(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = limited(redacted(clean(value)), characters: 320, bytes: 384)
        return result.isEmpty ? nil : result
    }

    public static func message(_ value: String) -> String {
        message(Optional(value)) ?? "update"
    }

    private static func clean(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        })
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func redacted(_ value: String) -> String {
        let patterns: [(String, String)] = [
            (#"(?i)(bearer\s+)[^\s,;]+"#, "$1[redacted]"),
            (#"(?i)((?:api[_-]?key|token|password|secret|authorization)\s*[:=]\s*)[^\s,;]+"#, "$1[redacted]"),
            (#"\b(?:sk|xox[baprs])-[A-Za-z0-9_-]{12,}\b"#, "[redacted]"),
            (#"\bgh[pousr]_[A-Za-z0-9]{12,}\b"#, "[redacted]"),
        ]
        return patterns.reduce(value) { result, entry in
            result.replacingOccurrences(
                of: entry.0,
                with: entry.1,
                options: .regularExpression
            )
        }
    }

    private static func limited(_ value: String, characters: Int, bytes: Int) -> String {
        var result = String(value.prefix(characters))
        while result.utf8.count > bytes, !result.isEmpty {
            result.removeLast()
        }
        return result
    }
}
