import Darwin
import Foundation

public struct InstallLocations: Sendable {
    public let home: URL
    public let reporterSource: URL
    public let codexHomes: [URL]

    public init(home: URL, reporterSource: URL, codexHomes: [URL]? = nil) {
        self.home = home
        self.reporterSource = reporterSource
        self.codexHomes = codexHomes.flatMap { $0.isEmpty ? nil : $0 }
            ?? [home.appendingPathComponent(".codex", isDirectory: true)]
    }

    public static func detectingCodexProfiles(
        home: URL,
        reporterSource: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> InstallLocations {
        var candidates: [URL] = []
        if let configuredHome = environment["CODEX_HOME"], !configuredHome.isEmpty {
            let expanded = (configuredHome as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, relativeTo: home).standardizedFileURL
            candidates.append(url)
        }

        candidates.append(home.appendingPathComponent(".codex", isDirectory: true))
        let profileKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: Array(profileKeys)
        )) ?? []
        candidates.append(contentsOf: profiles
            .filter { url in
                let prefix = ".codex-"
                guard url.lastPathComponent.hasPrefix(prefix) else { return false }
                let label = url.lastPathComponent.dropFirst(prefix.count).lowercased()
                let archivedLabels = ["backup", "backups", "old", "archive", "archived"]
                guard !archivedLabels.contains(where: { label == $0 || label.hasPrefix("\($0)-") }) else {
                    return false
                }
                guard let values = try? url.resourceValues(forKeys: profileKeys),
                      values.isDirectory == true,
                      values.isSymbolicLink != true
                else { return false }
                return FileManager.default.fileExists(
                    atPath: url.appendingPathComponent("config.toml").path
                )
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent })

        var seen: Set<String> = []
        let codexHomes = candidates.compactMap { candidate -> URL? in
            let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
            return seen.insert(canonical.path).inserted ? canonical : nil
        }
        return InstallLocations(home: home, reporterSource: reporterSource, codexHomes: codexHomes)
    }

    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/CodeWindow", isDirectory: true)
    }

    public var installedReporter: URL {
        supportDirectory.appendingPathComponent("bin/codewindow-report")
    }

    public var codexConfigurations: [URL] {
        codexHomes.map { $0.appendingPathComponent("hooks.json") }
    }

    public var codexConfiguration: URL {
        codexConfigurations[0]
    }

    public var claudeConfiguration: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    public var piExtension: URL {
        home.appendingPathComponent(".pi/agent/extensions/codewindow.js")
    }

    public var legacyPiExtension: URL {
        home.appendingPathComponent(".pi/agent/extensions/codewindow.ts")
    }
}

public struct InstallationResult: Sendable {
    public let changed: [URL]
}

public enum HookInstaller {
    public static let piMarker = "// CodeWindow managed extension"

