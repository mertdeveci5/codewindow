@testable import CodeWindowCore
import CoreGraphics
import Darwin
import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw TestFailure.assertion(message) }
    return value
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func testInspectorPlacement() throws {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let size = CGSize(width: 296, height: 320)

    let rightAnchor = CGRect(x: 1_126, y: 500, width: 296, height: 120)
    let fromRight = InspectorPlacementPolicy.frame(
        anchor: rightAnchor,
        size: size,
        gap: 8,
        margin: 18,
        within: visibleFrame
    )
    try require(fromRight.maxX == rightAnchor.minX - 8, "Right-edge panel should open left")

    let leftAnchor = CGRect(x: 18, y: 500, width: 296, height: 120)
    let fromLeft = InspectorPlacementPolicy.frame(
        anchor: leftAnchor,
        size: size,
        gap: 8,
        margin: 18,
        within: visibleFrame
    )
    try require(fromLeft.minX == leftAnchor.maxX + 8, "Left-edge panel should open right")

    let narrowFrame = CGRect(x: 0, y: 0, width: 600, height: 900)
    let topAnchor = CGRect(x: 152, y: 700, width: 296, height: 80)
    let fromTop = InspectorPlacementPolicy.frame(
        anchor: topAnchor,
        size: size,
        gap: 8,
        margin: 18,
        within: narrowFrame
    )
    try require(fromTop.maxY == topAnchor.minY - 8, "Top panel without horizontal room should open below")

    let bottomAnchor = CGRect(x: 152, y: 18, width: 296, height: 80)
    let fromBottom = InspectorPlacementPolicy.frame(
        anchor: bottomAnchor,
        size: size,
        gap: 8,
        margin: 18,
        within: narrowFrame
    )
    try require(fromBottom.minY == bottomAnchor.maxY + 8, "Bottom panel without horizontal room should open above")

    let negativeScreen = CGRect(x: -1_280, y: -120, width: 1_280, height: 800)
    let safeFrame = negativeScreen.insetBy(dx: 18, dy: 18)
    for x in stride(from: safeFrame.minX, through: safeFrame.maxX - 296, by: 100) {
        for y in stride(from: safeFrame.minY, through: safeFrame.maxY - 80, by: 100) {
            let placement = InspectorPlacementPolicy.frame(
                anchor: CGRect(x: x, y: y, width: 296, height: 80),
                size: size,
                gap: 8,
                margin: 18,
                within: negativeScreen
            )
            try require(safeFrame.contains(placement), "Inspector escaped the selected screen")
        }
    }
}

func testSessionFeed() throws {
    let first = SessionFeedEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        kind: .toolCall,
        text: "reading file",
        detail: "PanelContentView.swift"
    )
    let once = SessionFeed.appending(first, to: [])
    try require(once == [first], "First feed event was not recorded")
    try require(SessionFeed.appending(first, to: once) == once, "Duplicate feed event was recorded")

    let running = SessionFeedEvent(
        kind: .toolCall,
        text: "running command",
        detail: "swift test",
        operationKey: "operation-1"
    )
    let completed = SessionFeedEvent(
        kind: .toolResult,
        text: "Bash",
        succeeded: true,
        operationKey: "operation-1"
    )
    let lifecycle = SessionFeed.appending(completed, to: [first, running])
    try require(lifecycle.count == 2, "Tool completion appended a duplicate row")
    try require(lifecycle.last?.id == running.id, "Tool completion did not update the running row")
    try require(lifecycle.last?.kind == .toolResult, "Running tool row did not become a result")
    try require(lifecycle.last?.detail == "swift test", "Tool completion discarded the running detail")
    try require(lifecycle.last?.succeeded == true, "Tool completion status was not retained")

    let fallbackRunning = SessionFeedEvent(kind: .toolCall, text: "reading file", detail: "main.swift")
    let fallbackResult = SessionFeedEvent(kind: .toolResult, text: "read", succeeded: false)
    let fallbackLifecycle = SessionFeed.appending(fallbackResult, to: [fallbackRunning])
    try require(fallbackLifecycle.count == 1, "ID-less completion appended a duplicate row")
    try require(fallbackLifecycle[0].id == fallbackRunning.id, "ID-less completion replaced the wrong row")
    try require(fallbackLifecycle[0].succeeded == false, "ID-less failure status was lost")

    var events: [SessionFeedEvent] = []
    for index in 0...SessionFeed.maximumEvents {
        events = SessionFeed.appending(
            SessionFeedEvent(kind: .toolResult, text: "tool \(index)", succeeded: true),
            to: events
        )
    }
    try require(events.count == SessionFeed.maximumEvents, "Feed did not enforce its event limit")
    try require(events.first?.text == "tool 1", "Feed did not evict its oldest event")
}

