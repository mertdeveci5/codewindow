@testable import CodeWindowCore
import Darwin
import Foundation

/// An actual process registration for packaged reporter integration tests. EOF simulates quit;
/// SIGKILL simulates a crash. This helper is in the test executable, never the shipped app.
func runAppPresenceHost(in directory: URL) throws {
    let presence = try AppPresence(in: directory)
    defer { withExtendedLifetime(presence) {} }
    print("READY")
    fflush(stdout)
    _ = try FileHandle.standardInput.readToEnd()
}

func testAppPresence() throws {
    let parent = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let state = parent.appendingPathComponent("not-created", isDirectory: true)
    let location = try StateFiles.location(environment: ["CODEWINDOW_STATE_DIR": state.path])
    try require(location == state, "State location changed")
    try require(!AppPresence.isRunning(in: state), "Missing state looked like a live app")
    try require(!FileManager.default.fileExists(atPath: state.path), "Presence probe created state")

    var first: AppPresence? = try AppPresence(in: state)
    defer { withExtendedLifetime(first) {} }
    try require(AppPresence.isRunning(in: state), "App registration was not live")
    var second: AppPresence? = try AppPresence(in: state)
    defer { withExtendedLifetime(second) {} }
    first = nil
    try require(AppPresence.isRunning(in: state), "Quitting one instance disabled another")
    second = nil
    try require(!AppPresence.isRunning(in: state), "Last app quit left reporting active")

    let root = AppPresence.root(in: state)
    let current = try unwrap(ProcessInspector.stamp(pid: getpid()), "Missing test process")
    let reused = ProcessStamp(pid: current.pid, startedAtSeconds: current.startedAtSeconds + 1,
                              startedAtMicroseconds: current.startedAtMicroseconds)
    try JSONEncoder().encode(reused).write(to: root.appendingPathComponent("reused.json"))
    try Data("not json".utf8).write(to: root.appendingPathComponent("corrupt.json"))
    try Data(repeating: 65, count: 10_000).write(to: root.appendingPathComponent("oversized.json"))
    try require(!AppPresence.isRunning(in: state), "Stale or malformed registration activated hooks")
    let reopened = try AppPresence(in: state)
    defer { withExtendedLifetime(reopened) {} }
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    try require(files.count == 1, "Relaunch did not clean stale registrations")
    let mode = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? NSNumber
    try require(mode?.intValue == 0o600, "App registration is not private")
    let rootMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
    try require(rootMode?.intValue == 0o700, "App registration directory is not private")
}

func testInboxWithoutApp() throws {
    let state = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: state) }
    let root = try InboxFiles.directory(stateDirectory: state)
    try InboxFiles.setEnabled(true, in: root)
    let process = try unwrap(ProcessInspector.stamp(pid: getpid()), "Missing test process")
    let item = InboxItem(sessionKey: "closed", externalSessionID: "closed", agent: .claude,
                         projectLabel: "test", request: .permission(tool: "Bash", detail: "echo test"),
                         message: nil, task: nil, process: process)
    try InboxFiles.add(item, in: root)
    try InboxFiles.respond(.allow, to: item.id, in: root)
    let response = InboxWaiter.wait(for: item, in: root, deadline: Date().addingTimeInterval(1),
                                   isAgentAlive: { true })
    try require(response == nil, "Closed app delivered a leftover approval")
    try require(InboxFiles.item(id: item.id, in: root) == nil, "Closed-app wait kept its item")
    try require(InboxFiles.takeResponse(for: item.id, in: root) == nil, "Closed-app wait kept its response")
    try require(InboxFiles.isEnabled(in: root), "App exit changed the user's inbox-mode preference")
}
