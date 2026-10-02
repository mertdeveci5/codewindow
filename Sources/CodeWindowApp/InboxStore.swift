@preconcurrency import Dispatch
import AppKit
import CodeWindowCore
import Darwin
import SwiftUI

/// The sessions waiting on the user, the inbox view's state, and the one place answers are
/// sent from.
@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var isEnabled = false
    /// Items answered from the inbox but not yet confirmed gone, so they leave the list at once.
    @Published private(set) var sending: Set<String> = []
    @Published var deliveryFailure: String?
    /// The inbox view is showing: the panel or island grown around the waiting sessions.
    @Published private(set) var isOpen = false
    @Published private(set) var selectedItemID: String?
    /// Which way the reading pane last moved through the list: down (+1) or up (-1).
    @Published private(set) var travel = 1
    /// Just answered, shown for a moment with what happened before leaving the list.
    @Published private(set) var answered: [String: (item: InboxItem, outcome: String)] = [:]
    /// True for a moment after the last waiting session is answered.
    @Published private(set) var isClear = false
    /// Unsent replies, kept when the inbox closes so nothing typed is ever lost.
    @Published var drafts: [String: String] = [:]
    /// The reply field has focus, so the inbox does not close under the user's hands.
    @Published var isComposing = false

    private let stateDirectory: URL
    private var root: URL?
    private var itemsSource: DispatchSourceFileSystemObject?
    private var livenessTimer: DispatchSourceTimer?

    init(stateDirectory: URL) {
        self.stateDirectory = stateDirectory
        let root = InboxFiles.root(stateDirectory: stateDirectory)
        isEnabled = InboxFiles.isEnabled(in: root)
        if isEnabled { startWatching() }
    }

    deinit {
        itemsSource?.cancel()
        livenessTimer?.cancel()
    }

    /// Everything waiting, oldest first, minus whatever was just answered here.
    var waiting: [InboxItem] {
        items.filter { !sending.contains($0.id) }
    }

    /// The sidebar: everything waiting plus anything answered a moment ago, oldest first, so an
    /// answered session visibly settles before it leaves.
    var sidebar: [InboxItem] {
        let waitingIDs = Set(waiting.map(\.id))
        let recent = answered.values.map(\.item).filter { !waitingIDs.contains($0.id) }
        return (waiting + recent).sorted { $0.createdAt < $1.createdAt }
    }

    var selectedItem: InboxItem? {
        waiting.first { $0.id == selectedItemID }
    }

    /// Mid-reply: the field has focus and holds unsent words. Only then does the inbox stay open
    /// when the pointer leaves; an empty field is not a reason to keep it up.
    var holdsOpen: Bool {
        guard isComposing, let selectedItemID else { return false }
        return !(drafts[selectedItemID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func outcome(of item: InboxItem) -> String? {
        answered[item.id]?.outcome
    }

    // MARK: Opening

    /// Opens the inbox on a session, or on the one that has waited longest.
    func open(selecting item: InboxItem? = nil) {
        guard isEnabled else { return }
        let target = item.flatMap { candidate in waiting.first { $0.id == candidate.id } } ?? waiting.first
        if let target {
            isClear = false
            if selectedItemID == nil || item != nil { selectedItemID = target.id }
        }
        guard !isOpen else { return }
        withAnimation(Self.motion) { isOpen = true }
    }

    func close() {
        guard isOpen else { return }
        isComposing = false
        withAnimation(Self.motion) { isOpen = false }
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func select(_ item: InboxItem) {
        guard item.id != selectedItemID, waiting.contains(where: { $0.id == item.id }) else { return }
        let order = waiting.map(\.id)
        let from = order.firstIndex { $0 == selectedItemID } ?? -1
        let to = order.firstIndex { $0 == item.id } ?? 0
        travel = to >= from ? 1 : -1
        withAnimation(Self.travelMotion) { selectedItemID = item.id }
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let list = waiting
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedItemID } ?? 0
        select(list[min(max(index + offset, 0), list.count - 1)])
    }

    /// After an answer the session shows what happened for a moment and slides out of the list,
    /// and the reading pane moves on to the next one, like archiving in a mail inbox. Answering
    /// the last one marks the moment, then the inbox folds itself away.
    private func advance(after item: InboxItem, outcome: String) {
        drafts[item.id] = nil
        let order = items.map(\.id)
        let index = order.firstIndex(of: item.id) ?? 0
        let remaining = waiting.filter { $0.id != item.id }
        withAnimation(Self.motion) { answered[item.id] = (item, outcome) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            withAnimation(Self.motion) { _ = self.answered.removeValue(forKey: item.id) }
        }
        guard let next = remaining.first(where: { (order.firstIndex(of: $0.id) ?? 0) > index })
            ?? remaining.last
        else {
            withAnimation(Self.motion) {
                selectedItemID = nil
                isClear = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.isClear else { return }
                withAnimation(Self.motion) { self.isClear = false }
                if self.waiting.isEmpty { self.close() }
            }
            return
        }
        travel = 1
        withAnimation(Self.travelMotion) { selectedItemID = next.id }
    }

    private static var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : IslandMotion.resize
    }

    /// Family's quick travel between peers: in from about 25pt, settled in about a tenth of a
    /// second. Reduce Motion keeps a short crossfade so the change still reads.
    private static var travelMotion: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.12)
            : .spring(response: 0.2, dampingFraction: 0.86)
    }

    // MARK: Mode

    func setEnabled(_ enabled: Bool) {
        do {
            let root = try InboxFiles.directory(stateDirectory: stateDirectory)
            try InboxFiles.setEnabled(enabled, in: root)
            isEnabled = enabled
            if enabled {
                startWatching()
            } else {
                stopWatching()
                isOpen = false
                selectedItemID = nil
                items = []
                sending = []
                drafts = [:]
                answered = [:]
            }
        } catch {
            deliveryFailure = "Inbox mode could not change · \(error.localizedDescription)"
        }
    }

    private func startWatching() {
        guard itemsSource == nil, let root = try? InboxFiles.directory(stateDirectory: stateDirectory) else {
            return
        }
        self.root = root
        watch(InboxFiles.itemsDirectory(in: root))
        // A hook killed with its agent cannot clean up after itself; sweep for those.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        livenessTimer = timer
        refresh()
    }

    private func stopWatching() {
        itemsSource?.cancel()
        itemsSource = nil
        livenessTimer?.cancel()
        livenessTimer = nil
    }

    private func watch(_ directory: URL) {
        let descriptor = Darwin.open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        itemsSource = source
    }

    func refresh() {
        guard let root else { return }
        var live: [InboxItem] = []
        for item in InboxFiles.all(in: root) {
            if ProcessInspector.isCurrent(item.process) {
                live.append(item)
            } else {
                InboxFiles.remove(itemID: item.id, in: root)
            }
        }
        if live != items {
            withAnimation(Self.motion) { items = live }
        }
        let ids = Set(live.map(\.id))
        sending.formIntersection(ids)
        drafts = drafts.filter { ids.contains($0.key) }
        // The selected session moved on in the terminal: show the next one instead.
        if isOpen, selectedItem == nil, !isClear, let first = waiting.first {
            withAnimation(Self.travelMotion) { selectedItemID = first.id }
        }
    }

    // MARK: Answers

    func reply(_ text: String, to item: InboxItem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard item.replyDelivery == .codexQueue else {
            if respond(.reply(trimmed), to: item) { advance(after: item, outcome: "Replied") }
            return
        }
        sending.insert(item.id)
        advance(after: item, outcome: "Replied")
        let thread = item.externalSessionID
        Task {
            let result = await Self.queueCodexMessage(trimmed, thread: thread)
            switch result {
            case .success:
                if let root { InboxFiles.remove(itemID: item.id, in: root) }
                refresh()
            case let .failure(message):
                sending.remove(item.id)
                drafts[item.id] = trimmed
                deliveryFailure = message
            }
        }
    }

    func allow(_ item: InboxItem) {
        if respond(.allow, to: item) { advance(after: item, outcome: "Approved") }
    }

    func deny(_ item: InboxItem, reason: String?) {
        let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if respond(.deny(reason: reason?.isEmpty == false ? reason : nil), to: item) {
            advance(after: item, outcome: "Denied")
        }
    }

    func answerInTerminal(_ item: InboxItem) {
        // A Codex reply has no hook waiting, so the item simply leaves the inbox.
        if !item.request.isPermission, item.replyDelivery == .codexQueue, let root {
            InboxFiles.remove(itemID: item.id, in: root)
            sending.insert(item.id)
            advance(after: item, outcome: "In terminal")
            return
        }
        if respond(.answerInTerminal, to: item) { advance(after: item, outcome: "In terminal") }
    }

    @discardableResult
    private func respond(_ response: InboxResponse, to item: InboxItem) -> Bool {
        guard let root else { return false }
        guard InboxFiles.item(id: item.id, in: root) != nil else {
            deliveryFailure = "\(item.agent.displayName) already moved on in the terminal"
            refresh()
            return false
        }
        do {
            try InboxFiles.respond(response, to: item.id, in: root)
            sending.insert(item.id)
            return true
        } catch {
            deliveryFailure = "Answer not sent · \(error.localizedDescription)"
            return false
        }
    }

    private enum QueueResult: Sendable {
        case success
        case failure(String)
    }

    /// Codex delivers queued messages to the live session through its own local app server, as
    /// if the user had typed them, so no hook has to stay open while the item waits.
    nonisolated private static func queueCodexMessage(_ text: String, thread: String) async -> QueueResult {
        await Task.detached(priority: .userInitiated) {
            runCodexQueue(text, thread: thread)
        }.value
    }

    nonisolated private static func runCodexQueue(_ text: String, thread: String) -> QueueResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let codex = CodexHookTrust.discovered(home: home)?.executableURL else {
            return .failure("Codex is not installed where CodeWindow can find it")
        }
        let process = Process()
        process.executableURL = codex
        process.arguments = ["queue", "--thread", thread, "--message", text]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return .failure("Codex could not start · \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return .failure("Codex did not accept the reply in time")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: data.prefix(400), as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .last
                .map(String.init) ?? "exit \(process.terminationStatus)"
            return .failure("Codex did not take the reply · \(detail)")
        }
        return .success
    }
}
