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
    private let toolSubjectText: String?

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
        let toolName = Self.string(in: json, keys: ["tool_name", "toolName"])
        self.toolName = toolName
        self.notificationType = Self.string(in: json, keys: ["notification_type", "notificationType"])
        self.submittedText = Self.string(in: json, keys: ["user_prompt", "userPrompt", "prompt"])

        let toolInputValue = Self.value(in: json, keys: ["tool_input", "toolInput", "args", "input"])
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
            return (.working, Self.safeAction(for: toolName, hasQuery: queryText != nil))
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
