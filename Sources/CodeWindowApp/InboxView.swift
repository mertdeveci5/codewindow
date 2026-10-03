import AppKit
import Carbon.HIToolbox
import CodeWindowCore
import SwiftUI

// MARK: - Inbox

/// The inbox: the island or panel grown into a column of waiting sessions beside the one being
/// answered. It is the same object as the list it opens from, only bigger, so it closes back
/// into that list or island the moment the pointer leaves.
struct InboxView: View {
    @ObservedObject var inbox: InboxStore
    let feeds: [String: [SessionFeedEvent]]
    let workingCount: Int
    let reduceMotion: Bool
    let openTerminal: (InboxItem) -> Void

    static let sidebarWidth: CGFloat = 214

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            PanelPalette.divider
                .frame(width: PanelMetrics.separatorHeight)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(
            width: TopDockPlacementPolicy.inboxSize.width,
            height: TopDockPlacementPolicy.inboxSize.height
        )
        .background(alignment: .topLeading) { keyboardShortcuts }
        .onExitCommand { inbox.close() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inbox")
        .accessibilityAction(.escape) { inbox.close() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelPalette.title)
                Spacer()
                Text(inbox.waiting.isEmpty ? "" : "\(inbox.waiting.count) waiting")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(PanelPalette.meta)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(inbox.sidebar) { item in
                        InboxSidebarRow(
                            item: item,
                            isSelected: item.id == inbox.selectedItemID,
                            outcome: inbox.outcome(of: item),
                            reduceMotion: reduceMotion,
                            select: { inbox.select(item) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            if workingCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PanelPalette.working)
                    Text("\(workingCount) working")
                        .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                        .foregroundStyle(PanelPalette.meta)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Reading pane

    @ViewBuilder
    private var detail: some View {
        if let item = inbox.selectedItem {
            InboxDetail(
                item: item,
                inbox: inbox,
                feed: feeds[item.sessionKey] ?? [],
                reduceMotion: reduceMotion,
                openTerminal: { openTerminal(item) }
            )
            .id(item.id)
            .transition(paneTransition)
        } else {
            InboxZero(isClear: inbox.isClear, reduceMotion: reduceMotion)
                .transition(.opacity)
        }
    }

    /// Moving down the list brings the next message up from below, and back the other way.
    private var paneTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = inbox.travel > 0 ? 24 : -24
        return .asymmetric(
            insertion: .offset(y: distance).combined(with: .opacity),
            removal: .offset(y: -distance).combined(with: .opacity)
        )
    }

    /// ⌘[ and ⌘] step through the waiting sessions without leaving the reply field.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Previous session", action: inbox.selectPrevious)
                .keyboardShortcut("[", modifiers: .command)
            Button("Next session", action: inbox.selectNext)
                .keyboardShortcut("]", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct InboxSidebarRow: View {
    let item: InboxItem
    let isSelected: Bool
    let outcome: String?
    let reduceMotion: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                AgentLogo(agent: item.agent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.projectLabel)
                            .font(.system(size: PanelMetrics.actionSize, weight: .medium))
                            .foregroundStyle(PanelPalette.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        InboxAge(date: item.createdAt)
                            .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                            .foregroundStyle(PanelPalette.meta)
                    }
                    if let outcome {
                        Label(outcome, systemImage: "checkmark.circle.fill")
                            .font(.system(size: PanelMetrics.metaSize, weight: .medium))
                            .foregroundStyle(PanelPalette.working)
                            .transition(.opacity)
                    } else {
                        Text(InboxSummary.text(for: item))
                            .font(.system(size: PanelMetrics.metaSize + 0.5, weight: .regular))
                            .foregroundStyle(item.request.isPermission ? PanelPalette.attention : PanelPalette.meta)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(outcome != nil)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(item.agent.displayName) in \(item.projectLabel)")
        .accessibilityValue(outcome ?? InboxSummary.text(for: item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return Color.white.opacity(0.11) }
        return isHovered ? Color.white.opacity(0.05) : .clear
    }
}

/// The open session: who is asking, what the user asked, what the agent said, and one answer.
private struct InboxDetail: View {
    let item: InboxItem
    @ObservedObject var inbox: InboxStore
    let feed: [SessionFeedEvent]
    let reduceMotion: Bool
    let openTerminal: () -> Void

    @FocusState private var isComposing: Bool

    private var draft: Binding<String> {
        Binding(get: { inbox.drafts[item.id] ?? "" }, set: { inbox.drafts[item.id] = $0 })
    }

    private var canSend: Bool {
        !(inbox.drafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelPalette.divider.frame(height: PanelMetrics.separatorHeight)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    if let task = item.task {
                        YouAsked(text: task)
                    }
                    if let message = item.message {
                        Text(InboxMarkdown.render(message))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(PanelPalette.title)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(item.agent.displayName) said")
                            .accessibilityValue(message)
                    }
                    if case let .permission(tool, detail) = item.request {
                        PermissionRequestView(agent: item.agent, tool: tool, detail: detail)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.automatic)
            PanelPalette.divider.frame(height: PanelMetrics.separatorHeight)
            if item.request.isPermission {
                permissionActions
            } else {
                composer
            }
        }
        .onAppear {
            guard !item.request.isPermission else { return }
            // The pane opens because the user chose this session; the answer starts at the cursor.
            DispatchQueue.main.async { isComposing = true }
        }
        .onChange(of: isComposing) { inbox.isComposing = $0 }
        .onDisappear { inbox.isComposing = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentLogo(agent: item.agent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.projectLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelPalette.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.agent.displayName)
                    Text("·")
                    Text(item.request.isPermission ? "needs approval" : "waiting for you")
                    Text("·")
                    InboxAge(date: item.createdAt)
                }
                .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                .foregroundStyle(PanelPalette.meta)
            }
            Spacer(minLength: 8)
            Button(action: openTerminal) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PanelPalette.meta)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .help("Open this session's terminal (⌘O)")
            .accessibilityLabel("Open terminal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply to \(item.agent.displayName)…", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(PanelPalette.title)
                .lineLimit(1...6)
                .focused($isComposing)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(isComposing ? 0.24 : 0.08), lineWidth: 0.75)
                )
                .accessibilityLabel("Reply to \(item.agent.displayName)")
                .accessibilityHint("Return sends. Option-Return adds a line. Escape closes the inbox.")

            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send and go to the next waiting session (↩)")
                .accessibilityLabel("Send reply")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : IslandMotion.resize, value: canSend)
        .padding(12)
    }

    private var permissionActions: some View {
        HStack(spacing: 8) {
            Button("Answer in Terminal") {
                inbox.answerInTerminal(item)
                openTerminal()
            }
            .help("Show the agent's own prompt in the terminal")
            Spacer(minLength: 0)
            Button("Deny") { inbox.deny(item, reason: nil) }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Deny (⌘⌫)")
            Button("Approve") { inbox.allow(item) }
                .cwGlassButton(prominent: true)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Approve and go to the next waiting session (⌘↩)")
        }
        .font(.system(size: PanelMetrics.metaSize + 0.5, weight: .medium))
        .buttonStyle(CapsuleActionButtonStyle())
        .controlSize(.regular)
        .padding(12)
    }

    private func send() {
        guard canSend else { return }
        inbox.reply(inbox.drafts[item.id] ?? "", to: item)
    }
}

private struct YouAsked: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.18))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("You asked")
                    .font(.system(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(PanelPalette.meta)
                Text(text)
                    .font(.system(size: PanelMetrics.metaSize + 1, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRequestView: View {
    let agent: AgentKind
    let tool: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(agent.displayName) wants to use \(tool)", systemImage: "exclamationmark.shield.fill")
                .font(.system(size: PanelMetrics.actionSize, weight: .medium))
                .foregroundStyle(PanelPalette.attention)
            Text(detail ?? tool)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(PanelPalette.title)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PanelPalette.attention.opacity(0.25), lineWidth: 0.75)
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InboxZero: View {
    let isClear: Bool
    let reduceMotion: Bool
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(PanelPalette.working)
                .inboxClearBounce(on: arrived, enabled: !reduceMotion)
            Text("Inbox zero")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelPalette.title)
            Text("Nothing is waiting on you.")
                .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                .foregroundStyle(PanelPalette.meta)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One small bounce for clearing the last session; nothing repeats.
        .onAppear { arrived = true }
        .accessibilityElement(children: .combine)
    }
}

enum InboxSummary {
    static func text(for item: InboxItem) -> String {
        switch item.request {
        case let .permission(tool, detail):
            return "Run \(detail ?? tool)?"
        case .reply:
            return item.message?
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "Finished and waiting"
        }
    }
}

enum InboxMarkdown {
    /// Agents write Markdown. Inline styling and line breaks render; block syntax stays readable.
    static func render(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - List rows

/// A waiting session in the ordinary list: tinted, with its question in place of its action, and
/// one click from opening the inbox on it.
struct WaitingSessionRow: View {
    let session: PresentedSession
    let item: InboxItem
    let reduceMotion: Bool
    let open: () -> Void

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: open) {
            HStack(spacing: PanelMetrics.glyphGap) {
                AgentLogo(agent: session.agent)

                VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                    Text(InboxSummary.text(for: item))
                        .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                        .foregroundStyle(item.request.isPermission ? PanelPalette.attention : PanelPalette.title)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.request.isPermission ? "needs approval" : "waiting for you")
                            .fixedSize()
                        Text("·")
                        Text(session.projectLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(-1)
                    }
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                }

                Spacer(minLength: 6)

                InboxAge(date: item.createdAt)
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PanelPalette.meta.opacity(isHovered ? 1 : 0.5))
            }
            .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
            .frame(height: PanelMetrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                    .fill(fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .help("Answer in the inbox")
        .accessibilityLabel("\(session.agent.displayName) in \(session.projectLabel)")
        .accessibilityValue(InboxSummary.text(for: item))
        .accessibilityHint("Opens the inbox on this session")
    }

    private var fill: Color {
        let boost: Double = contrast == .increased ? 1.8 : 1
        if item.request.isPermission {
            return PanelPalette.attention.opacity((isHovered ? 0.22 : 0.15) * boost)
        }
        return Color.white.opacity((isHovered ? 0.11 : 0.065) * boost)
    }
}

/// Separates what waits on the user from what is busy on its own.
struct ListSectionHeader: View {
    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    var action: (() -> Void)?
    let reduceMotion: Bool

    var body: some View {
        let content = HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(PanelPalette.meta)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PanelPalette.meta.opacity(0.8))
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if action != nil {
                Text("Open inbox")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PanelPalette.meta)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PanelPalette.meta)
            }
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: 24)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : IslandMotion.resize, value: count)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .help("Open the inbox (\(InboxHotKey.display))")
                .accessibilityLabel("\(count) \(title)")
                .accessibilityHint("Opens the inbox")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) \(title)")
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private extension View {
    /// The one bit of ceremony: clearing the last waiting session.
    @ViewBuilder
    func inboxClearBounce(on trigger: Bool, enabled: Bool) -> some View {
        if #available(macOS 14, *), enabled {
            symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}

/// "now", "4m", "2h".
struct InboxAge: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.text(from: date, to: context.date))
                .monospacedDigit()
        }
    }

    static func text(from date: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }
}

// MARK: - Global shortcut

/// ⌃⌥I opens the oldest waiting session from anywhere. A registered hot key needs no
/// Accessibility permission. It lives as long as the app, so it is never unregistered.
@MainActor
final class InboxHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    static let display = "⌃⌥I"

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<InboxHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_I),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: OSType(0x4357_4958), id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }
}

// MARK: - Menu

enum CodeWindowMenu {
    /// CodeWindow never shows a menu bar, but text editing shortcuts such as ⌘C, ⌘V, and ⌘Z
    /// reach a text field only through menu key equivalents.
    @MainActor
    static func install() {
        let main = NSMenu()

        let app = NSMenu(title: "CodeWindow")
        app.addItem(withTitle: "Quit CodeWindow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "CodeWindow")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        NSApplication.shared.mainMenu = main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
