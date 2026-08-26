import AppKit
import CodeWindowCore
import Combine

/// Presentation state shared with the panel's SwiftUI content.
@MainActor
final class TopDockModel: ObservableObject {
    /// The panel is parked at the top of the screen instead of floating freely.
    @Published var isDocked = false
    /// A docked panel showing its full session list below the top anchor.
    @Published var isUnfolded = false
    /// 0 while a dragged panel is nowhere near the dock, 1 sitting on it.
    @Published var dockProximity: Double = 0
    /// The capsule is attached to a real camera housing rather than hanging off the edge.
    @Published var isAttachedToNotch = false
    /// Measured width of that housing, which the island's connector matches exactly.
    /// Zero whenever there is nothing to attach to.
    @Published var notchWidth: CGFloat = 0
}

/// Owns everything about where the single panel lives: the floating origin it returns to,
/// the docked capsule frame, and the gestures that move it between the two.
@MainActor
final class TopDockController: NSObject, TopDockPanelObserver {
    private enum Key {
        static let docked = "topDockEnabled"
        static let floatingTopLeft = "floatingPanelTopLeft"
    }

    let model = TopDockModel()

    private let panel: FloatingPanel
    private let defaults: UserDefaults
    /// True while this controller is the one moving the panel, so its own frame changes
    /// are not mistaken for a user drag.
    private var isApplyingLayout = false
    /// SwiftUI can report a new measured size from inside AppKit's animated-resize run loop.
    /// Starting a second NSWindow animation there is unsafe, so settle it after the active
    /// frame application returns.
    private var hasDeferredMeasurementLayout = false
    private var deferredMeasurementLayoutAnimated = false
    private var isDragging = false
    private var dragStartFrame: NSRect?
    private var fullContentSize = CGSize(
        width: PanelMetrics.width,
        height: PanelMetrics.initialHeight
    )
    private var capsuleContentSize = CGSize(
        width: TopDockPlacementPolicy.minimumCapsuleWidth,
        height: TopDockPlacementPolicy.capsuleHeight
    )
    /// Set when the floating panel must return to a remembered spot instead of staying put.
    private var pendingFloatingTopLeft: CGPoint?
    private var lastLayoutFrame: NSRect = .zero
    private var foldWork: DispatchWorkItem?
    private var isUnfoldedHovered = false

    /// The inspector keeps an unfolded panel open while the pointer is off in a detail view.
    var isInspectorActive: () -> Bool = { false }
    var didChangeDockState: () -> Void = {}

