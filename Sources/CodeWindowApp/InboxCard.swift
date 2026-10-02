import AppKit
import Carbon.HIToolbox
import CodeWindowCore
import SwiftUI

/// A waiting session's row. It is the same row the session always has, risen into the Waiting
/// section; opening it grows the row in place into a card with the question and the answer, so
/// the user never leaves the panel or loses sight of which session they are answering.
struct WaitingSessionRow: View {
    let session: PresentedSession
    let item: InboxItem
    let isOpen: Bool
    let showsDivider: Bool
    let reduceMotion: Bool
    @ObservedObject var inbox: InboxStore
    let openTerminal: () -> Void

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isOpen ? inbox.close() : inbox.open(item)
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(session.agent.displayName) in \(session.projectLabel)")
            .accessibilityValue(summary)
            .accessibilityHint(isOpen ? "Closes the reply" : "Opens the reply")

            if isOpen {
                InboxCard(
                    item: item,
                    inbox: inbox,
                    reduceMotion: reduceMotion,
                    openTerminal: openTerminal
                )
                .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
                .padding(.bottom, PanelMetrics.rowInsetHorizontal)
                .transition(.inboxCardContent)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                .fill(fill)
        }
        .overlay(alignment: .top) {
            if showsDivider, !isOpen {
                PanelPalette.divider
                    .frame(height: PanelMetrics.separatorHeight)
                    .padding(.leading, PanelMetrics.separatorInset)
                    .padding(.trailing, PanelMetrics.rowInsetHorizontal)
            }
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    private var fill: Color {
        if item.request.isPermission {
            return PanelPalette.attention.opacity(isOpen ? 0.14 : (isHovered ? 0.22 : 0.16))
        }
        if isOpen { return PanelPalette.rowHover.opacity(contrast == .increased ? 2.4 : 1.3) }
        guard isHovered else { return .clear }
        return contrast == .increased ? PanelPalette.rowHover.opacity(2) : PanelPalette.rowHover
    }

    /// The row keeps its shape when it opens: same mark, same place, the question in the slot
    /// where the live action normally sits.
    private var header: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            AgentLogo(agent: session.agent)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                // Open, the card below says it all in full; the row just names who is asking.
                Text(isOpen ? session.agent.displayName : summary)
                    .font(.system(size: PanelMetrics.actionSize, weight: isOpen ? .medium : .regular))
                    .foregroundStyle(item.request.isPermission ? PanelPalette.attention : PanelPalette.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(isOpen)
                    .transition(.opacity)
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
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private var summary: String {
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

/// The open half of a waiting row: what the user asked, what the agent said, and one answer.
struct InboxCard: View {
    let item: InboxItem
    @ObservedObject var inbox: InboxStore
    let reduceMotion: Bool
    let openTerminal: () -> Void

    @FocusState private var isComposing: Bool
    @State private var messageHeight: CGFloat = 0

    private static let maximumMessageHeight: CGFloat = 150

    private var draft: Binding<String> {
        Binding(get: { inbox.drafts[item.id] ?? "" }, set: { inbox.drafts[item.id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = item.task {
                (Text("You asked  ").foregroundColor(PanelPalette.meta.opacity(0.8))
                    + Text(task).foregroundColor(PanelPalette.meta))
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .lineLimit(2)
                    .accessibilityLabel("You asked: \(task)")
            }

            if let message = item.message {
                ScrollView(.vertical) {
                    Text(Self.markdown(message))
                        .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                        .foregroundStyle(PanelPalette.title)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: InboxMessageHeightKey.self, value: proxy.size.height)
                            }
                        }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(max(messageHeight, 1), Self.maximumMessageHeight))
                .mask {
                    // A long message fades out at the bottom edge to say there is more below.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: overflows ? 0.82 : 1),
                            .init(color: .black.opacity(overflows ? 0 : 1), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .onPreferenceChange(InboxMessageHeightKey.self) { messageHeight = $0 }
                .accessibilityLabel("\(item.agent.displayName) said")
                .accessibilityValue(message)
            }

            if case let .permission(tool, detail) = item.request {
                Text(detail ?? tool)
                    .font(.system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(PanelPalette.title)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
                    .accessibilityLabel("\(item.agent.displayName) wants to run")
                    .accessibilityValue(detail ?? tool)
                permissionActions
            } else {
                composer
            }
        }
        .onAppear {
            // The card opens because the user chose it; the answer starts at the cursor.
            DispatchQueue.main.async { isComposing = true }
        }
        .onExitCommand { inbox.close() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { inbox.close() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply to \(item.agent.displayName)…", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                .foregroundStyle(PanelPalette.title)
                .lineLimit(1...6)
                .focused($isComposing)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(isComposing ? 0.22 : 0.08), lineWidth: 0.75)
                )
                .accessibilityLabel("Reply to \(item.agent.displayName)")
                .accessibilityHint("Return sends. Escape closes without sending.")

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(canSend ? Color.black : PanelPalette.meta)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(canSend ? Color.white : Color.white.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send and open the next waiting session (↩)")
            .accessibilityLabel("Send reply")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: canSend)
        }
    }

    private var permissionActions: some View {
        HStack(spacing: 6) {
            Button("Terminal") { inbox.answerInTerminal(item); openTerminal() }
                .help("Answer this in the terminal instead")
            Spacer(minLength: 0)
            Button("Deny") { inbox.deny(item, reason: nil) }
                .keyboardShortcut("n", modifiers: .command)
                .help("Deny (⌘N)")
            Button("Approve") { inbox.allow(item) }
                .cwGlassButton(prominent: true)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Approve and open the next waiting session (⌘↩)")
        }
        .font(.system(size: PanelMetrics.metaSize, weight: .medium))
        .controlSize(.small)
        .buttonStyle(CapsuleActionButtonStyle())
    }

    private var overflows: Bool {
        messageHeight > Self.maximumMessageHeight + 1
    }

    private var canSend: Bool {
        !(inbox.drafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        inbox.reply(inbox.drafts[item.id] ?? "", to: item)
    }

    /// Agents write Markdown. Inline styling and line breaks render; block syntax stays readable.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// "Waiting for you · 3", or for a moment after the last answer, "Inbox zero".
struct InboxSectionHeader: View {
    let count: Int
    let isClear: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isClear ? "checkmark.circle.fill" : "tray.full.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isClear ? PanelPalette.working : PanelPalette.attention)
                .contentTransition(.symbolEffectIfAvailable)
                .inboxClearBounce(on: isClear, enabled: !reduceMotion)
            Text(isClear ? "Inbox zero" : "Waiting for you")
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(isClear ? PanelPalette.working : PanelPalette.meta)
                .id(isClear)
                .transition(.opacity)
            Spacer(minLength: 0)
            if !isClear {
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PanelPalette.meta)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: 22)
        .animation(reduceMotion ? nil : IslandMotion.resize, value: count)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isClear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isClear ? "Inbox zero" : "\(count) waiting for you")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct InboxMessageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension ContentTransition {
    static var symbolEffectIfAvailable: ContentTransition {
        if #available(macOS 14, *) { .symbolEffect } else { .opacity }
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

extension AnyTransition {
    /// Family's tray content: the old content fades out quickly with a little blur, and the new
    /// content fades in while it grows from 90% into place, anchored to the row it opens from.
    static var inboxCardContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.18))
                .combined(with: .scale(scale: 0.9, anchor: .top)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
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
