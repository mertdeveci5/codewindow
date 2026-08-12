import CoreGraphics

/// Layout constants for the always-expanded Live Activity panel.
/// Every session gets one equal-height row inside a single compact island.
enum PanelMetrics {
    static let width: CGFloat = 296
    static let outerRadius: CGFloat = 18
    static let bezel: CGFloat = 5
    static let rowRadius: CGFloat = outerRadius - bezel
    static let rowInsetHorizontal: CGFloat = 9
    static let rowHeight: CGFloat = 40
    static let expandedDetailHeight: CGFloat = 50

    static let glyphSize: CGFloat = 22
    static let glyphGap: CGFloat = 9

    static let actionSize: CGFloat = 12.5
    static let commandSize: CGFloat = 11.5
    static let metaSize: CGFloat = 10
    static let textLineGap: CGFloat = 1.5
    static let detailLineGap: CGFloat = 4

    static let statusColumn: CGFloat = 10
    static let statusDot: CGFloat = 5
    static let attentionRailWidth: CGFloat = 2
    static let attentionRailHeight: CGFloat = rowHeight - 14

    static let separatorHeight: CGFloat = 0.5
    static let separatorInset: CGFloat = rowInsetHorizontal + glyphSize + glyphGap

    /// Height used before SwiftUI reports its first measurement.
    static let initialHeight: CGFloat = rowHeight + bezel * 2

    static let screenMargin: CGFloat = 18
}
