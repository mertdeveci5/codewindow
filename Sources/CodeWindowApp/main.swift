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
    private var dock: TopDockController?
    private var inspector: InspectorController?
    private var store: SessionStore?
    private var sessionsCancellable: AnyCancellable?
    private var isManuallyHidden = false
    private var updaterController: SPUStandardUpdaterController?
    private lazy var updateReminder = UpdateReminder(isPanelManuallyHidden: { [weak self] in
        self?.isManuallyHidden ?? true
    })

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
                    userDriverDelegate: updateReminder
                )
            }

            if let smokeDirectory,
               let process = ProcessInspector.stamp(pid: getpid())
            {
                for index in 0...8 {
                    try StateFiles.write(
                        SessionState(
                            sessionKey: index == 0 ? "smoke-session" : "smoke-session-\(index)",
                            agent: .codex,
                            activity: .idle,
                            projectLabel: "codewindow",
                            action: .waiting,
                            actionPreview: "Inspector smoke fixture \(index + 1)",
                            feedEvents: index == 0 ? [SessionFeedEvent(
                                kind: .assistant,
                                text: "Inspector smoke fixture"
                            )] : [],
                            process: process
                        ),
                        to: smokeDirectory
                    )
                }
            }

            let store = try SessionStore(directory: smokeDirectory)
            self.store = store
            if isSmokeTest {
                updateReminder.availableVersion = "99.0"
            }
            // The smoke test asserts the floating geometry, so it must not inherit a
            // developer's persisted Top Dock preference. Its isolated domain is removed
            // before the process exits so repeated runs do not leave preferences behind.
            let smokeDefaultsSuite = isSmokeTest
                ? "codewindow.smoke-\(UUID().uuidString)"
                : nil
            let dockDefaults = smokeDefaultsSuite.flatMap(UserDefaults.init(suiteName:))
                ?? .standard
            let panel = makePanel(
                store: store,
                dockDefaults: dockDefaults
            )
            self.panel = panel

            if isSmokeTest {
                panel.orderFrontRegardless()
                let smokeSession = store.sessions.first(where: { $0.id == "smoke-session" })
                if let session = smokeSession {
                    inspector?.rowHoverChanged(session, isHovered: true)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let hoverIntentWorks = panel.childWindows?.first?.isVisible != true
                let presentationDeadline = Date().addingTimeInterval(2)
                while panel.childWindows?.first?.isVisible != true,
                      Date() < presentationDeadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
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
                    let transitionDeadline = Date().addingTimeInterval(2)
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
                let diagnosticFixture = PresentedSession.detected(TerminalAgentProcess(
                    agent: .codex,
                    process: ProcessStamp(pid: 1, startedAtSeconds: 1, startedAtMicroseconds: 0),
                    projectLabel: "codewindow"
                ))
                let diagnosticGuidanceWorks =
                    diagnosticFixture.metadataLabel(hooksInstalled: nil) == "checking setup"
                    && diagnosticFixture.metadataLabel(hooksInstalled: false) == "setup needed"
                    && diagnosticFixture.metadataLabel(hooksInstalled: true) == "restart needed"
                    && diagnosticFixture.accessibilityDescription(hooksInstalled: true)
                        .contains("trust hooks if prompted")
                let workingFixture = PresentedSession.reported(SessionState(
                    sessionKey: "smoke-preview",
                    agent: .claude,
                    activity: .working,
                    projectLabel: "codewindow",
                    action: .runningCommand,
                    taskPreview: "lets go",
                    actionPreview: "swift build",
                    process: ProcessStamp(pid: 1, startedAtSeconds: 1, startedAtMicroseconds: 0)
                ))
                let livePreviewWorks = workingFixture.primaryLabel == "swift build"
                let visibleReminder = UpdateReminder(isPanelManuallyHidden: { false })
                let hiddenReminder = UpdateReminder(isPanelManuallyHidden: { true })
                let updateRoutingWorks =
                    !visibleReminder.shouldLetSparklePresent(immediateFocus: false)
                    && visibleReminder.shouldLetSparklePresent(immediateFocus: true)
                    && hiddenReminder.shouldLetSparklePresent(immediateFocus: false)
                let hasAppIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil
                let hasSparkleFramework = FileManager.default.fileExists(
                    atPath: Bundle.main.bundleURL
                        .appendingPathComponent("Contents/Frameworks/Sparkle.framework")
                        .path
                )
                let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
                let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
                let scheduledCheckInterval = Bundle.main.object(
                    forInfoDictionaryKey: "SUScheduledCheckInterval"
                ) as? Int
                let hasSparkleConfiguration = feedURL ==
                    "https://github.com/mertdeveci5/codewindow/releases/latest/download/appcast.xml"
                    && publicKey?.isEmpty == false
                    && scheduledCheckInterval == 3_600
                let originalOrigin = panel.frame.origin
                let trackpadMovement = panel.moveByTrackpad(deltaX: 8, deltaY: 0)
                let trackpadMoveWorks = trackpadMovement == NSPoint(x: -8, y: 0)
                let overflowInteractionWorks = smokeTestOverflowInteraction(of: panel)
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
                let topDockWorks = smokeTestTopDockInteraction(of: panel)
                // Named checks rather than one conjunction: a failing run has to say which
                // check failed, or the next person reads `false` and starts guessing.
                let checks: [(name: String, passed: Bool)] = [
                    ("floating", panel.level == .floating),
                    ("allSpaces", behavior.contains(.canJoinAllSpaces)),
                    ("fullscreen", behavior.contains(.fullScreenAuxiliary)),
                    ("nonactivating", panel.styleMask.contains(.nonactivatingPanel)),
                    ("width", panel.frame.width == PanelMetrics.width),
                    ("logos", AgentLogoAssets.allAvailable),
                    ("icon", hasAppIcon),
                    ("sparkle", hasSparkleFramework && hasSparkleConfiguration),
                    ("hookGuidance", diagnosticGuidanceWorks),
                    ("livePreview", livePreviewWorks),
                    ("updateRouting", updateRoutingWorks),
                    ("trackpad", trackpadMoveWorks),
                    ("momentum", momentumMoveWorks),
                    ("topDock", topDockWorks),
                    ("overflowInteraction", overflowInteractionWorks),
                    ("screenBounds", validPositionWasPreserved && offscreenPositionWasConstrained),
                    ("hoverIntent", hoverIntentWorks),
                    ("inspector", inspectorWorks),
                    ("transition", inspectorTransitionWorks),
                ]
                let failures = checks.filter { !$0.passed }.map(\.name)
                print(
                    checks.map { "\($0.name)=\($0.passed)" }.joined(separator: " ")
                        + " sessions=\(store.sessions.count) detected=\(detected)"
                )
                if !failures.isEmpty {
                    fputs("smoke test failed: \(failures.joined(separator: ", "))\n", stderr)
                }
                inspector?.dismissImmediately()
                panel.orderOut(nil)
                if let smokeDirectory {
                    try? FileManager.default.removeItem(at: smokeDirectory)
                }
                if let smokeDefaultsSuite {
                    dockDefaults.removePersistentDomain(forName: smokeDefaultsSuite)
                }
                exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
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

    /// Overflow rows scroll, while the grab strip above them remains a two-axis drag surface.
    private func smokeTestOverflowInteraction(of panel: FloatingPanel) -> Bool {
        let reportedHeight = panel.scrollableListHeight
        defer { panel.scrollableListHeight = reportedHeight }

        panel.scrollableListHeight = PanelMetrics.maximumListHeight
        let insideList = NSPoint(x: 100, y: PanelMetrics.bezel + 1)
        let grabStrip = NSPoint(
            x: 100,
            y: PanelMetrics.bezel
                + PanelMetrics.maximumListHeight
                + PanelMetrics.dragHandleHeight / 2
        )
        let overflowingListScrolls = panel.scrollsList(at: insideList, deltaX: 0, deltaY: -6)
            && !panel.scrollsList(at: insideList, deltaX: -6, deltaY: 0)
        let grabStripMoves = !panel.scrollsList(at: grabStrip, deltaX: 0, deltaY: -6)

        panel.scrollableListHeight = 0
        let shortListMovesPanel = !panel.scrollsList(at: insideList, deltaX: 0, deltaY: -6)
        return reportedHeight == PanelMetrics.maximumListHeight
            && overflowingListScrolls
            && grabStripMoves
            && shortListMovesPanel
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

    private func smokeTestTopDockInteraction(of panel: FloatingPanel) -> Bool {
        guard let dock, let screen = panel.screen ?? NSScreen.main else { return false }
        inspector?.dismissImmediately()

        let originalTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let notch = TopDockPlacementPolicy.notch(
            screenFrame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        let dockTarget = TopDockPlacementPolicy.dockedFrame(
            contentSize: CGSize(
                width: TopDockPlacementPolicy.minimumCapsuleWidth,
                height: TopDockPlacementPolicy.capsuleHeight
            ),
            notch: notch,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        dock.panelDragDidBegin()
        panel.setFrameOrigin(NSPoint(
            x: dockTarget.midX - panel.frame.width / 2,
            y: dockTarget.maxY - panel.frame.height
        ))
        dock.panelDragDidEnd(moved: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        let foldedTop = panel.frame.maxY
        // A docked island reaches up into the camera housing, so the folded height is the
        // activity bar plus that overlap.
        let housingOverlap = notch == nil ? 0 : TopDockPlacementPolicy.notchOverlap
        let foldedWorks = dock.model.isDocked
            && !dock.model.isUnfolded
            && panel.isTopDocked
            && panel.level == .statusBar
            && !panel.hasShadow
            && abs(panel.frame.midX - dockTarget.midX) < 1
            && abs(
                panel.frame.height
                    - (TopDockPlacementPolicy.capsuleHeight + housingOverlap)
            ) < 1

        dock.unfold()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        let unfoldedWorks = dock.model.isUnfolded
            && panel.hasShadow
            && panel.frame.width == PanelMetrics.width
            && panel.frame.height > TopDockPlacementPolicy.capsuleHeight
            && abs(panel.frame.maxY - foldedTop) < 1

        dock.fold()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let refoldedWorks = !dock.model.isUnfolded
            && abs(panel.frame.maxY - foldedTop) < 1

        let dockedFrame = panel.frame
        dock.panelDragDidBegin()
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + TopDockPlacementPolicy.detachDistance / 2,
            y: panel.frame.minY
        ))
        dock.panelDragDidEnd(moved: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let resistedPullWorks = dock.model.isDocked
            && panel.isTopDocked
            && abs(panel.frame.minX - dockedFrame.minX) < 1
            && abs(panel.frame.minY - dockedFrame.minY) < 1

        dock.detach()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let restoredWorks = !dock.model.isDocked
            && !panel.isTopDocked
            && panel.level == .floating
            && panel.frame.width == PanelMetrics.width
            && abs(panel.frame.minX - originalTopLeft.x) < 1
            && abs(panel.frame.maxY - originalTopLeft.y) < 1

        dock.dock()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        dock.panelDragDidBegin()
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + TopDockPlacementPolicy.detachDistance + 1,
            y: panel.frame.minY
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let pullToDetachWorks = !dock.model.isDocked
            && !panel.isTopDocked
            && panel.frame.width == PanelMetrics.width
        dock.panelDragDidEnd(moved: true)

        return foldedWorks
            && unfoldedWorks
            && refoldedWorks
            && resistedPullWorks
            && restoredWorks
            && pullToDetachWorks
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        isManuallyHidden = false
        updatePanelVisibility()
        return true
    }

    private func makePanel(store: SessionStore, dockDefaults: UserDefaults) -> FloatingPanel {
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
        let dock = TopDockController(panel: panel, defaults: dockDefaults)
        self.dock = dock
        dock.isInspectorActive = { [weak inspector] in inspector?.isPresenting ?? false }
        dock.didChangeDockState = { [weak self] in self?.dockStateDidChange() }

        let content = PanelContentView(
            store: store,
            updateReminder: updateReminder,
            dock: dock.model,
            reportFullContentSize: { [weak dock] size in
                dock?.fullContentSizeChanged(to: size)
            },
            reportCapsuleContentSize: { [weak dock] size in
                dock?.capsuleContentSizeChanged(to: size)
            },
            reportScrollableListHeight: { [weak panel] height in
                panel?.scrollableListHeight = height
            },
            installHooks: { [weak self] in
                guard let self else {
                    return PanelNotice(message: "setup failed · use the Terminal command", succeeded: false)
                }
                return await self.installHooks()
            },
            uninstallHooks: { [weak self] in
                guard let self else {
                    return PanelNotice(message: "removal failed · use the Terminal command", succeeded: false)
                }
                return await self.uninstallHooks()
            },
            checkHooks: { [weak self] in
                guard let self else { return false }
                // Repair before reporting: a build that adds a hook event would otherwise show
                // the setup prompt for the moment between the check and the refresh.
                await self.refreshInstalledHooks()
                return await self.hooksAreInstalled()
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
            },
            toggleDock: { [weak dock] in
                dock?.toggleDock()
            },
            unfoldedHoverChanged: { [weak dock] isHovered in
                dock?.unfoldedHoverChanged(isHovered)
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

    /// Folding hides the rows the inspector hangs off, and a docked panel outranks the
    /// auto-hide rule, so both have to be re-evaluated.
    private func dockStateDidChange() {
        inspector?.dismissImmediately()
        updatePanelVisibility()
    }

    @objc private func screenParametersDidChange() {
        // A resolution or display change moves the notch: recentre rather than drift.
        dock?.screenParametersDidChange()
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
        // A docked panel is part of the screen furniture: it stays put over the terminal
        // that owns the session. Only the floating panel gets out of the way.
        let shouldHide = isManuallyHidden
            || (dock?.isDocked != true && frontmostApplicationOwnsSession(store.sessions))
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

    nonisolated private static let installerHelper = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Helpers/codewindow-install")

    /// Agents execute a copy of the reporter from the user's home, so replacing the app bundle
    /// leaves that copy behind and a reporter fix never reaches them. Rewrite it whenever this
    /// build differs. Best effort: a failure leaves the previous copy in place and working.
    private func refreshInstalledHooks() async {
        let result = await Task.detached(priority: .utility) {
            Self.runInstaller(at: Self.installerHelper, command: "refresh")
        }.value
        if result.terminationStatus != 0 {
            fputs("CodeWindow: could not refresh agent hooks · \(result.output)\n", stderr)
        }
    }

    private func installHooks() async -> PanelNotice {
        let helper = Self.installerHelper
        let result = await Task.detached(priority: .userInitiated) {
            Self.runInstaller(at: helper, command: "install")
        }.value
        guard result.terminationStatus == 0 else {
            return PanelNotice(message: Self.installerFailureMessage(result.output), succeeded: false)
        }
        return PanelNotice(message: "hooks installed · restart agents, then run /hooks", succeeded: true)
    }

    private func hooksAreInstalled() async -> Bool {
        let helper = Self.installerHelper
        let result = await Task.detached(priority: .utility) {
            Self.runInstaller(at: helper, command: "status")
        }.value
        return result.terminationStatus == 0
    }

    private func uninstallHooks() async -> PanelNotice {
        let helper = Self.installerHelper
        let result = await Task.detached(priority: .userInitiated) {
            Self.runInstaller(at: helper, command: "uninstall")
        }.value
        guard result.terminationStatus == 0 else {
            return PanelNotice(message: Self.installerFailureMessage(result.output), succeeded: false)
        }
        return PanelNotice(message: "agent hooks and local state removed", succeeded: true)
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
