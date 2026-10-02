import CoreGraphics

/// How much of itself the docked island is showing. It only ever grows downward from the
/// top edge, so every state is the same black body at a different size.
public enum IslandPresentation: String, Equatable, Sendable {
    /// No sessions: barely wider than the camera housing, with a single quiet dot.
    case minimal
    /// The resting state: the agent mark on one side of the camera, live status on the other.
    case compact
    /// A peek on hover, or a short-lived alert: the current action below the camera.
    case expanded
    /// Every session, as in the floating panel.
    case list
}

/// Pure geometry for the top dock. AppKit adapts `NSScreen` into these values, while tests
/// can exercise the behavior without a display or window server.
public enum TopDockPlacementPolicy {
    public static let magnetHeight: CGFloat = 110
    public static let magnetHalfWidth: CGFloat = 220
    public static let dockThreshold: Double = 0.45
    public static let detachDistance: CGFloat = 96

    /// Width of each region beside the camera in the compact state: room for one glyph and
    /// a short count, like the leading and trailing slots of a compact Dynamic Island. Kept
    /// tight because on a 13-inch display menu-bar items run right up to the housing.
    public static let compactSideWidth: CGFloat = 36
    /// The minimal state shows only a status dot, so its sides barely clear the housing.
    public static let minimalSideWidth: CGFloat = 18
    /// Outward concave flares where the island meets the top bezel, the way the hardware
    /// housing itself does. They sit inside the island frame on both sides.
    public static let bezelFlare: CGFloat = 6
    /// Height of the island's top band on a display without a camera housing. On a notched
    /// display that band is exactly as tall as the housing.
    public static let fallbackBandHeight: CGFloat = 30
    /// The gap a notchless band leaves between its leading and trailing slots.
    public static let fallbackCenterGap: CGFloat = 20
    /// Room below the band for two action lines and one quiet context line.
    public static let expandedBodyHeight: CGFloat = 54
    /// Matches the full activity panel. The island must never become wider than the view it
    /// unfolds into, or opening it would visibly reverse direction and shrink.
    public static let maximumIslandWidth: CGFloat = 296

