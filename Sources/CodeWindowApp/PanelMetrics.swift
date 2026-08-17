import CoreGraphics

/// Layout constants shared by the compact activity panel and its inspector.
enum PanelMetrics {
    static let width: CGFloat = 296
    static let outerRadius: CGFloat = 18
    static let bezel: CGFloat = 5
    static let rowRadius: CGFloat = outerRadius - bezel
    static let rowInsetHorizontal: CGFloat = 9
    static let rowHeight: CGFloat = 40
    static let inspectorHeight: CGFloat = 320
    static let inspectorGap: CGFloat = 8

    static let glyphSize: CGFloat = 22
    static let glyphGap: CGFloat = 9

    static let actionSize: CGFloat = 12.5
    static let commandSize: CGFloat = 11.5
    static let metaSize: CGFloat = 10
    static let textLineGap: CGFloat = 1.5

    static let statusColumn: CGFloat = 10
    static let statusDot: CGFloat = 5

    static let separatorHeight: CGFloat = 0.5
    static let separatorInset: CGFloat = rowInsetHorizontal + glyphSize + glyphGap

    /// Height used before SwiftUI reports its first measurement.
    static let initialHeight: CGFloat = rowHeight + bezel * 2

    /// Sessions past this height scroll instead of growing the panel, so a machine
    /// running many agents never gets an island that covers the whole screen.
    static let maximumListHeight: CGFloat = rowHeight * 8

    static let screenMargin: CGFloat = 18
}