func testHookPayloads() throws {
    let process = ProcessStamp(pid: 42, startedAtSeconds: 100, startedAtMicroseconds: 5)
    let cases: [(String, String?, Activity, SafeAction)] = [
        ("SessionStart", nil, .starting, .waiting),
        ("UserPromptSubmit", nil, .working, .thinking),
        ("PreToolUse", "Bash", .working, .runningCommand),
        ("PostToolUse", "Bash", .working, .runningCommand),
        ("PostToolUse", nil, .working, .thinking),
        ("PermissionRequest", nil, .needsAttention, .awaitingPermission),
        ("PostToolUseFailure", "Edit", .needsAttention, .failed),
        ("Stop", nil, .idle, .waiting),
        ("SessionEnd", nil, .ended, .waiting),
        ("tool_execution_start", "read", .working, .readingFile),
        ("tool_execution_end", "read", .working, .readingFile),
        ("message_end", nil, .idle, .waiting),
    ]

    for (event, tool, activity, action) in cases {
        var json: [String: Any] = [
            "session_id": "private-session",
            "hook_event_name": event,
            "cwd": "/Users/person/secret-project",
        ]
        json["tool_name"] = tool
        let state = try unwrap(
            HookPayload(json: json).state(agent: .codex, process: process),
            "\(event) should produce state"
        )
        try require(state.activity == activity, "\(event) activity mismatch")
        try require(state.action == action, "\(event) action mismatch")
        try require(state.projectLabel == "secret-project", "project label should be basename only")
    }

    let privatePayload = try HookPayload(json: [
        "session_id": "pi-session",
        "event": "tool_call",
        "cwd": "/tmp/codewindow",
        "tool_name": "edit",
        "input": ["path": "/private/secret.txt", "content": "SENTINEL_SECRET"],
    ])
    let sanitized = try unwrap(privatePayload.state(agent: .pi, process: process), "Pi state missing")
    let text = try unwrap(String(data: JSONEncoder().encode(sanitized), encoding: .utf8), "State is not UTF-8")
    try require(!text.contains("SENTINEL_SECRET"), "raw content leaked")
    try require(!text.contains("/private/secret.txt"), "raw path leaked")
    try require(!text.contains("pi-session"), "external session ID leaked")

    let taskState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/tmp/codewindow",
            "user_prompt": "Please verify the compact agent preview without exposing private output",
        ]).state(agent: .claude, process: process),
        "Task preview state missing"
    )
    try require(taskState.taskPreview == "Please verify the compact agent preview without exposing private output", "Task preview mismatch")
    try require(taskState.feedEvent?.kind == .user, "User prompt was not added to the feed")
    try require(taskState.feedEvent?.text == taskState.taskPreview, "User feed text mismatch")

    let commandState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "Bash",
            "tool_use_id": "tool-123",
            "tool_input": ["command": "OPENAI_API_KEY=sk-example-secret-value swift test\n--filter PreviewTests"],
        ]).state(agent: .claude, process: process, previous: taskState),
        "Command preview state missing"
    )
    try require(commandState.taskPreview == taskState.taskPreview, "Task preview was not carried forward")
    try require(commandState.actionPreview == "OPENAI_API_KEY=•••• swift test --filter PreviewTests", "Command preview was not sanitized")
    try require(commandState.feedEvent?.kind == .toolCall, "Tool call was not added to the feed")
    try require(commandState.feedEvent?.detail == commandState.actionPreview, "Tool feed detail mismatch")
    let commandText = try unwrap(String(data: JSONEncoder().encode(commandState), encoding: .utf8), "Command state is not UTF-8")
    try require(!commandText.contains("sk-example-secret-value"), "Credential leaked into command preview")

    let completedState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PostToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "Bash",
            "tool_use_id": "tool-123",
        ]).state(agent: .claude, process: process, previous: commandState),
        "Tool result state missing"
    )
    try require(completedState.feedEvent?.kind == .toolResult, "Tool result was not added to the feed")
    try require(completedState.feedEvent?.succeeded == true, "Successful tool result was marked failed")
    try require(
        completedState.feedEvent?.operationKey == commandState.feedEvent?.operationKey,
        "Matching tool lifecycle events did not receive the same opaque key"
    )
    try require(completedState.action == .runningCommand, "Finished tool handed the row back to thinking")
    try require(
        completedState.actionPreview == commandState.actionPreview,
        "Finished tool dropped the subject the row was already showing"
    )

    let repeatedInputState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PostToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "Edit",
            "tool_use_id": "tool-124",
            "tool_input": ["file_path": "/Users/person/project/PanelContentView.swift"],
        ]).state(agent: .claude, process: process),
        "Repeated tool input state missing"
    )
    try require(repeatedInputState.action == .editingFile, "Finished edit lost its action")
    try require(
        repeatedInputState.actionPreview == "PanelContentView.swift",
        "Finished edit lost its subject"
    )

    // A finished turn keeps the newest thing that happened on the row. Claude's Stop payload
    // carries no message, and falling back to the task preview would put the prompt that
    // opened the turn back on the row long after the agent moved past it.
    let settledState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "Stop",
            "cwd": "/tmp/codewindow",
        ]).state(agent: .claude, process: process, previous: completedState),
        "Settled state missing"
    )
    try require(settledState.action == .waiting, "Finished turn is not waiting")
    try require(
        settledState.actionPreview == completedState.actionPreview,
        "Finished turn dropped the work and fell back to the prompt"
    )
    try require(settledState.taskPreview == taskState.taskPreview, "Finished turn lost the task preview")

    let settledWithMessageState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "Stop",
            "cwd": "/tmp/codewindow",
            "last_assistant_message": "Reviewed the panel and pushed the fix",
        ]).state(agent: .claude, process: process, previous: completedState),
        "Settled state with a message missing"
    )
    try require(
        settledWithMessageState.actionPreview == "Reviewed the panel and pushed the fix",
        "A closing message should win over the previous subject"
    )

    let failedState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "event": "tool_execution_end",
            "cwd": "/tmp/codewindow",
            "tool_name": "read",
            "is_error": true,
        ]).state(agent: .pi, process: process),
        "Failed tool result state missing"
    )
    try require(failedState.activity == .needsAttention, "Failed Pi tool did not request attention")
    try require(failedState.feedEvent?.succeeded == false, "Failed tool result was marked successful")

    let assistantState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "Stop",
            "cwd": "/tmp/codewindow",
            "last_assistant_message": "Implemented the change using TOKEN=private-value and verified the tests.",
        ]).state(agent: .claude, process: process),
        "Assistant message state missing"
    )
    try require(assistantState.feedEvent?.kind == .assistant, "Assistant reply was not added to the feed")
    try require(
        assistantState.feedEvent?.text == "Implemented the change using TOKEN=•••• and verified the tests.",
        "Assistant reply was not sanitized"
    )

    let longAssistantState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "Stop",
            "cwd": "/tmp/codewindow",
            "last_assistant_message": String(repeating: "a", count: 1_000),
        ]).state(agent: .codex, process: process),
        "Long assistant message state missing"
    )
    try require(longAssistantState.feedEvent?.text.count == 320, "Assistant message was not bounded")

    let readState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "event": "tool_execution_start",
            "cwd": "/tmp/codewindow",
            "tool_name": "read",
            "tool_input": ["path": "/Users/person/private/PanelContentView.swift"],
        ]).state(agent: .pi, process: process),
        "Read preview state missing"
    )
    try require(readState.actionPreview == "PanelContentView.swift", "Read preview should contain only the basename")

    let freeformCommandState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "exec",
            "tool_input": #"const result = await tools.exec_command({cmd:"TOKEN=private-value swift test"});"#,
        ]).state(agent: .codex, process: process),
        "Codex freeform command preview missing"
    )
    try require(freeformCommandState.action == .runningCommand, "Codex exec tool should be a command")
    try require(
        freeformCommandState.actionPreview == "TOKEN=•••• swift test",
        "Codex freeform command was not extracted or sanitized"
    )

    let webSearchState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "web.run",
            "tool_input": ["search_query": [["q": "native macOS floating panel"]]],
        ]).state(agent: .codex, process: process),
        "Nested web search preview missing"
    )
    try require(webSearchState.action == .searching, "Nested query should be shown as a search")
    try require(webSearchState.actionPreview == "native macOS floating panel", "Nested query preview mismatch")

    let navigationState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "steel_navigate",
            "tool_input": ["url": "https://person:password@example.com/docs?page=private#token"],
        ]).state(agent: .claude, process: process),
        "Browser navigation preview missing"
    )
    try require(navigationState.action == .usingTool, "Navigation tool classification mismatch")
    try require(navigationState.actionPreview == "example.com/docs", "URL credentials or query were not removed")

    let directoryState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "event": "tool_execution_start",
            "cwd": "/tmp/codewindow",
            "tool_name": "ls",
            "tool_input": ["path": "/Users/person/private/Sources"],
        ]).state(agent: .pi, process: process),
        "Directory listing preview missing"
    )
    try require(directoryState.action == .readingFile, "Directory listing classification mismatch")
    try require(directoryState.actionPreview == "Sources", "Directory preview should contain only the basename")

    let patchState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "apply_patch",
            "tool_input": "*** Begin Patch\n*** Update File: /Users/person/private/HookPayload.swift\nSENTINEL_PATCH_CONTENT",
        ]).state(agent: .codex, process: process),
        "Patch preview missing"
    )
    try require(patchState.actionPreview == "HookPayload.swift", "Patch preview should show only the file name")
    let patchText = try unwrap(String(data: JSONEncoder().encode(patchState), encoding: .utf8), "Patch state is not UTF-8")
    try require(!patchText.contains("SENTINEL_PATCH_CONTENT"), "Patch content leaked into state")

    let genericToolState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "custom_tool",
            "tool_input": "SENTINEL_TOOL_CONTENT",
        ]).state(agent: .claude, process: process),
        "Generic tool preview missing"
    )
    try require(genericToolState.actionPreview == "custom tool", "Generic tool name was not made readable")
    let genericText = try unwrap(String(data: JSONEncoder().encode(genericToolState), encoding: .utf8), "Generic state is not UTF-8")
    try require(!genericText.contains("SENTINEL_TOOL_CONTENT"), "Unapproved tool input leaked into state")

    for event in ["message_update", "irrelevant_event"] {
        let payload = try HookPayload(json: ["session_id": "id", "event": event])
        try require(payload.state(agent: .claude, process: process) == nil, "\(event) should be ignored")
    }

    let permissionNotification = try HookPayload(json: [
        "session_id": "id",
        "event": "Notification",
        "notification_type": "permission_prompt",
    ])
    let notificationState = try unwrap(
        permissionNotification.state(agent: .claude, process: process),
        "Permission notification should produce state"
    )
    try require(notificationState.activity == .needsAttention, "Permission notification activity mismatch")
    try require(notificationState.action == .awaitingPermission, "Permission notification action mismatch")
}

