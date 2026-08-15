import CoreGraphics

public enum InspectorPlacementPolicy {
    private enum Edge: Hashable {
        case left
        case right
        case above
        case below
    }

    public static func frame(
        anchor: CGRect,
        size requestedSize: CGSize,
        gap: CGFloat,
        margin: CGFloat,
        within visibleFrame: CGRect
    ) -> CGRect {
        let field = visibleFrame.insetBy(dx: margin, dy: margin)
        let size = CGSize(
            width: min(requestedSize.width, field.width),
            height: min(requestedSize.height, field.height)
        )
        let spaces: [Edge: CGFloat] = [
            .left: max(0, anchor.minX - field.minX),
            .right: max(0, field.maxX - anchor.maxX),
            .above: max(0, field.maxY - anchor.maxY),
            .below: max(0, anchor.minY - field.minY),
        ]

        let horizontal: Edge = spaces[.right, default: 0] >= spaces[.left, default: 0]
            ? .right : .left
        let vertical: Edge = spaces[.above, default: 0] >= spaces[.below, default: 0]
            ? .above : .below
        let edge: Edge
        if spaces[horizontal, default: 0] >= size.width + gap {
            edge = horizontal
        } else if spaces[vertical, default: 0] >= size.height + gap {
            edge = vertical
        } else {
            let horizontalFit = spaces[horizontal, default: 0] / max(1, size.width + gap)
            let verticalFit = spaces[vertical, default: 0] / max(1, size.height + gap)
            edge = horizontalFit >= verticalFit ? horizontal : vertical
        }

        return frame(for: edge, anchor: anchor, size: size, gap: gap, within: field)
    }

    private static func frame(
        for edge: Edge,
        anchor: CGRect,
        size: CGSize,
        gap: CGFloat,
        within field: CGRect
    ) -> CGRect {
        let origin: CGPoint
        switch edge {
        case .left:
            origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.maxY - size.height)
        case .right:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.maxY - size.height)
        case .above:
            origin = CGPoint(x: anchor.minX, y: anchor.maxY + gap)
        case .below:
            origin = CGPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        }

        let maximumX = max(field.minX, field.maxX - size.width)
        let maximumY = max(field.minY, field.maxY - size.height)
        return CGRect(
            origin: CGPoint(
                x: min(max(origin.x, field.minX), maximumX),
                y: min(max(origin.y, field.minY), maximumY)
            ),
            size: size
        )
    }
}
