import CodeWindowCore
import SwiftUI

/// The folded Top Dock: one true-black island grown out of the camera housing. A connector
/// the exact measured width of the housing carries sculpted concave shoulders down into a
/// wider, pill-shaped activity bar. That bar has room for up to three lines — two for the
/// concrete current action, then one quiet context line — while short actions keep their
/// context close rather than leaving a blank row. Nothing inside it is bolder than regular
/// weight: hierarchy comes from size, opacity, spacing, and color.
struct TopDockCapsule: View {
    private enum Metrics {
        static let actionLineCount = 2
        static let lineGap: CGFloat = 2
        static let verticalPadding: CGFloat = 4
    }

    let sessions: [PresentedSession]
    /// Measured width of the camera housing. Zero on a display without one, which leaves an
    /// ordinary standalone capsule below the menu bar.
    let notchWidth: CGFloat
    let hooksInstalled: Bool?
    let reduceMotion: Bool
    let reportContentSize: (CGSize) -> Void

    /// Hovering only peeks: the bar deepens and the quiet context line brightens to full
    /// strength, nothing unfolds.
    @State private var isPeeking = false
    @State private var peekGeneration = 0

    private var isAttachedToNotch: Bool { notchWidth > 0 }

    private var headline: PresentedSession? {
        sessions.max { $0.updatedAt < $1.updatedAt }
    }

    private var activeCount: Int {
        sessions.filter { $0.activity != .ended }.count
    }

    /// The lower bar carries every pixel of content, and it is the only part that moves.
    private var barHeight: CGFloat {
        TopDockPlacementPolicy.capsuleHeight + (isPeeking ? 3 : 0)
    }

    /// How far the black reaches up into the housing so the shoulders have material to cut.
    private var connectorDrop: CGFloat {
        isAttachedToNotch ? TopDockPlacementPolicy.notchOverlap : 0
    }

    private var height: CGFloat { barHeight + connectorDrop }

    var body: some View {
        content(truncates: true)
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .padding(.top, connectorDrop)
            .background(PanelPalette.island)
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                // Hardware needs no outline. Off a housing the capsule earns one hairline
                // so it does not dissolve into a dark wallpaper.
                if !isAttachedToNotch {
                    shape
                        .strokeBorder(Color.white.opacity(isPeeking ? 0.10 : 0.05), lineWidth: 0.75)
                        .accessibilityHidden(true)
                }
            }
            .background(measurement)
            .onHover(perform: hoverChanged)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPeeking)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("CodeWindow, docked at the top of the screen")
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityHint("Click to open the session list")
    }

    /// A hidden, unconstrained copy decides how wide the island wants to be. Measuring the
    /// visible copy instead would trap it at its current width, since that copy truncates.
    private var measurement: some View {
        content(truncates: false)
            .fixedSize()
            .hidden()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TopDockSizeKey.self,
                        value: CGSize(
                            width: proxy.size.width,
                            height: height
                        )
                    )
                }
            }
            .onPreferenceChange(TopDockSizeKey.self, perform: reportContentSize)
            .accessibilityHidden(true)
    }

    /// Up to three lines on the left, the count held apart on the right, open black between.
    @ViewBuilder
    private func content(truncates: Bool) -> some View {
        HStack(spacing: 0) {
            if let headline {
                HStack(spacing: 8) {
                    AgentLogo(agent: headline.agent)
                        .scaleEffect(0.78)
                        .frame(width: 17, height: 17)

                    lines(for: headline, truncates: truncates)
                }

                Spacer(minLength: 14)

                ActiveCount(
                    count: activeCount,
                    tint: PanelPalette.statusColor(for: headline)
                )
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(PanelPalette.muted)
                        .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)

                    VStack(alignment: .leading, spacing: Metrics.lineGap) {
                        Text("no agents")
                            .font(.system(size: PanelMetrics.actionSize, weight: .regular))
                            .foregroundStyle(PanelPalette.title)
                        contextText("waiting for a terminal session")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Metrics.verticalPadding)
        .padding(.leading, isAttachedToNotch ? 13 : 11)
        .padding(.trailing, isAttachedToNotch ? 9 : 8)
    }

    /// The action preview gets the top two reserved lines so a real command or message can
    /// be read rather than guessed at; the quiet line underneath carries the same metadata +
    /// project pairing the full session row uses. The outer island stays fixed-height, while
    /// this group remains compact for one-line actions and naturally grows for two.
    private func lines(for session: PresentedSession, truncates: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.lineGap) {
            actionLine(for: session)
            contextLine(for: session)
        }
        .frame(maxWidth: truncates ? .infinity : 268, alignment: .leading)
    }

    /// The end of a command is the part that identifies it, so long commands lose their head.
    /// Two lines are allowed before that truncation kicks in.
    private func actionLine(for session: PresentedSession) -> some View {
        Text(session.primaryLabel)
            .font(
                session.usesMonospacedPreview
                    ? .system(size: PanelMetrics.commandSize, weight: .regular, design: .monospaced)
                    : .system(size: PanelMetrics.actionSize, weight: .regular)
            )
            .foregroundStyle(actionColor(for: session))
            .lineLimit(Metrics.actionLineCount)
            .multilineTextAlignment(.leading)
            .truncationMode(session.prefersLeadingTruncation ? .head : .tail)
            .fixedSize(horizontal: false, vertical: true)
            .id(session.primaryLabel)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.primaryLabel)
    }

    private func actionColor(for session: PresentedSession) -> Color {
        if session.needsAttention { return PanelPalette.attention }
        if session.isDiagnostic { return PanelPalette.diagnostic }
        return PanelPalette.title
    }

    /// Identity is supporting metadata, exactly as in the unfolded session row: what the
    /// agent is doing, then where. The project gives way first when space runs out.
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
        .opacity(isPeeking ? 1 : 0.78)
    }

    private func contextText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: PanelMetrics.metaSize, weight: .regular))
            .foregroundStyle(PanelPalette.meta)
            .opacity(isPeeking ? 1 : 0.78)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Sculpted shoulders under a camera housing, a plain capsule when there is none.
    private var shape: TopDockIslandShape {
        TopDockIslandShape(
            connectorWidth: notchWidth,
            connectorDrop: connectorDrop,
            topRadius: isAttachedToNotch
                ? TopDockPlacementPolicy.barTopRadius
                : barHeight / 2,
            // The lower body stays a true pill in both modes; attached mode additionally
            // carves the concave connector shoulders from its top edge.
            bottomRadius: isAttachedToNotch
                ? min(TopDockPlacementPolicy.barRadius, barHeight / 2)
                : barHeight / 2
        )
    }

    private func hoverChanged(_ isHovered: Bool) {
        peekGeneration &+= 1
        let generation = peekGeneration
        guard isHovered else {
            isPeeking = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard self.peekGeneration == generation else { return }
            self.isPeeking = true
        }
    }

    private var accessibilityValue: String {
        guard let headline else { return "no terminal agents" }
        return "\(activeCount) active, \(headline.accessibilityDescription(hooksInstalled: hooksInstalled))"
    }
}

