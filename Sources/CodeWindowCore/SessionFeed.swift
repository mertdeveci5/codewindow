import Foundation

public enum SessionFeedEventKind: String, Codable, Sendable {
    case user
    case assistant
    case toolCall
    case toolResult
    case attention
}

public struct SessionFeedEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SessionFeedEventKind
    public let text: String
    public let detail: String?
    public let succeeded: Bool?

    public init(
        id: UUID = UUID(),
        kind: SessionFeedEventKind,
        text: String,
        detail: String? = nil,
        succeeded: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.succeeded = succeeded
    }
}

public enum SessionFeed {
    public static let maximumEvents = 40

    public static func appending(
        _ event: SessionFeedEvent,
        to events: [SessionFeedEvent]
    ) -> [SessionFeedEvent] {
        guard !events.contains(where: { $0.id == event.id }) else { return events }
        return Array((events + [event]).suffix(maximumEvents))
    }
}
