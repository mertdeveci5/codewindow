@preconcurrency import Combine
@preconcurrency import Dispatch
import CodeWindowCore
import Darwin
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [PresentedSession] = []
    @Published private(set) var feeds: [String: [SessionFeedEvent]] = [:]
    /// Set when a hook could not record activity. The panel says so once and clears it, because
    /// the alternative is a panel that quietly stops moving with no way to tell why.
    @Published private(set) var reportingFailure: String?

    private let directory: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var processSources: [String: DispatchSourceProcess] = [:]
    private var discoveryTimer: DispatchSourceTimer?
    private var deliveredEventIDs: [String: Set<UUID>] = [:]
    private let discoveryQueue = DispatchQueue(label: "dev.codewindow.process-discovery", qos: .utility)
    private var isDiscovering = false

    init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            self.directory = try StateFiles.directory()
        }
        refresh()
        watchDirectory()
        watchForTerminalAgents()
    }

    deinit {
        directorySource?.cancel()
        discoveryTimer?.cancel()
        processSources.values.forEach { $0.cancel() }
    }

    private func watchDirectory() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.directorySource?.data ?? []
            if events.contains(.rename) || events.contains(.delete) {
                self.reopenDirectory()
            } else {
                self.refresh()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    private func reopenDirectory() {
        directorySource?.cancel()
        directorySource = nil
        guard (try? StateFiles.directory(environment: ["CODEWINDOW_STATE_DIR": directory.path])) != nil else {
            return
        }
        watchDirectory()
        refresh()
        discoverTerminalAgents()
    }

    private func watchForTerminalAgents() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in self?.discoverTerminalAgents() }
        timer.resume()
        discoveryTimer = timer
        discoverTerminalAgents()
    }

    /// Hooks update immediately through the directory watcher. Process discovery is only
    /// a fallback, so back it off once at least one session is already represented.
    private func scheduleDiscovery() {
        guard let discoveryTimer else { return }
        let hasSessions = !sessions.isEmpty
        discoveryTimer.schedule(
            deadline: .now() + .seconds(hasSessions ? 15 : 5),
            repeating: .never,
            leeway: .seconds(hasSessions ? 3 : 1)
        )
    }

    private func discoverTerminalAgents() {
        guard !isDiscovering else { return }
        isDiscovering = true
        discoveryQueue.async { [weak self] in
            let processes = ProcessInspector.terminalAgentProcesses()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDiscovering = false
                self.refresh(discoveredProcesses: processes)
                self.scheduleDiscovery()
            }
        }
    }

    private func refresh(discoveredProcesses: [TerminalAgentProcess]? = nil) {
        let wasEmpty = sessions.isEmpty
        var hooked: [SessionState] = []
        var nextFeeds = feeds
        // A state file re-offers the events it still carries. Remembering the last run it
        // carried folds each event in exactly once without holding every id ever seen: an
        // event that has slid out of the file can never be offered again.
        var nextDeliveredEventIDs: [String: Set<UUID>] = [:]
        for entry in StateFiles.all(in: directory) {
            guard let state = entry.state,
                  state.activity != .ended,
                  ProcessInspector.isCurrent(state.process)
            else {
                discard(entry.url)
                continue
            }
            hooked.append(state)
            let delivered = deliveredEventIDs[state.id] ?? []
            for event in state.feedEvents where !delivered.contains(event.id) {
                nextFeeds[state.id] = SessionFeed.appending(event, to: nextFeeds[state.id] ?? [])
            }
            nextDeliveredEventIDs[state.id] = Set(state.feedEvents.map(\.id))
        }
        deliveredEventIDs = nextDeliveredEventIDs

        let failure = StateFiles.reportingFailure(in: directory)
        if reportingFailure != failure {
            reportingFailure = failure
        }

        let hookedProcesses = Set(hooked.map(\.process))
        let diagnostics = discoveredProcesses?.map(PresentedSession.detected)
            ?? sessions.filter(\.isDiagnostic)
        let discovered = diagnostics
            .filter { ProcessInspector.isCurrent($0.process) }
            .filter { !hookedProcesses.contains($0.process) }
            .filter { candidate in
                // Codex can start a bundled Codex helper beneath the real terminal process.
                // The helper inherits its TTY and working directory, but it is part of the
                // already reported session rather than another agent missing its hooks.
                let sameAgentAncestors = Set(hooked.compactMap { state in
                    state.agent == candidate.agent ? state.process : nil
                })
                return !ProcessInspector.process(
                    candidate.process,
                    descendsFromAny: sameAgentAncestors
                )
            }

        let next = (hooked.map(PresentedSession.reported) + discovered).sorted {
            if $0.activity.priority != $1.activity.priority {
                return $0.activity.priority < $1.activity.priority
            }
            return $0.updatedAt > $1.updatedAt
        }
        let liveSessionIDs = Set(next.map(\.id))
        nextFeeds = nextFeeds.filter { liveSessionIDs.contains($0.key) }
        if feeds != nextFeeds {
            feeds = nextFeeds
        }
        if sessions != next {
            sessions = next
        }
        reconcileProcessSources()
        if !wasEmpty && sessions.isEmpty {
            scheduleDiscovery()
        }
    }

    func acknowledgeReportingFailure() {
        StateFiles.clearReportingFailure(in: directory)
        reportingFailure = nil
    }

    /// A session file and the lock its hooks coordinate through belong together.
    private func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        let key = file.deletingPathExtension().lastPathComponent
        try? FileManager.default.removeItem(at: StateFiles.lockFile(for: key, in: directory))
    }

    private func reconcileProcessSources() {
        let liveKeys = Set(sessions.map(\.id))
        for key in processSources.keys where !liveKeys.contains(key) {
            processSources.removeValue(forKey: key)?.cancel()
        }

        for session in sessions where processSources[session.id] == nil {
            let source = DispatchSource.makeProcessSource(
                identifier: pid_t(session.process.pid),
                eventMask: .exit,
                queue: .main
            )
            source.setEventHandler { [weak self] in self?.discoverTerminalAgents() }
            source.resume()
            processSources[session.id] = source
        }
    }
}
