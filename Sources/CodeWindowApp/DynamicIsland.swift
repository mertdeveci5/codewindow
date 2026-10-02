import CodeWindowCore
import SwiftUI

/// The docked panel: one true-black body that pours out of the top bezel and only ever
/// changes size. Its top band is the camera housing itself, with a slot on each side of the
/// camera; whatever the current presentation adds hangs below that band. Nothing inside is
/// bolder than medium weight: hierarchy comes from size, opacity, spacing, and color.
struct DockedIsland<ListBody: View>: View {
    let sessions: [PresentedSession]
    @ObservedObject var dock: TopDockModel
    let hooksInstalled: Bool?
    let reduceMotion: Bool
    let listBody: ListBody
    let reportExpandedWidth: (CGFloat) -> Void
    let reportListSize: (CGSize) -> Void
    /// Sessions waiting in the inbox, so a waiting reply is visible before anything opens.
    let waitingCount: Int
    let hoverChanged: (Bool) -> Void
    /// Pointer clicks reach the island through the window; these are the same two actions
    /// for VoiceOver, which cannot click a borderless panel's background.
    let open: () -> Void
    let close: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var headline: PresentedSession? {
        IslandHeadline.pick(from: sessions)
    }

    private var notch: CGRect? {
        dock.isAttachedToNotch
            ? CGRect(x: 0, y: 0, width: dock.notchWidth, height: dock.bandHeight)
            : nil
    }

    var body: some View {
        island
            // The window may briefly be larger than the island while it changes size. The
            // island always hangs from the window's top center, so it never moves inside it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(alignment: .top) { measurements }
    }

    private var island: some View {
        VStack(spacing: 0) {
            band
            presentationBody
        }
        .frame(width: dock.islandSize.width, height: dock.islandSize.height, alignment: .top)
        .background(PanelPalette.island)
        .clipShape(shape)
        .overlay {
            // Hardware needs no outline. Off a housing the island earns one hairline so it
            // does not dissolve into a dark wallpaper.
            if !dock.isAttachedToNotch {
                shape
                    .strokeBorder(
                        Color.white.opacity(contrast == .increased ? 0.30 : 0.08),
                        lineWidth: 0.75
                    )
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onHover(perform: hoverChanged)
        .accessibilityElement(children: dock.isUnfolded ? .contain : .ignore)
        .accessibilityLabel("CodeWindow, docked at the top of the screen")
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(dock.isUnfolded ? [] : .isButton)
        .accessibilityHint(dock.isUnfolded ? "Escape closes the session list" : "Opens the session list")
        .accessibilityAction {
            if !dock.isUnfolded { open() }
        }
        .accessibilityAction(.escape) {
            if dock.isUnfolded { close() }
        }
    }

    private var shape: IslandShape {
        IslandShape(
            presentation: dock.presentation,
            attachedToNotch: dock.isAttachedToNotch,
            bandHeight: dock.bandHeight
        )
    }

    /// The slots beside the camera stay put through every presentation, so expanding and
    /// unfolding read as the same object growing rather than a new view replacing it.
    private var band: some View {
        HStack(spacing: 0) {
            leadingSlot
                .frame(maxWidth: .infinity)
                .animation(leadingSlotAnimation, value: headline?.agent)
            Color.clear
                .frame(width: TopDockPlacementPolicy.centerGap(notch: notch))
            IslandStatusIndicator(
                sessions: sessions,
                waitingCount: waitingCount,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TopDockPlacementPolicy.flare(notch: notch))
        .frame(height: dock.bandHeight)
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if let headline, dock.presentation != .minimal {
            AgentLogo(agent: headline.agent)
                .scaleEffect(0.82)
                .frame(width: 18, height: 18)
                .id(headline.agent)
                .transition(.islandContent)
        }
    }

    private var leadingSlotAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    @ViewBuilder
    private var presentationBody: some View {
        switch dock.presentation {
        case .minimal, .compact:
            EmptyView()
        case .expanded:
            IslandExpandedBody(
                headline: headline,
                hooksInstalled: hooksInstalled,
                reduceMotion: reduceMotion,
                truncates: true
            )
            .frame(height: TopDockPlacementPolicy.expandedBodyHeight)
            .transition(.islandContent)
        case .list:
            listBody
                .transition(.islandContent)
        }
    }

    /// Hidden, unconstrained copies decide how large the island wants to be in the states it
    /// is not showing yet, so a hover or a click opens straight to the right size.
    private var measurements: some View {
        ZStack(alignment: .top) {
            IslandExpandedBody(
                headline: headline,
                hooksInstalled: hooksInstalled,
                reduceMotion: true,
                truncates: false
            )
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: IslandExpandedWidthKey.self,
                        value: proxy.size.width + TopDockPlacementPolicy.flare(notch: notch) * 2
                    )
                }
            }

            listBody
                .frame(width: PanelMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: IslandListHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onPreferenceChange(IslandExpandedWidthKey.self, perform: reportExpandedWidth)
        .onPreferenceChange(IslandListHeightKey.self) { height in
            reportListSize(CGSize(width: PanelMetrics.width, height: height))
        }
    }

    private var accessibilityValue: String {
        guard let headline else { return "no terminal agents" }
        let active = sessions.filter { $0.activity != .ended }.count
        let waiting = sessions.filter(\.needsAttention).count
        let attention = waiting > 0 ? "\(waiting) need\(waiting == 1 ? "s" : "") attention, " : ""
        let inbox = waitingCount > 0 ? "\(waitingCount) waiting in the inbox, " : ""
        return "\(active) active, \(attention)\(inbox)"
            + headline.accessibilityDescription(hooksInstalled: hooksInstalled)
    }
}

enum IslandHeadline {
    /// A session waiting on the user outranks whatever moved most recently.
    static func pick(from sessions: [PresentedSession]) -> PresentedSession? {
        let attention = sessions.filter(\.needsAttention)
        return (attention.isEmpty ? sessions : attention).max { $0.updatedAt < $1.updatedAt }
    }
}

/// The expanded peek: two lines for the concrete current action, then one quiet context line.
/// Short actions keep their context close rather than leaving a blank row.
struct IslandExpandedBody: View {
    private static let actionLineCount = 2
    private static let inset: CGFloat = 16

    let headline: PresentedSession?
    let hooksInstalled: Bool?
    let reduceMotion: Bool
    let truncates: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let headline {
                actionLine(for: headline)
                contextLine(for: headline)
            } else {
                Text("No agents running")
                    .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                    .foregroundStyle(PanelPalette.title)
                Text("watching codex · claude · pi")
                    .font(.system(size: PanelMetrics.metaSize, weight: .regular))
                    .foregroundStyle(PanelPalette.meta)
            }
        }
        .frame(
            maxWidth: truncates ? .infinity : TopDockPlacementPolicy.maximumIslandWidth - Self.inset * 2,
            alignment: .leading
        )
        .padding(.horizontal, Self.inset)
        .padding(.bottom, 4)
    }

