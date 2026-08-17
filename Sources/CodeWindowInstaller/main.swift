import CodeWindowCore
import Darwin
import Foundation

private final class CaptureResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ value: Bool) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func value(after name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
}

func appInfo(for executable: URL) -> [String: Any] {
    let infoURL = executable
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
          let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let info = object as? [String: Any]
    else { return [:] }
    return info
}

func sendInstallationEvent(to endpoint: URL, body: Data) -> Bool {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 2
    configuration.timeoutIntervalForResource = 2
    let session = URLSession(configuration: configuration)
    let completion = DispatchSemaphore(value: 0)
    let response = CaptureResponse()
    let task = session.dataTask(with: request) { _, urlResponse, _ in
        if let status = (urlResponse as? HTTPURLResponse)?.statusCode {
            response.set((200..<300).contains(status))
        }
        completion.signal()
    }
    task.resume()
    guard completion.wait(timeout: .now() + 2.25) == .success else {
        task.cancel()
        return false
    }
    return response.get()
}

func recordInstallationIfNeeded(executable: URL, locations: InstallLocations) {
    guard ProcessInfo.processInfo.environment["CODEWINDOW_DISABLE_ANALYTICS"] != "1" else { return }
    let info = appInfo(for: executable)
    let hostValue = (info["CodeWindowPostHogHost"] as? String) ?? "https://us.i.posthog.com"
    guard let apiKey = info["CodeWindowPostHogKey"] as? String,
          let version = info["CFBundleShortVersionString"] as? String,
          let apiHost = URL(string: hostValue)
    else { return }

    #if arch(arm64)
    let architecture = "arm64"
    #elseif arch(x86_64)
    let architecture = "x86_64"
    #else
    let architecture = "unknown"
    #endif

    _ = try? InstallationAnalytics.captureIfNeeded(
        supportDirectory: locations.supportDirectory,
        apiKey: apiKey,
        apiHost: apiHost,
        releaseVersion: version,
        architecture: architecture,
        send: sendInstallationEvent
    )
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
let commands = Set(["install", "refresh", "uninstall", "status"])
let command = CommandLine.arguments.dropFirst().first { commands.contains($0) } ?? "status"

do {
    switch command {
    case "install":
        let result = try HookInstaller.install(at: locations)
        print(result.changed.isEmpty ? "CodeWindow hooks are already installed." : "Installed CodeWindow hooks.")
        let profiles = locations.codexHomes.map(\.lastPathComponent).joined(separator: ", ")
        print("Codex profiles: \(profiles)")
        print("Codex: start a new session, run /hooks, and trust the CodeWindow entries.")
        if overriddenHome == nil {
            recordInstallationIfNeeded(executable: executable, locations: locations)
        }
    case "refresh":
        // Runs on every app launch. Only integrations that are already installed get rewritten,
        // so this never resurrects hooks somebody removed by hand.
        if !HookInstaller.isInstalled(at: locations) {
            print("CodeWindow hooks are not installed.")
        } else if HookInstaller.isUpToDate(at: locations) {
            print("CodeWindow hooks are up to date.")
        } else {
            let result = try HookInstaller.install(at: locations)
            print(result.changed.isEmpty ? "CodeWindow hooks are up to date." : "Refreshed CodeWindow hooks.")
        }
    case "uninstall":
        let result = try HookInstaller.uninstall(at: locations)
        print(result.changed.isEmpty ? "CodeWindow hooks were not installed." : "Uninstalled CodeWindow hooks.")
    case "status":
        let installed = HookInstaller.isInstalled(at: locations)
        print(installed ? "installed" : "not installed")
        if !installed { exit(1) }
    default:
        print("Usage: codewindow-install [install|refresh|uninstall|status] [--reporter-path PATH] [--home PATH]")
        exit(2)
    }
} catch {
    fputs("codewindow-install: \(error)\n", stderr)
    exit(1)
}
