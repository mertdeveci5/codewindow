import CryptoKit
import Foundation

public struct HookPayload: Sendable {
    /// Codex and Claude report the Claude hook names, Pi reports its own. Every alias lives
    /// here once, so the presentation, the feed, and the previews all read the same model
    /// instead of each re-matching raw event strings.
    private enum HookEvent {
        case sessionStarted
        case promptSubmitted
        case toolStarted
        case toolFinished
        case toolFailed
        case permissionRequested
        case turnEnded
        case interrupted
        case sessionEnded

        init?(name: String, notificationType: String?) {
            switch HookPayload.normalized(name) {
            case "sessionstart":
                self = .sessionStarted
            case "userpromptsubmit", "beforeagentstart", "agentstart":
                self = .promptSubmitted
            case "pretooluse", "toolcall", "toolexecutionstart":
                self = .toolStarted
            case "posttooluse", "toolresult", "toolexecutionend":
                self = .toolFinished
            case "posttoolusefailure":
                self = .toolFailed
            case "permissionrequest":
                self = .permissionRequested
            case "notification"
                where HookPayload.normalized(notificationType ?? "").contains("permission"):
                self = .permissionRequested
            case "messageend", "stop", "agentsettled":
                self = .turnEnded
            case "interrupt":
                self = .interrupted
            case "sessionend", "sessionshutdown":
                self = .sessionEnded
            default:
                return nil
            }
        }
    }

    public let externalSessionID: String
    public let cwd: String
    public let toolName: String?
    private let toolOperationKey: String?
    private let submittedText: String?
    private let commandText: String?
    private let pathText: String?
    private let queryText: String?
    private let toolSubjectText: String?
    private let assistantText: String?
    private let toolFailed: Bool
    private let hasToolInput: Bool
    private let isSubagent: Bool
    private let event: HookEvent?

    public init(json: [String: Any]) throws {
        guard let sessionID = Self.string(in: json, keys: ["session_id", "sessionId"]),
              !sessionID.isEmpty,
              let eventName = Self.string(in: json, keys: ["hook_event_name", "event_name", "event", "type"]),
              !eventName.isEmpty
        else {
            throw HookPayloadError.missingRequiredField
        }

        self.externalSessionID = sessionID
        self.cwd = Self.string(in: json, keys: ["cwd"]) ?? FileManager.default.currentDirectoryPath
        self.isSubagent = Self.string(in: json, keys: ["agent_id", "agentId"])
            .map { !$0.isEmpty } ?? false
        let toolName = Self.string(in: json, keys: ["tool_name", "toolName"])
        self.toolName = toolName
        let event = HookEvent(
            name: eventName,
            notificationType: Self.string(in: json, keys: ["notification_type", "notificationType"])
        )
        self.event = event
        self.toolOperationKey = Self.operationKey(
            sessionID: sessionID,
            toolCallID: Self.string(
                in: json,
                keys: ["tool_call_id", "toolCallId", "tool_use_id", "toolUseId"]
            ),
            toolName: toolName
        )
        self.submittedText = Self.string(in: json, keys: ["user_prompt", "userPrompt", "prompt"])
        self.assistantText = Self.string(
            in: json,
            keys: ["last_assistant_message", "lastAssistantMessage", "assistant_message", "assistantMessage"]
        )
        // A dedicated failure event and an is_error flag mean the same thing to every reader.
        self.toolFailed = (Self.boolean(in: json, keys: ["is_error", "isError"]) ?? false)
            || event == .toolFailed

        let toolInputValue = Self.value(in: json, keys: ["tool_input", "toolInput", "args", "input"])
        self.hasToolInput = toolInputValue != nil
        let toolInput = toolInputValue as? [String: Any] ?? [:]
        let rawToolInput = toolInputValue as? String
        let isCommandTool = Self.isCommandTool(toolName)
        self.commandText = Self.stringOrArray(in: toolInput, keys: ["command", "cmd"])
            ?? Self.string(in: json, keys: ["command", "cmd"])
            ?? (isCommandTool ? Self.command(inFreeformInput: rawToolInput) ?? rawToolInput : nil)
        self.pathText = Self.firstString(
            in: toolInputValue,
            keys: ["file_path", "filePath", "path", "notebook_path", "notebookPath", "file"]
        )
        self.queryText = Self.firstString(
            in: toolInputValue,
            keys: ["pattern", "query", "search", "q", "selector"]
        )
        self.toolSubjectText = Self.toolSubject(in: toolInputValue, toolName: toolName)
    }

    public func state(
        agent: AgentKind,
        process: ProcessStamp,
        previous: SessionState? = nil,
        now: Date = Date()
    ) -> SessionState? {
        guard !isSubagent, let presentation = presentation(for: agent) else { return nil }
        let actionPreview = actionPreview(for: presentation.action, previous: previous)
        return SessionState(
            sessionKey: SessionState.key(agent: agent, externalSessionID: externalSessionID),
            agent: agent,
            activity: presentation.activity,
            projectLabel: SessionState.projectLabel(cwd: cwd),
            action: presentation.action,
            taskPreview: taskPreview ?? previous?.taskPreview,
            actionPreview: actionPreview,
            feedEvents: SessionFeed.persisted(
                previous?.feedEvents ?? [],
                appending: feedEvent(action: presentation.action, actionPreview: actionPreview)
            ),
            process: process,
            updatedAt: now
        )
    }

