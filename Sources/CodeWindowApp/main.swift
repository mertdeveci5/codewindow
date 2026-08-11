import AppKit
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var store: SessionStore?

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
                let passed = panel.level == .floating
                    && behavior.contains(.canJoinAllSpaces)
                    && behavior.contains(.fullScreenAuxiliary)
                    && panel.styleMask.contains(.nonactivatingPanel)
                    && panel.frame.width == PanelMetrics.width
                    && AgentLogoAssets.allAvailable
                    && hasAppIcon
                print(
                    "floating=\(panel.level == .floating) "
                        + "allSpaces=\(behavior.contains(.canJoinAllSpaces)) "
                        + "fullscreen=\(behavior.contains(.fullScreenAuxiliary)) "
                        + "nonactivating=\(panel.styleMask.contains(.nonactivatingPanel)) "
                        + "width=\(Int(panel.frame.width)) "
                        + "logos=\(AgentLogoAssets.allAvailable) icon=\(hasAppIcon) "
                        + "sessions=\(store.sessions.count) detected=\(detected)"
                )
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            panel.orderFrontRegardless()
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
