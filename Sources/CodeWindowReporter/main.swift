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
    let previous = StateFiles.read(from: directory.appendingPathComponent("\(key).json"))
    guard let process,
          let state = payload.state(
              agent: agent,
              process: process,
              previousTaskPreview: previous?.taskPreview
          )
    else { return }

    try StateFiles.write(state, to: directory)
}

try? report()
exit(0)
