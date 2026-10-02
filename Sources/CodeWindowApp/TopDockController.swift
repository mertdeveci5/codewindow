import AppKit
import CodeWindowCore
import Combine
import SwiftUI

/// Presentation state shared with the panel's SwiftUI content.
@MainActor
final class TopDockModel: ObservableObject {
    /// The panel is parked at the top of the screen instead of floating freely.
    @Published var isDocked = false
    /// How much of itself the docked island is showing.
    @Published var presentation: IslandPresentation = .compact
    /// The island's outer size. Changed inside a spring, so the body and its content animate
    /// together while the window holds still around them.
    @Published var islandSize = CGSize(
        width: TopDockPlacementPolicy.maximumIslandWidth,
        height: TopDockPlacementPolicy.fallbackBandHeight
    )
    /// 0 while a dragged panel is nowhere near the dock, 1 sitting on it.
    @Published var dockProximity: Double = 0
    /// Measured width of the camera housing the island grows from. Zero whenever there is
    /// nothing to attach to.
    @Published var notchWidth: CGFloat = 0
    /// Height of the band beside the camera: the housing itself, or a plain pill without one.
    @Published var bandHeight: CGFloat = TopDockPlacementPolicy.fallbackBandHeight

    /// A docked panel showing its full session list below the top band.
    var isUnfolded: Bool { presentation == .list }
    var isAttachedToNotch: Bool { notchWidth > 0 }
}

/// Owns everything about where the single panel lives: the floating origin it returns to,
/// the docked island and its presentations, and the gestures that move between the two.
@MainActor
final class TopDockController: NSObject, TopDockPanelObserver {
    private enum Key {
        static let docked = "topDockEnabled"
        static let floatingTopLeft = "floatingPanelTopLeft"
    }

    /// A short hover intent so sweeping past the menu bar does not flash the island open.
    static let peekDelay: TimeInterval = 0.16
    static let peekReleaseDelay: TimeInterval = 0.28

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
    private var expandedContentWidth: CGFloat = 0
    /// Set when the floating panel must return to a remembered spot instead of staying put.
    private var pendingFloatingTopLeft: CGPoint?
    private var lastLayoutFrame: NSRect = .zero
    private var foldWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var alertWork: DispatchWorkItem?
    private var settleWork: DispatchWorkItem?
    private var isUnfolded = false
    private var isIslandHovered = false
    private var isPeeking = false
    private var isAlerting = false
    private var hasSessions = false
    private var lastActivities: [String: Activity]?
    private var ghost: NSPanel?
    private var ghostAttachedToNotch: Bool?
    private var isInDockZone = false

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

    // MARK: - Measurements

    func fullContentSizeChanged(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != fullContentSize else { return }
        fullContentSize = size
        guard !model.isDocked || model.isUnfolded else { return }
        layoutAfterMeasurement(animated: model.isDocked)
    }

    func expandedContentWidthChanged(to width: CGFloat) {
        guard width > 0, width != expandedContentWidth else { return }
        expandedContentWidth = width
        guard model.isDocked, model.presentation == .expanded else { return }
        layoutAfterMeasurement(animated: true)
    }

    private func layoutAfterMeasurement(animated: Bool) {
        guard isApplyingLayout else {
            layout(animated: animated)
            return
        }
        hasDeferredMeasurementLayout = true
        deferredMeasurementLayoutAnimated = deferredMeasurementLayoutAnimated || animated
    }

    // MARK: - Sessions

    /// New sessions can change the resting state, and a session that starts waiting on the
    /// user or finishes its turn briefly expands the island to say so.
    func sessionsChanged(_ sessions: [PresentedSession]) {
        let activities = Dictionary(
            sessions.map { ($0.id, $0.activity) },
            uniquingKeysWith: { first, _ in first }
        )
        let hadSessions = hasSessions
        hasSessions = !sessions.isEmpty
        defer { lastActivities = activities }
        // The first snapshot is history, not news: launching must not alert for every
        // session that was already waiting, but it does settle the island's resting state.
        guard let previous = lastActivities else {
            if model.isDocked { layout() }
            return
        }
        if let alert = IslandPresentationPolicy.alert(previous: previous, current: activities) {
            beginAlert(alert)
        } else if model.isDocked, hadSessions != hasSessions {
            layout(animated: true)
        }
    }

