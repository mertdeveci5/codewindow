import AppKit

/// A borderless, non-activating panel that floats above every Space and over
/// full-screen apps. It never takes key or main status, so clicking or dragging
/// it never steals focus from the terminal the user is working in.
final class FloatingPanel: NSPanel {
    private var cursorRevealWorkItem: DispatchWorkItem?
    private var isCursorCaptured = false

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
            if let movement = moveByTrackpad(
                deltaX: event.scrollingDeltaX * directionCorrection,
                deltaY: event.scrollingDeltaY * directionCorrection
            ) {
                captureCursor(movingBy: movement)
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || !event.momentumPhase.isEmpty
        {
            releaseCursor()
        }
    }

    @discardableResult
    func moveByTrackpad(deltaX: CGFloat, deltaY: CGFloat) -> NSPoint? {
        guard deltaX != 0 || deltaY != 0 else { return nil }

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

        guard nextOrigin != currentOrigin else { return nil }
        setFrameOrigin(nextOrigin)
        return NSPoint(
            x: nextOrigin.x - currentOrigin.x,
            y: nextOrigin.y - currentOrigin.y
        )
    }

    override func close() {
        releaseCursor()
        super.close()
    }

    private func captureCursor(movingBy movement: NSPoint) {
        guard let cursorPosition = CGEvent(source: nil)?.location else { return }

        if !isCursorCaptured {
            guard CGDisplayHideCursor(CGMainDisplayID()) == .success else { return }
            isCursorCaptured = true
        }

        // AppKit screen coordinates grow upward. Quartz cursor coordinates grow downward.
        _ = CGWarpMouseCursorPosition(CGPoint(
            x: cursorPosition.x + movement.x,
            y: cursorPosition.y - movement.y
        ))

        cursorRevealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.releaseCursor()
        }
        cursorRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func releaseCursor() {
        cursorRevealWorkItem?.cancel()
        cursorRevealWorkItem = nil
        guard isCursorCaptured else { return }
        _ = CGDisplayShowCursor(CGMainDisplayID())
        isCursorCaptured = false
    }
}
