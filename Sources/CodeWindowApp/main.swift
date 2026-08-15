import AppKit
import Combine
import CodeWindowCore
import Darwin
import Sparkle
import SwiftUI

private struct InstallerCommandResult: Sendable {
    let terminationStatus: Int32
    let output: String
}

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
                let smokeSession = store.sessions.first(where: { $0.id == "smoke-session" })
                if let session = smokeSession {
                    inspector?.rowHoverChanged(session, isHovered: true)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }
                let inspectorPanel = panel.childWindows?.first
                let inspectorWorks = inspectorPanel?.isVisible == true
                    && inspectorPanel?.frame.width == PanelMetrics.width
                    && abs((inspectorPanel?.frame.maxX ?? 0) - panel.frame.minX + PanelMetrics.inspectorGap) < 0.5
                    && store.feeds["smoke-session"]?.count == 1
                let inspectorTransitionWorks: Bool
                if let session = smokeSession {
                    inspector?.rowHoverChanged(session, isHovered: false)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.28))
                    inspector?.rowHoverChanged(session, isHovered: true)
                    let transitionDeadline = Date().addingTimeInterval(1)
                    while (inspectorPanel?.alphaValue ?? 0) <= 0.95, Date() < transitionDeadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                    }
                    inspectorTransitionWorks = inspectorPanel?.isVisible == true
                        && (inspectorPanel?.alphaValue ?? 0) > 0.95
                } else {
                    inspectorTransitionWorks = false
                }
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
                let momentumMoveWorks = smokeTestMomentumMovement(of: panel, from: originalOrigin)
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
                    && momentumMoveWorks
                    && validPositionWasPreserved
                    && offscreenPositionWasConstrained
                    && inspectorWorks
                    && inspectorTransitionWorks
                print(
                    "floating=\(panel.level == .floating) "
                        + "allSpaces=\(behavior.contains(.canJoinAllSpaces)) "
                        + "fullscreen=\(behavior.contains(.fullScreenAuxiliary)) "
                        + "nonactivating=\(panel.styleMask.contains(.nonactivatingPanel)) "
                        + "width=\(Int(panel.frame.width)) "
                        + "logos=\(AgentLogoAssets.allAvailable) icon=\(hasAppIcon) "
                        + "sparkle=\(hasSparkleFramework && hasSparkleConfiguration) "
                        + "trackpad=\(trackpadMoveWorks) momentum=\(momentumMoveWorks) "
                        + "screenBounds=\(validPositionWasPreserved && offscreenPositionWasConstrained) "
                        + "inspector=\(inspectorWorks) transition=\(inspectorTransitionWorks) "
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

    private func smokeTestMomentumMovement(
        of panel: FloatingPanel,
        from originalOrigin: NSPoint
    ) -> Bool {
        guard let momentumCGEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 8,
            wheel3: 0
        ) else { return false }

        momentumCGEvent.setIntegerValueField(
            .scrollWheelEventMomentumPhase,
            value: Int64(CGMomentumScrollPhase.continuous.rawValue)
        )
        guard let momentumEvent = NSEvent(cgEvent: momentumCGEvent),
              let cursorBefore = CGEvent(source: nil)?.location
        else { return false }

        defer { panel.setFrameOrigin(originalOrigin) }
        panel.sendEvent(momentumEvent)
        guard let cursorAfter = CGEvent(source: nil)?.location else { return false }

        let expectedOrigin = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? originalOrigin
            : NSPoint(x: originalOrigin.x - 8, y: originalOrigin.y)
        return momentumEvent.momentumPhase.contains(.changed)
            && panel.frame.origin == expectedOrigin
            && cursorAfter == cursorBefore
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
            checkHooks: { [weak self] in
                await self?.hooksAreInstalled() ?? false
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
        let result = await Task.detached(priority: .userInitiated) {
            Self.runInstaller(at: helper, command: "install")
        }.value
        guard result.terminationStatus == 0 else {
            return PanelNotice(message: Self.installerFailureMessage(result.output), succeeded: false)
        }
        return PanelNotice(message: "hooks installed · restart agents, then run /hooks", succeeded: true)
    }

    private func hooksAreInstalled() async -> Bool {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codewindow-install")
        let result = await Task.detached(priority: .utility) {
            Self.runInstaller(at: helper, command: "status")
        }.value
        return result.terminationStatus == 0
    }

    nonisolated private static func runInstaller(at helper: URL, command: String) -> InstallerCommandResult {
        let process = Process()
        process.executableURL = helper
        process.arguments = [command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            output.fileHandleForWriting.closeFile()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return InstallerCommandResult(
                terminationStatus: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self)
            )
        } catch {
            output.fileHandleForWriting.closeFile()
            return InstallerCommandResult(
                terminationStatus: -1,
                output: "The installer could not start. Reinstall CodeWindow and try again."
            )
        }
    }

    nonisolated private static func installerFailureMessage(_ output: String) -> String {
        let detail = output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)?
            .replacingOccurrences(of: "codewindow-install: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detail, !detail.isEmpty else { return "setup failed · reinstall CodeWindow and try again" }
        return "setup failed · \(detail.prefix(96))"
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
