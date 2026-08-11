import Foundation

public struct HookPayload: Sendable {
    public let externalSessionID: String
    public let eventName: String
    public let cwd: String
    public let toolName: String?
    public let notificationType: String?
    private let submittedText: String?
    private let commandText: String?
    private let pathText: String?
    private let queryText: String?

    public init(json: [String: Any]) throws {
        guard let sessionID = Self.string(in: json, keys: ["session_id", "sessionId"]),
              !sessionID.isEmpty,
              let eventName = Self.string(in: json, keys: ["hook_event_name", "event_name", "event", "type"]),
              !eventName.isEmpty
        else {
            throw HookPayloadError.missingRequiredField
        }

        self.externalSessionID = sessionID
        self.eventName = eventName
        self.cwd = Self.string(in: json, keys: ["cwd"]) ?? FileManager.default.currentDirectoryPath
        self.toolName = Self.string(in: json, keys: ["tool_name", "toolName"])
        self.notificationType = Self.string(in: json, keys: ["notification_type", "notificationType"])
        self.submittedText = Self.string(in: json, keys: ["user_prompt", "userPrompt", "prompt"])

        let toolInput = Self.dictionary(in: json, keys: ["tool_input", "toolInput", "args", "input"])
        self.commandText = Self.stringOrArray(in: toolInput, keys: ["command", "cmd"])
            ?? Self.string(in: json, keys: ["command", "cmd"])
        self.pathText = Self.string(in: toolInput, keys: ["file_path", "filePath", "path", "notebook_path"])
        self.queryText = Self.string(in: toolInput, keys: ["pattern", "query", "search"])
    }

    public func state(
        agent: AgentKind,
        process: ProcessStamp,
        previousTaskPreview: String? = nil,
        now: Date = Date()
    ) -> SessionState? {
        guard let presentation = presentation else { return nil }
        return SessionState(
            sessionKey: SessionState.key(agent: agent, externalSessionID: externalSessionID),
            agent: agent,
            activity: presentation.activity,
            projectLabel: SessionState.projectLabel(cwd: cwd),
            action: presentation.action,
            taskPreview: taskPreview ?? previousTaskPreview,
            actionPreview: actionPreview(for: presentation.action),
            process: process,
            updatedAt: now
        )
    }

    private var presentation: (activity: Activity, action: SafeAction)? {
        switch Self.normalized(eventName) {
        case "sessionstart":
            return (.starting, .waiting)
        case "userpromptsubmit", "beforeagentstart", "agentstart":
            return (.working, .thinking)
        case "pretooluse", "toolcall", "toolexecutionstart":
            return (.working, Self.safeAction(for: toolName))
        case "posttooluse", "toolresult", "toolexecutionend":
            return (.working, .thinking)
        case "permissionrequest":
            return (.needsAttention, .awaitingPermission)
        case "notification" where Self.normalized(notificationType ?? "").contains("permission"):
            return (.needsAttention, .awaitingPermission)
        case "posttoolusefailure":
            return (.needsAttention, .failed)
        case "stop", "agentsettled":
            return (.idle, .waiting)
        case "sessionend", "sessionshutdown":
            return (.ended, .waiting)
        default:
            return nil
        }
    }

    private var taskPreview: String? {
        switch Self.normalized(eventName) {
        case "userpromptsubmit", "beforeagentstart":
            return Self.preview(submittedText)
        default:
            return nil
        }
    }

    private func actionPreview(for action: SafeAction) -> String? {
        switch action {
        case .runningCommand:
            return Self.preview(commandText)
        case .editingFile, .readingFile:
            guard let pathText else { return nil }
            return Self.preview(URL(fileURLWithPath: pathText).lastPathComponent)
        case .searching:
            return Self.preview(queryText)
        case .waiting, .thinking, .usingTool, .awaitingPermission, .failed:
            return nil
        }
    }

    private static func safeAction(for toolName: String?) -> SafeAction {
        let tool = normalized(toolName ?? "")
        if tool.contains("bash") || tool.contains("shell") || tool.contains("exec") {
            return .runningCommand
        }
        if tool.contains("edit") || tool.contains("write") || tool.contains("patch") {
            return .editingFile
        }
        if tool.contains("read") || tool.contains("view") {
            return .readingFile
        }
        if tool.contains("search") || tool.contains("grep") || tool.contains("find") || tool.contains("glob") {
            return .searching
        }
        return .usingTool
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func string(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String { return value }
        }
        return nil
    }

    private static func dictionary(in json: [String: Any], keys: [String]) -> [String: Any] {
        for key in keys {
            if let value = json[key] as? [String: Any] { return value }
        }
        return [:]
    }

    private static func stringOrArray(in json: [String: Any], keys: [String]) -> String? {
        if let value = string(in: json, keys: keys) { return value }
        for key in keys {
            if let values = json[key] as? [String] { return values.joined(separator: " ") }
        }
        return nil
    }

    /// Keeps state files small and removes common credential shapes before persistence.
    private static func preview(_ rawValue: String?) -> String? {
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

        let maximumCharacters = 96
        guard value.count > maximumCharacters else { return value }
        return String(value.prefix(maximumCharacters - 1)) + "…"
    }
}

public enum HookPayloadError: Error {
    case missingRequiredField
}
