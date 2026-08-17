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

func report() throws {
    guard let rawAgent = argument(after: "--agent"),
          let agent = AgentKind(rawValue: rawAgent),
          let input = try FileHandle.standardInput.read(upToCount: maximumInputBytes + 1),
          input.count <= maximumInputBytes,
          let json = try JSONSerialization.jsonObject(with: input) as? [String: Any]
    else { return }

    let process: ProcessStamp?
    if let rawPID = argument(after: "--pid"), let pid = Int32(rawPID) {
        process = ProcessInspector.stamp(pid: pid)
    } else {
        process = ProcessInspector.findAgentProcess(agent: agent)
            ?? ProcessInspector.findNodeProcess()
    }

    let directory = try StateFiles.directory()
    let payload = try HookPayload(json: json)
    let key = SessionState.key(agent: agent, externalSessionID: payload.externalSessionID)
    guard let process else { return }

    try StateFiles.withSessionLock(key, in: directory) {
        let previous = StateFiles.read(from: directory.appendingPathComponent("\(key).json"))
        guard let state = payload.state(agent: agent, process: process, previous: previous) else {
            return
        }
        try StateFiles.write(state, to: directory)
    }
}

do {
    try report()
} catch {
    // Leave the reason where the panel can find it. A hook that fails quietly is how a stale
    // reporter goes unnoticed for weeks. Exit 1 rather than 2: an agent treats 2 as a request
    // to block the tool call, and a reporting problem must never stop the user's work.
    StateFiles.recordReportingFailure(summary(of: error))
    fputs("codewindow-report: \(error)\n", stderr)
    exit(1)
}
exit(0)
