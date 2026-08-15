import CodeWindowCore
import Darwin
import Foundation

func value(after name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
}

let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let reporter = value(after: "--reporter-path").map { URL(fileURLWithPath: $0) }
    ?? executable.deletingLastPathComponent().appendingPathComponent("codewindow-report")
let overriddenHome = value(after: "--home").map { URL(fileURLWithPath: $0, isDirectory: true) }
let home = overriddenHome ?? FileManager.default.homeDirectoryForCurrentUser
let environment = overriddenHome == nil ? ProcessInfo.processInfo.environment : [:]
let locations = InstallLocations.detectingCodexProfiles(
    home: home,
    reporterSource: reporter,
    environment: environment
)
let commands = Set(["install", "uninstall", "status"])
let command = CommandLine.arguments.dropFirst().first { commands.contains($0) } ?? "status"

do {
    switch command {
    case "install":
        let result = try HookInstaller.install(at: locations)
        print(result.changed.isEmpty ? "CodeWindow hooks are already installed." : "Installed CodeWindow hooks.")
        let profiles = locations.codexHomes.map(\.lastPathComponent).joined(separator: ", ")
        print("Codex profiles: \(profiles)")
        print("Codex: start a new session, run /hooks, and trust the CodeWindow entries.")
    case "uninstall":
        let result = try HookInstaller.uninstall(at: locations)
        print(result.changed.isEmpty ? "CodeWindow hooks were not installed." : "Uninstalled CodeWindow hooks.")
    case "status":
        let installed = HookInstaller.isInstalled(at: locations)
        print(installed ? "installed" : "not installed")
        if !installed { exit(1) }
    default:
        print("Usage: codewindow-install [install|uninstall|status] [--reporter-path PATH] [--home PATH]")
        exit(2)
    }
} catch {
    fputs("codewindow-install: \(error)\n", stderr)
    exit(1)
}
