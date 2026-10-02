import AppKit
import Combine
import CodeWindowCloud
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
    private var cloudStateCancellable: AnyCancellable?
    private var cloudView: CloudViewController?
    private var inbox: InboxStore?
    private var inboxHotKey: InboxHotKey?
    private var inboxCancellable: AnyCancellable?
    private var inboxVisibilityCancellable: AnyCancellable?
    private var isManuallyHidden = false
    /// The design preview's fixtures belong to this process, so a preview launched from a
    /// terminal would otherwise hide itself whenever that terminal is in front.
    private var isPreview = false
    /// Nil until the first snapshot, which is history rather than news.
    private var announcedAttentionIDs: Set<String>?
    private var updaterController: SPUStandardUpdaterController?
    private lazy var updateReminder = UpdateReminder(isPanelManuallyHidden: { [weak self] in
        self?.isManuallyHidden ?? true
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
            let isPreview = !isSmokeTest && CommandLine.arguments.contains("--ui-preview")
            self.isPreview = isPreview
            let smokeDirectory: URL?
            if isPreview {
                smokeDirectory = try Self.writePreviewFixtures()
            } else if isSmokeTest {
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

            if isSmokeTest, let smokeDirectory,
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

            let store = try SessionStore(
                directory: smokeDirectory,
                discoversTerminalAgents: !isPreview
            )
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
                ?? (isPreview ? Self.previewDefaults() : .standard)
            if isSmokeTest {
                let savedCloudView = CloudMirrorHandle(
                    computerID: "smoke-saved-computer",
                    slug: "meatproxy1",
                    generation: 1,
                    visibility: .privateAccess,
                    ownershipMarker: String(repeating: "a", count: 64),
                    remoteIDSeed: String(repeating: "b", count: 64),
                    ownershipEstablished: true,
                    publicURL: URL(string: "https://meatproxy1.cool.computer")
                )
                dockDefaults.set(
                    try JSONEncoder().encode(savedCloudView),
                    forKey: "cloudView.handle"
                )
                dockDefaults.set(true, forKey: "cloudView.enabled")
            }
            let cloudView = CloudViewController(defaults: dockDefaults)
            self.cloudView = cloudView
            let inbox = InboxStore(stateDirectory: store.directory)
            self.inbox = inbox
            CodeWindowMenu.install()
            if !isSmokeTest {
                inboxHotKey = InboxHotKey { [weak self] in self?.answerNextWaiting() }
            }
            let panel = makePanel(
                store: store,
                dockDefaults: dockDefaults,
                cloudView: cloudView,
                inbox: inbox
            )
            self.panel = panel
            inboxCancellable = inbox.$isOpen
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] isOpen in self?.inboxDidChange(isOpen: isOpen) }
            // A session landing in the inbox brings the panel back over the terminal at once.
            inboxVisibilityCancellable = inbox.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updatePanelVisibility() }

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
                    && diagnosticFixture.metadataLabel(hooksInstalled: true) == "waiting for hooks"
                    && diagnosticFixture.accessibilityDescription(hooksInstalled: true)
                        .contains("restart the agent if updates do not appear")
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
                let cloudViewerURL = Bundle.main.url(
                    forResource: "index",
                    withExtension: "html",
                    subdirectory: "CloudView"
                )
                let cloudViewer = cloudViewerURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                let hasCloudViewer = cloudViewer?.contains("Content-Security-Policy") == true
                    && cloudViewer?.contains("state.json") == true
                    && cloudViewer?.contains("font-weight: 400") == true
                cloudView.applicationDidWake()
                let savedCloudViewStartsDormant = cloudView.phase == .disabled
                    && cloudView.statusPresentation == nil
                    && cloudView.setupTitle == "Connect Cloud View…"
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
                let inboxWorks = smokeTestInbox(inbox: inbox, panel: panel, directory: smokeDirectory)
                let terminalAutoHideWorks = Self.shouldHidePanel(
                    isManuallyHidden: false,
                    frontmostApplicationOwnsSession: true
                ) && !Self.shouldHidePanel(
                    isManuallyHidden: false,
                    frontmostApplicationOwnsSession: false
                ) && !Self.shouldHidePanel(
                    isManuallyHidden: false,
                    frontmostApplicationOwnsSession: true,
                    inboxNeedsUser: true
                ) && Self.shouldHidePanel(
                    isManuallyHidden: true,
                    frontmostApplicationOwnsSession: false,
                    inboxNeedsUser: true
                )
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
                    ("cloudViewer", hasCloudViewer),
                    ("cloudDormant", savedCloudViewStartsDormant),
                    ("sparkle", hasSparkleFramework && hasSparkleConfiguration),
                    ("hookGuidance", diagnosticGuidanceWorks),
                    ("livePreview", livePreviewWorks),
                    ("updateRouting", updateRoutingWorks),
                    ("trackpad", trackpadMoveWorks),
                    ("momentum", momentumMoveWorks),
                    ("topDock", topDockWorks),
                    ("inbox", inboxWorks),
                    ("terminalAutoHide", terminalAutoHideWorks),
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
                self?.announceNewAttention(in: sessions)
                self?.dock?.sessionsChanged(sessions)
                self?.inspector?.reconcile(with: sessions)
                self?.updatePanelVisibility()
            }
            if isPreview { startPreview() }
            cloudStateCancellable = store.$sessions
                .combineLatest(store.$feeds)
                .sink { [weak cloudView] sessions, feeds in
                    cloudView?.update(sessions: sessions, feeds: feeds)
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
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(applicationDidWake),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
        } catch {
            fputs("CodeWindow: \(error)\n", stderr)
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Design preview

    /// `--ui-preview` opens the panel over fixed sessions in an isolated state directory and
    /// preferences domain, so the design can be checked on screen without touching real hooks,
    /// sessions, or the user's saved panel position. `CODEWINDOW_PREVIEW` picks the starting
    /// presentation: floating, minimal, compact (default), expanded, list, inspector, inbox,
    /// inbox-floating, or inbox-list; `inbox-cycle` answers each session in turn, and `cycle`
    /// steps through the docked presentations on its own so their transitions can be recorded.
    private static var previewMode: String {
        ProcessInfo.processInfo.environment["CODEWINDOW_PREVIEW"] ?? "compact"
    }

    private static func writePreviewFixtures() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeWindow-preview", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        let directory = try StateFiles.directory(environment: ["CODEWINDOW_STATE_DIR": url.path])
        guard previewMode != "minimal", let process = ProcessInspector.stamp(pid: getpid()) else {
            return directory
        }
        let now = Date()
        let fixtures = [
            SessionState(
                sessionKey: "preview-claude",
                agent: .claude,
                activity: .working,
                projectLabel: "codewindow",
                action: .runningCommand,
                taskPreview: "make the island feel native",
                actionPreview: "swift build --product CodeWindow",
                feedEvents: [
                    SessionFeedEvent(kind: .user, text: "make the island feel native"),
                    SessionFeedEvent(kind: .assistant, text: "Reading the dock controller first."),
                    SessionFeedEvent(kind: .toolCall, text: "swift build --product CodeWindow"),
                ],
                process: process,
                updatedAt: now
            ),
            SessionState(
                sessionKey: "preview-codex",
                agent: .codex,
                activity: .needsAttention,
                projectLabel: "website",
                action: .awaitingPermission,
                actionPreview: "npm run deploy",
                process: process,
                updatedAt: now.addingTimeInterval(-40)
            ),
            SessionState(
                sessionKey: "preview-pi",
                agent: .pi,
                activity: .idle,
                projectLabel: "notes",
                action: .waiting,
                taskPreview: "summarize the changelog",
                process: process,
                updatedAt: now.addingTimeInterval(-300)
            ),
        ]
        for fixture in fixtures {
            try StateFiles.write(fixture, to: directory)
        }
        if previewMode.hasPrefix("inbox") {
            let inbox = try InboxFiles.directory(stateDirectory: directory)
            try InboxFiles.setEnabled(true, in: inbox)
            let items = [
                InboxItem(
                    sessionKey: "preview-claude",
                    externalSessionID: "preview-claude",
                    agent: .claude,
                    projectLabel: "codewindow",
                    request: .reply,
                    message: "The island now springs between its sizes and the panel uses Liquid Glass. "
                        + "Two things are left:\n\n1. The **website demo** still shows the old capsule.\n"
                        + "2. I have not tried it on a display without a notch.\n\n"
                        + "Should I update the demo first, or test the notchless layout?",
                    task: "make the island feel native",
                    process: process,
                    createdAt: now.addingTimeInterval(-420)
                ),
                InboxItem(
                    sessionKey: "preview-codex",
                    externalSessionID: "preview-codex",
                    agent: .codex,
                    projectLabel: "website",
                    request: .permission(tool: "Bash", detail: "npm run deploy -- --production"),
                    message: nil,
                    task: "ship the new landing page",
                    process: process,
                    createdAt: now.addingTimeInterval(-90)
                ),
                InboxItem(
                    sessionKey: "preview-pi",
                    externalSessionID: "preview-pi",
                    agent: .pi,
                    projectLabel: "notes",
                    request: .reply,
                    message: "Here is the changelog summary. Want me to post it to the team channel?",
                    task: "summarize the changelog",
                    process: process,
                    createdAt: now.addingTimeInterval(-20)
                ),
            ]
            for item in items {
                try InboxFiles.add(item, in: inbox)
            }
        }
        return directory
    }

    private static func previewDefaults() -> UserDefaults {
        let name = "codewindow.ui-preview"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        defaults.set(!previewMode.hasSuffix("floating"), forKey: "topDockEnabled")
        return defaults
    }

    private func startPreview() {
        switch Self.previewMode {
        case "expanded":
            dock?.islandHoverChanged(true)
        case "list":
            dock?.unfold()
        case "inspector":
            dock?.unfold()
            if let session = store?.sessions.first {
                inspector?.rowHoverChanged(session, isHovered: true)
            }
        case "cycle":
            cyclePreview(step: 0)
        case "inbox", "inbox-floating":
            inbox?.open()
        case "inbox-list":
            dock?.unfold()
        case "inbox-cycle":
            inbox?.open()
            answerPreviewSessions()
        default:
            break
        }
    }

    /// Answers whatever session is selected every couple of seconds, for recording the inbox
    /// flow from the first session to inbox zero.
    private func answerPreviewSessions() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, let inbox = self.inbox, let item = inbox.selectedItem else { return }
            if item.request.isPermission {
                inbox.allow(item)
            } else {
                inbox.reply("Sounds good, go ahead.", to: item)
            }
            self.answerPreviewSessions()
        }
    }

    /// Steps through every presentation on its own, for recording the transitions.
    private func cyclePreview(step: Int) {
        switch step % 4 {
        case 0: dock?.islandHoverChanged(true)
        case 1: dock?.unfold()
        case 2: dock?.fold()
        default: dock?.islandHoverChanged(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.cyclePreview(step: step + 1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cloudView?.shutdown()
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

    /// A waiting session opens the inbox, which takes typing without activating the app, an
    /// answer reaches the waiting hook, and the inbox moves on and lets go of the keyboard.
    private func smokeTestInbox(inbox: InboxStore, panel: FloatingPanel, directory: URL?) -> Bool {
        guard let directory,
              let process = ProcessInspector.stamp(pid: getpid()),
              let root = try? InboxFiles.directory(stateDirectory: directory)
        else { return false }
        dock?.detach()
        panel.orderFrontRegardless()
        inbox.setEnabled(true)
        let item = InboxItem(
            sessionKey: "smoke-session",
            externalSessionID: "smoke-session",
            agent: .claude,
            projectLabel: "codewindow",
            request: .reply,
            message: "Ship it?",
            task: "smoke",
            process: process
        )
        guard (try? InboxFiles.add(item, in: root)) != nil else { return false }
        inbox.refresh()
        let listed = inbox.waiting.map(\.id) == [item.id]

        inbox.open()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let opened = inbox.isOpen && inbox.selectedItemID == item.id
            && panel.allowsKeyFocus && panel.isKeyWindow
            && panel.frame.width == TopDockPlacementPolicy.inboxSize.width

        inbox.reply("Yes, ship it.", to: item)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let delivered = InboxFiles.takeResponse(for: item.id, in: root) == .reply("Yes, ship it.")
        let cleared = inbox.isClear && inbox.waiting.isEmpty
        // Inbox zero shows for a moment, then the inbox folds itself and lets go of the keyboard.
        RunLoop.current.run(until: Date().addingTimeInterval(2.4))
        let released = !inbox.isOpen && !panel.allowsKeyFocus && !panel.isKeyWindow
            && panel.frame.width == PanelMetrics.width

        InboxFiles.remove(itemID: item.id, in: root)
        inbox.setEnabled(false)
        let works = listed && opened && delivered && cleared && released
        if !works {
            fputs(
                "inbox smoke failed: listed=\(listed) opened=\(opened) delivered=\(delivered) "
                    + "cleared=\(cleared) released=\(released) frame=\(panel.frame)\n",
                stderr
            )
        }
        return works
    }

    private func smokeTestTopDockInteraction(of panel: FloatingPanel) -> Bool {
        guard let dock, let screen = panel.screen ?? NSScreen.main else { return false }
        inspector?.dismissImmediately()
        // The live sink is attached after the smoke test, so hand the dock its sessions here.
        dock.sessionsChanged(store?.sessions ?? [])
        let settle = IslandMotion.settleDelay + 0.12
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let originalTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let notch = TopDockPlacementPolicy.notch(
            screenFrame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        let compact = TopDockPlacementPolicy.islandFrame(
            size: TopDockPlacementPolicy.islandSize(
                for: .compact,
                notch: notch,
                expandedContentWidth: 0,
                listSize: .zero
            ),
            notch: notch,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            margin: PanelMetrics.screenMargin
        )
        func isAnchored(_ frame: NSRect) -> Bool {
            abs(frame.maxY - compact.maxY) < 1 && abs(frame.midX - compact.midX) < 1
        }
        func isCompact(_ frame: NSRect) -> Bool {
            isAnchored(frame)
                && abs(frame.width - compact.width) < 1
                && abs(frame.height - compact.height) < 1
        }

        dock.panelDragDidBegin()
        panel.setFrameOrigin(NSPoint(
            x: compact.midX - panel.frame.width / 2,
            y: compact.maxY - panel.frame.height
        ))
        dock.panelDragDidEnd(moved: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        let topAttachedWorks = isAnchored(panel.frame)
        print(
            "topDockScreen=\(notch == nil ? "notchless" : "notched") "
                + "topAttached=\(topAttachedWorks)"
        )
        // Under a housing the resting island is exactly as tall as the camera band.
        let foldedWorks = dock.model.isDocked
            && dock.model.presentation == .compact
            && panel.isTopDocked
            && panel.level == .statusBar
            && !panel.hasShadow
            && isCompact(panel.frame)

        // Docking re-evaluates auto-hide, and a smoke run launched from a terminal owns its
        // own fixture sessions. Keep the panel on screen so the springs really run.
        panel.orderFrontRegardless()
        dock.islandHoverChanged(true)
        RunLoop.current.run(
            until: Date().addingTimeInterval(TopDockController.peekDelay + settle)
        )
        let peekWorks = dock.model.presentation == .expanded
            && isAnchored(panel.frame)
            && abs(
                panel.frame.height - (compact.height + TopDockPlacementPolicy.expandedBodyHeight)
            ) < 1
        dock.islandHoverChanged(false)
        RunLoop.current.run(
            until: Date().addingTimeInterval(TopDockController.peekReleaseDelay + settle)
        )
        let unpeekWorks = dock.model.presentation == .compact && isCompact(panel.frame)

        panel.orderFrontRegardless()
        dock.unfold()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        // Mid-spring the window holds a stage covering both sizes, anchored like the island.
        let stagedWorks = reduceMotion
            || (isAnchored(panel.frame) && panel.frame.height > compact.height && !panel.hasShadow)
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        let unfoldedWorks = dock.model.isUnfolded
            && panel.hasShadow
            && panel.frame.width == PanelMetrics.width
            && panel.frame.height > compact.height
            && isAnchored(panel.frame)

        dock.fold()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        let refoldedWorks = !dock.model.isUnfolded && isCompact(panel.frame) && !panel.hasShadow

        let dockedFrame = panel.frame
        dock.panelDragDidBegin()
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + TopDockPlacementPolicy.detachDistance / 2,
            y: panel.frame.minY
        ))
        dock.panelDragDidEnd(moved: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let resistedPullWorks = dock.model.isDocked
            && panel.isTopDocked
            && abs(panel.frame.minX - dockedFrame.minX) < 1
            && abs(panel.frame.minY - dockedFrame.minY) < 1

        dock.detach()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let restoredWorks = !dock.model.isDocked
            && !panel.isTopDocked
            && panel.level == .floating
            && panel.hasShadow
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

        let works = foldedWorks
            && peekWorks
            && unpeekWorks
            && stagedWorks
            && unfoldedWorks
            && refoldedWorks
            && resistedPullWorks
            && restoredWorks
            && pullToDetachWorks
        if !works {
            fputs(
                "top dock smoke failed: folded=\(foldedWorks) peek=\(peekWorks) "
                    + "unpeek=\(unpeekWorks) staged=\(stagedWorks) unfolded=\(unfoldedWorks) "
                    + "refolded=\(refoldedWorks) resistedPull=\(resistedPullWorks) "
                    + "restored=\(restoredWorks) pullToDetach=\(pullToDetachWorks) "
                    + "topAttached=\(topAttachedWorks) frame=\(panel.frame) compact=\(compact)\n",
                stderr
            )
        }
        return works
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        isManuallyHidden = false
        updatePanelVisibility()
        return true
    }

    private func makePanel(
        store: SessionStore,
        dockDefaults: UserDefaults,
        cloudView: CloudViewController,
        inbox: InboxStore
    ) -> FloatingPanel {
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
        // An open inspector or inbox, or the moment of reaching inbox zero, holds an
        // unfolded island open even with the pointer elsewhere.
        dock.isInspectorActive = { [weak inspector, weak inbox] in
            (inspector?.isPresenting ?? false) || inbox?.isOpen == true || inbox?.isClear == true
        }
        dock.hasWaiting = { [weak inbox] in
            guard let inbox, inbox.isEnabled else { return false }
            return !inbox.waiting.isEmpty
        }
        dock.isInboxHeld = { [weak inbox] in inbox?.holdsOpen ?? false }
        dock.requestInboxOpen = { [weak inbox] in inbox?.open() }
        dock.requestInboxClose = { [weak inbox] in inbox?.close() }
        dock.didChangeDockState = { [weak self] in self?.dockStateDidChange() }

        let content = PanelContentView(
            store: store,
            updateReminder: updateReminder,
            dock: dock.model,
            cloudView: cloudView,
            inbox: inbox,
            reportFullContentSize: { [weak dock] size in
                dock?.fullContentSizeChanged(to: size)
            },
            reportExpandedContentWidth: { [weak dock] width in
                dock?.expandedContentWidthChanged(to: width)
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
                // The UI smoke test and the design preview must not install or grant trust in
                // the real user's profiles.
                if CommandLine.arguments.contains("--smoke-test")
                    || CommandLine.arguments.contains("--ui-preview")
                {
                    return true
                }
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
            revealPanel: { [weak dock] in
                dock?.unfold()
            },
            foldPanel: { [weak dock, weak inbox] in
                // Escape closes whatever is grown furthest: the inbox, then the list.
                if inbox?.isOpen == true { inbox?.close() } else { dock?.fold() }
            },
            islandHoverChanged: { [weak dock] isHovered in
                dock?.islandHoverChanged(isHovered)
            }
        )
        let hostingView = NSHostingView(rootView: content)
        // The controller sizes the window from measured content; the hosting view must not
        // impose size constraints of its own on the window or on its container.
        hostingView.sizingOptions = []
        panel.installContent(hostingView)
        position(panel: panel)
        // A panel left docked at quit must open as the island, even before any measurement
        // or session update arrives to trigger a layout.
        if dock.isDocked { dock.layout() }
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

    /// Folding hides the rows the inspector hangs off, and any change of dock state moves the
    /// panel, so both the inspector and the auto-hide rule have to be re-evaluated.
    private func dockStateDidChange() {
        inspector?.dismissImmediately()
        updatePanelVisibility()
    }

    @objc private func screenParametersDidChange() {
        // A resolution or display change moves the notch: recentre rather than drift.
        dock?.screenParametersDidChange()
        inspector?.relayout()
    }

    @objc private func applicationDidWake() {
        cloudView?.applicationDidWake()
    }

    @objc private func frontmostApplicationDidChange() {
        updatePanelVisibility()
    }

    /// The island expands for a session that starts waiting on the user; VoiceOver users get
    /// the same news spoken, whether the panel is docked, floating, or auto-hidden.
    private func announceNewAttention(in sessions: [PresentedSession]) {
        let waiting = sessions.filter(\.needsAttention)
        let ids = Set(waiting.map(\.id))
        defer { announcedAttentionIDs = ids }
        guard let previous = announcedAttentionIDs,
              let session = waiting.first(where: { !previous.contains($0.id) })
        else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(session.agent.displayName) needs attention in \(session.projectLabel): "
                    + session.primaryLabel,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func hidePanelManually() {
        isManuallyHidden = true
        inspector?.dismissImmediately()
        panel?.orderOut(nil)
    }

    private func updatePanelVisibility() {
        guard let panel, let store else { return }
        let shouldHide = Self.shouldHidePanel(
            isManuallyHidden: isManuallyHidden,
            frontmostApplicationOwnsSession: !isPreview
                && frontmostApplicationOwnsSession(store.sessions),
            inboxNeedsUser: inboxNeedsUser
        )
        if shouldHide {
            inspector?.dismissImmediately()
            if panel.isVisible {
                panel.orderOut(nil)
            }
        } else if !shouldHide, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// The panel steps aside while the user looks at a terminal running a session, like
    /// picture-in-picture. Inbox mode is the exception: its job is to say that another agent is
    /// waiting while the user is busy in a terminal, so it stays up whenever someone is waiting.
    nonisolated private static func shouldHidePanel(
        isManuallyHidden: Bool,
        frontmostApplicationOwnsSession: Bool,
        inboxNeedsUser: Bool = false
    ) -> Bool {
        isManuallyHidden || (frontmostApplicationOwnsSession && !inboxNeedsUser)
    }

    private var inboxNeedsUser: Bool {
        guard let inbox, inbox.isEnabled else { return false }
        return !inbox.waiting.isEmpty || inbox.isOpen
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

    /// ⌃⌥I: bring the inbox up wherever the user is, on the session that has waited longest,
    /// or close it again. Pressing it is a clear request for the inbox, so it also turns the
    /// mode on; with nobody waiting it opens on inbox zero.
    private func answerNextWaiting() {
        guard let inbox else { return }
        if inbox.isOpen {
            inbox.close()
            return
        }
        if !inbox.isEnabled { inbox.setEnabled(true) }
        isManuallyHidden = false
        inbox.open()
    }

    /// The open inbox is where the user types: the panel takes key focus without activating the
    /// app, stays on screen even over the terminal, and the island grows around it.
    private func inboxDidChange(isOpen: Bool) {
        guard let panel else { return }
        panel.allowsKeyFocus = isOpen
        if isOpen {
            inspector?.dismissImmediately()
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        dock?.inboxDidChange(isOpen: isOpen)
        if isOpen {
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
        updatePanelVisibility()
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
        return PanelNotice(message: "agents connected", succeeded: true)
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