    /// The end of a command is the part that identifies it, so long commands lose their head.
    private func actionLine(for session: PresentedSession) -> some View {
        Text(session.primaryLabel)
            .font(
                session.usesMonospacedPreview
                    ? .system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced)
                    : .system(size: PanelMetrics.actionSize, weight: .regular)
            )
            .foregroundStyle(actionColor(for: session))
            .lineLimit(Self.actionLineCount)
            .multilineTextAlignment(.leading)
            .truncationMode(session.prefersLeadingTruncation ? .head : .tail)
            .fixedSize(horizontal: false, vertical: true)
            .id(session.primaryLabel)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.primaryLabel)
    }

    private func actionColor(for session: PresentedSession) -> Color {
        if session.needsAttention { return PanelPalette.attention }
        if session.isDiagnostic { return PanelPalette.diagnostic }
        return PanelPalette.title
    }

    /// Identity is supporting metadata, exactly as in the session row: what the agent is
    /// doing, then where. The project gives way first when space runs out.
    private func contextLine(for session: PresentedSession) -> some View {
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

/// The trailing slot: a live glyph for the most urgent state across every session, plus a
/// count once there is more than one. Working is the one continuous animation in the app.
struct IslandStatusIndicator: View {
    let sessions: [PresentedSession]
    var waitingCount = 0
    let reduceMotion: Bool

    private enum Status: Equatable {
        case none
        case attention
        case waiting
        case working
        case starting
        case idle
    }

    private var status: Status {
        if sessions.isEmpty { return .none }
        if sessions.contains(where: \.needsAttention) { return .attention }
        if waitingCount > 0 { return .waiting }
        if sessions.contains(where: { $0.activity == .working }) { return .working }
        if sessions.contains(where: { $0.activity == .starting || $0.isDiagnostic }) { return .starting }
        return .idle
    }

    private var activeCount: Int {
        sessions.filter { $0.activity != .ended }.count
    }

    /// While replies wait in the inbox, the count says how many; otherwise how many are active.
    private var displayedCount: Int {
        status == .waiting ? waitingCount : activeCount
    }

    private var attentionCount: Int {
        sessions.filter(\.needsAttention).count
    }

    private var tint: Color {
        switch status {
        case .attention: PanelPalette.attention
        case .waiting: PanelPalette.title
        case .working: PanelPalette.working
        case .starting: PanelPalette.starting
        case .idle, .none: PanelPalette.muted
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            glyph
                .frame(width: 14, height: 14)
            if displayedCount > 1 || status == .waiting {
                Text("\(displayedCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: displayedCount)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: status)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch status {
        case .attention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .islandBounce(on: attentionCount, enabled: !reduceMotion)
                .transition(.scale.combined(with: .opacity))
        case .waiting:
            Image(systemName: "tray.full.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
                .islandBounce(on: waitingCount, enabled: !reduceMotion)
                .transition(.scale.combined(with: .opacity))
        case .working:
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .islandWorking(enabled: !reduceMotion)
                .transition(.scale.combined(with: .opacity))
        case .starting, .idle, .none:
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private extension View {
    @ViewBuilder
    func islandBounce(on value: Int, enabled: Bool) -> some View {
        if #available(macOS 14, *), enabled {
            symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func islandWorking(enabled: Bool) -> some View {
        if #available(macOS 14, *), enabled {
            symbolEffect(.variableColor.iterative.dimInactiveLayers)
        } else {
            self
        }
    }
}

/// The island silhouette. Under a camera housing the top edge is flush with the bezel and
/// flares outward into it at both corners, the way the housing itself meets the screen; the
/// lower corners round more as the island grows. Without a housing it is a plain pill.
struct IslandShape: InsettableShape {
    var flare: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var inset: CGFloat = 0

    init(flare: CGFloat, topRadius: CGFloat, bottomRadius: CGFloat, inset: CGFloat = 0) {
        self.flare = flare
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.inset = inset
    }

    init(presentation: IslandPresentation, attachedToNotch: Bool, bandHeight: CGFloat) {
        let grownRadius: CGFloat = presentation == .list ? 24 : 22
        let isResting = presentation == .minimal || presentation == .compact
        if attachedToNotch {
            self.init(
                flare: TopDockPlacementPolicy.bezelFlare,
                topRadius: 0,
                bottomRadius: isResting ? 12 : grownRadius
            )
        } else {
            self.init(
                flare: 0,
                topRadius: bandHeight / 2,
                bottomRadius: isResting ? bandHeight / 2 : grownRadius
            )
        }
    }

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flare, AnimatablePair(topRadius, bottomRadius)) }
        set {
            flare = newValue.first
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func inset(by amount: CGFloat) -> IslandShape {
        IslandShape(
            flare: flare,
            topRadius: max(0, topRadius - amount),
            bottomRadius: max(0, bottomRadius - amount),
            inset: inset + amount
        )
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let flare = max(0, min(flare, rect.width / 4, rect.height / 2))
        let body = rect.insetBy(dx: flare, dy: 0)
        let top = flare > 0 ? 0 : max(0, min(topRadius, body.width / 2, rect.height / 2))
        let bottom = max(0, min(bottomRadius, body.width / 2, rect.height - max(flare, top)))

        var path = Path()
        if flare > 0 {
            // Along the bezel, then a concave quarter-circle down into each wall.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: body.maxX, y: rect.minY),
                tangent2End: CGPoint(x: body.maxX, y: rect.minY + flare),
                radius: flare
            )
        } else {
            path.move(to: CGPoint(x: body.minX + top, y: rect.minY))
            path.addLine(to: CGPoint(x: body.maxX - top, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: body.maxX, y: rect.minY),
                tangent2End: CGPoint(x: body.maxX, y: rect.minY + top),
                radius: top
            )
        }
        path.addLine(to: CGPoint(x: body.maxX, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: body.maxX - bottom, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: body.minX + bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: rect.maxY),
            tangent2End: CGPoint(x: body.minX, y: rect.maxY - bottom),
            radius: bottom
        )
        if flare > 0 {
            path.addLine(to: CGPoint(x: body.minX, y: rect.minY + flare))
            path.addArc(
                tangent1End: CGPoint(x: body.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.minY),
                radius: flare
            )
        } else {
            path.addLine(to: CGPoint(x: body.minX, y: rect.minY + top))
            path.addArc(
                tangent1End: CGPoint(x: body.minX, y: rect.minY),
                tangent2End: CGPoint(x: body.minX + top, y: rect.minY),
                radius: top
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The silhouette a dragged panel is about to become, shown at the dock while the panel nears it.
struct IslandGhost: View {
    let attachedToNotch: Bool
    let bandHeight: CGFloat

    var body: some View {
        let shape = IslandShape(
            presentation: .compact,
            attachedToNotch: attachedToNotch,
            bandHeight: bandHeight
        )
        shape
            .fill(PanelPalette.island)
            .overlay {
                if !attachedToNotch {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct IslandExpandedWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IslandListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
