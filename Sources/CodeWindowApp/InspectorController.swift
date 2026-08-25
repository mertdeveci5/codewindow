import AppKit
import CodeWindowCore
import Combine
import SwiftUI

@MainActor
final class InspectorModel: ObservableObject {
    @Published var session: PresentedSession?
}

final class InspectorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class InspectorController: NSObject {
    private static let initialHoverDelay: DispatchTimeInterval = .milliseconds(700)

    private let parentPanel: FloatingPanel
    private let store: SessionStore
    private let model = InspectorModel()
    private var panel: InspectorPanel?
    private var hoveredSessionID: String?
    private var inspectorIsHovered = false
    private var pendingTransition: DispatchWorkItem?
    private var transitionGeneration = 0

    init(parentPanel: FloatingPanel, store: SessionStore) {
        self.parentPanel = parentPanel
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentGeometryDidChange),
            name: NSWindow.didMoveNotification,
            object: parentPanel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentGeometryDidChange),
            name: NSWindow.didResizeNotification,
            object: parentPanel
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func rowHoverChanged(_ session: PresentedSession, isHovered: Bool) {
        if isHovered {
            hoveredSessionID = session.id
            pendingTransition?.cancel()
            if panel?.isVisible == true {
                present(session)
            } else {
                schedule(after: Self.initialHoverDelay) { [weak self] in
                    guard let self, self.hoveredSessionID == session.id else { return }
                    self.present(session)
                }
            }
        } else if hoveredSessionID == session.id {
            hoveredSessionID = nil
            scheduleDismissalIfNeeded()
        }
    }

    func reconcile(with sessions: [PresentedSession]) {
        guard let visibleSession = model.session else { return }
        guard let updated = sessions.first(where: { $0.id == visibleSession.id }) else {
            dismissImmediately()
            return
        }
        if updated != visibleSession {
            model.session = updated
            relayout()
        }
    }

    func dismissImmediately() {
        pendingTransition?.cancel()
        pendingTransition = nil
        hoveredSessionID = nil
        inspectorIsHovered = false
        transitionGeneration &+= 1
        hidePanel()
    }

    func relayout() {
        guard let panel else { return }
        let screen = bestScreen(for: parentPanel.frame)
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = InspectorPlacementPolicy.frame(
            anchor: parentPanel.frame,
            size: NSSize(width: PanelMetrics.width, height: PanelMetrics.inspectorHeight),
            gap: PanelMetrics.inspectorGap,
            margin: PanelMetrics.screenMargin,
            within: visibleFrame
        )
        panel.setFrame(frame, display: true, animate: false)
    }

    @objc private func parentGeometryDidChange() {
        relayout()
    }

    private func present(_ session: PresentedSession) {
        transitionGeneration &+= 1
        model.session = store.sessions.first(where: { $0.id == session.id }) ?? session
        let panel = inspectorPanel()
        relayout()
        if panel.parent !== parentPanel {
            parentPanel.addChildWindow(panel, ordered: .above)
        }
        let wasVisible = panel.isVisible
        if !wasVisible {
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.orderFrontRegardless()
        }
        animate(panel: panel, to: 1, duration: 0.14)
    }

    private func inspectorPanel() -> InspectorPanel {
        if let panel { return panel }

        let panel = InspectorPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: PanelMetrics.inspectorHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureForCodeWindow()
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: InspectorContentView(
            store: store,
            model: model,
            hoverChanged: { [weak self] in self?.inspectorHoverChanged($0) }
        ))
        self.panel = panel
        return panel
    }

    private func inspectorHoverChanged(_ isHovered: Bool) {
        inspectorIsHovered = isHovered
        if isHovered {
            pendingTransition?.cancel()
            pendingTransition = nil
        } else {
            scheduleDismissalIfNeeded()
        }
    }

    private func scheduleDismissalIfNeeded() {
        guard hoveredSessionID == nil, !inspectorIsHovered else { return }
        schedule(after: .milliseconds(260)) { [weak self] in
            guard let self, self.hoveredSessionID == nil, !self.inspectorIsHovered else { return }
            self.dismiss()
        }
    }

    private func schedule(
        after delay: DispatchTimeInterval,
        _ transition: @escaping @MainActor () -> Void
    ) {
        pendingTransition?.cancel()
        let work = DispatchWorkItem { transition() }
        pendingTransition = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dismiss() {
        guard let panel else { return }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hidePanel(ifCurrent: generation)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.panel === panel else { return }
                self.hidePanel(ifCurrent: generation)
            }
        }
    }

    private func animate(panel: NSPanel, to alpha: CGFloat, duration: TimeInterval) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = alpha
        }
    }

    private func hidePanel(ifCurrent generation: Int) {
        guard transitionGeneration == generation,
              hoveredSessionID == nil,
              !inspectorIsHovered
        else { return }
        hidePanel()
    }

    private func hidePanel() {
        guard let panel else { return }
        panel.alphaValue = 0
        if panel.parent === parentPanel {
            parentPanel.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        model.session = nil
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let screen = NSScreen.screens.max {
            $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
        }
        guard let screen, screen.visibleFrame.intersection(frame).area > 0 else {
            return parentPanel.screen ?? NSScreen.main
        }
        return screen
    }
}