/// The trailing count is its own object rather than a trailing word: a tinted capsule the
/// eye can find without reading the action line first. Its tint and enclosure do that work,
/// so the digit itself stays regular weight like everything else in the island.
private struct ActiveCount: View {
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: PanelMetrics.statusDot, height: PanelMetrics.statusDot)
            Text("\(count)")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The island silhouette: a black connector as wide as the measured camera housing, two
/// concave shoulders carved out of the overlap, and a wider, pill-shaped activity bar
/// hanging below.
/// `UnevenRoundedRectangle` needs macOS 14; this ships to 13.
struct TopDockIslandShape: InsettableShape {
    /// Width of the top edge that meets the housing. Zero draws a standalone capsule.
    var connectorWidth: CGFloat = 0
    /// How far that connector reaches up into the housing.
    var connectorDrop: CGFloat = 0
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> TopDockIslandShape {
        TopDockIslandShape(
            connectorWidth: max(0, connectorWidth - amount * 2),
            connectorDrop: max(0, connectorDrop - amount),
            topRadius: max(0, topRadius - amount),
            bottomRadius: max(0, bottomRadius - amount),
            inset: inset + amount
        )
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let drop = max(0, min(connectorDrop, rect.height / 2))
        let connector = TopDockPlacementPolicy.connectorWidth(
            notchWidth: connectorWidth,
            dockWidth: rect.width
        )
        guard drop > 0, connector > 0 else {
            return capsulePath(in: rect)
        }

        // The bar's top edge sits on the housing's bottom edge; the shoulders bridge the
        // two walls inside the overlap above it.
        let shelf = rect.minY + drop
        let leftWall = rect.midX - connector / 2
        let rightWall = rect.midX + connector / 2
        let shoulder = min(drop, (rect.width - connector) / 2)
        let lip = min(topRadius, max(0, leftWall - shoulder - rect.minX))
        let bottom = min(bottomRadius, rect.width / 2, rect.height - drop)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: shelf + lip))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: shelf),
            tangent2End: CGPoint(x: rect.minX + lip, y: shelf),
            radius: lip
        )
        path.addArc(
            tangent1End: CGPoint(x: leftWall, y: shelf),
            tangent2End: CGPoint(x: leftWall, y: rect.minY),
            radius: shoulder
        )
        path.addLine(to: CGPoint(x: leftWall, y: rect.minY))
        path.addLine(to: CGPoint(x: rightWall, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rightWall, y: shelf),
            tangent2End: CGPoint(x: rect.maxX, y: shelf),
            radius: shoulder
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: shelf),
            tangent2End: CGPoint(x: rect.maxX, y: shelf + lip),
            radius: lip
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.midY),
            radius: bottom
        )
        path.closeSubpath()
        return path
    }

    /// No housing to grow from: an ordinary rounded body, uneven radii allowed.
    private func capsulePath(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let top = min(topRadius, limit)
        let bottom = min(bottomRadius, limit)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.midY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.midX, y: rect.minY),
            radius: top
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.midY),
            radius: top
        )
        path.closeSubpath()
        return path
    }
}

private struct TopDockSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}
