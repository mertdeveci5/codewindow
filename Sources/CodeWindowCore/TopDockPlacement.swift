import CoreGraphics

/// Pure geometry for the top dock. AppKit adapts `NSScreen` into these values, while tests
/// can exercise the behavior without a display or window server.
public enum TopDockPlacementPolicy {
    public static let magnetHeight: CGFloat = 110
    public static let magnetHalfWidth: CGFloat = 220
    public static let dockThreshold: Double = 0.45
    public static let detachDistance: CGFloat = 96

    /// Fixed outer height with room for two action lines and one quiet context line.
    public static let capsuleHeight: CGFloat = 54
    /// How far the island reaches up into the camera housing. The shoulders are carved out
    /// of this overlap, so the connector and the hardware are one uninterrupted black.
    public static let notchOverlap: CGFloat = 13
    /// Radius of the concave transition from the housing wall out to the activity bar.
    /// Matching the overlap lands the shoulder exactly on the housing's bottom edge.
    public static var shoulderRadius: CGFloat { notchOverlap }
    /// Both outer corners use a half-height radius, making the lower body a real pill. The
    /// concave center shoulders cut into that pill and carry it upward into the housing.
    public static var barRadius: CGFloat { capsuleHeight / 2 }
    public static var barTopRadius: CGFloat { barRadius }

    /// Stacked lines need enough run to be worth reading before they wrap and truncate.
    public static let minimumCapsuleWidth: CGFloat = 184
    /// Matches the full activity panel. A folded island must never become wider than the
    /// view it unfolds into, or opening it would visibly reverse direction and shrink.
    public static let maximumCapsuleWidth: CGFloat = 296
    /// How far the activity bar overhangs the housing on each side. This overhang is what
    /// makes the folded island read as hardware growing, not as a pill parked below it.
    public static let notchShoulder: CGFloat = 42
    public static let edgeGap: CGFloat = 6

    /// Derives the camera housing between the two unobscured menu-bar regions.
    public static func notch(
        screenFrame: CGRect,
        topInset: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> CGRect? {
        guard topInset > 0, let leftArea, let rightArea else { return nil }
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

    /// Width of the black connector where the island meets the housing, clamped so both
    /// sculpted shoulders always have room inside the panel. Zero means no housing, and the
    /// island falls back to a standalone capsule.
    public static func connectorWidth(notchWidth: CGFloat, dockWidth: CGFloat) -> CGFloat {
        guard notchWidth > 0, dockWidth > 0 else { return 0 }
        let room = dockWidth - (shoulderRadius + barTopRadius) * 2
        return max(0, min(notchWidth, room))
    }

    /// Places the folded island so its connector overlaps the camera housing, or just below
    /// the menu bar on an ordinary display. The attachment stays put while hover and new
    /// content grow the bar downward and outward.
    public static func dockedFrame(
        contentSize: CGSize,
        notch: CGRect?,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let height = max(capsuleHeight, contentSize.height)
        let requestedWidth = max(minimumCapsuleWidth, contentSize.width)
        let width = min(
            max(requestedWidth, notch.map { $0.width + notchShoulder * 2 } ?? 0),
            min(maximumCapsuleWidth, screenFrame.width)
        )
        let centerX = notch?.midX ?? screenFrame.midX
        let top = notch.map { $0.minY + min(notchOverlap, $0.height) }
            ?? min(visibleFrame.maxY, screenFrame.maxY) - edgeGap
        return CGRect(
            x: (centerX - width / 2).rounded(),
            y: (top - height).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// Expands downward while preserving the folded island's top edge. This continuity is
    /// what makes the full panel read as the island unfolding instead of a separate popover.
    public static func unfoldedFrame(
        contentSize: CGSize,
        dockedFrame: CGRect,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let minimumX = visibleFrame.minX + margin
        let minimumY = visibleFrame.minY + margin
        let maximumWidth = max(1, visibleFrame.width - margin * 2)
        let maximumHeight = max(1, dockedFrame.maxY - minimumY)
        let size = CGSize(
            width: min(contentSize.width, maximumWidth),
            height: min(contentSize.height, maximumHeight)
        )
        let desiredX = dockedFrame.midX - size.width / 2
        let maximumX = max(minimumX, visibleFrame.maxX - margin - size.width)
        return CGRect(
            x: min(max(desiredX, minimumX), maximumX),
            y: dockedFrame.maxY - size.height,
            width: size.width,
            height: size.height
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
