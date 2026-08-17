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
    /// An opaque, local-only key used to update a running tool row when it completes.
    public let operationKey: String?

    public init(
        id: UUID = UUID(),
        kind: SessionFeedEventKind,
        text: String,
        detail: String? = nil,
        succeeded: Bool? = nil,
        operationKey: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.succeeded = succeeded
        self.operationKey = operationKey
    }
}

public enum SessionFeed {
    public static let maximumEvents = 40

    public static func appending(
        _ event: SessionFeedEvent,
        to events: [SessionFeedEvent]
    ) -> [SessionFeedEvent] {
        guard !events.contains(where: { $0.id == event.id }) else { return events }

        if event.kind == .toolResult,
           let index = matchingToolCall(for: event, in: events)
        {
            var updated = events
            let running = events[index]
            updated[index] = SessionFeedEvent(
                id: running.id,
                kind: .toolResult,
                text: running.text,
                detail: running.detail,
                succeeded: event.succeeded,
                operationKey: running.operationKey ?? event.operationKey
            )
            return updated
        }

        return Array((events + [event]).suffix(maximumEvents))
    }

    private static func matchingToolCall(
        for result: SessionFeedEvent,
        in events: [SessionFeedEvent]
    ) -> Int? {
        if let operationKey = result.operationKey,
           let exact = events.lastIndex(where: {
               $0.kind == .toolCall && $0.operationKey == operationKey
           })
        {
            return exact
        }

        // Some hook versions omit a tool-call ID. Updating the most recent
        // unresolved tool is still more faithful than rendering two rows for
        // the same lifecycle transition.
        return events.lastIndex { $0.kind == .toolCall }
    }
}
