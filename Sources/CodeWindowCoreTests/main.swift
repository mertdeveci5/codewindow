@testable import CodeWindowCore
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

func testHookPayloads() throws {
    let process = ProcessStamp(pid: 42, startedAtSeconds: 100, startedAtMicroseconds: 5)
    let cases: [(String, String?, Activity, SafeAction)] = [
        ("SessionStart", nil, .starting, .waiting),
        ("UserPromptSubmit", nil, .working, .thinking),
        ("PreToolUse", "Bash", .working, .runningCommand),
        ("PostToolUse", "Bash", .working, .thinking),
        ("PermissionRequest", nil, .needsAttention, .awaitingPermission),
        ("PostToolUseFailure", "Edit", .needsAttention, .failed),
        ("Stop", nil, .idle, .waiting),
        ("SessionEnd", nil, .ended, .waiting),
        ("tool_execution_start", "read", .working, .readingFile),
        ("tool_execution_end", "read", .working, .thinking),
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

    let commandState = try unwrap(
        HookPayload(json: [
            "session_id": "preview-session",
            "hook_event_name": "PreToolUse",
            "cwd": "/tmp/codewindow",
            "tool_name": "Bash",
            "tool_input": ["command": "OPENAI_API_KEY=sk-example-secret-value swift test\n--filter PreviewTests"],
        ]).state(agent: .claude, process: process, previousTaskPreview: taskState.taskPreview),
        "Command preview state missing"
    )
    try require(commandState.taskPreview == taskState.taskPreview, "Task preview was not carried forward")
    try require(commandState.actionPreview == "OPENAI_API_KEY=•••• swift test --filter PreviewTests", "Command preview was not sanitized")
    let commandText = try unwrap(String(data: JSONEncoder().encode(commandState), encoding: .utf8), "Command state is not UTF-8")
    try require(!commandText.contains("sk-example-secret-value"), "Credential leaked into command preview")

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
    try require(ProcessInspector.isCurrent(process), "Current process identity rejected")
    let impossible = ProcessStamp(pid: process.pid, startedAtSeconds: 0, startedAtMicroseconds: 0)
    try require(!ProcessInspector.isCurrent(impossible), "PID reuse guard accepted wrong start time")
    try require(ProcessInspector.stamp(pid: Int32.max) == nil, "Impossible PID accepted")
}

func testAppVersions() throws {
    let current = try unwrap(AppVersion("0.1.2"), "Current version was rejected")
    let newer = try unwrap(AppVersion("v0.1.10"), "Tagged version was rejected")
    let equivalent = try unwrap(AppVersion("0.1.2.0"), "Equivalent version was rejected")

    try require(newer > current, "Numeric components were compared lexically")
    try require(current == equivalent, "Trailing zero changed version equality")
    try require(AppVersion("1.0-beta") == nil, "Prerelease text was accepted")
    try require(AppVersion("1..0") == nil, "Empty version component was accepted")
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
    let locations = InstallLocations(home: root.appendingPathComponent("home"), reporterSource: reporter)
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
    try writeJSON(original, to: locations.codexConfiguration)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o640],
        ofItemAtPath: locations.claudeConfiguration.path
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: locations.codexConfiguration.path
    )

    let first = try HookInstaller.install(at: locations)
    try require(!first.changed.isEmpty, "First install changed nothing")
    try require(HookInstaller.isInstalled(at: locations), "Install status is false")
    let installedCodex = try readJSON(locations.codexConfiguration)
    let installedClaude = try readJSON(locations.claudeConfiguration)
    try require(installedCodex["model"] as? String == "keep-me", "Codex config field lost")
    try require(installedClaude["model"] as? String == "keep-me", "Claude config field lost")
    let codexHooks = try unwrap(installedCodex["hooks"] as? [String: Any], "Codex hooks missing")
    let claudeHooks = try unwrap(installedClaude["hooks"] as? [String: Any], "Claude hooks missing")
    try require(codexHooks["PostToolUse"] != nil, "Codex tool completion hook missing")
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
    try require(!piExtension.contains("pi.on(\"tool_call\""), "Legacy Pi tool hook remains")

    let second = try HookInstaller.install(at: locations)
    try require(second.changed.isEmpty, "Second install was not idempotent")
    _ = try HookInstaller.uninstall(at: locations)
    try require(!HookInstaller.isInstalled(at: locations), "Uninstall status is true")
    let finalCodex = try readJSON(locations.codexConfiguration)
    let finalClaude = try readJSON(locations.claudeConfiguration)
    try require(NSDictionary(dictionary: finalCodex).isEqual(to: original), "Codex config did not round trip")
    try require(NSDictionary(dictionary: finalClaude).isEqual(to: original), "Claude config did not round trip")
    try require(!FileManager.default.fileExists(atPath: locations.piExtension.path), "Pi extension remains")
    try require(!FileManager.default.fileExists(atPath: locations.installedReporter.path), "Reporter remains")
    try require(!FileManager.default.fileExists(atPath: locations.supportDirectory.path), "Support directory remains")
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
        locations.installedReporter,
        locations.supportDirectory,
        legacyCodexBackup,
        legacyClaudeBackup,
    ] {
        try require(!FileManager.default.fileExists(atPath: url.path), "Uninstall left \(url.lastPathComponent)")
    }
    try require(!HookInstaller.isInstalled(at: locations), "Fresh uninstall still reports installed")
}

func testForeignPiExtension() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let reporter = root.appendingPathComponent("reporter")
    try Data("reporter".utf8).write(to: reporter)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: reporter.path)
    let locations = InstallLocations(home: root.appendingPathComponent("home"), reporterSource: reporter)
    try FileManager.default.createDirectory(at: locations.piExtension.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("foreign content".utf8).write(to: locations.piExtension)

    do {
        _ = try HookInstaller.install(at: locations)
        throw TestFailure.assertion("Foreign Pi extension was overwritten")
    } catch is InstallerError {
        let content = try String(contentsOf: locations.piExtension, encoding: .utf8)
        try require(content == "foreign content", "Foreign Pi extension changed")
        try require(!FileManager.default.fileExists(atPath: locations.installedReporter.path), "Reporter installed before Pi preflight")
        try require(!FileManager.default.fileExists(atPath: locations.codexConfiguration.path), "Codex config changed before Pi preflight")
        try require(!FileManager.default.fileExists(atPath: locations.claudeConfiguration.path), "Claude config changed before Pi preflight")
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
    ("hook payloads", testHookPayloads),
    ("state files", testStateFiles),
    ("app versions", testAppVersions),
    ("terminal agent discovery", testTerminalAgentDiscovery),
    ("highest agent PIDs", testHighestAgentPIDs),
    ("terminal application ownership", testApplicationOwnership),
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