func testStateFiles() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = try StateFiles.directory(environment: ["CODEWINDOW_STATE_DIR": root.path])
    let process = try unwrap(
        ProcessInspector.stamp(pid: ProcessInfo.processInfo.processIdentifier),
        "Current process stamp missing"
    )
    let state = SessionState(
        sessionKey: "abc123",
        agent: .codex,
        activity: .working,
        projectLabel: "codewindow",
        action: .thinking,
        process: process,
        updatedAt: Date(timeIntervalSince1970: 123)
    )

    try StateFiles.write(state, to: directory)
    let file = directory.appendingPathComponent("abc123.json")
    try require(StateFiles.read(from: file) == state, "State did not round trip")
    let directoryMode = try unwrap(
        FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber,
        "Directory permissions missing"
    )
    let fileMode = try unwrap(
        FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber,
        "File permissions missing"
    )
    try require(directoryMode.intValue & 0o777 == 0o700, "State directory is not 0700")
    try require(fileMode.intValue & 0o777 == 0o600, "State file is not 0600")
    let stateByteCount = try Data(contentsOf: file).count
    try require(stateByteCount < 1_024, "State exceeds 1KB")

    let boundedFeedState = try unwrap(
        HookPayload(json: [
            "session_id": "bounded-feed",
            "hook_event_name": "Stop",
            "cwd": "/tmp/codewindow",
            "last_assistant_message": String(repeating: "a", count: 1_000),
        ]).state(
            agent: .codex,
            process: process,
            previous: SessionState(
                sessionKey: "bounded-feed",
                agent: .codex,
                activity: .working,
                projectLabel: "codewindow",
                action: .thinking,
                taskPreview: String(repeating: "t", count: 96),
                process: process
            )
        ),
        "Bounded feed state missing"
    )
    try StateFiles.write(boundedFeedState, to: directory)
    let boundedFeedFile = directory.appendingPathComponent("\(boundedFeedState.sessionKey).json")
    let boundedFeedByteCount = try Data(contentsOf: boundedFeedFile).count
    try require(
        boundedFeedByteCount <= StateFiles.maximumStateBytes,
        "Largest feed state exceeds the file limit"
    )

    let emojiTaskState = try unwrap(
        HookPayload(json: [
            "session_id": "emoji-feed",
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/tmp/codewindow",
            "user_prompt": String(repeating: "🤖", count: 1_000),
        ]).state(agent: .codex, process: process),
        "Emoji feed state missing"
    )
    try StateFiles.write(emojiTaskState, to: directory)
    let emojiFeedFile = directory.appendingPathComponent("\(emojiTaskState.sessionKey).json")
    let emojiFeedByteCount = try Data(contentsOf: emojiFeedFile).count
    try require(
        emojiFeedByteCount <= StateFiles.maximumStateBytes,
        "Multi-byte feed state exceeds the file limit"
    )
    try require(ProcessInspector.isCurrent(process), "Current process identity rejected")
    let impossible = ProcessStamp(pid: process.pid, startedAtSeconds: 0, startedAtMicroseconds: 0)
    try require(!ProcessInspector.isCurrent(impossible), "PID reuse guard accepted wrong start time")
    try require(ProcessInspector.stamp(pid: Int32.max) == nil, "Impossible PID accepted")
}

