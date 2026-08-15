import AppKit
import Combine
import CodeWindowCore
import Darwin
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var inspector: InspectorController?
    private var store: SessionStore?
    private var sessionsCancellable: AnyCancellable?
    private var isManuallyHidden = false
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
            let smokeDirectory: URL?
            if isSmokeTest {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CodeWindow-smoke-\(UUID().uuidString)", isDirectory: true)
                smokeDirectory = try StateFiles.directory(environment: ["CODEWINDOW_STATE_DIR": url.path])
            } else {
                smokeDirectory = nil
                updaterController = SPUStandardUpdaterController(
                    startingUpdater: true,
                    updaterDelegate: nil,
                    userDriverDelegate: nil
                )
            }

            if let smokeDirectory,
               let process = ProcessInspector.stamp(pid: getpid())
            {
                try StateFiles.write(
                    SessionState(
                        sessionKey: "smoke-session",
                        agent: .codex,
                        activity: .idle,
                        projectLabel: "codewindow",
                        action: .waiting,
                        feedEvent: SessionFeedEvent(
                            kind: .assistant,
                            text: "Inspector smoke fixture"
                        ),
                        process: process
                    ),
                    to: smokeDirectory
                )
            }

            let store = try SessionStore(directory: smokeDirectory)
            self.store = store
            let panel = makePanel(store: store)
            self.panel = panel

            if isSmokeTest {
                panel.orderFrontRegardless()
                if let session = store.sessions.first(where: { $0.id == "smoke-session" }) {
                    inspector?.rowHoverChanged(session, isHovered: true)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }
                let inspectorPanel = panel.childWindows?.first
                let inspectorWorks = inspectorPanel?.isVisible == true
                    && inspectorPanel?.frame.width == PanelMetrics.width
                    && abs((inspectorPanel?.frame.maxX ?? 0) - panel.frame.minX + PanelMetrics.inspectorGap) < 0.5
                    && store.feeds["smoke-session"]?.count == 1
                let behavior = panel.collectionBehavior
                let detected = store.sessions.filter(\.isDiagnostic).count
                let hasAppIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil
                let hasSparkleFramework = FileManager.default.fileExists(
                    atPath: Bundle.main.bundleURL
                        .appendingPathComponent("Contents/Frameworks/Sparkle.framework")
                        .path
                )
                let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
                let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
                let hasSparkleConfiguration = feedURL ==
                    "https://github.com/mertdeveci5/codewindow/releases/latest/download/appcast.xml"
                    && publicKey?.isEmpty == false
                let originalOrigin = panel.frame.origin
                let trackpadMovement = panel.moveByTrackpad(deltaX: 8, deltaY: 0)
                let trackpadMoveWorks = trackpadMovement == NSPoint(x: -8, y: 0)
                let movedOrigin = panel.frame.origin
                panel.constrainToVisibleArea()
                let validPositionWasPreserved = panel.frame.origin == movedOrigin
                if let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                    panel.setFrameOrigin(NSPoint(x: visibleFrame.maxX + 100, y: visibleFrame.maxY + 100))
                }
                panel.constrainToVisibleArea()
                let offscreenPositionWasConstrained = NSScreen.screens.contains {
                    $0.visibleFrame.contains(panel.frame)
                }
                panel.setFrameOrigin(originalOrigin)
                let passed = panel.level == .floating
                    && behavior.contains(.canJoinAllSpaces)
                    && behavior.contains(.fullScreenAuxiliary)
                    && panel.styleMask.contains(.nonactivatingPanel)
                    && panel.frame.width == PanelMetrics.width
                    && AgentLogoAssets.allAvailable
                    && hasAppIcon
                    && hasSparkleFramework
                    && hasSparkleConfiguration
                    && trackpadMoveWorks
                    && validPositionWasPreserved
                    && offscreenPositionWasConstrained
                    && inspectorWorks
                print(
                    "floating=\(panel.level == .floating) "
                        + "allSpaces=\(behavior.contains(.canJoinAllSpaces)) "
                        + "fullscreen=\(behavior.contains(.fullScreenAuxiliary)) "
                        + "nonactivating=\(panel.styleMask.contains(.nonactivatingPanel)) "
                        + "width=\(Int(panel.frame.width)) "
                        + "logos=\(AgentLogoAssets.allAvailable) icon=\(hasAppIcon) "
                        + "sparkle=\(hasSparkleFramework && hasSparkleConfiguration) "
                        + "trackpad=\(trackpadMoveWorks) "
                        + "screenBounds=\(validPositionWasPreserved && offscreenPositionWasConstrained) "
                        + "inspector=\(inspectorWorks) "
                        + "sessions=\(store.sessions.count) detected=\(detected)"
                )
                inspector?.dismissImmediately()
                panel.orderOut(nil)
                if let smokeDirectory {
                    try? FileManager.default.removeItem(at: smokeDirectory)
                }
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            sessionsCancellable = store.$sessions.sink { [weak self] sessions in
                self?.inspector?.reconcile(with: sessions)
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
        panel.configureForCodeWindow()
        panel.isMovableByWindowBackground = true
        panel.title = "CodeWindow"
        let inspector = InspectorController(parentPanel: panel, store: store)
        self.inspector = inspector

        let content = PanelContentView(
            store: store,
            reportHeight: { [weak self, weak panel] height in
                guard let self, let panel else { return }
                self.resize(panel: panel, to: height)
            },
            installHooks: { [weak self] in
                guard let self else {
                    return PanelNotice(message: "setup failed · use the Terminal command", succeeded: false)
                }
                return await self.installHooks()
            },
            checkForUpdates: { [weak self] in
                self?.updaterController?.checkForUpdates(nil)
            },
            hidePanel: { [weak self] in
                self?.hidePanelManually()
            },
            activateTerminal: { [weak self] session in
                self?.activateTerminal(for: session) ?? false
            },
            hoverSession: { [weak inspector] session, isHovered in
                inspector?.rowHoverChanged(session, isHovered: isHovered)
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
        panel.constrainToVisibleArea()
        inspector?.relayout()
    }

    @objc private func frontmostApplicationDidChange() {
        updatePanelVisibility()
    }

    private func hidePanelManually() {
        isManuallyHidden = true
        inspector?.dismissImmediately()
        panel?.orderOut(nil)
    }

    private func updatePanelVisibility() {
        guard let panel, let store else { return }
        let shouldHide = isManuallyHidden || frontmostApplicationOwnsSession(store.sessions)
        if shouldHide {
            inspector?.dismissImmediately()
            if panel.isVisible {
                panel.orderOut(nil)
            }
        } else if !shouldHide, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func frontmostApplicationOwnsSession(_ sessions: [PresentedSession]) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        let bundlePath = application.bundleURL?.standardizedFileURL.path
        return sessions.contains { session in
            ProcessInspector.process(
                session.process,
                belongsToApplicationPID: application.processIdentifier,
                bundlePath: bundlePath
            )
        }
    }

    private func activateTerminal(for session: PresentedSession) -> Bool {
        let applications = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.activationPolicy == .regular
        }

        if let application = applications.first(where: {
            ProcessInspector.process(
                session.process,
                belongsToApplicationPID: $0.processIdentifier,
                bundlePath: nil
            )
        }) {
            return application.activate(options: [.activateIgnoringOtherApps])
        }

        let bundleMatches = applications.filter {
            ProcessInspector.process(
                session.process,
                belongsToApplicationPID: $0.processIdentifier,
                bundlePath: $0.bundleURL?.standardizedFileURL.path
            )
        }
        guard bundleMatches.count == 1, let application = bundleMatches.first else {
            return false
        }
        return application.activate(options: [.activateIgnoringOtherApps])
    }

    private func installHooks() async -> PanelNotice {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codewindow-install")
        return await Task.detached(priority: .userInitiated) {
            Self.runInstaller(at: helper)
        }.value
    }

    nonisolated private static func runInstaller(at helper: URL) -> PanelNotice {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["install"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return PanelNotice(message: "hooks installed · restart agents", succeeded: true)
            }
            return PanelNotice(message: "setup failed · use the Terminal command", succeeded: false)
        } catch {
            return PanelNotice(message: "setup failed · use the Terminal command", succeeded: false)
        }
    }

}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