    private func presentation(for agent: AgentKind) -> (activity: Activity, action: SafeAction)? {
        switch event {
        case .sessionStarted:
            return (.starting, .waiting)
        case .promptSubmitted:
            return (.working, .thinking)
        case .toolStarted:
            return (.working, Self.safeAction(for: toolName, hasQuery: queryText != nil))
        case .toolFinished, .toolFailed:
            // A finished tool stays on the row. Handing the row back to thinking drops the
            // subject, and the panel then falls back to the task prompt from the start of
            // the turn instead of the work the agent just did.
            guard !toolFailed else { return (.needsAttention, .failed) }
            guard let toolName, !toolName.isEmpty else { return (.working, .thinking) }
            return (.working, Self.safeAction(for: toolName, hasQuery: queryText != nil))
        case .permissionRequested:
            return (.needsAttention, .awaitingPermission)
        case .turnEnded:
            return (agent == .codex ? .ended : .idle, .waiting)
        case .interrupted, .sessionEnded:
            return (.ended, .waiting)
        case nil:
            return nil
        }
    }

    private func feedEvent(
        action: SafeAction,
        actionPreview: String?
    ) -> SessionFeedEvent? {
        switch event {
        case .promptSubmitted:
            guard let text = Self.messagePreview(submittedText) else { return nil }
            return SessionFeedEvent(kind: .user, text: text)
        case .toolStarted:
            return SessionFeedEvent(
                kind: .toolCall,
                text: action.label,
                detail: actionPreview,
                operationKey: toolOperationKey
            )
        case .toolFinished, .toolFailed:
            return SessionFeedEvent(
                kind: .toolResult,
                text: Self.toolLabel(toolName) ?? "tool",
                succeeded: !toolFailed,
                operationKey: toolOperationKey
            )
        case .permissionRequested:
            return SessionFeedEvent(kind: .attention, text: action.label)
        case .turnEnded:
            guard let text = Self.messagePreview(assistantText) else { return nil }
            return SessionFeedEvent(kind: .assistant, text: text)
        case .sessionStarted, .interrupted, .sessionEnded, nil:
            return nil
        }
    }

    private var taskPreview: String? {
        guard event == .promptSubmitted else { return nil }
        return Self.preview(submittedText)
    }

    /// The row shows the newest thing that happened. Most events carry their own subject; a
    /// finished tool or a finished turn that arrives without one keeps the subject the row
    /// already showed. Nothing here may fall back to the task preview, or the prompt that
    /// opened the turn lands back on the row long after the agent moved past it.
    private func actionPreview(for action: SafeAction, previous: SessionState?) -> String? {
        switch event {
        case .turnEnded:
            return Self.preview(assistantText) ?? previous?.actionPreview
        case .toolFinished where !toolFailed && !hasToolInput:
            return previous?.actionPreview ?? subject(for: action)
        default:
            return subject(for: action)
        }
    }

    private func subject(for action: SafeAction) -> String? {
        switch action {
        case .runningCommand:
            return Self.preview(commandText ?? toolSubjectText)
        case .editingFile, .readingFile:
            return Self.preview(pathText.map(Self.fileSubject) ?? toolSubjectText)
        case .searching:
            return Self.preview(queryText ?? toolSubjectText)
        case .usingTool:
            return Self.preview(toolSubjectText)
        case .waiting, .thinking, .awaitingPermission, .failed:
            return nil
        }
    }

    private static func safeAction(for toolName: String?, hasQuery: Bool) -> SafeAction {
        let tool = normalized(toolName ?? "")
        if isCommandTool(toolName) {
            return .runningCommand
        }
        if tool.contains("edit") || tool.contains("write") || tool.contains("patch") {
            return .editingFile
        }
        if tool.contains("read") || tool.contains("view") || tool == "ls" {
            return .readingFile
        }
        if hasQuery || tool.contains("search") || tool.contains("query") || tool.contains("grep")
            || tool.contains("find") || tool.contains("glob")
        {
            return .searching
        }
        return .usingTool
    }

    private static func isCommandTool(_ toolName: String?) -> Bool {
        let tool = normalized(toolName ?? "")
        return tool.contains("bash") || tool.contains("shell") || tool.contains("exec")
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func operationKey(
        sessionID: String,
        toolCallID: String?,
        toolName: String?
    ) -> String? {
        let identity = toolCallID.flatMap { $0.isEmpty ? nil : $0 }
            ?? toolName.flatMap { normalized($0).isEmpty ? nil : normalized($0) }
        guard let identity else { return nil }
        let digest = SHA256.hash(data: Data("\(sessionID)\u{0}\(identity)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func string(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String { return value }
        }
        return nil
    }

    private static func value(in json: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = json[key] { return value }
        }
        return nil
    }

    private static func boolean(in json: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = json[key] as? Bool { return value }
        }
        return nil
    }

