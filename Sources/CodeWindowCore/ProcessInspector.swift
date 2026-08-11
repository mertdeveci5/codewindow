import Darwin
import Foundation

public struct TerminalAgentProcess: Equatable, Sendable {
    public let agent: AgentKind
    public let process: ProcessStamp
    public let projectLabel: String

    public init(agent: AgentKind, process: ProcessStamp, projectLabel: String) {
        self.agent = agent
        self.process = process
        self.projectLabel = projectLabel
    }
}

public enum ProcessInspector {
    public static func stamp(pid: Int32) -> ProcessStamp? {
        guard let info = bsdInfo(pid: pid) else { return nil }
        return ProcessStamp(
            pid: pid,
            startedAtSeconds: UInt64(info.pbi_start_tvsec),
            startedAtMicroseconds: UInt64(info.pbi_start_tvusec)
        )
    }

    public static func isCurrent(_ expected: ProcessStamp) -> Bool {
        stamp(pid: expected.pid) == expected
    }

    public static func process(
        _ process: ProcessStamp,
        belongsToApplicationPID applicationPID: Int32,
        bundlePath: String?
    ) -> Bool {
        guard isCurrent(process) else { return false }
        return processBelongsToApplication(
            processPID: process.pid,
            applicationPID: applicationPID,
            bundlePath: bundlePath,
            parentPID: parentPID(pid:),
            executablePath: executablePath(pid:)
        )
    }

    public static func findAgentProcess(agent: AgentKind, startingAt initialPID: Int32 = getppid()) -> ProcessStamp? {
        var pid = initialPID

        for _ in 0..<16 where pid > 1 {
            if agentKind(executablePath: executablePath(pid: pid)) == agent, let stamp = stamp(pid: pid) {
                return stamp
            }
            guard let info = bsdInfo(pid: pid) else { return nil }
            pid = Int32(info.pbi_ppid)
        }
        return nil
    }

    /// Finds only native agent executables attached to a controlling terminal.
    /// This deliberately excludes desktop app servers and background helpers.
    public static func terminalAgentProcesses() -> [TerminalAgentProcess] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }

        var infoByPID: [Int32: proc_bsdinfo] = [:]
        for pid in pids.prefix(Int(count)) where pid > 1 {
            guard let info = bsdInfo(pid: pid), info.pbi_uid == getuid() else { continue }
            infoByPID[pid] = info
        }

        var sessionByPID: [Int32: TerminalAgentProcess] = [:]
        var agentByPID: [Int32: AgentKind] = [:]
        for (pid, info) in infoByPID where info.e_tdev != UInt32.max {
            guard let agent = agentKind(executablePath: executablePath(pid: pid)) else { continue }
            let process = ProcessStamp(
                pid: pid,
                startedAtSeconds: UInt64(info.pbi_start_tvsec),
                startedAtMicroseconds: UInt64(info.pbi_start_tvusec)
            )
            let cwd = currentDirectory(pid: pid) ?? "Terminal"
            sessionByPID[pid] = TerminalAgentProcess(
                agent: agent,
                process: process,
                projectLabel: SessionState.projectLabel(cwd: cwd)
            )
            agentByPID[pid] = agent
        }

        let parentByPID = infoByPID.mapValues { Int32($0.pbi_ppid) }
        let rootPIDs = highestAgentPIDs(parentByPID: parentByPID, agentByPID: agentByPID)
        return rootPIDs.compactMap { sessionByPID[$0] }
    }

    static func highestAgentPIDs(
        parentByPID: [Int32: Int32],
        agentByPID: [Int32: AgentKind]
    ) -> Set<Int32> {
        Set(agentByPID.compactMap { pid, agent in
            var ancestor = parentByPID[pid]
            var visited: Set<Int32> = []
            while let current = ancestor, current > 1, visited.insert(current).inserted {
                if agentByPID[current] == agent { return nil }
                ancestor = parentByPID[current]
            }
            return pid
        })
    }

    static func processBelongsToApplication(
        processPID: Int32,
        applicationPID: Int32,
        bundlePath: String?,
        parentPID: (Int32) -> Int32?,
        executablePath: (Int32) -> String
    ) -> Bool {
        var pid = processPID
        var visited: Set<Int32> = []

        while pid > 1, visited.insert(pid).inserted {
            if pid == applicationPID { return true }
            if let bundlePath,
               executablePath(pid).hasPrefix(bundlePath + "/Contents/")
            {
                return true
            }
            guard let parent = parentPID(pid) else { return false }
            pid = parent
        }
        return false
    }

    private static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size))
        }
        return result == size ? info : nil
    }

    private static func parentPID(pid: Int32) -> Int32? {
        if let info = bsdInfo(pid: pid) {
            return Int32(info.pbi_ppid)
        }

        // Terminal process trees commonly include the root-owned `login`
        // executable. macOS withholds its full BSD record from regular apps,
        // but still exposes the short record that contains its parent PID.
        var info = proc_bsdshortinfo()
        let size = MemoryLayout<proc_bsdshortinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, $0, Int32(size))
        }
        return result == size ? Int32(info.pbsi_ppid) : nil
    }

    private static func executablePath(pid: Int32) -> String {
        var bytes = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = bytes.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return "" }
        return String(decoding: bytes.prefix(Int(length)), as: UTF8.self)
    }

    private static func currentDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, Int32(size))
        }
        guard result == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
    }

    private static func agentKind(executablePath: String) -> AgentKind? {
        switch URL(fileURLWithPath: executablePath).lastPathComponent.lowercased() {
        case "codex": .codex
        case "claude": .claude
        case "pi": .pi
        default: nil
        }
    }
}
