import CodeWindowCore
import Darwin
import Foundation

private let maximumInputBytes = 1_048_576

func argument(after name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
}

/// The panel shows this to the user, so name the problem rather than the Swift case.
func summary(of error: Error) -> String {
    guard let stateError = error as? StateFileError else {
        return String(describing: error)
    }
    switch stateError {
    case .tooLarge: return "session state grew past its size limit"
    case let .lockFailed(code): return "could not lock session state (errno \(code))"
    case let .renameFailed(code): return "could not replace session state (errno \(code))"
    }
}

struct HookEvent {
    let agent: AgentKind
    let payload: HookPayload
    let key: String
    let process: ProcessStamp
}

func readEvent(_ input: Data) throws -> HookEvent? {
    guard let rawAgent = argument(after: "--agent"),
          let agent = AgentKind(rawValue: rawAgent),
          input.count <= maximumInputBytes,
          let json = try JSONSerialization.jsonObject(with: input) as? [String: Any]
    else { return nil }

    let process: ProcessStamp?
    if let rawPID = argument(after: "--pid"), let pid = Int32(rawPID) {
        process = ProcessInspector.stamp(pid: pid)
    } else {
        process = ProcessInspector.findAgentProcess(agent: agent)
            ?? ProcessInspector.findNodeProcess()
    }

    let payload = try HookPayload(json: json)
    guard let process else { return nil }
    return HookEvent(
        agent: agent,
        payload: payload,
        key: SessionState.key(agent: agent, externalSessionID: payload.externalSessionID),
        process: process
    )
}

func report(_ event: HookEvent) throws {
    let directory = try StateFiles.directory()
    try StateFiles.withSessionLock(event.key, in: directory) {
        let previous = StateFiles.read(from: directory.appendingPathComponent("\(event.key).json"))
        guard let state = event.payload.state(agent: event.agent, process: event.process, previous: previous) else {
            return
        }
        try StateFiles.write(state, to: directory)
    }

    // Inbox bookkeeping costs one file check while the mode is off.
    guard InboxFiles.isEnabled(in: InboxFiles.root(stateDirectory: directory)) else { return }
    let inbox = try InboxFiles.directory(stateDirectory: directory)
    InboxFiles.rememberTask(event.payload.fullPrompt, sessionKey: event.key, in: inbox)
    if event.payload.settlesInbox {
        InboxFiles.retire(sessionKey: event.key, in: inbox)
    }
    if event.payload.endsSession {
        InboxFiles.forgetTask(sessionKey: event.key, in: inbox)
    }
}

/// Removes this hook's item if the agent kills the hook at its timeout, so the inbox never offers
/// an answer nobody is waiting for. Only async-signal-safe calls are allowed in the handler.
nonisolated(unsafe) var pendingItemPath: UnsafeMutablePointer<CChar>?

func removePendingItemOnTermination(_ path: String) {
    pendingItemPath = strdup(path)
    let handler: @convention(c) (Int32) -> Void = { _ in
        if let path = pendingItemPath { unlink(path) }
        _exit(0)
    }
    signal(SIGTERM, handler)
    signal(SIGINT, handler)
    signal(SIGHUP, handler)
}

/// Files a question in the inbox and, where the agent can take an answer back through this hook,
/// waits for the user. Returns at once while inbox mode is off.
func inbox(_ event: HookEvent) throws -> InboxHookOutput {
    guard let request = event.payload.inboxRequest else { return .nothing }
    let directory = try StateFiles.directory()
    guard InboxFiles.isEnabled(in: InboxFiles.root(stateDirectory: directory)) else { return .nothing }
    let root = try InboxFiles.directory(stateDirectory: directory)

    let item = InboxItem(
        sessionKey: event.key,
        externalSessionID: event.payload.externalSessionID,
        agent: event.agent,
        projectLabel: SessionState.projectLabel(cwd: event.payload.cwd),
        request: request,
        message: event.payload.fullAssistantMessage,
        task: InboxFiles.task(sessionKey: event.key, in: root),
        process: event.process
    )
    try InboxFiles.add(item, in: root)

    let waits = request.isPermission || item.replyDelivery == .waitingHook
    guard waits else { return .nothing }
    removePendingItemOnTermination(
        InboxFiles.itemsDirectory(in: root).appendingPathComponent("\(item.id).json").path
    )
    // Give up just before the agent's own timeout so the item is gone before the hook is.
    let deadline = request.isPermission
        ? Date().addingTimeInterval(TimeInterval(HookInstaller.inboxPermissionTimeout - 30))
        : .distantFuture
    let response = InboxWaiter.wait(for: item, in: root, deadline: deadline) {
        ProcessInspector.isCurrent(event.process)
    }
    return InboxHookOutput.output(for: response, agent: event.agent, request: request)
}

do {
    // Consume the bounded hook input so the agent does not see a broken stdin pipe. When the
    // app is closed, skip JSON parsing, process discovery, state writes, and inbox interception.
    guard let input = try FileHandle.standardInput.read(upToCount: maximumInputBytes + 1),
          let directory = try? StateFiles.location(),
          AppPresence.isRunning(in: directory),
          let event = try readEvent(input)
    else { exit(0) }
    if CommandLine.arguments.contains("--inbox") {
        let output = try inbox(event)
        if let text = output.standardOutput { print(text) }
        if let text = output.standardError { fputs(text, stderr) }
        exit(output.exitCode)
    }
    try report(event)
} catch {
    // Leave the reason where the panel can find it. A hook that fails quietly is how a stale
    // reporter goes unnoticed for weeks. Exit 1 rather than 2: an agent treats 2 as a request
    // to block the tool call, and a reporting problem must never stop the user's work.
    StateFiles.recordReportingFailure(summary(of: error))
    fputs("codewindow-report: \(error)\n", stderr)
    exit(1)
}
exit(0)