    private func beginAlert(_ alert: IslandAlert) {
        guard model.isDocked else { return }
        alertWork?.cancel()
        isAlerting = true
        layout(animated: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isAlerting = false
            self.layout(animated: true)
        }
        alertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + alert.duration, execute: work)
    }

    // MARK: - Layout

    private var currentPresentation: IslandPresentation {
        IslandPresentationPolicy.presentation(
            hasSessions: hasSessions,
            isUnfolded: isUnfolded,
            isHovered: isPeeking,
            isAlerting: isAlerting
        )
    }

    func layout(animated: Bool = false) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        guard model.isDocked else {
            apply(floatingFrame(on: screen), animated: animated)
            return
        }
        // The user is holding the island; snapping it home now would fight their hand. The
        // end of the drag lays it out again.
        guard !isDragging else { return }
        let presentation = currentPresentation
        morph(
            to: islandFrame(for: presentation, on: screen),
            presentation: presentation,
            animated: animated
        )
    }

    private func islandFrame(for presentation: IslandPresentation, on screen: NSScreen) -> NSRect {
        let notch = notch(of: screen)
        return TopDockPlacementPolicy.islandFrame(
            size: TopDockPlacementPolicy.islandSize(
                for: presentation,
                notch: notch,
                expandedContentWidth: ceil(expandedContentWidth),
                listSize: CGSize(width: PanelMetrics.width, height: ceil(fullContentSize.height))
            ),
            notch: notch,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            margin: PanelMetrics.screenMargin
        )
    }

    /// Changes the island's size with a spring. AppKit window resizing cannot spring and
    /// re-lays out SwiftUI on every step, so the window jumps once to a stage large enough
    /// for both sizes, SwiftUI animates the body inside it, and the window shrinks to fit
    /// once the spring has settled. The stage shares the island's top edge and center line,
    /// so neither jump moves a single pixel on screen.
    private func morph(to target: NSRect, presentation: IslandPresentation, animated: Bool) {
        let current = panel.frame
        let isAnchored = abs(current.maxY - target.maxY) < 1 && abs(current.midX - target.midX) < 1
        let changes = model.islandSize != target.size || model.presentation != presentation
        // A measurement echoed back from the stage resize changes nothing; the spring already
        // in flight will settle the window itself.
        if !changes, isAnchored, settleWork != nil, lastLayoutFrame == target { return }
        settleWork?.cancel()
        settleWork = nil
        lastLayoutFrame = target
        panel.dockedIslandSize = target.size
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard animated, changes, isAnchored, panel.isVisible, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.presentation = presentation
                model.islandSize = target.size
            }
            // A drag that did not tear the island away springs back to its anchor.
            apply(target, animated: animated && !isAnchored)
            settleShadow()
            return
        }

        let expanding = target.height >= model.islandSize.height
        apply(
            TopDockPlacementPolicy.stage(
                from: current,
                to: target,
                overshoot: expanding ? TopDockPlacementPolicy.springOvershoot : 0
            ),
            animated: false
        )
        panel.hasShadow = false
        withAnimation(expanding ? IslandMotion.expand : IslandMotion.collapse) {
            model.presentation = presentation
            model.islandSize = target.size
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.isDocked, self.lastLayoutFrame == target else { return }
            self.settleWork = nil
            self.apply(target, animated: false)
            self.settleShadow()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMotion.settleDelay, execute: work)
    }

    /// Only the unfolded list floats over other windows; the smaller states sit on the bezel.
    private func settleShadow() {
        panel.hasShadow = !model.isDocked || model.isUnfolded
        panel.invalidateShadow()
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
        if !model.isDocked { lastLayoutFrame = frame }
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
        cancelTransientWork()
        rememberFloatingOrigin(frame: dragStartFrame ?? panel.frame)
        model.isDocked = true
        isUnfolded = false
        isPeeking = false
        model.dockProximity = 0
        hideGhost()
        defaults.set(true, forKey: Key.docked)
        applyLevel()
        layout()
        didChangeDockState()
    }

    func detach() {
        guard model.isDocked else { return }
        cancelTransientWork()
        model.isDocked = false
        isUnfolded = false
        isPeeking = false
        isAlerting = false
        model.dockProximity = 0
        panel.dockedIslandSize = nil
        defaults.set(false, forKey: Key.docked)
        applyLevel()
        settleShadow()
        // Keep whatever spot the drag reached; a menu-driven detach returns to the last one.
        if !isDragging { pendingFloatingTopLeft = storedFloatingTopLeft() }
        layout(animated: !isDragging)
        didChangeDockState()
    }

    func toggleDock() {
        model.isDocked ? detach() : dock()
    }

    func unfold() {
        guard model.isDocked, !isUnfolded else { return }
        foldWork?.cancel()
        isUnfolded = true
        layout(animated: true)
        didChangeDockState()
    }

    func fold() {
        guard isUnfolded else { return }
        foldWork?.cancel()
        isUnfolded = false
        isPeeking = false
        layout(animated: true)
        didChangeDockState()
    }

    private func cancelTransientWork() {
        foldWork?.cancel()
        peekWork?.cancel()
        alertWork?.cancel()
        settleWork?.cancel()
        settleWork = nil
    }

    // MARK: - Hover

    /// Resting under the pointer peeks at the current action; leaving an unfolded list closes
    /// it once the pointer has been away for a moment, unless an inspector is the reason.
    func islandHoverChanged(_ isHovered: Bool) {
        isIslandHovered = isHovered
        guard model.isDocked else { return }
        if isUnfolded {
            foldWork?.cancel()
            if !isHovered { scheduleFold(after: 0.45) }
            return
        }
        peekWork?.cancel()
        guard isHovered != isPeeking else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isIslandHovered == isHovered, !self.isUnfolded else { return }
            self.isPeeking = isHovered
            self.layout(animated: true)
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (isHovered ? Self.peekDelay : Self.peekReleaseDelay),
            execute: work
        )
    }

    private func scheduleFold(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isUnfolded, !self.isIslandHovered else { return }
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
        let screen = panel.screen ?? NSScreen.main
        // Wide enough for the widest stage, tall enough for the tallest island on this screen.
        panel.dockedCanvasSize = model.isDocked
            ? CGSize(
                width: TopDockPlacementPolicy.maximumIslandWidth
                    + TopDockPlacementPolicy.springOvershoot * 4,
                height: screen?.frame.height ?? 1_200
            )
            : nil
        let housing = model.isDocked ? screen.flatMap { notch(of: $0) } : nil
        let width = housing?.width ?? 0
        if model.notchWidth != width { model.notchWidth = width }
        let band = TopDockPlacementPolicy.bandHeight(notch: housing)
        if model.bandHeight != band { model.bandHeight = band }
        panel.level = model.isDocked ? .statusBar : .floating
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
        // The gesture is over before anything below runs, so docking can lay the island out.
        isDragging = false
        defer { dragStartFrame = nil }
        guard moved else {
            // A click on the resting island, not a drag.
            if model.isDocked, !isUnfolded { unfold() }
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
        hideGhost()
        if TopDockPlacementPolicy.shouldDock(proximity: proximity) {
            dock()
        } else {
            rememberFloatingOrigin()
        }
    }

    func panelDragDidCancel() {
        isDragging = false
        dragStartFrame = nil
        model.dockProximity = 0
        hideGhost()
    }

    @objc private func panelDidMove() {
        guard !isApplyingLayout else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        if model.isDocked {
            guard isDragging else { return }
            // Anywhere it was last placed is home; carrying it away from there is a detach,
            // in any presentation.
            if TopDockPlacementPolicy.shouldDetach(
                panelFrame: panel.frame,
                dockedFrame: lastLayoutFrame
            ) {
                detach()
            }
            return
        }
        guard isDragging else { return }
        let target = islandFrame(for: hasSessions ? .compact : .minimal, on: screen)
        let proximity = TopDockPlacementPolicy.proximity(of: panel.frame, target: target)
        if abs(proximity - model.dockProximity) > 0.01 {
            model.dockProximity = proximity
        }
        showGhost(at: target, on: screen, proximity: proximity)
    }

    // MARK: - Dock preview

    /// While a floating panel nears the dock, the island it is about to become fades in at the
    /// camera, and the trackpad ticks once as the panel enters the zone where letting go docks.
    private func showGhost(at frame: NSRect, on screen: NSScreen, proximity: Double) {
        let inZone = TopDockPlacementPolicy.shouldDock(proximity: proximity)
        if inZone, !isInDockZone {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isInDockZone = inZone
        guard proximity > 0 else {
            hideGhost()
            return
        }
        let ghost = ghost ?? makeGhost()
        let housing = notch(of: screen)
        if ghostAttachedToNotch != (housing != nil) {
            ghostAttachedToNotch = housing != nil
            ghost.contentView = NSHostingView(rootView: IslandGhost(
                attachedToNotch: housing != nil,
                bandHeight: TopDockPlacementPolicy.bandHeight(notch: housing)
            ))
        }
        if ghost.frame != frame { ghost.setFrame(frame, display: true) }
        ghost.alphaValue = CGFloat(min(1, proximity * 1.4))
        if !ghost.isVisible { ghost.orderFrontRegardless() }
    }

    private func makeGhost() -> NSPanel {
        let ghost = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        ghost.configureForCodeWindow()
        ghost.level = .statusBar
        ghost.hasShadow = false
        ghost.ignoresMouseEvents = true
        self.ghost = ghost
        return ghost
    }

    private func hideGhost() {
        isInDockZone = false
        ghost?.orderOut(nil)
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