    private static func stringOrArray(in json: [String: Any], keys: [String]) -> String? {
        if let value = string(in: json, keys: keys) { return value }
        for key in keys {
            if let values = json[key] as? [String] { return values.joined(separator: " ") }
        }
        return nil
    }

    private static func firstString(in value: Any?, keys: [String], depth: Int = 0) -> String? {
        guard depth < 5 else { return nil }
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let string = dictionary[key] as? String, !string.isEmpty { return string }
                if let strings = dictionary[key] as? [String], !strings.isEmpty {
                    return strings.joined(separator: " ")
                }
            }
            for key in dictionary.keys.sorted() {
                if let string = firstString(in: dictionary[key], keys: keys, depth: depth + 1) {
                    return string
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let string = firstString(in: item, keys: keys, depth: depth + 1) {
                    return string
                }
            }
        }
        return nil
    }

    private static func toolSubject(in input: Any?, toolName: String?) -> String? {
        if let query = firstString(
            in: input,
            keys: ["pattern", "query", "search", "q", "selector", "prompt"]
        ) {
            return query
        }
        if let path = firstString(
            in: input,
            keys: ["file_path", "filePath", "path", "notebook_path", "notebookPath", "file"]
        ) {
            return fileSubject(path)
        }
        if let url = firstString(in: input, keys: ["url", "uri"]) {
            return urlSubject(url)
        }
        if let target = firstString(
            in: input,
            keys: ["task_name", "taskName", "target", "title", "name", "location", "ticker", "ref_id", "refId"]
        ) {
            return target
        }
        if let rawInput = input as? String {
            if let patchFile = patchFile(in: rawInput) { return patchFile }
            if isCommandTool(toolName) {
                return command(inFreeformInput: rawInput) ?? rawInput
            }
        }
        return toolLabel(toolName)
    }

    private static func fileSubject(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func urlSubject(_ value: String) -> String {
        guard var components = URLComponents(string: value), components.scheme != nil else {
            return value
        }
        if components.scheme == "file" {
            return fileSubject(components.path)
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let host = components.host ?? ""
        let subject = host + components.percentEncodedPath
        return subject.isEmpty ? value : subject
    }

    private static func patchFile(in input: String) -> String? {
        let markers = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        for line in input.split(whereSeparator: \.isNewline) {
            for marker in markers where line.hasPrefix(marker) {
                return fileSubject(String(line.dropFirst(marker.count)))
            }
        }
        return nil
    }

    private static func command(inFreeformInput input: String?) -> String? {
        guard let input,
              let expression = try? NSRegularExpression(
                  pattern: #"\bcmd\s*:\s*(\"(?:\\.|[^\"\\])*\")"#
              ),
              let match = expression.firstMatch(
                  in: input,
                  range: NSRange(input.startIndex..., in: input)
              ),
              let captureRange = Range(match.range(at: 1), in: input)
        else { return nil }

        let quoted = String(input[captureRange])
        guard let data = "[\(quoted)]".data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return values.first
    }

    private static func toolLabel(_ toolName: String?) -> String? {
        guard let toolName, !toolName.isEmpty else { return nil }
        let separators = CharacterSet(charactersIn: "._-/")
        return toolName.unicodeScalars
            .map { separators.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Keeps state files small and removes common credential shapes before persistence.
    private static func preview(_ rawValue: String?) -> String? {
        sanitized(rawValue, maximumCharacters: 96, maximumUTF8Bytes: 192)
    }

    private static func messagePreview(_ rawValue: String?) -> String? {
        sanitized(rawValue, maximumCharacters: 320, maximumUTF8Bytes: 384)
    }

    private static func sanitized(
        _ rawValue: String?,
        maximumCharacters: Int,
        maximumUTF8Bytes: Int
    ) -> String? {
        guard let rawValue else { return nil }
        var value = rawValue.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !value.isEmpty else { return nil }

        let redactions: [(pattern: String, replacement: String)] = [
            (#"(?i)(bearer\s+)[^\s'\"]+"#, "$1••••"),
            (#"(?i)((?:api[_-]?key|access[_-]?token|token|password|passwd|secret|authorization)\s*[=:]\s*)[^\s'\"]+"#, "$1••••"),
            (#"(?i)((?:--?(?:api[_-]?key|access[_-]?token|token|password|passwd|secret|authorization))(?:=|\s+))[^\s'\"]+"#, "$1••••"),
            (#"\b(?:sk|xox[baprs]|gh[pousr])-[A-Za-z0-9_-]{8,}\b"#, "••••"),
        ]
        for redaction in redactions {
            value = value.replacingOccurrences(
                of: redaction.pattern,
                with: redaction.replacement,
                options: .regularExpression
            )
        }

        guard value.count > maximumCharacters || value.utf8.count > maximumUTF8Bytes else {
            return value
        }

        value = String(value.prefix(maximumCharacters - 1))
        let maximumContentBytes = maximumUTF8Bytes - "…".utf8.count
        while value.utf8.count > maximumContentBytes {
            value.removeLast()
        }
        return value + "…"
    }
}

public enum HookPayloadError: Error {
    case missingRequiredField
}
