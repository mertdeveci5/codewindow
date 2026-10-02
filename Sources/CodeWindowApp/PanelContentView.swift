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
/// No timers and no clocks. The panel only moves when state moves; the one repeating
/// animation is the docked island's working glyph, which runs only while an agent works.
struct PanelContentView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var updateReminder: UpdateReminder
    @ObservedObject var dock: TopDockModel
    @ObservedObject var cloudView: CloudViewController
    @ObservedObject var inbox: InboxStore
    let reportFullContentSize: (CGSize) -> Void
    let reportExpandedContentWidth: (CGFloat) -> Void
    let reportScrollableListHeight: (CGFloat) -> Void
    let installHooks: () async -> PanelNotice
    let uninstallHooks: () async -> PanelNotice
    let checkHooks: () async -> Bool
    let checkForUpdates: () -> Void
    let hidePanel: () -> Void
    let activateTerminal: (PresentedSession) -> Bool
    let hoverSession: (PresentedSession, Bool) -> Void
    let toggleDock: () -> Void
    let revealPanel: () -> Void
    let foldPanel: () -> Void
    let islandHoverChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("hookSetupPromptDismissed") private var hookSetupPromptDismissed = false
    @State private var hooksInstalled: Bool?
    @State private var isInstallingHooks = false
    @State private var isUninstallingHooks = false
    @State private var confirmsUninstall = false
    @State private var confirmsCloudSetup = false
    @State private var confirmsCloudTurnOff = false
    @State private var confirmsCloudForget = false
    @State private var notice: PanelNotice?
    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        Group {
            if dock.isDocked {
                DockedIsland(
                    sessions: store.sessions,
                    dock: dock,
                    hooksInstalled: hooksInstalled,
                    reduceMotion: reduceMotion,
                    listBody: panelBody,
                    reportExpandedWidth: reportExpandedContentWidth,
                    reportListSize: reportFullContentSize,
                    waitingCount: inbox.isEnabled ? inbox.waiting.count : 0,
                    hoverChanged: islandHoverChanged,
                    open: revealPanel,
                    close: foldPanel
                )
            } else {
                floatingPanel
                    // While the window briefly holds a taller stage, the panel stays pinned to
                    // the corner it grows from.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
            .onAppear { reportScrollableListHeight(activeScrollableListHeight) }
            .onChange(of: activeScrollableListHeight, perform: reportScrollableListHeight)
            .onAppear { showReportingFailure(store.reportingFailure) }
            .onChange(of: inbox.deliveryFailure) { failure in
                guard let failure else { return }
                show(PanelNotice(message: failure, succeeded: false))
                inbox.deliveryFailure = nil
            }
            .onChange(of: store.reportingFailure, perform: showReportingFailure)
            .task {
                let installed = await checkHooks()
                if hooksInstalled == nil {
                    hooksInstalled = installed
                }
            }
            .contextMenu {
                if inbox.isEnabled, !inbox.waiting.isEmpty {
                    Button("Answer Next Waiting") { inbox.openOldest() }
                }
                Toggle(
                    "Inbox Mode",
                    isOn: Binding(get: { inbox.isEnabled }, set: { inbox.setEnabled($0) })
                )
                Divider()
                Button(cloudView.setupTitle) {
                    beginCloudViewAction()
                }
                .disabled(cloudView.isBusy)
                if cloudView.canOpen {
                    Button("Copy Cloud View Link") {
                        cloudView.copyLink()
                    }
                }
                if cloudView.isConfigured, !cloudView.hasPendingDeletion {
                    Button("Turn Off Cloud View…", role: .destructive) {
                        confirmsCloudTurnOff = true
                    }
                    .disabled(cloudView.isBusy)
                }
                if cloudView.canForgetSavedView {
                    Button("Forget Saved Cloud View…", role: .destructive) {
                        confirmsCloudForget = true
                    }
                }
                Divider()
                Button("Install or update agent hooks…") {
                    Task { await installAgentHooks() }
                }
                Button("Remove agent hooks and quit…", role: .destructive) {
                    confirmsUninstall = true
                }
                .disabled(isInstallingHooks || isUninstallingHooks)
                Button("Check for Updates…", action: checkForUpdates)
                Divider()
                Button(dock.isDocked ? "Detach from Top" : "Dock at Top", action: toggleDock)
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
            .alert("Set up public Cloud View?", isPresented: $confirmsCloudSetup) {
                Button("Cancel", role: .cancel) {
                    cloudView.cancelConsent()
                }
                Button("Create Public View") {
                    Task { await cloudView.createCloudView() }
                }
            } message: {
                Text("CodeWindow will create a public Cool Computer. Anyone with the link can view the bounded session summaries and recent activity shown by Cloud View. Agents keep running on this Mac, and the view goes offline when CodeWindow stops updating it.")
            }
            .alert("Turn off Cloud View?", isPresented: $confirmsCloudTurnOff) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Cloud View", role: .destructive) {
                    Task { await cloudView.turnOff() }
                }
            } message: {
                Text("This permanently deletes the dedicated Cool Computer and its link. Your local CodeWindow sessions and agent setup are unchanged.")
            }
            .alert("Forget the saved Cloud View?", isPresented: $confirmsCloudForget) {
                Button("Cancel", role: .cancel) {}
                Button("Forget Saved View", role: .destructive) {
                    cloudView.forgetSavedView()
                }
            } message: {
                Text("CodeWindow will remove only its local saved link. It will not change or delete the unverified Cool Computer. You can then set up a new sequential Cloud View.")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CodeWindow, agent activity")
    }

    /// The rows and status lines both the floating panel and the unfolded island show.
    private var panelBody: some View {
        stack
            .padding(PanelMetrics.bezel)
            .frame(width: PanelMetrics.width)
    }

    private var floatingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PanelMetrics.outerRadius, style: .continuous)
    }

    private var floatingPanel: some View {
        panelBody
            .clipShape(floatingShape)
            .cwGlassSurface(
                in: floatingShape,
                reduceTransparency: reduceTransparency,
                increasedContrast: contrast == .increased
            )
            .overlay {
                // Nearing the dock, the edge brightens as the island fades in at the camera.
                floatingShape
                    .strokeBorder(Color.white.opacity(0.34 * dock.dockProximity), lineWidth: 0.75)
                    .accessibilityHidden(true)
            }
            .contentShape(floatingShape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dock.dockProximity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(PanelHeightKey.self) { height in
                reportFullContentSize(CGSize(width: PanelMetrics.width, height: height))
            }
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
                HookRestartRow()
                    .transition(.opacity)
            }
            if let availableVersion = updateReminder.availableVersion {
                AvailableUpdateRow(version: availableVersion, showUpdate: checkForUpdates)
                    .transition(.opacity)
            }
            if let status = cloudView.statusPresentation {
                CloudViewStatusRow(
                    status: status,
                    retry: beginCloudViewAction
                )
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
        .animation(motion, value: cloudView.statusPresentation)
        .animation(motion, value: inbox.isEnabled)
    }

    private func beginCloudViewAction() {
        if cloudView.canOpen {
            cloudView.open()
            return
        }
        revealPanel()
        Task {
            if await cloudView.prepareSetup() {
                confirmsCloudSetup = true
            }
        }
    }

    private enum ListEntry: Identifiable {
        case waitingHeader
        case waiting(PresentedSession, InboxItem)
        case session(PresentedSession)

        /// A session keeps one identity whether it is waiting or working, so moving between
        /// the sections is the same row traveling, not one row leaving and another arriving.
        var id: String {
            switch self {
            case .waitingHeader: "inbox-waiting-header"
            case let .waiting(session, _), let .session(session): session.id
            }
        }
    }

    /// Waiting sessions rise into their own section at the top, oldest first; every other
    /// session keeps the order it always has.
    private var listEntries: [ListEntry] {
        guard inbox.isEnabled else { return store.sessions.map(ListEntry.session) }
        var waitingIDs = Set<String>()
        var entries: [ListEntry] = []
        for item in inbox.waiting {
            guard let session = store.sessions.first(where: { $0.id == item.sessionKey }),
                  waitingIDs.insert(session.id).inserted
            else { continue }
            entries.append(.waiting(session, item))
        }
        if !entries.isEmpty || inbox.isClear {
            entries.insert(.waitingHeader, at: 0)
        }
        entries += store.sessions.filter { !waitingIDs.contains($0.id) }.map(ListEntry.session)
        return entries
    }

    /// The list scrolls once it outgrows `maximumListHeight`. Without this the rows past
    /// the panel edge are clipped by the window and no gesture can ever reach them.
    @ViewBuilder
    private var sessionList: some View {
        if store.sessions.isEmpty {
            EmptyRow()
                .transition(.opacity)
        } else {
            let entries = listEntries
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(for: entry, showsDivider: index > 0 && !isHeader(entries[index - 1]))
                                .transition(rowTransition)
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ListHeightKey.self, value: geometry.size.height)
                        }
                    }
                }
                .frame(height: listHeight)
                .onPreferenceChange(ListHeightKey.self) { listContentHeight = $0 }
                .onChange(of: inbox.openItemID) { _ in
                    // An opened card at the bottom of a long list scrolls into view whole.
                    guard let session = inbox.openItem?.sessionKey else { return }
                    withAnimation(motion) { proxy.scrollTo(session, anchor: .top) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: ListEntry, showsDivider: Bool) -> some View {
        switch entry {
        case .waitingHeader:
            InboxSectionHeader(
                count: inbox.waiting.count,
                isClear: inbox.isClear && inbox.waiting.isEmpty,
                reduceMotion: reduceMotion
            )
        case let .waiting(session, item):
            WaitingSessionRow(
                session: session,
                item: item,
                isOpen: inbox.openItemID == item.id,
                showsDivider: showsDivider,
                reduceMotion: reduceMotion,
                inbox: inbox,
                openTerminal: { _ = activateTerminal(session) }
            )
        case let .session(session):
            SessionRow(
                session: session,
                showsDivider: showsDivider,
                reduceMotion: reduceMotion,
                hooksInstalled: hooksInstalled,
                select: { select(session) },
                hoverChanged: { hoverSession(session, $0) }
            )
        }
    }

    private func isHeader(_ entry: ListEntry) -> Bool {
        if case .waitingHeader = entry { true } else { false }
    }

    private var listHeight: CGFloat {
        // An open card may need more room than the usual eight rows.
        let limit = PanelMetrics.maximumListHeight + (inbox.openItemID == nil ? 0 : 200)
        return min(max(listContentHeight, PanelMetrics.rowHeight), limit)
    }

    private var isSessionListOverflowing: Bool {
        listContentHeight > PanelMetrics.maximumListHeight + (inbox.openItemID == nil ? 0 : 200)
    }

    /// Height of the scrollable band, measured up from the panel's bottom bezel. Zero while
    /// every session fits, which keeps trackpad gestures moving the panel as they always have.
    private var scrollableListHeight: CGFloat {
        isSessionListOverflowing ? listHeight : 0
    }

    /// Only a visible list can scroll; the smaller island states are all drag surface.
    private var activeScrollableListHeight: CGFloat {
        !dock.isDocked || dock.isUnfolded ? scrollableListHeight : 0
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

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: select) {
            header
        }
        .buttonStyle(.plain)
        .background {
            // Concentric with the panel: the row radius is the outer radius minus the bezel.
            RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
                .fill(rowFill)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .overlay(alignment: .top) {
            if showsDivider {
                PanelPalette.divider
                    .frame(height: PanelMetrics.separatorHeight)
                    .padding(.leading, PanelMetrics.separatorInset)
                    .padding(.trailing, PanelMetrics.rowInsetHorizontal)
            }
        }
        .onHover { hovered in
            isHovered = hovered
            hoverChanged(hovered)
        }
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint("Activates the terminal for this session")
    }

    private var rowFill: Color {
        if session.needsAttention { return PanelPalette.attention.opacity(isHovered ? 0.22 : 0.16) }
        guard isHovered else { return .clear }
        return contrast == .increased ? PanelPalette.rowHover.opacity(2) : PanelPalette.rowHover
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

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