func testInstallationAnalytics() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let support = root.appendingPathComponent("CodeWindow", isDirectory: true)
    let host = try unwrap(URL(string: "https://us.i.posthog.com"), "PostHog host URL is invalid")
    var requests: [(URL, Data)] = []

    let first = try InstallationAnalytics.captureIfNeeded(
        supportDirectory: support,
        apiKey: "phc_test_project_token",
        apiHost: host,
        releaseVersion: "1.2.3",
        architecture: "arm64"
    ) { endpoint, body in
        requests.append((endpoint, body))
        return true
    }
    try require(first == .sent, "First installation event was not sent")
    try require(requests.count == 1, "First install did not produce exactly one request")
    try require(requests[0].0.absoluteString == "https://us.i.posthog.com/i/v0/e/", "Capture endpoint mismatch")
    let payload = try unwrap(
        JSONSerialization.jsonObject(with: requests[0].1) as? [String: Any],
        "Installation analytics payload is invalid"
    )
    try require(payload["api_key"] as? String == "phc_test_project_token", "Project token missing")
    try require(payload["event"] as? String == InstallationAnalytics.eventName, "Event name mismatch")
    let identifier = try unwrap(payload["distinct_id"] as? String, "Anonymous installation ID missing")
    try require(UUID(uuidString: identifier) != nil, "Installation ID is not anonymous UUID data")
    let properties = try unwrap(payload["properties"] as? [String: Any], "Event properties missing")
    try require(properties["release_version"] as? String == "1.2.3", "Release version missing")
    try require(properties["platform"] as? String == "macOS", "Platform missing")
    try require(properties["architecture"] as? String == "arm64", "Architecture missing")
    try require(properties["$process_person_profile"] as? Bool == false, "Event creates a person profile")

    let second = try InstallationAnalytics.captureIfNeeded(
        supportDirectory: support,
        apiKey: "phc_test_project_token",
        apiHost: host,
        releaseVersion: "1.2.3",
        architecture: "arm64"
    ) { endpoint, body in
        requests.append((endpoint, body))
        return true
    }
    try require(second == .alreadySent, "Repeat install was counted twice")
    try require(requests.count == 1, "Repeat install sent another request")

    try FileManager.default.removeItem(at: support)
    let reinstalled = try InstallationAnalytics.captureIfNeeded(
        supportDirectory: support,
        apiKey: "phc_test_project_token",
        apiHost: host,
        releaseVersion: "1.2.3",
        architecture: "arm64"
    ) { endpoint, body in
        requests.append((endpoint, body))
        return true
    }
    try require(reinstalled == .sent, "Clean reinstall was not counted")
    let reinstalledPayload = try unwrap(
        JSONSerialization.jsonObject(with: requests[1].1) as? [String: Any],
        "Reinstall analytics payload is invalid"
    )
    try require(
        reinstalledPayload["distinct_id"] as? String != identifier,
        "Clean reinstall reused the removed anonymous installation ID"
    )

    let failedSupport = root.appendingPathComponent("Failed", isDirectory: true)
    var retryIdentifiers: [String] = []
    for shouldSucceed in [false, true] {
        let result = try InstallationAnalytics.captureIfNeeded(
            supportDirectory: failedSupport,
            apiKey: "phc_test_project_token",
            apiHost: host,
            releaseVersion: "1.2.3",
            architecture: "arm64"
        ) { _, body in
            let body = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            if let id = body?["distinct_id"] as? String { retryIdentifiers.append(id) }
            return shouldSucceed
        }
        try require(result == (shouldSucceed ? .sent : .failed), "Failed capture retry result mismatch")
    }
    try require(retryIdentifiers.count == 2, "Failed capture was not retried")
    try require(retryIdentifiers[0] == retryIdentifiers[1], "Capture retry changed its anonymous ID")
}

