@preconcurrency import Dispatch
import AppKit
import CodeWindowCore
import Darwin
import SwiftUI

/// The sessions waiting on the user, and the one place their answers are sent from.
@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var isEnabled = false
    /// Items answered from the inbox but not yet confirmed gone, so they leave the list at once.
    @Published private(set) var sending: Set<String> = []
    @Published var deliveryFailure: String?
    /// The waiting row currently open into a card in the panel.
    @Published private(set) var openItemID: String?
    /// True for a moment after the last waiting session is answered.
    @Published private(set) var isClear = false
    /// Unsent replies, kept when a card closes so nothing typed is ever lost.
    @Published var drafts: [String: String] = [:]

    private let stateDirectory: URL
    private var root: URL?
    private var itemsSource: DispatchSourceFileSystemObject?
    private var livenessTimer: DispatchSourceTimer?

    init(stateDirectory: URL) {
        self.stateDirectory = stateDirectory
        let root = InboxFiles.root(stateDirectory: stateDirectory)
        isEnabled = InboxFiles.isEnabled(in: root)
        if isEnabled { open() }
    }

    deinit {
        itemsSource?.cancel()
        livenessTimer?.cancel()
    }

    /// Everything waiting, oldest first, minus whatever was just answered here.
    var waiting: [InboxItem] {
        items.filter { !sending.contains($0.id) }
    }

    var openItem: InboxItem? {
        waiting.first { $0.id == openItemID }
    }

    // MARK: Cards

    func open(_ item: InboxItem) {
        guard waiting.contains(where: { $0.id == item.id }) else { return }
        isClear = false
        withAnimation(Self.motion) { openItemID = item.id }
    }

    /// Opens the session that has waited longest. Returns false when nobody is waiting.
    @discardableResult
    func openOldest() -> Bool {
        guard let first = waiting.first else { return false }
        open(first)
        return true
    }

    func close() {
        guard openItemID != nil else { return }
        withAnimation(Self.motion) { openItemID = nil }
    }

    /// After an answer the card folds back into its row, which leaves the Waiting section as the
    /// agent starts working, and the next waiting session opens, like the next message in a mail
    /// inbox. Answering the last one marks the moment before the section folds away.
    private func advance(after item: InboxItem) {
        drafts[item.id] = nil
        let next = waiting.first { $0.id != item.id }
        withAnimation(Self.motion) { openItemID = nil }
        let delay: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.openItemID == nil else { return }
            if let next, self.waiting.contains(where: { $0.id == next.id }) {
                self.open(next)
            } else if self.waiting.isEmpty {
                self.celebrateClear()
            }
        }
    }

    private func celebrateClear() {
        withAnimation(Self.motion) { isClear = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.isClear else { return }
            withAnimation(Self.motion) { self.isClear = false }
        }
    }

    private static var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : IslandMotion.resize
    }

    // MARK: Mode

    func setEnabled(_ enabled: Bool) {
        do {
            let root = try InboxFiles.directory(stateDirectory: stateDirectory)
            try InboxFiles.setEnabled(enabled, in: root)
            isEnabled = enabled
            if enabled {
                open()
            } else {
                stopWatching()
                openItemID = nil
                items = []
                sending = []
                drafts = [:]
            }
        } catch {
            deliveryFailure = "Inbox mode could not change · \(error.localizedDescription)"
        }
    }

    private func open() {
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
        if live != items { items = live }
        let ids = Set(live.map(\.id))
        sending.formIntersection(ids)
        drafts = drafts.filter { ids.contains($0.key) }
        // The session moved on in the terminal while its card was open.
        if let openItemID, !ids.contains(openItemID) {
            withAnimation(Self.motion) { self.openItemID = nil }
        }
    }

    // MARK: Answers

    func reply(_ text: String, to item: InboxItem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard item.replyDelivery == .codexQueue else {
            if respond(.reply(trimmed), to: item) { advance(after: item) }
            return
        }
        sending.insert(item.id)
        advance(after: item)
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
        if respond(.allow, to: item) { advance(after: item) }
    }

    func deny(_ item: InboxItem, reason: String?) {
        let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if respond(.deny(reason: reason?.isEmpty == false ? reason : nil), to: item) {
            advance(after: item)
        }
    }

    func answerInTerminal(_ item: InboxItem) {
        // A Codex reply has no hook waiting, so the item simply leaves the inbox.
        if !item.request.isPermission, item.replyDelivery == .codexQueue, let root {
            InboxFiles.remove(itemID: item.id, in: root)
            close()
            refresh()
            return
        }
        if respond(.answerInTerminal, to: item) { close() }
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