    /// Derives the camera housing between the two unobscured menu-bar regions.
    public static func notch(
        screenFrame: CGRect,
        topInset: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> CGRect? {
        guard topInset > 0, var leftArea, var rightArea else { return nil }
        // Accept the unobscured areas in either the screen's own coordinates or global ones:
        // a built-in display arranged away from the origin must still find its housing.
        if !screenFrame.intersects(leftArea.union(rightArea)) {
            leftArea = leftArea.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            rightArea = rightArea.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        }
        let minX = max(screenFrame.minX, leftArea.maxX)
        let maxX = min(screenFrame.maxX, rightArea.minX)
        guard maxX > minX else { return nil }
        return CGRect(
            x: minX,
            y: screenFrame.maxY - topInset,
            width: maxX - minX,
            height: topInset
        )
    }

    /// The top band carries the leading and trailing slots. Under a housing it is the housing,
    /// so nothing the island shows can ever hide behind the camera.
    public static func bandHeight(notch: CGRect?) -> CGFloat {
        notch?.height ?? fallbackBandHeight
    }

    /// What sits between the two slots: the camera itself, or a small gap on a plain display.
    public static func centerGap(notch: CGRect?) -> CGFloat {
        notch?.width ?? fallbackCenterGap
    }

    /// Flares only make sense where the island pours out of a bezel.
    public static func flare(notch: CGRect?) -> CGFloat {
        notch == nil ? 0 : bezelFlare
    }

    /// The island's outer size for a presentation. `expandedContentWidth` is the natural width
    /// of the expanded body and `listContentHeight` the natural height of the session list;
    /// both are measured by the view and only matter for their own states.
    public static func islandSize(
        for presentation: IslandPresentation,
        notch: CGRect?,
        expandedContentWidth: CGFloat,
        listSize: CGSize
    ) -> CGSize {
        let band = bandHeight(notch: notch)
        let sideWidth = presentation == .minimal ? minimalSideWidth : compactSideWidth
        let resting = (sideWidth + flare(notch: notch)) * 2 + centerGap(notch: notch)
        switch presentation {
        case .minimal, .compact:
            return CGSize(width: resting, height: band)
        case .expanded:
            let width = min(max(resting, expandedContentWidth), maximumIslandWidth)
            return CGSize(width: width, height: band + expandedBodyHeight)
        case .list:
            return CGSize(
                width: max(resting, listSize.width),
                height: band + max(0, listSize.height)
            )
        }
    }

    /// Places the island centered on the camera housing and flush with the top of the screen,
    /// or flush below the menu bar on a display without one. Every presentation shares this
    /// top edge and center line, so a change of state only ever grows or shrinks the body.
    public static func islandFrame(
        size: CGSize,
        notch: CGRect?,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let top = notch == nil ? min(visibleFrame.maxY, screenFrame.maxY) : screenFrame.maxY
        let width = min(size.width, screenFrame.width)
        let height = min(size.height, max(1, top - (visibleFrame.minY + margin)))
        let centerX = notch?.midX ?? screenFrame.midX
        let x = min(max(centerX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(
            x: x.rounded(),
            y: (top - height).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// Room for the opening spring to overshoot its target before settling back.
    public static let springOvershoot: CGFloat = 14

    /// While the body animates between two sizes the window has to hold both of them, plus
    /// any overshoot. The stage shares their top edge and center line, and grows by an even
    /// number of points on each side, so the island never moves inside it — not even by the
    /// half point an odd difference in width would cost.
    public static func stage(from current: CGRect, to target: CGRect, overshoot: CGFloat = 0) -> CGRect {
        let spare = max(current.width - target.width, overshoot * 2, 0)
        let width = target.width + (spare / 2).rounded(.up) * 2
        let height = max(current.height, target.height + overshoot)
        return CGRect(
            x: target.midX - width / 2,
            y: target.maxY - height,
            width: width,
            height: height
        )
    }

    /// Returns 0 outside the magnetic zone and 1 at the dock. Both axes must agree, so a
    /// panel near a top corner never lights up merely because it is high on the screen.
    public static func proximity(of panelFrame: CGRect, target: CGRect) -> Double {
        let horizontal = 1 - abs(panelFrame.midX - target.midX) / magnetHalfWidth
        let vertical = 1 - abs(panelFrame.maxY - target.maxY) / magnetHeight
        return min(max(min(horizontal, vertical), 0), 1)
    }

    public static func shouldDock(proximity: Double) -> Bool {
        proximity >= dockThreshold
    }

    public static func shouldDetach(panelFrame: CGRect, dockedFrame: CGRect) -> Bool {
        let dx = panelFrame.midX - dockedFrame.midX
        let dy = panelFrame.maxY - dockedFrame.maxY
        return (dx * dx + dy * dy).squareRoot() >= detachDistance
    }
}

/// Something worth briefly expanding the island for, without the user asking.
public enum IslandAlert: Equatable, Sendable {
    case attention
    case finished

    /// Attention waits on the user, so it stays up longer than a plain completion.
    public var duration: Double {
        switch self {
        case .attention: 4
        case .finished: 2.5
        }
    }
}

public enum IslandPresentationPolicy {
    public static func presentation(
        hasSessions: Bool,
        isUnfolded: Bool,
        isHovered: Bool,
        isAlerting: Bool
    ) -> IslandPresentation {
        if isUnfolded { return .list }
        if isHovered { return .expanded }
        guard hasSessions else { return .minimal }
        return isAlerting ? .expanded : .compact
    }

    /// Compares two snapshots of session activity keyed by session ID. Only transitions count:
    /// a session that already needed attention in `previous` does not alert again.
    public static func alert(
        previous: [String: Activity],
        current: [String: Activity]
    ) -> IslandAlert? {
        let attention = current.contains { id, activity in
            activity == .needsAttention && previous[id] != .needsAttention
        }
        if attention { return .attention }
        let finished = current.contains { id, activity in
            activity == .idle && previous[id] == .working
        }
        return finished ? .finished : nil
    }
}
