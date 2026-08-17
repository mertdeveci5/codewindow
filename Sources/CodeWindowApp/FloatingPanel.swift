import AppKit

extension NSPanel {
    func configureForCodeWindow() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }
}

/// A borderless, non-activating panel that floats above every Space and over
/// full-screen apps. The panel itself never takes key or main status. A session
/// row can still explicitly return focus to the terminal that owns that session.
final class FloatingPanel: NSPanel {
    private enum ScrollGesture {
        case movesPanel
        case scrollsList
    }

    private var cursorRevealWorkItem: DispatchWorkItem?
    private var isCursorCaptured = false
    private var scrollGesture: ScrollGesture?

    /// Height of the session list that can scroll, measured up from the bottom bezel.
    /// Zero while every row fits, so the whole panel stays a trackpad drag surface.
    var scrollableListHeight: CGFloat = 0

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, event.hasPreciseScrollingDeltas else {
            super.sendEvent(event)
            return
        }

        // A gesture keeps whatever it started as. Trackpads open with a zero-delta event,
        // so the decision waits for the first movement and momentum inherits it.
        if event.phase.contains(.began) {
            scrollGesture = nil
        }
        if scrollGesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            scrollGesture = scrollsList(
                at: event.locationInWindow,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            ) ? .scrollsList : .movesPanel
        }
        guard scrollGesture == .movesPanel else {
            super.sendEvent(event)
            return
        }

        // This is a drag gesture, not scrolling. Remove the user's scroll-direction
        // preference so the panel always follows the physical finger movement.
        let directionCorrection: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let isMomentum = !event.momentumPhase.isEmpty
        if isMomentum && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            releaseCursor()
            return
        }

        if let movement = moveByTrackpad(
            deltaX: event.scrollingDeltaX * directionCorrection,
            deltaY: event.scrollingDeltaY * directionCorrection
        ) {
            // Keep the pointer attached only while the user's fingers are touching the
            // trackpad. Native momentum then throws the panel while the pointer stays put.
            if !isMomentum {
                captureCursor(movingBy: movement)
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || isMomentum
        {
            releaseCursor()
        }
    }

    /// A vertical gesture over an overflowing list belongs to that list. Horizontal gestures,
    /// and anything above the list, keep dragging the panel around the screen.
    func scrollsList(at locationInWindow: NSPoint, deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard scrollableListHeight > 0, abs(deltaY) > abs(deltaX) else { return false }
        let listRange = PanelMetrics.bezel...(PanelMetrics.bezel + scrollableListHeight)
        return listRange.contains(locationInWindow.y)
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
            nextOrigin = constrainedOrigin(nextOrigin, in: visibleFrame)
        }

        guard nextOrigin != currentOrigin else { return nil }
        setFrameOrigin(nextOrigin)
        return NSPoint(
            x: nextOrigin.x - currentOrigin.x,
            y: nextOrigin.y - currentOrigin.y
        )
    }

    func constrainToVisibleArea() {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard !visibleFrames.contains(where: { $0.contains(frame) }),
              let target = visibleFrames.max(by: {
                  $0.intersection(frame).area < $1.intersection(frame).area
              }) ?? NSScreen.main?.visibleFrame
        else { return }

        let origin = constrainedOrigin(frame.origin, in: target)
        if origin != frame.origin { setFrameOrigin(origin) }
    }

    override func close() {
        releaseCursor()
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        releaseCursor()
        super.orderOut(sender)
    }

    private func captureCursor(movingBy movement: NSPoint) {
        guard let cursorPosition = CGEvent(source: nil)?.location else { return }

        if !isCursorCaptured {
            guard CGDisplayHideCursor(CGMainDisplayID()) == .success else { return }
            isCursorCaptured = true
        }

        // AppKit screen coordinates grow upward. Quartz cursor coordinates grow downward.
        let result = CGWarpMouseCursorPosition(CGPoint(
            x: cursorPosition.x + movement.x,
            y: cursorPosition.y - movement.y
        ))
        guard result == .success else {
            releaseCursor()
            return
        }

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

    private func constrainedOrigin(_ origin: NSPoint, in visibleFrame: NSRect) -> NSPoint {
        let minimumX = visibleFrame.minX + PanelMetrics.screenMargin
        let minimumY = visibleFrame.minY + PanelMetrics.screenMargin
        let maximumX = max(minimumX, visibleFrame.maxX - frame.width - PanelMetrics.screenMargin)
        let maximumY = max(minimumY, visibleFrame.maxY - frame.height - PanelMetrics.screenMargin)
        return NSPoint(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY)
        )
    }
}

extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
