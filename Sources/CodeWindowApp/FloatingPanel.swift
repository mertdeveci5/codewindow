import AppKit

/// A borderless, non-activating panel that floats above every Space and over
/// full-screen apps. It never takes key or main status, so clicking or dragging
/// it never steals focus from the terminal the user is working in.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, event.hasPreciseScrollingDeltas else {
            super.sendEvent(event)
            return
        }

        // Momentum can continue after the pointer has left the panel. Keep this a direct
        // two-finger gesture instead, so the island stops when the user's fingers stop.
        if event.momentumPhase.isEmpty {
            // This is a drag gesture, not scrolling. Remove the user's scroll-direction
            // preference so the panel always follows the physical finger movement.
            let directionCorrection: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            moveByTrackpad(
                deltaX: event.scrollingDeltaX * directionCorrection,
                deltaY: event.scrollingDeltaY * directionCorrection
            )
        }
    }

    @discardableResult
    func moveByTrackpad(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard deltaX != 0 || deltaY != 0 else { return false }

        let currentOrigin = frame.origin
        var nextOrigin = NSPoint(
            x: currentOrigin.x - deltaX,
            y: currentOrigin.y + deltaY
        )

        if let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let minimumX = visibleFrame.minX + PanelMetrics.screenMargin
            let minimumY = visibleFrame.minY + PanelMetrics.screenMargin
            let maximumX = max(minimumX, visibleFrame.maxX - frame.width - PanelMetrics.screenMargin)
            let maximumY = max(minimumY, visibleFrame.maxY - frame.height - PanelMetrics.screenMargin)
            nextOrigin.x = min(max(nextOrigin.x, minimumX), maximumX)
            nextOrigin.y = min(max(nextOrigin.y, minimumY), maximumY)
        }

        guard nextOrigin != currentOrigin else { return false }
        setFrameOrigin(nextOrigin)
        return true
    }
}
