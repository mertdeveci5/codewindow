import Darwin
import Foundation

public struct InstallLocations: Sendable {
    public let home: URL
    public let reporterSource: URL

    public init(home: URL, reporterSource: URL) {
        self.home = home
        self.reporterSource = reporterSource
    }

    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/CodeWindow", isDirectory: true)
    }

    public var installedReporter: URL {
        supportDirectory.appendingPathComponent("bin/codewindow-report")
    }

    public var codexConfiguration: URL {
        home.appendingPathComponent(".codex/hooks.json")
    }

    public var claudeConfiguration: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    public var piExtension: URL {
        home.appendingPathComponent(".pi/agent/extensions/codewindow.ts")
    }
}

public struct InstallationResult: Sendable {
    public let changed: [URL]
    public let backups: [URL]
}

public enum HookInstaller {
    public static let piMarker = "// CodeWindow managed extension"

    private static let codexEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop",
        "SessionEnd",
    ]
    private static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]

    public static func install(at locations: InstallLocations) throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(atPath: locations.reporterSource.path) else {
            throw InstallerError.reporterMissing
        }
        try preflightConfiguration(at: locations.codexConfiguration, events: codexEvents)
        try preflightConfiguration(at: locations.claudeConfiguration, events: claudeEvents)
        try preflightPiExtension(at: locations.piExtension)

        return try withRollback(at: installationTargets(locations)) {
            try installPrepared(at: locations)
        }
    }

    private static func installPrepared(at locations: InstallLocations) throws -> InstallationResult {
        var changed: [URL] = []
        var backups: [URL] = []
        if try installReporter(at: locations) { changed.append(locations.installedReporter) }

        let codexCommand = "\(shellQuote(locations.installedReporter.path)) --agent codex"
        let claudeCommand = "\(shellQuote(locations.installedReporter.path)) --agent claude"

        let codex = try updateConfiguration(
            at: locations.codexConfiguration,
            events: codexEvents,
            command: codexCommand,
            operation: .install
        )
        changed.append(contentsOf: codex.changed)
        backups.append(contentsOf: codex.backups)

        let claude = try updateConfiguration(
            at: locations.claudeConfiguration,
            events: claudeEvents,
            command: claudeCommand,
            operation: .install
        )
        changed.append(contentsOf: claude.changed)
        backups.append(contentsOf: claude.backups)

        if try installPiExtension(at: locations) { changed.append(locations.piExtension) }
        return InstallationResult(changed: changed, backups: backups)
    }

    public static func uninstall(at locations: InstallLocations) throws -> InstallationResult {
        try preflightConfiguration(at: locations.codexConfiguration, events: codexEvents)
        try preflightConfiguration(at: locations.claudeConfiguration, events: claudeEvents)

        return try withRollback(at: installationTargets(locations)) {
            try uninstallPrepared(at: locations)
        }
    }

    private static func uninstallPrepared(at locations: InstallLocations) throws -> InstallationResult {
        var changed: [URL] = []
        var backups: [URL] = []
        let codexCommand = "\(shellQuote(locations.installedReporter.path)) --agent codex"
        let claudeCommand = "\(shellQuote(locations.installedReporter.path)) --agent claude"

        let codex = try updateConfiguration(
            at: locations.codexConfiguration,
            events: codexEvents,
            command: codexCommand,
            operation: .uninstall
        )
        changed.append(contentsOf: codex.changed)
        backups.append(contentsOf: codex.backups)

        let claude = try updateConfiguration(
            at: locations.claudeConfiguration,
            events: claudeEvents,
            command: claudeCommand,
            operation: .uninstall
        )
        changed.append(contentsOf: claude.changed)
        backups.append(contentsOf: claude.backups)

        if try removeOwnedFile(at: locations.piExtension, containing: piMarker) {
            changed.append(locations.piExtension)
        }
        if try removeOwnedReporter(at: locations.installedReporter) {
            changed.append(locations.installedReporter)
        }
        return InstallationResult(changed: changed, backups: backups)
    }

    private static func installationTargets(_ locations: InstallLocations) -> [URL] {
        [
            locations.installedReporter,
            locations.codexConfiguration,
            locations.claudeConfiguration,
            locations.piExtension,
        ]
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
        let codexCommand = "\(shellQuote(locations.installedReporter.path)) --agent codex"
        let claudeCommand = "\(shellQuote(locations.installedReporter.path)) --agent claude"
        return FileManager.default.isExecutableFile(atPath: locations.installedReporter.path)
            && configuration(at: locations.codexConfiguration, contains: codexCommand, for: codexEvents)
            && configuration(at: locations.claudeConfiguration, contains: claudeCommand, for: claudeEvents)
            && ((try? String(contentsOf: locations.piExtension, encoding: .utf8).contains(piMarker)) == true)
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
        events: [String],
        command: String,
        operation: ConfigurationOperation
    ) throws -> InstallationResult {
        let original = try loadObject(at: url)
        try validateHookStructure(in: original, events: events, at: url)
        let updated = mutate(original, events: events, command: command, operation: operation)
        guard !NSDictionary(dictionary: original).isEqual(to: updated) else {
            return InstallationResult(changed: [], backups: [])
        }

        var backups: [URL] = []
        if FileManager.default.fileExists(atPath: url.path) {
            backups.append(try backup(url))
        }
        try writeObject(updated, to: url)
        return InstallationResult(changed: [url], backups: backups)
    }

    private static func mutate(
        _ root: [String: Any],
        events: [String],
        command: String,
        operation: ConfigurationOperation
    ) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            switch operation {
            case .install:
                if !groups.contains(where: { groupContains($0, command: command) }) {
                    groups.append([
                        "hooks": [["type": "command", "command": command, "timeout": 2]],
                    ])
                }
            case .uninstall:
                groups = groups.compactMap { group in
                    guard var commands = group["hooks"] as? [[String: Any]] else { return group }
                    commands.removeAll { ($0["command"] as? String) == command }
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

    private static func configuration(at url: URL, contains command: String, for events: [String]) -> Bool {
        guard let root = try? loadObject(at: url), let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return events.allSatisfy { event in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.contains { groupContains($0, command: command) }
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
        try atomicWrite(data, to: url, permissions: 0o600)
    }

    private static func backup(_ url: URL) throws -> URL {
        let destination = url.appendingPathExtension("codewindow-backup-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private static func installPiExtension(at locations: InstallLocations) throws -> Bool {
        let content = try piExtension(reporterPath: locations.installedReporter.path)
        if (try? String(contentsOf: locations.piExtension, encoding: .utf8)) == content { return false }
        try FileManager.default.createDirectory(
            at: locations.piExtension.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(Data(content.utf8), to: locations.piExtension, permissions: 0o600)
        return true
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
        return """
        \(piMarker)
        import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
        import { spawn } from "node:child_process";

        const reporter = \(encodedPath);

        function report(
          event: string,
          ctx: ExtensionContext,
          toolName?: string,
          toolInput?: unknown,
          userPrompt?: string,
        ): Promise<void> {
          return new Promise((resolve) => {
            const child = spawn(reporter, ["--agent", "pi", "--pid", String(process.pid)], {
              stdio: ["pipe", "ignore", "ignore"],
            });
            let settled = false;
            const finish = () => {
              if (settled) return;
              settled = true;
              clearTimeout(timer);
              resolve();
            };
            const timer = setTimeout(() => {
              child.kill();
              finish();
            }, 250);
            child.once("error", finish);
            child.once("close", finish);
            child.stdin.once("error", finish);
            child.stdin.end(JSON.stringify({
              session_id: ctx.sessionManager.getSessionId(),
              event,
              cwd: ctx.cwd,
              tool_name: toolName,
              tool_input: toolInput,
              user_prompt: userPrompt,
            }));
          });
        }

        export default function (pi: ExtensionAPI) {
          pi.on("session_start", (_event, ctx) => report("session_start", ctx));
          pi.on("before_agent_start", (event, ctx) => report("before_agent_start", ctx, undefined, undefined, event.prompt));
          pi.on("tool_execution_start", (event, ctx) => report("tool_execution_start", ctx, event.toolName, event.args));
          pi.on("tool_execution_end", (_event, ctx) => report("tool_execution_end", ctx));
          pi.on("agent_settled", (_event, ctx) => report("agent_settled", ctx));
          pi.on("session_shutdown", (_event, ctx) => report("session_shutdown", ctx));
        }
        """
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

    private static func shellQuote(_ value: String) -> String {
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
        case .reporterMissing: "The reporter executable is missing. Build CodeWindow first."
        case let .invalidConfiguration(url): "Invalid JSON configuration: \(url.path)"
        case let .unsupportedHookStructure(url): "Unsupported hooks structure in \(url.path); no changes were made."
        case .piExtensionAlreadyExists: "A non-CodeWindow Pi extension already exists at codewindow.ts."
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