func testTerminalAgentDiscovery() throws {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let discovered = ProcessInspector.terminalAgentProcesses()
    try require(!discovered.contains { $0.process.pid == currentPID }, "Non-terminal test process was discovered")
    try require(discovered.allSatisfy { !$0.projectLabel.contains("/") }, "Discovery exposed a full working directory")
    try require(
        ProcessInspector.findAgentProcess(agent: .pi, startingAt: currentPID) == nil,
        "Short agent name matched an unrelated executable path"
    )
    try require(
        ProcessInspector.agentKind(
            executablePath: "/Users/person/.local/share/claude/versions/2.1.233"
        ) == .claude,
        "Version-named native Claude executable was not recognized"
    )
    try require(
        ProcessInspector.agentKind(executablePath: "/tmp/claude/versions/not-a-version") == nil,
        "Unrelated executable under a similar path was identified as Claude"
    )
}

func testHighestAgentPIDs() throws {
    let parentByPID: [Int32: Int32] = [
        100: 1,
        110: 100,
        120: 110,
        200: 1,
        210: 200,
    ]
    let agentByPID: [Int32: AgentKind] = [
        100: .codex,
        110: .codex,
        120: .codex,
        200: .claude,
        210: .pi,
    ]
    let roots = ProcessInspector.highestAgentPIDs(
        parentByPID: parentByPID,
        agentByPID: agentByPID
    )
    try require(
        roots == Set<Int32>([100, 200, 210]),
        "Nested same-agent PIDs were not collapsed while different agents remained"
    )
}

func testApplicationOwnership() throws {
    let parentByPID: [Int32: Int32] = [
        300: 200,
        200: 100,
        100: 1,
        400: 350,
        350: 1,
        500: 1,
        600: 601,
        601: 600,
    ]
    let executableByPID: [Int32: String] = [
        350: "/Applications/Warp.app/Contents/Helpers/warp-terminal-server",
        500: "/Applications/Warp.app.backup/Contents/MacOS/Warp",
    ]
    func belongs(processPID: Int32, applicationPID: Int32, bundlePath: String? = nil) -> Bool {
        ProcessInspector.processBelongsToApplication(
            processPID: processPID,
            applicationPID: applicationPID,
            bundlePath: bundlePath,
            parentPID: { parentByPID[$0] },
            executablePath: { executableByPID[$0] ?? "" }
        )
    }

    try require(belongs(processPID: 300, applicationPID: 100), "Direct terminal ancestry was not matched")
    try require(
        belongs(processPID: 400, applicationPID: 999, bundlePath: "/Applications/Warp.app"),
        "Bundled terminal helper was not matched"
    )
    try require(
        !belongs(processPID: 500, applicationPID: 100, bundlePath: "/Applications/Warp.app"),
        "Similar application path produced a false match"
    )
    try require(!belongs(processPID: 600, applicationPID: 100), "Cyclic ancestry did not terminate")
}

