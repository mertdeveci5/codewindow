import AppKit
import CodeWindowCore
import SwiftUI

struct PanelNotice: Equatable, Sendable {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

/// An always-on-top Live Activity: every running session remains visible and
/// each compact row shows its latest safe action.
/// No timers, no clocks, no repeating animation. The panel only moves when state moves.
struct PanelContentView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var updateReminder: UpdateReminder
    let reportHeight: (CGFloat) -> Void
    let reportScrollableListHeight: (CGFloat) -> Void
    let installHooks: () async -> PanelNotice
    let uninstallHooks: () async -> PanelNotice
    let checkHooks: () async -> Bool
    let checkForUpdates: () -> Void
    let hidePanel: () -> Void
    let activateTerminal: (PresentedSession) -> Bool
    let hoverSession: (PresentedSession, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hookSetupPromptDismissed") private var hookSetupPromptDismissed = false
    @State private var hooksInstalled: Bool?
    @State private var isInstallingHooks = false
    @State private var isUninstallingHooks = false
    @State private var confirmsUninstall = false
    @State private var notice: PanelNotice?

    var body: some View {
        stack
            .padding(PanelMetrics.bezel)
            .frame(width: PanelMetrics.width)
            .background(PanelPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                    .accessibilityHidden(true)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(PanelHeightKey.self, perform: reportHeight)
            .onAppear { reportScrollableListHeight(scrollableListHeight) }
            .onChange(of: scrollableListHeight, perform: reportScrollableListHeight)
            .onAppear { showReportingFailure(store.reportingFailure) }
            .onChange(of: store.reportingFailure, perform: showReportingFailure)
            .task {
                let installed = await checkHooks()
                if hooksInstalled == nil {
                    hooksInstalled = installed
                }
            }
            .contextMenu {
                Button("Install or update agent hooks…") {
                    Task { await installAgentHooks() }
                }
                Button("Remove agent hooks and quit…", role: .destructive) {
                    confirmsUninstall = true
                }
                .disabled(isInstallingHooks || isUninstallingHooks)
                Button("Check for Updates…", action: checkForUpdates)
                Divider()
                Button("Hide CodeWindow", action: hidePanel)
                Button("Quit CodeWindow") { NSApplication.shared.terminate(nil) }
            }
            .alert("Remove CodeWindow agent hooks?", isPresented: $confirmsUninstall) {
                Button("Cancel", role: .cancel) {}
                Button("Remove and Quit", role: .destructive) {
                    Task { await uninstallAgentHooks() }
                }
            } message: {
                Text("This removes CodeWindow's Codex and Claude hooks, Pi extension, reporter, and local state. Other agent settings stay unchanged.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CodeWindow, agent activity")
    }

    private var stack: some View {
        VStack(spacing: 0) {
            if let notice {
                NoticeRow(notice: notice)
                    .transition(.opacity)
            }
            if hooksInstalled == false, !hookSetupPromptDismissed {
                HookSetupRow(
                    isInstalling: isInstallingHooks,
                    install: { Task { await installAgentHooks() } },
                    dismiss: { hookSetupPromptDismissed = true }
                )
                .transition(.opacity)
            }
            if hooksInstalled == true, store.sessions.contains(where: \.isDiagnostic) {
                HookRestartRow(
                    showsCodexTrustStep: store.sessions.contains {
                        $0.isDiagnostic && $0.agent == .codex
                    }
                )
                    .transition(.opacity)
            }
            if let availableVersion = updateReminder.availableVersion {
                AvailableUpdateRow(version: availableVersion, showUpdate: checkForUpdates)
                    .transition(.opacity)
            }
            if isSessionListOverflowing {
                PanelDragHandle()
            }
            sessionList
        }
        .animation(motion, value: store.sessions.map(\.id))
        .animation(motion, value: hooksInstalled)
        .animation(motion, value: updateReminder.availableVersion)
        .animation(motion, value: notice)
    }

    /// The list scrolls once it outgrows `maximumListHeight`. Without this the rows past
    /// the panel edge are clipped by the window and no gesture can ever reach them.
    @ViewBuilder
    private var sessionList: some View {
        if store.sessions.isEmpty {
            EmptyRow()
                .transition(.opacity)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionRow(
                            session: session,
                            showsDivider: index > 0,
                            reduceMotion: reduceMotion,
                            hooksInstalled: hooksInstalled,
                            select: { select(session) },
                            hoverChanged: { hoverSession(session, $0) }
                        )
                        .transition(rowTransition)
                    }
                }
            }
            .frame(height: listHeight)
        }
    }

    private var listContentHeight: CGFloat {
        CGFloat(store.sessions.count) * PanelMetrics.rowHeight
    }

    private var listHeight: CGFloat {
        min(listContentHeight, PanelMetrics.maximumListHeight)
    }

    private var isSessionListOverflowing: Bool {
        listContentHeight > PanelMetrics.maximumListHeight
    }

    /// Height of the scrollable band, measured up from the panel's bottom bezel. Zero while
    /// every session fits, which keeps trackpad gestures moving the panel as they always have.
    private var scrollableListHeight: CGFloat {
        isSessionListOverflowing ? listHeight : 0
    }