    init(panel: FloatingPanel, defaults: UserDefaults = .standard) {
        self.panel = panel
        self.defaults = defaults
        super.init()
        panel.dockObserver = self
        model.isDocked = defaults.bool(forKey: Key.docked)
        if let stored = defaults.string(forKey: Key.floatingTopLeft) {
            let point = NSPointFromString(stored)
            if point != .zero { pendingFloatingTopLeft = point }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        applyLevel()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isDocked: Bool { model.isDocked }

    // MARK: - Layout

    func fullContentSizeChanged(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != fullContentSize else { return }
        fullContentSize = size
        layoutAfterMeasurement(animated: model.isDocked && model.isUnfolded)
    }

    func capsuleContentSizeChanged(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != capsuleContentSize else { return }
        capsuleContentSize = size
        layoutAfterMeasurement(animated: model.isDocked && !model.isUnfolded)
    }

    private func layoutAfterMeasurement(animated: Bool) {
        guard isApplyingLayout else {
            layout(animated: animated)
            return
        }
        hasDeferredMeasurementLayout = true
        deferredMeasurementLayoutAnimated = deferredMeasurementLayoutAnimated || animated
    }

    func layout(animated: Bool = false) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let target: NSRect
        if model.isDocked {
            let docked = dockedFrame(on: screen)
            target = model.isUnfolded
                ? TopDockPlacementPolicy.unfoldedFrame(
                    contentSize: CGSize(
                        width: PanelMetrics.width,
                        height: ceil(fullContentSize.height)
                    ),
                    dockedFrame: docked,
                    visibleFrame: screen.visibleFrame,
                    margin: PanelMetrics.screenMargin
                )
                : docked
        } else {
            target = floatingFrame(on: screen)
        }
        apply(target, animated: animated)
    }

    private func dockedFrame(on screen: NSScreen) -> NSRect {
        TopDockPlacementPolicy.dockedFrame(
            contentSize: CGSize(
                width: ceil(capsuleContentSize.width),
                height: ceil(capsuleContentSize.height)
            ),
            notch: notch(of: screen),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }

    private func floatingFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let maximumHeight = visibleFrame.height - PanelMetrics.screenMargin * 2
        let height = min(ceil(fullContentSize.height), maximumHeight)
        let currentTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        // A size measurement can arrive while AppKit is still visually animating a
        // menu-driven detach. Use the remembered floating anchor instead of treating an
        // intermediate animation frame as the new home. During a real drag, the pointer's
        // current frame remains authoritative and is persisted when the drag ends.
        let topLeft = isDragging
            ? currentTopLeft
            : (pendingFloatingTopLeft ?? storedFloatingTopLeft() ?? currentTopLeft)
        pendingFloatingTopLeft = nil
        var frame = NSRect(
            x: topLeft.x,
            y: topLeft.y - height,
            width: PanelMetrics.width,
            height: height
        )
        let minimumX = visibleFrame.minX + PanelMetrics.screenMargin
        let minimumY = visibleFrame.minY + PanelMetrics.screenMargin
        frame.origin.x = min(
            max(frame.origin.x, minimumX),
            max(minimumX, visibleFrame.maxX - frame.width - PanelMetrics.screenMargin)
        )
        frame.origin.y = min(
            max(frame.origin.y, minimumY),
            max(minimumY, visibleFrame.maxY - frame.height - PanelMetrics.screenMargin)
        )
        return frame
    }

    private func notch(of screen: NSScreen) -> CGRect? {
        TopDockPlacementPolicy.notch(
            screenFrame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }

    private func apply(_ frame: NSRect, animated: Bool) {
        lastLayoutFrame = frame
        guard frame != panel.frame else { return }
        isApplyingLayout = true
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: animates)
        panel.invalidateShadow()
        isApplyingLayout = false
        if hasDeferredMeasurementLayout {
            let deferredAnimation = deferredMeasurementLayoutAnimated
            hasDeferredMeasurementLayout = false
            deferredMeasurementLayoutAnimated = false
            DispatchQueue.main.async { [weak self] in
                self?.layout(animated: deferredAnimation)
            }
        }
    }

    // MARK: - Mode

    func dock() {
        guard !model.isDocked else { return }
        foldWork?.cancel()
        rememberFloatingOrigin(frame: dragStartFrame ?? panel.frame)
        model.isDocked = true
        model.isUnfolded = false
        model.dockProximity = 0
        defaults.set(true, forKey: Key.docked)
        applyLevel()
        layout(animated: true)
        didChangeDockState()
    }

    func detach() {
        guard model.isDocked else { return }
        foldWork?.cancel()
        model.isDocked = false
        model.isUnfolded = false
        model.dockProximity = 0
        defaults.set(false, forKey: Key.docked)
        applyLevel()
        // Keep whatever spot the drag reached; a menu-driven detach returns to the last one.
        if !isDragging { pendingFloatingTopLeft = storedFloatingTopLeft() }
        layout(animated: !isDragging)
        didChangeDockState()
    }

    func toggleDock() {
        model.isDocked ? detach() : dock()
    }

    func unfold() {
        guard model.isDocked, !model.isUnfolded else { return }
        foldWork?.cancel()
        model.isUnfolded = true
        applyLevel()
        layout(animated: true)
        didChangeDockState()
    }

    func fold() {
        guard model.isUnfolded else { return }
        foldWork?.cancel()
        model.isUnfolded = false
        applyLevel()
        layout(animated: true)
        didChangeDockState()
    }

    /// The unfolded list closes once the pointer has been away for a moment, unless the
    /// inspector is the reason the pointer left.
    func unfoldedHoverChanged(_ isHovered: Bool) {
        isUnfoldedHovered = isHovered
        foldWork?.cancel()
        guard model.isUnfolded, !isHovered else { return }
        scheduleFold(after: 0.45)
    }

    private func scheduleFold(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.isUnfolded, !self.isUnfoldedHovered else { return }
            if self.isInspectorActive() {
                // The pointer may have crossed into an inspector. Try again when that
                // transition has had time to finish instead of leaving the island open.
                self.scheduleFold(after: 0.20)
            } else {
                self.fold()
            }
        }
        foldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyLevel() {
        panel.isTopDocked = model.isDocked
        let housing = (panel.screen ?? NSScreen.main).flatMap { notch(of: $0) }
        let attached = model.isDocked && housing != nil
        if model.isAttachedToNotch != attached { model.isAttachedToNotch = attached }
        let connector = attached ? (housing?.width ?? 0) : 0
        if model.notchWidth != connector { model.notchWidth = connector }
        panel.level = model.isDocked ? .statusBar : .floating
        panel.hasShadow = !model.isDocked || model.isUnfolded
    }

    // MARK: - Screens

    func screenParametersDidChange() {
        guard model.isDocked else {
            panel.constrainToVisibleArea()
            return
        }
        applyLevel()
        layout()
    }

    // MARK: - Drag lifecycle

    func panelDragDidBegin() {
        isDragging = true
        dragStartFrame = panel.frame
    }

    func panelDragDidEnd(moved: Bool) {
        defer {
            isDragging = false
            dragStartFrame = nil
        }
        guard moved else {
            // A click on the folded capsule, not a drag.
            if model.isDocked, !model.isUnfolded { unfold() }
            return
        }
        if model.isDocked {
            model.dockProximity = 0
            // A tentative pull that did not cross the detach threshold returns to the
            // hardware anchor instead of leaving a logically docked panel displaced.
            layout(animated: true)
            return
        }
        let proximity = model.dockProximity
        model.dockProximity = 0
        if TopDockPlacementPolicy.shouldDock(proximity: proximity) {
            dock()
        } else {
            rememberFloatingOrigin()
        }
    }

    @objc private func panelDidMove() {
        guard !isApplyingLayout else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        if model.isDocked {
            guard isDragging else { return }
            // Anywhere it was last placed is home; carrying it away from there is a detach,
            // folded or unfolded.
            if TopDockPlacementPolicy.shouldDetach(
                panelFrame: panel.frame,
                dockedFrame: lastLayoutFrame
            ) {
                detach()
            }
            return
        }
        guard isDragging else { return }
        let notchOrEdge = TopDockPlacementPolicy.dockedFrame(
            contentSize: CGSize(
                width: TopDockPlacementPolicy.minimumCapsuleWidth,
                height: TopDockPlacementPolicy.capsuleHeight
            ),
            notch: notch(of: screen),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let proximity = TopDockPlacementPolicy.proximity(
            of: panel.frame,
            target: notchOrEdge
        )
        if abs(proximity - model.dockProximity) > 0.01 {
            model.dockProximity = proximity
        }
    }

    private func rememberFloatingOrigin(frame: NSRect? = nil) {
        guard !model.isDocked else { return }
        let frame = frame ?? panel.frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        defaults.set(NSStringFromPoint(topLeft), forKey: Key.floatingTopLeft)
    }

    private func storedFloatingTopLeft() -> CGPoint? {
        guard let stored = defaults.string(forKey: Key.floatingTopLeft) else { return nil }
        let point = NSPointFromString(stored)
        return point == .zero ? nil : point
    }
}