    static let codexEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop",
        "Interrupt", "SessionEnd",
    ]
    private static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]

    /// How long a permission prompt may wait in the inbox before the agent falls back to its own
    /// prompt in the terminal.
    public static let inboxPermissionTimeout = 3_600

    /// One command a configuration must carry for one event, with its exact attributes.
    struct HookEntry {
        let event: String
        let handler: [String: Any]

        var command: String { handler["command"] as? String ?? "" }
    }

    static func reporterCommand(_ locations: InstallLocations, agent: AgentKind) -> String {
        "\(shellQuote(locations.installedReporter.path)) --agent \(agent.rawValue)"
    }

    static func inboxCommand(_ locations: InstallLocations, agent: AgentKind) -> String {
        reporterCommand(locations, agent: agent) + " --inbox"
    }

    /// Every command CodeWindow owns in an agent's configuration.
    public static func ownedCommands(_ locations: InstallLocations, agent: AgentKind) -> Set<String> {
        [reporterCommand(locations, agent: agent), inboxCommand(locations, agent: agent)]
    }

    /// Reporting hooks only record state and must never slow the agent down. The inbox hooks are
    /// the ones that wait: they return at once while inbox mode is off, and otherwise hold the
    /// session until the user answers.
    static func codexEntries(_ locations: InstallLocations) -> [HookEntry] {
        let report = reporterCommand(locations, agent: .codex)
        let inbox = inboxCommand(locations, agent: .codex)
        return codexEvents.map {
            HookEntry(event: $0, handler: ["type": "command", "command": report, "timeout": 2])
        } + [
            // Codex replies are queued through its app server, so the turn-end hook only files
            // the item and returns.
            HookEntry(event: "Stop", handler: ["type": "command", "command": inbox, "timeout": 5]),
            HookEntry(event: "PermissionRequest", handler: [
                "type": "command",
                "command": inbox,
                "timeout": inboxPermissionTimeout,
                "statusMessage": "Waiting for your answer in the CodeWindow inbox",
            ]),
        ]
    }

    static func claudeEntries(_ locations: InstallLocations) -> [HookEntry] {
        let report = reporterCommand(locations, agent: .claude)
        let inbox = inboxCommand(locations, agent: .claude)
        return claudeEvents.map {
            HookEntry(event: $0, handler: ["type": "command", "command": report, "timeout": 2])
        } + [
            // A background Stop hook leaves the terminal free while it waits, and wakes the
            // session with the reply when the user answers from the inbox.
            HookEntry(event: "Stop", handler: [
                "type": "command",
                "command": inbox,
                "async": true,
                "asyncRewake": true,
            ]),
            HookEntry(event: "PermissionRequest", handler: [
                "type": "command",
                "command": inbox,
                "timeout": inboxPermissionTimeout,
            ]),
        ]
    }

    public static func install(at locations: InstallLocations) throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(atPath: locations.reporterSource.path) else {
            throw InstallerError.reporterMissing
        }
        for configuration in locations.codexConfigurations {
            try preflightConfiguration(at: configuration, events: events(of: codexEntries(locations)))
        }
        try preflightConfiguration(at: locations.claudeConfiguration, events: events(of: claudeEntries(locations)))
        try preflightPiExtension(at: locations.piExtension)
        try preflightPiExtension(at: locations.legacyPiExtension)

        return try withRollback(at: installationTargets(locations)) {
            try installPrepared(at: locations)
        }
    }

    private static func installPrepared(at locations: InstallLocations) throws -> InstallationResult {
        var changed: [URL] = []
        if try installReporter(at: locations) { changed.append(locations.installedReporter) }

        for configuration in locations.codexConfigurations {
            if try updateConfiguration(
                at: configuration,
                entries: codexEntries(locations),
                operation: .install
            ) {
                changed.append(configuration)
            }
        }

        if try updateConfiguration(
            at: locations.claudeConfiguration,
            entries: claudeEntries(locations),
            operation: .install
        ) {
            changed.append(locations.claudeConfiguration)
        }

        changed.append(contentsOf: try installPiExtension(at: locations))
        return InstallationResult(changed: changed)
    }

    public static func uninstall(at locations: InstallLocations) throws -> InstallationResult {
        for configuration in locations.codexConfigurations {
            try preflightConfiguration(at: configuration, events: events(of: codexEntries(locations)))
        }
        try preflightConfiguration(at: locations.claudeConfiguration, events: events(of: claudeEntries(locations)))

        return try withRollback(at: installationTargets(locations)) {
            try uninstallPrepared(at: locations)
        }
    }

    private static func uninstallPrepared(at locations: InstallLocations) throws -> InstallationResult {
        var changed: [URL] = []
        for configuration in locations.codexConfigurations {
            if try updateConfiguration(
                at: configuration,
                entries: codexEntries(locations),
                operation: .uninstall
            ) {
                changed.append(configuration)
            }
        }

        if try updateConfiguration(
            at: locations.claudeConfiguration,
            entries: claudeEntries(locations),
            operation: .uninstall
        ) {
            changed.append(locations.claudeConfiguration)
        }

        for extensionURL in [locations.piExtension, locations.legacyPiExtension] {
            if try removeOwnedFile(at: extensionURL, containing: piMarker) {
                changed.append(extensionURL)
            }
        }
        if try removeOwnedReporter(at: locations.installedReporter) {
            changed.append(locations.installedReporter)
        }
        if try removeSupportDirectory(at: locations.supportDirectory) {
            changed.append(locations.supportDirectory)
        }
        for configuration in locations.codexConfigurations + [locations.claudeConfiguration] {
            changed.append(contentsOf: try removeLegacyBackups(for: configuration))
        }
        for directory in locations.codexConfigurations.map({ $0.deletingLastPathComponent() }) + [
            locations.claudeConfiguration.deletingLastPathComponent(),
            locations.piExtension.deletingLastPathComponent(),
        ] {
            try removeEmptyAncestors(from: directory, stoppingBefore: locations.home)
        }
        return InstallationResult(changed: changed)
    }

    private static func installationTargets(_ locations: InstallLocations) -> [URL] {
        var targets = locations.codexConfigurations + [
            locations.installedReporter,
            locations.claudeConfiguration,
            locations.piExtension,
            locations.legacyPiExtension,
        ]
        for configuration in locations.codexConfigurations {
            targets.append(contentsOf: legacyBackups(for: configuration))
        }
        targets.append(contentsOf: legacyBackups(for: locations.claudeConfiguration))
        return targets
    }

    private static func withRollback<Result>(
        at urls: [URL],
        operation: () throws -> Result
    ) throws -> Result {
        let snapshots = try urls.map(FileSnapshot.init)
        do {
            return try operation()
        } catch {
            do {
                for snapshot in snapshots.reversed() {
                    try restore(snapshot)
                }
            } catch let rollbackError {
                throw InstallerError.rollbackFailed(original: String(describing: error), rollback: String(describing: rollbackError))
            }
            throw error
        }
    }

    private static func restore(_ snapshot: FileSnapshot) throws {
        let current = try? Data(contentsOf: snapshot.url)
        guard current != snapshot.data else { return }
        guard let data = snapshot.data else {
            if FileManager.default.fileExists(atPath: snapshot.url.path) {
                try FileManager.default.removeItem(at: snapshot.url)
            }
            return
        }

        try FileManager.default.createDirectory(
            at: snapshot.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(data, to: snapshot.url, permissions: snapshot.permissions)
    }

    public static func isInstalled(at locations: InstallLocations) -> Bool {
        FileManager.default.isExecutableFile(atPath: locations.installedReporter.path)
            && locations.codexConfigurations.allSatisfy {
                configuration(at: $0, contains: codexEntries(locations))
            }
            && configuration(at: locations.claudeConfiguration, contains: claudeEntries(locations))
            && ((try? String(contentsOf: locations.piExtension, encoding: .utf8).contains(piMarker)) == true)
    }

    /// True when the copies the agents actually execute match what this build ships. Agents run
    /// the reporter and the Pi extension out of the user's home, not out of the app bundle, so
    /// replacing the bundle leaves both behind until an install rewrites them.
    public static func isUpToDate(at locations: InstallLocations) -> Bool {
        guard let source = try? Data(contentsOf: locations.reporterSource),
              let installed = try? Data(contentsOf: locations.installedReporter),
              source == installed,
              let extensionSource = try? piExtension(reporterPath: locations.installedReporter.path),
              (try? String(contentsOf: locations.piExtension, encoding: .utf8)) == extensionSource
        else { return false }
        return true
    }

    private static func installReporter(at locations: InstallLocations) throws -> Bool {
        let sourceData = try Data(contentsOf: locations.reporterSource)
        if let installedData = try? Data(contentsOf: locations.installedReporter), installedData == sourceData {
            return false
        }

        let directory = locations.installedReporter.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try atomicWrite(sourceData, to: locations.installedReporter, permissions: 0o755)
        return true
    }

    private static func updateConfiguration(
        at url: URL,
        entries: [HookEntry],
        operation: ConfigurationOperation
    ) throws -> Bool {
        let original = try loadObject(at: url)
        try validateHookStructure(in: original, events: events(of: entries), at: url)
        let updated = mutate(original, entries: entries, operation: operation)
        guard !NSDictionary(dictionary: original).isEqual(to: updated) else {
            return false
        }

        if operation == .uninstall, updated.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } else {
            try writeObject(updated, to: url)
        }
        return true
    }

    private static func events(of entries: [HookEntry]) -> [String] {
        var seen = Set<String>()
        return entries.map(\.event).filter { seen.insert($0).inserted }
    }

    /// Installing adds each entry once, or brings an older copy of it up to date in place, so a
    /// new timeout reaches existing installs. Uninstalling removes every command CodeWindow owns
    /// and leaves everything else exactly as it was.
    private static func mutate(
        _ root: [String: Any],
        entries: [HookEntry],
        operation: ConfigurationOperation
    ) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let owned = Set(entries.map(\.command))

        for event in events(of: entries) {
            var groups = hooks[event] as? [[String: Any]] ?? []
            switch operation {
            case .install:
                for entry in entries where entry.event == event {
                    if let index = groups.firstIndex(where: { groupContains($0, command: entry.command) }) {
                        var group = groups[index]
                        var commands = group["hooks"] as? [[String: Any]] ?? []
                        commands = commands.map {
                            ($0["command"] as? String) == entry.command ? entry.handler : $0
                        }
                        group["hooks"] = commands
                        groups[index] = group
                    } else {
                        groups.append(["hooks": [entry.handler]])
                    }
                }
            case .uninstall:
                groups = groups.compactMap { group in
                    guard var commands = group["hooks"] as? [[String: Any]] else { return group }
                    commands.removeAll { owned.contains($0["command"] as? String ?? "") }
                    guard !commands.isEmpty else { return nil }
                    var group = group
                    group["hooks"] = commands
                    return group
                }
            }

            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return root
    }

    private static func groupContains(_ group: [String: Any], command: String) -> Bool {
        let commands = group["hooks"] as? [[String: Any]] ?? []
        return commands.contains { ($0["command"] as? String) == command }
    }

    /// True only when every entry is present with exactly the attributes this build installs.
    private static func configuration(at url: URL, contains entries: [HookEntry]) -> Bool {
        guard let root = try? loadObject(at: url), let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return entries.allSatisfy { entry in
            let groups = hooks[entry.event] as? [[String: Any]] ?? []
            return groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    NSDictionary(dictionary: $0).isEqual(to: entry.handler)
                }
            }
        }
    }

    private static func loadObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.invalidConfiguration(url)
        }
        return root
    }

    private static func writeObject(_ root: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atomicWrite(data, to: url, permissions: filePermissions(at: url) ?? 0o600)
    }

    private static func installPiExtension(at locations: InstallLocations) throws -> [URL] {
        let content = try piExtension(reporterPath: locations.installedReporter.path)
        var changed: [URL] = []
        if (try? String(contentsOf: locations.piExtension, encoding: .utf8)) != content {
            try FileManager.default.createDirectory(
                at: locations.piExtension.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try atomicWrite(Data(content.utf8), to: locations.piExtension, permissions: 0o600)
            changed.append(locations.piExtension)
        }
        if try removeOwnedFile(at: locations.legacyPiExtension, containing: piMarker) {
            changed.append(locations.legacyPiExtension)
        }
        return changed
    }

    private static func preflightConfiguration(at url: URL, events: [String]) throws {
        let root = try loadObject(at: url)
        try validateHookStructure(in: root, events: events, at: url)
    }

    private static func validateHookStructure(in root: [String: Any], events: [String], at url: URL) throws {
        guard let rawHooks = root["hooks"] else { return }
        guard let hooks = rawHooks as? [String: Any] else {
            throw InstallerError.unsupportedHookStructure(url)
        }
        for event in events where hooks[event] != nil {
            guard hooks[event] is [[String: Any]] else {
                throw InstallerError.unsupportedHookStructure(url)
            }
        }
    }

    private static func preflightPiExtension(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let existing = try String(contentsOf: url, encoding: .utf8)
        guard existing.hasPrefix("\(piMarker)\n") else { throw InstallerError.piExtensionAlreadyExists }
    }

    private static func piExtension(reporterPath: String) throws -> String {
        let encodedPathData = try JSONEncoder().encode(reporterPath)
        guard let encodedPath = String(data: encodedPathData, encoding: .utf8) else {
            throw InstallerError.invalidReporterPath
        }
        return #"""
        \#(piMarker)
        import { spawn } from "node:child_process";
        import { existsSync, readdirSync, readFileSync, rmSync } from "node:fs";
        import { homedir } from "node:os";
        import { join } from "node:path";

        const reporter = \#(encodedPath);
        const activeTools = new Map();
        const inboxRoot = join(
          process.env.CODEWINDOW_STATE_DIR || join(homedir(), "Library", "Application Support", "CodeWindow", "State"),
          "Inbox",
        );
        let lastAssistantMessage;
        let inboxTimer;

        function report(event, ctx, details = {}, extraArguments = []) {
          let child;
          try {
            child = spawn(reporter, ["--agent", "pi", "--pid", String(process.pid), ...extraArguments], {
              stdio: ["pipe", "ignore", "ignore"],
            });
          } catch {
            return;
          }

          const timer = setTimeout(() => child.kill(), 1000);
          timer.unref();
          const finish = () => clearTimeout(timer);
          child.once("error", finish);
          child.once("close", finish);
          child.stdin?.once("error", () => {});
          child.stdin?.end(JSON.stringify({
            session_id: ctx.sessionManager.getSessionId(),
            event,
            cwd: ctx.cwd,
            tool_name: details.toolName,
            tool_input: details.toolInput,
            tool_call_id: details.toolCallId,
            user_prompt: details.userPrompt,
            last_assistant_message: details.assistantMessage,
            is_error: details.toolFailed,
          }));
        }

        function visibleAssistantText(message) {
          if (!message || typeof message !== "object") return undefined;
          if (message.role !== "assistant" || !Array.isArray(message.content)) return undefined;

          const text = message.content
            .filter((part) => part?.type === "text" && typeof part.text === "string")
            .map((part) => part.text)
            .join("\n")
            .trim();
          return text || undefined;
        }

        function readJSON(path) {
          try {
            return JSON.parse(readFileSync(path, "utf8"));
          } catch {
            return undefined;
          }
        }

        // Replies the user writes in the CodeWindow inbox arrive as files addressed to a session.
        // Each one is consumed once and handed to Pi as if it had been typed.
        function deliverInboxReplies(pi, ctx) {
          if (!existsSync(join(inboxRoot, ".enabled"))) return;
          let names;
          try {
            names = readdirSync(join(inboxRoot, "Responses"));
          } catch {
            return;
          }
          let sessionId;
          try {
            sessionId = ctx.sessionManager.getSessionId();
          } catch {
            return;
          }
          for (const name of names) {
            if (!name.endsWith(".json")) continue;
            const item = readJSON(join(inboxRoot, "Items", name));
            if (!item || item.agent !== "pi" || item.externalSessionID !== sessionId) continue;
            const response = readJSON(join(inboxRoot, "Responses", name));
            rmSync(join(inboxRoot, "Responses", name), { force: true });
            rmSync(join(inboxRoot, "Items", name), { force: true });
            if (response?.kind !== "reply" || typeof response.text !== "string" || !response.text.trim()) continue;
            try {
              if (ctx.isIdle()) pi.sendUserMessage(response.text);
              else pi.sendUserMessage(response.text, { deliverAs: "followUp" });
            } catch {
              // A session that was replaced mid-delivery has nobody left to answer.
            }
          }
        }

        export default function (pi) {
          pi.on("session_start", (_event, ctx) => {
            report("session_start", ctx);
            clearInterval(inboxTimer);
            inboxTimer = setInterval(() => deliverInboxReplies(pi, ctx), 750);
            inboxTimer.unref?.();
          });
          pi.on("before_agent_start", (event, ctx) => report("before_agent_start", ctx, {
            userPrompt: event.prompt,
          }));
          pi.on("tool_execution_start", (event, ctx) => {
            activeTools.set(event.toolCallId, {
              toolName: event.toolName,
              toolInput: event.args,
            });
            report("tool_execution_start", ctx, {
              toolCallId: event.toolCallId,
              toolName: event.toolName,
              toolInput: event.args,
            });
          });
          pi.on("tool_execution_end", (event, ctx) => {
            const started = activeTools.get(event.toolCallId);
            activeTools.delete(event.toolCallId);
            report("tool_execution_end", ctx, {
              toolCallId: event.toolCallId,
              toolName: event.toolName,
              toolInput: started?.toolInput,
              toolFailed: event.isError,
            });
          });
          pi.on("message_end", (event, ctx) => {
            const assistantMessage = visibleAssistantText(event.message);
            if (assistantMessage) lastAssistantMessage = assistantMessage;
            report("message_end", ctx, { assistantMessage });
          });
          // Settled means Pi is idle and waiting for the user: the moment the inbox files a reply.
          pi.on("agent_settled", (_event, ctx) => report("agent_settled", ctx, {
            assistantMessage: lastAssistantMessage,
          }, ["--inbox"]));
          pi.on("session_shutdown", (_event, ctx) => {
            clearInterval(inboxTimer);
            report("session_shutdown", ctx);
          });
        }
        """#
    }

    private static func atomicWrite(_ data: Data, to destination: URL, permissions: Int) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".codewindow-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
        let result = temporary.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw InstallerError.renameFailed(code)
        }
    }

    private static func removeOwnedFile(at url: URL, containing marker: String) throws -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8), content.hasPrefix("\(marker)\n") else {
            return false
        }
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func removeOwnedReporter(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func removeSupportDirectory(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func legacyBackups(for configuration: URL) -> [URL] {
        let directory = configuration.deletingLastPathComponent()
        let prefix = configuration.lastPathComponent + ".codewindow-backup"
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private static func removeLegacyBackups(for configuration: URL) throws -> [URL] {
        let backups = legacyBackups(for: configuration)
        for backup in backups { try FileManager.default.removeItem(at: backup) }
        return backups
    }

    private static func removeEmptyAncestors(from directory: URL, stoppingBefore root: URL) throws {
        var directory = directory.standardizedFileURL
        let root = root.standardizedFileURL
        while directory != root, directory.path.hasPrefix(root.path + "/") {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return }
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard contents.isEmpty else { return }
            try FileManager.default.removeItem(at: directory)
            directory.deleteLastPathComponent()
        }
    }

    private static func filePermissions(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return nil }
        return permissions.intValue
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private enum ConfigurationOperation {
    case install
    case uninstall
}

public enum InstallerError: Error, CustomStringConvertible {
    case reporterMissing
    case invalidConfiguration(URL)
    case unsupportedHookStructure(URL)
    case piExtensionAlreadyExists
    case invalidReporterPath
    case renameFailed(Int32)
    case rollbackFailed(original: String, rollback: String)

    public var description: String {
        switch self {
        case .reporterMissing: "The reporter executable is missing. Reinstall CodeWindow and try again."
        case let .invalidConfiguration(url): "Invalid JSON configuration: \(url.path)"
        case let .unsupportedHookStructure(url): "Unsupported hooks structure in \(url.path); no changes were made."
        case .piExtensionAlreadyExists: "A non-CodeWindow Pi extension already exists at the CodeWindow extension path."
        case .invalidReporterPath: "The reporter path could not be encoded."
        case let .renameFailed(code): "Atomic file replacement failed with errno \(code)."
        case let .rollbackFailed(original, rollback): "Installation failed (\(original)) and rollback failed (\(rollback))."
        }
    }
}

private struct FileSnapshot {
    let url: URL
    let data: Data?
    let permissions: Int

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            data = try Data(contentsOf: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        } else {
            data = nil
            permissions = 0o600
        }
    }
}