    private func installAgentHooks() async {
        guard !isInstallingHooks else { return }
        isInstallingHooks = true
        let result = await installHooks()
        isInstallingHooks = false
        if result.succeeded {
            hooksInstalled = true
            hookSetupPromptDismissed = false
        }
        show(result)
    }

    private func uninstallAgentHooks() async {
        guard !isInstallingHooks, !isUninstallingHooks else { return }
        isUninstallingHooks = true
        let result = await uninstallHooks()
        isUninstallingHooks = false
        guard result.succeeded else {
            show(result)
            return
        }
        NSApplication.shared.terminate(nil)
    }

    private func select(_ session: PresentedSession) {
        if !activateTerminal(session) {
            show(PanelNotice(message: "terminal is no longer available", succeeded: false))
        }
    }

    private func showReportingFailure(_ reason: String?) {
        guard let reason else { return }
        show(PanelNotice(message: "activity not recorded · \(reason)", succeeded: false))
        store.acknowledgeReportingFailure()
    }

    private func show(_ notice: PanelNotice) {
        self.notice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6)) {
            if self.notice?.id == notice.id {
                self.notice = nil
            }
        }
    }

    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.30, dampingFraction: 0.88)
    }

    private var rowTransition: AnyTransition {
        .opacity
    }
}

// MARK: - Session rows

/// A stable movement target when the session rows need to own vertical scrolling.
/// Scroll gestures start outside the list here, so `FloatingPanel` moves in any direction.
private struct PanelDragHandle: View {
    var body: some View {
        Capsule()
            .fill(PanelPalette.meta.opacity(0.65))
            .frame(
                width: PanelMetrics.dragHandleWidth,
                height: PanelMetrics.dragHandleThickness
            )
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.dragHandleHeight)
            .contentShape(Rectangle())
            .help("Move CodeWindow")
            .accessibilityHidden(true)
    }
}

private struct SessionRow: View {
    let session: PresentedSession
    let showsDivider: Bool
    let reduceMotion: Bool
    let hooksInstalled: Bool?
    let select: () -> Void
    let hoverChanged: (Bool) -> Void

    var body: some View {
        Button(action: select) {
            header
        }
        .buttonStyle(.plain)
        .background {
            if session.needsAttention {
                RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                    .fill(PanelPalette.attention.opacity(0.16))
            }
        }
        .overlay(alignment: .top) {
            if showsDivider {
                PanelPalette.divider
                    .frame(height: PanelMetrics.separatorHeight)
                    .padding(.leading, PanelMetrics.separatorInset)
                    .padding(.trailing, PanelMetrics.rowInsetHorizontal)
            }
        }
        .onHover(perform: hoverChanged)
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint("Activates the terminal for this session")
    }

    private var header: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            AgentLogo(agent: session.agent)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                PreviewLine(session: session, reduceMotion: reduceMotion)
                identityLine
            }

            Spacer(minLength: 6)
            StatusMark(session: session, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    private var accessibilityValue: String {
        session.accessibilityDescription(hooksInstalled: hooksInstalled)
    }

    /// Identity is supporting metadata; the changing live action remains dominant.
    private var identityLine: some View {
        HStack(spacing: 4) {
            Text(session.metadataLabel(hooksInstalled: hooksInstalled))
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
}

/// The latest safe subject. Cross-fades in place when the text changes so the row never jumps.
private struct PreviewLine: View {
    let session: PresentedSession
    let reduceMotion: Bool

    var body: some View {
        Text(session.primaryLabel)
            .font(primaryFont)
            .foregroundStyle(primaryColor)
            .lineLimit(1)
            .truncationMode(session.prefersLeadingTruncation ? .head : .tail)
            .transition(transition)
            .id(session.primaryLabel)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.primaryLabel)
    }

    private var primaryFont: Font {
        if session.usesMonospacedPreview {
            return .system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced)
        }
        return .system(size: PanelMetrics.actionSize, weight: .regular)
    }

    private var primaryColor: Color {
        if session.needsAttention { return PanelPalette.attention }
        if session.isDiagnostic { return PanelPalette.diagnostic }
        return PanelPalette.title
    }

    private var transition: AnyTransition {
        .opacity
    }
}

private struct StatusMark: View {
    let session: PresentedSession
    let reduceMotion: Bool

    var body: some View {
        Group {
            if session.needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
            }
        }
        .frame(width: PanelMetrics.statusColumn)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.activity)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        PanelPalette.statusColor(for: session)
    }
}

private struct EmptyRow: View {
    var body: some View {
        HStack(spacing: PanelMetrics.glyphGap) {
            Circle()
                .fill(PanelPalette.muted)
                .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
                .frame(width: PanelMetrics.glyphSize, height: PanelMetrics.glyphSize)

            VStack(alignment: .leading, spacing: PanelMetrics.textLineGap) {
                Text("No agents running")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text("watching codex · claude · pi")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, PanelMetrics.rowInsetHorizontal)
        .frame(height: PanelMetrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CodeWindow, no terminal agents")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
