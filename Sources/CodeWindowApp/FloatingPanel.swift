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

/// Receives the start and the end of a panel-moving gesture. Docking is decided when the
/// gesture ends, so the panel never snaps away mid-drag.
@MainActor
protocol TopDockPanelObserver: AnyObject {
    func panelDragDidBegin()
    func panelDragDidEnd(moved: Bool)
    /// The panel was hidden mid-gesture; nothing should dock or stay highlighted.
    func panelDragDidCancel()
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
    private var isTrackpadDragActive = false
    private var trackpadEndWorkItem: DispatchWorkItem?

    /// Height of the session list that can scroll, measured up from the bottom bezel.
    /// Zero while every row fits, so the whole panel stays a trackpad drag surface.
    var scrollableListHeight: CGFloat = 0

    weak var dockObserver: TopDockPanelObserver?

    /// While docked the panel deliberately lives outside the visible frame — flush with the
    /// notch — so the usual on-screen clamping has to stand down until it detaches.
    var isTopDocked = false

    /// The docked island's resting size. While it springs between sizes the window briefly
    /// holds a larger transparent stage, and a click there must not count as one on the island.
    var dockedIslandSize: CGSize?

    private let canvasContainer = CanvasContainerView()

    /// Docked, SwiftUI draws into a fixed canvas pinned to the window's top center, and the
    /// window grows and shrinks around it. The container repositions that canvas in the same
    /// pass as the resize, so the island stays exactly where it is. Letting the hosting view
    /// resize with the window instead shows one frame of old content pinned to the new
    /// top-left corner before SwiftUI catches up. Nil while floating, where content fills
    /// the window.
    var dockedCanvasSize: CGSize? {
        get { canvasContainer.canvasSize }
        set { canvasContainer.canvasSize = newValue }
    }

    /// True only while an inbox card is open. The panel then takes typing like Spotlight does,
    /// without activating CodeWindow or taking the menu bar from the app the user is in.
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }

    func installContent(_ view: NSView) {
        canvasContainer.frame = NSRect(origin: .zero, size: frame.size)
        contentView = canvasContainer
        canvasContainer.hostedView = view
    }

    override func sendEvent(_ event: NSEvent) {
        // Background dragging runs its own event loop inside AppKit, so this call only
        // returns once the mouse is up. That return is the end of the gesture.
        if event.type == .leftMouseDown, !isOnDockedIsland(event.locationInWindow) {
            return
        }
        if event.type == .leftMouseDown, dockObserver != nil {
            dockObserver?.panelDragDidBegin()
            let startAnchor = anchor
            super.sendEvent(event)
            // The docked island resizes itself around a fixed top-center anchor, sometimes
            // mid-click. Only a change of that anchor is the user moving the panel.
            dockObserver?.panelDragDidEnd(moved: anchor != startAnchor)
            return
        }

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
        if isMomentum {
            trackpadEndWorkItem?.cancel()
            trackpadEndWorkItem = nil
        }
        if isMomentum && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            releaseCursor()
            finishTrackpadDrag()
            return
        }

        if !isTrackpadDragActive, !isMomentum {
            isTrackpadDragActive = true
            dockObserver?.panelDragDidBegin()
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

        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            finishTrackpadDrag()
        } else if event.phase.contains(.cancelled) {
            finishTrackpadDrag()
        } else if event.phase.contains(.ended) {
            // Momentum arrives as a separate event. This grace period prevents docking at
            // fingers-up and immediately tearing the new capsule away with the glide.
            scheduleTrackpadDragEnd()
        }
    }

    /// Top center: the point the island grows around and the floating panel hangs from.
    private var anchor: NSPoint {
        NSPoint(x: frame.midX, y: frame.maxY)
    }

    private func isOnDockedIsland(_ point: NSPoint) -> Bool {
        guard isTopDocked, let size = dockedIslandSize else { return true }
        let island = NSRect(
            x: (frame.width - size.width) / 2,
            y: frame.height - size.height,
            width: size.width,
            height: size.height
        )
        return island.contains(point)
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

        if !isTopDocked,
           let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        {
            nextOrigin = constrainedOrigin(nextOrigin, in: visibleFrame)
        }

        guard nextOrigin != currentOrigin else { return nil }
        setFrameOrigin(nextOrigin)
        return NSPoint(
            x: nextOrigin.x - currentOrigin.x,
            y: nextOrigin.y - currentOrigin.y
        )
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isTopDocked ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    func constrainToVisibleArea() {
        guard !isTopDocked else { return }
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
        trackpadEndWorkItem?.cancel()
        trackpadEndWorkItem = nil
        isTrackpadDragActive = false
        releaseCursor()
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        trackpadEndWorkItem?.cancel()
        trackpadEndWorkItem = nil
        if isTrackpadDragActive { dockObserver?.panelDragDidCancel() }
        isTrackpadDragActive = false
        releaseCursor()
        super.orderOut(sender)
    }

    private func scheduleTrackpadDragEnd() {
        trackpadEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishTrackpadDrag()
        }
        trackpadEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func finishTrackpadDrag() {
        trackpadEndWorkItem?.cancel()
        trackpadEndWorkItem = nil
        guard isTrackpadDragActive else { return }
        isTrackpadDragActive = false
        dockObserver?.panelDragDidEnd(moved: true)
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

/// Holds the SwiftUI hosting view: filling the window while floating, or as a fixed canvas
/// centered on the window's top edge while docked. Placement happens in `resizeSubviews`, which
/// AppKit runs synchronously inside the window's own resize.
final class CanvasContainerView: NSView {
    var hostedView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let hostedView { addSubview(hostedView) }
            placeHostedView()
        }
    }

    var canvasSize: CGSize? {
        didSet {
            guard canvasSize != oldValue else { return }
            placeHostedView()
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        placeHostedView()
    }

    private func placeHostedView() {
        guard let hostedView else { return }
        guard let canvasSize else {
            hostedView.frame = bounds
            return
        }
        // Not rounded: the island is centered inside the canvas as well, so when the window's
        // width and the canvas's differ in parity the two half-point offsets cancel, and the
        // island itself lands on whole points.
        hostedView.frame = NSRect(
            x: (bounds.width - canvasSize.width) / 2,
            y: bounds.height - canvasSize.height,
            width: canvasSize.width,
            height: canvasSize.height
        )
    }
}

extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