func testHookInstaller() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let reporter = root.appendingPathComponent("source-reporter")
    try Data("reporter".utf8).write(to: reporter)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
    let home = root.appendingPathComponent("home")
    let locations = InstallLocations(
        home: home,
        reporterSource: reporter,
        codexHomes: [
            home.appendingPathComponent(".codex"),
            home.appendingPathComponent(".codex-work"),
        ]
    )
    let original: [String: Any] = [
        "model": "keep-me",
        "hooks": [
            "SessionStart": [[
                "matcher": "*",
                "hooks": [["type": "command", "command": "/usr/bin/existing-hook"]],
            ]],
        ],
    ]
    try writeJSON(original, to: locations.claudeConfiguration)
    for configuration in locations.codexConfigurations {
        try writeJSON(original, to: configuration)
    }
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o640],
        ofItemAtPath: locations.claudeConfiguration.path
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: locations.codexConfiguration.path
    )
    try FileManager.default.createDirectory(
        at: locations.legacyPiExtension.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("\(HookInstaller.piMarker)\nlegacy managed extension\n".utf8)
        .write(to: locations.legacyPiExtension)

    let first = try HookInstaller.install(at: locations)
    try require(!first.changed.isEmpty, "First install changed nothing")
    try require(HookInstaller.isInstalled(at: locations), "Install status is false")
    let installedCodex = try readJSON(locations.codexConfiguration)
    let installedClaude = try readJSON(locations.claudeConfiguration)
    try require(installedCodex["model"] as? String == "keep-me", "Codex config field lost")
    try require(installedClaude["model"] as? String == "keep-me", "Claude config field lost")
    let codexHooks = try unwrap(installedCodex["hooks"] as? [String: Any], "Codex hooks missing")
    let secondCodex = try readJSON(locations.codexConfigurations[1])
    let secondCodexHooks = try unwrap(secondCodex["hooks"] as? [String: Any], "Second Codex profile hooks missing")
    let claudeHooks = try unwrap(installedClaude["hooks"] as? [String: Any], "Claude hooks missing")
    try require(codexHooks["PostToolUse"] != nil, "Codex tool completion hook missing")
    try require(secondCodexHooks["PostToolUse"] != nil, "Second Codex profile tool hook missing")
    try require(claudeHooks["PostToolUseFailure"] != nil, "Claude tool failure hook missing")
    try require(claudeHooks["Notification"] != nil, "Claude notification hook missing")
    let installedCodexMode = try unwrap(
        FileManager.default.attributesOfItem(atPath: locations.codexConfiguration.path)[.posixPermissions]
            as? NSNumber,
        "Installed Codex config permissions missing"
    )
    let installedClaudeMode = try unwrap(
        FileManager.default.attributesOfItem(atPath: locations.claudeConfiguration.path)[.posixPermissions]
            as? NSNumber,
        "Installed Claude config permissions missing"
    )
    try require(installedCodexMode.intValue & 0o777 == 0o644, "Codex config permissions changed")
    try require(installedClaudeMode.intValue & 0o777 == 0o640, "Claude config permissions changed")
    let piExtension = try String(contentsOf: locations.piExtension, encoding: .utf8)
    try require(piExtension.contains("tool_execution_start"), "Pi tool start hook missing")
    try require(piExtension.contains("before_agent_start"), "Pi task preview hook missing")
    try require(piExtension.contains("event.args"), "Pi tool arguments are not forwarded for sanitization")
    try require(piExtension.contains("tool_execution_end"), "Pi tool completion hook missing")
    try require(piExtension.contains("event.isError"), "Pi tool failures are not forwarded")
    try require(piExtension.contains("message_end"), "Pi assistant message hook missing")
    try require(piExtension.contains("last_assistant_message"), "Pi assistant text is not forwarded")
    try require(piExtension.contains(#"part?.type === "text""#), "Pi visible text is not isolated from reasoning")
    try require(piExtension.contains(#".join("\n")"#), "Pi extension contains an invalid newline literal")
    try require(!piExtension.contains("import type"), "Pi extension still depends on TypeScript type imports")
    try require(locations.piExtension.pathExtension == "js", "Pi extension is not plain JavaScript")
    try require(
        !FileManager.default.fileExists(atPath: locations.legacyPiExtension.path),
        "Broken legacy Pi extension was not migrated"
    )
    try require(!piExtension.contains("pi.on(\"tool_call\""), "Legacy Pi tool hook remains")

    let second = try HookInstaller.install(at: locations)
    try require(second.changed.isEmpty, "Second install was not idempotent")

    // An app update replaces the bundled reporter, not the copy the agents execute.
    try require(HookInstaller.isUpToDate(at: locations), "Fresh install reports itself out of date")
    try Data("newer reporter".utf8).write(to: reporter)
    try require(!HookInstaller.isUpToDate(at: locations), "A superseded reporter reports itself current")
    let refreshed = try HookInstaller.install(at: locations)
    try require(refreshed.changed == [locations.installedReporter], "Refresh did not rewrite the reporter")
    try require(HookInstaller.isUpToDate(at: locations), "Refresh left the reporter behind")
    try require(
        (try? Data(contentsOf: locations.installedReporter)) == Data("newer reporter".utf8),
        "Installed reporter still holds the superseded build"
    )

    try Data("\(HookInstaller.piMarker)\nsuperseded extension\n".utf8).write(to: locations.piExtension)
    try require(!HookInstaller.isUpToDate(at: locations), "A superseded Pi extension reports itself current")
    _ = try HookInstaller.install(at: locations)
    try require(HookInstaller.isUpToDate(at: locations), "Refresh left the Pi extension behind")
    _ = try HookInstaller.uninstall(at: locations)
    try require(!HookInstaller.isInstalled(at: locations), "Uninstall status is true")
    let finalCodex = try readJSON(locations.codexConfiguration)
    let finalSecondCodex = try readJSON(locations.codexConfigurations[1])
    let finalClaude = try readJSON(locations.claudeConfiguration)
    try require(NSDictionary(dictionary: finalCodex).isEqual(to: original), "Codex config did not round trip")
    try require(
        NSDictionary(dictionary: finalSecondCodex).isEqual(to: original),
        "Second Codex profile did not round trip"
    )
    try require(NSDictionary(dictionary: finalClaude).isEqual(to: original), "Claude config did not round trip")
    try require(!FileManager.default.fileExists(atPath: locations.piExtension.path), "Pi extension remains")
    try require(!FileManager.default.fileExists(atPath: locations.legacyPiExtension.path), "Legacy Pi extension remains")
    try require(!FileManager.default.fileExists(atPath: locations.installedReporter.path), "Reporter remains")
    try require(!FileManager.default.fileExists(atPath: locations.supportDirectory.path), "Support directory remains")
}

func testCodexProfileDiscovery() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let standard = home.appendingPathComponent(".codex", isDirectory: true)
    let active = home.appendingPathComponent(".codex-mertdev", isDirectory: true)
    let backup = home.appendingPathComponent(".codex-backup-2025", isDirectory: true)
    let incomplete = home.appendingPathComponent(".codex-empty", isDirectory: true)
    for directory in [standard, active, backup, incomplete] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    for directory in [standard, active, backup] {
        try Data("model = \"test\"\n".utf8).write(to: directory.appendingPathComponent("config.toml"))
    }

    let locations = InstallLocations.detectingCodexProfiles(
        home: home,
        reporterSource: root.appendingPathComponent("reporter"),
        environment: ["CODEX_HOME": active.path]
    )
    let discovered = Set(locations.codexHomes.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    let expected = Set([standard, active].map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    try require(discovered == expected, "Codex profile discovery was not safely scoped")
    try require(locations.codexHomes.count == 2, "Codex profile discovery did not deduplicate CODEX_HOME")

    let normalized = InstallLocations(home: home, reporterSource: locations.reporterSource, codexHomes: [])
    try require(normalized.codexHomes.count == 1, "Empty Codex profile input was not normalized")
}

func testInstallRollback() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let reporter = root.appendingPathComponent("source-reporter")
    try Data("new reporter".utf8).write(to: reporter)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
    let locations = InstallLocations(home: root.appendingPathComponent("home"), reporterSource: reporter)
    let codexOriginal: [String: Any] = ["model": "codex-model"]
    let claudeOriginal: [String: Any] = ["model": "claude-model"]
    try writeJSON(codexOriginal, to: locations.codexConfiguration)
    try writeJSON(claudeOriginal, to: locations.claudeConfiguration)
    let originalCodexData = try Data(contentsOf: locations.codexConfiguration)

    let claudeDirectory = locations.claudeConfiguration.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: claudeDirectory.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: claudeDirectory.path)
    }

    let writeProbe = claudeDirectory.appendingPathComponent("write-probe")
    var permissionsBlockWrites = false
    do {
        try Data().write(to: writeProbe, options: .withoutOverwriting)
        try? FileManager.default.removeItem(at: writeProbe)
    } catch {
        permissionsBlockWrites = true
    }
    try require(permissionsBlockWrites, "Directory permissions do not block writes on this machine")

    do {
        _ = try HookInstaller.install(at: locations)
        throw TestFailure.assertion("Install unexpectedly succeeded with an unwritable Claude directory")
    } catch is TestFailure {
        throw TestFailure.assertion("Install unexpectedly succeeded with an unwritable Claude directory")
    } catch {
        try require(
            !FileManager.default.fileExists(atPath: locations.installedReporter.path),
            "Reporter was not removed during rollback"
        )
        let restoredCodexData = try Data(contentsOf: locations.codexConfiguration)
        try require(
            restoredCodexData == originalCodexData,
            "Codex configuration was not restored byte for byte"
        )
        try require(
            !FileManager.default.fileExists(atPath: locations.piExtension.path),
            "Pi extension was created despite rollback"
        )
        try require(
            !FileManager.default.fileExists(atPath: locations.legacyPiExtension.path),
            "Legacy Pi extension was created despite rollback"
        )
        let restoredClaude = try readJSON(locations.claudeConfiguration)
        try require(
            NSDictionary(dictionary: restoredClaude).isEqual(to: claudeOriginal),
            "Claude configuration changed"
        )
    }
}

func testCleanUninstall() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let reporter = root.appendingPathComponent("source-reporter")
    try Data("reporter".utf8).write(to: reporter)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
    let home = root.appendingPathComponent("home")
    let locations = InstallLocations(home: home, reporterSource: reporter)

    let untouched = try HookInstaller.uninstall(at: locations)
    try require(untouched.changed.isEmpty, "Uninstall changed a home without CodeWindow hooks")

    _ = try HookInstaller.install(at: locations)
    let unrelatedPiExtension = locations.piExtension
        .deletingLastPathComponent()
        .appendingPathComponent("unrelated-extension.js")
    try Data("export default function () {}\n".utf8).write(to: unrelatedPiExtension)
    let analyticsMarker = locations.supportDirectory.appendingPathComponent(".installation-analytics-sent")
    let stateDirectory = locations.supportDirectory.appendingPathComponent("State", isDirectory: true)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    try Data("sent\n".utf8).write(to: analyticsMarker)
    try Data("{}\n".utf8).write(to: stateDirectory.appendingPathComponent("stale.json"))
    let legacyCodexBackup = locations.codexConfiguration
        .deletingLastPathComponent()
        .appendingPathComponent("hooks.json.codewindow-backup")
    let legacyClaudeBackup = locations.claudeConfiguration
        .deletingLastPathComponent()
        .appendingPathComponent("settings.json.codewindow-backup-old")
    try Data("legacy".utf8).write(to: legacyCodexBackup)
    try Data("legacy".utf8).write(to: legacyClaudeBackup)

    _ = try HookInstaller.uninstall(at: locations)
    for url in [
        locations.codexConfiguration,
        locations.claudeConfiguration,
        locations.piExtension,
        locations.legacyPiExtension,
        locations.installedReporter,
        locations.supportDirectory,
        legacyCodexBackup,
        legacyClaudeBackup,
    ] {
        try require(!FileManager.default.fileExists(atPath: url.path), "Uninstall left \(url.lastPathComponent)")
    }
    try require(!HookInstaller.isInstalled(at: locations), "Fresh uninstall still reports installed")
    try require(
        FileManager.default.fileExists(atPath: unrelatedPiExtension.path),
        "Uninstall removed an unrelated Pi extension"
    )
}

func testForeignPiExtension() throws {
    for useLegacyPath in [false, true] {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reporter = root.appendingPathComponent("reporter")
        try Data("reporter".utf8).write(to: reporter)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
        let locations = InstallLocations(home: root.appendingPathComponent("home"), reporterSource: reporter)
        let foreignExtension = useLegacyPath ? locations.legacyPiExtension : locations.piExtension
        try FileManager.default.createDirectory(
            at: foreignExtension.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("foreign content".utf8).write(to: foreignExtension)

        do {
            _ = try HookInstaller.install(at: locations)
            throw TestFailure.assertion("Foreign Pi extension was overwritten")
        } catch is InstallerError {
            let content = try String(contentsOf: foreignExtension, encoding: .utf8)
            try require(content == "foreign content", "Foreign Pi extension changed")
            try require(!FileManager.default.fileExists(atPath: locations.installedReporter.path), "Reporter installed before Pi preflight")
            try require(!FileManager.default.fileExists(atPath: locations.codexConfiguration.path), "Codex config changed before Pi preflight")
            try require(!FileManager.default.fileExists(atPath: locations.claudeConfiguration.path), "Claude config changed before Pi preflight")
        }
    }
}

func testUnexpectedHookStructure() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let reporter = root.appendingPathComponent("reporter")
    try Data("reporter".utf8).write(to: reporter)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
    let locations = InstallLocations(home: root.appendingPathComponent("home"), reporterSource: reporter)
    let unexpected: [String: Any] = ["hooks": ["SessionStart": "do-not-replace"]]
    try writeJSON(unexpected, to: locations.codexConfiguration)

    do {
        _ = try HookInstaller.install(at: locations)
        throw TestFailure.assertion("Unexpected hook structure was overwritten")
    } catch is InstallerError {
        let unchanged = try readJSON(locations.codexConfiguration)
        try require(NSDictionary(dictionary: unchanged).isEqual(to: unexpected), "Unexpected hook structure changed")
        try require(!FileManager.default.fileExists(atPath: locations.installedReporter.path), "Reporter installed before hook preflight")
        try require(!FileManager.default.fileExists(atPath: locations.claudeConfiguration.path), "Claude config changed before hook preflight")
    }
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
}

func readJSON(_ url: URL) throws -> [String: Any] {
    try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], "Invalid JSON at \(url.path)")
}

let tests: [(String, () throws -> Void)] = [
    ("inspector placement", testInspectorPlacement),
    ("session feed", testSessionFeed),
    ("hook payloads", testHookPayloads),
    ("state files", testStateFiles),
    ("installation analytics", testInstallationAnalytics),
    ("terminal agent discovery", testTerminalAgentDiscovery),
    ("highest agent PIDs", testHighestAgentPIDs),
    ("terminal application ownership", testApplicationOwnership),
    ("Codex profile discovery", testCodexProfileDiscovery),
    ("hook installer", testHookInstaller),
    ("install rollback", testInstallRollback),
    ("clean uninstall", testCleanUninstall),
    ("foreign Pi extension", testForeignPiExtension),
    ("unexpected hook structure", testUnexpectedHookStructure),
]

do {
    for (name, test) in tests {
        try test()
        print("PASS \(name)")
    }
    print("PASS all \(tests.count) test groups")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
