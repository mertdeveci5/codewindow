import AppKit
import Combine
import CodeWindowCore
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var store: SessionStore?
    private var sessionsCancellable: AnyCancellable?
    private var isManuallyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            let store = try SessionStore()
            self.store = store
            let panel = makePanel(store: store)
            self.panel = panel

            if CommandLine.arguments.contains("--smoke-test") {
                let behavior = panel.collectionBehavior
                let detected = store.sessions.filter(\.isDiagnostic).count
                let hasAppIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil
                let originalOrigin = panel.frame.origin
                let trackpadMovement = panel.moveByTrackpad(deltaX: 8, deltaY: 0)
                let trackpadMoveWorks = trackpadMovement == NSPoint(x: -8, y: 0)
                panel.setFrameOrigin(originalOrigin)
                let passed = panel.level == .floating
                    && behavior.contains(.canJoinAllSpaces)
                    && behavior.contains(.fullScreenAuxiliary)
                    && panel.styleMask.contains(.nonactivatingPanel)
                    && panel.frame.width == PanelMetrics.width
                    && AgentLogoAssets.allAvailable
                    && hasAppIcon
                    && trackpadMoveWorks
                print(
                    "floating=\(panel.level == .floating) "
                        + "allSpaces=\(behavior.contains(.canJoinAllSpaces)) "
                        + "fullscreen=\(behavior.contains(.fullScreenAuxiliary)) "
                        + "nonactivating=\(panel.styleMask.contains(.nonactivatingPanel)) "
                        + "width=\(Int(panel.frame.width)) "
                        + "logos=\(AgentLogoAssets.allAvailable) icon=\(hasAppIcon) "
                        + "trackpad=\(trackpadMoveWorks) "
                        + "sessions=\(store.sessions.count) detected=\(detected)"
                )
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            sessionsCancellable = store.$sessions.sink { [weak self] _ in
                self?.updatePanelVisibility()
            }
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(frontmostApplicationDidChange),
                name: NSWorkspace.didActivateApplicationNotification,
                object: nil
            )
            updatePanelVisibility()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenParametersDidChange),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        } catch {
            fputs("CodeWindow: \(error)\n", stderr)
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        isManuallyHidden = false
        updatePanelVisibility()
        return true
    }

    private func makePanel(store: SessionStore) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.title = "CodeWindow"
        // The panel is a dark opaque capsule in every system appearance, so pin the
        // appearance rather than letting label colors flip to dark-on-dark in Light Mode.
        panel.appearance = NSAppearance(named: .darkAqua)

        let content = PanelContentView(
            store: store,
            reportHeight: { [weak self, weak panel] height in
                guard let self, let panel else { return }
                self.resize(panel: panel, to: height)
            },
            installHooks: { [weak self] in
                self?.installHooks()
                    ?? SetupNotice(message: "setup failed · use the Terminal command", succeeded: false)
            },
            hidePanel: { [weak self] in
                self?.hidePanelManually()
            }
        )
        panel.contentView = NSHostingView(rootView: content)
        position(panel: panel)
        return panel
    }

    private func position(panel: NSPanel) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - PanelMetrics.screenMargin,
            y: frame.maxY - panel.frame.height - PanelMetrics.screenMargin
        ))
    }

    private func resize(panel: NSPanel, to measuredHeight: CGFloat) {
        guard measuredHeight > 0 else { return }
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maximumHeight = visibleFrame.map { $0.height - PanelMetrics.screenMargin * 2 } ?? measuredHeight
        let height = min(ceil(measuredHeight), maximumHeight)
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        if let visibleFrame {
            frame.origin.y = max(frame.origin.y, visibleFrame.minY + PanelMetrics.screenMargin)
        }
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    @objc private func screenParametersDidChange() {
        guard let panel else { return }
        position(panel: panel)
    }

    @objc private func frontmostApplicationDidChange() {
        updatePanelVisibility()
    }

    private func hidePanelManually() {
        isManuallyHidden = true
        panel?.orderOut(nil)
    }

    private func updatePanelVisibility() {
        guard let panel, let store else { return }
        let shouldHide = isManuallyHidden || frontmostApplicationOwnsReportedSession(store.sessions)
        if shouldHide, panel.isVisible {
            panel.orderOut(nil)
        } else if !shouldHide, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func frontmostApplicationOwnsReportedSession(_ sessions: [PresentedSession]) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        let bundlePath = application.bundleURL?.standardizedFileURL.path
        return sessions.contains { session in
            !session.isDiagnostic && ProcessInspector.process(
                session.process,
                belongsToApplicationPID: application.processIdentifier,
                bundlePath: bundlePath
            )
        }
    }

    private func installHooks() -> SetupNotice {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codewindow-install")
        let output = Pipe()
        let process = Process()
        process.executableURL = helper
        process.arguments = ["install"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            _ = output.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus == 0 {
                return SetupNotice(message: "hooks installed · restart agents", succeeded: true)
            }
            return SetupNotice(message: "setup failed · use the Terminal command", succeeded: false)
        } catch {
            return SetupNotice(message: "setup failed · use the Terminal command", succeeded: false)
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
