import AppKit
import CodeWindowCloud
import CodeWindowCore
import Foundation

enum CloudViewPhase: Equatable {
    case disabled
    case checking
    case awaitingConsent
    case provisioning(String)
    case live
    case recovering
    case needsLogin
    case unavailable(String)
    case paused(String)
    case deleting
    case pendingDeletion(String)
    case needsRepair(String)
}

struct CloudViewStatusPresentation: Equatable {
    let title: String
    let detail: String
    let isWorking: Bool
    let isError: Bool
}

@MainActor
final class CloudViewController: ObservableObject {
    @Published private(set) var phase: CloudViewPhase
    @Published private(set) var publicURL: URL?

    private enum DefaultsKey {
        static let handle = "cloudView.handle"
        static let provisioningIntent = "cloudView.provisioningIntent"
        static let enabled = "cloudView.enabled"
        static let pendingDeletion = "cloudView.pendingDeletion"
        static let nextGeneration = "cloudView.meatproxyNextGeneration"
        static let revision = "cloudView.revision"
    }

    private let defaults: UserDefaults
    private let viewerHTML: Data?
    private var engine: CloudMirrorEngine?
    private var handle: CloudMirrorHandle?
    private var provisioningIntent: CloudProvisioningIntent?
    private var sessions: [PresentedSession] = []
    private var feeds: [String: [SessionFeedEvent]] = [:]
    private var revision: UInt64
    private var pendingSnapshot: Data?
    private var publishTask: Task<Void, Never>?
    private var isReconnecting = false
    private var retryIndex = 0
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        viewerHTML: Data? = CloudViewController.bundledViewerHTML(),
        runner: (any CoolCommandRunning)? = nil
    ) {
        self.defaults = defaults
        self.viewerHTML = viewerHTML
        let storedRevision = (defaults.object(forKey: DefaultsKey.revision) as? NSNumber)?.uint64Value ?? 0
        revision = storedRevision

        if let data = defaults.data(forKey: DefaultsKey.handle),
           let decoded = try? JSONDecoder().decode(CloudMirrorHandle.self, from: data)
        {
            handle = decoded
            publicURL = decoded.publicURL
        } else {
            handle = nil
            publicURL = nil
        }

        if let data = defaults.data(forKey: DefaultsKey.provisioningIntent),
           let decoded = try? JSONDecoder().decode(CloudProvisioningIntent.self, from: data)
        {
            provisioningIntent = decoded
        } else {
            provisioningIntent = nil
        }

        if let resolvedRunner = runner ?? CoolCLIClient.discovered(), let viewerHTML {
            engine = CloudMirrorEngine(runner: resolvedRunner, viewerHTML: viewerHTML)
        } else {
            engine = nil
        }

        // A saved view is deliberately dormant after every app launch. Reconnecting
        // can contact Cool and must start only from an explicit context-menu action.
        phase = .disabled
    }

    deinit {
        debounceTask?.cancel()
        retryTask?.cancel()
        heartbeatTask?.cancel()
        publishTask?.cancel()
    }

    var isConfigured: Bool { handle != nil || provisioningIntent != nil }

    var hasPendingDeletion: Bool {
        defaults.bool(forKey: DefaultsKey.pendingDeletion) && isConfigured
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .provisioning, .recovering, .deleting: true
        default: false
        }
    }

    var canOpen: Bool { publicURL != nil && phase == .live }

    var canForgetSavedView: Bool {
        if case .needsRepair = phase { return true }
        return false
    }

    var setupTitle: String {
        switch phase {
        case .disabled where hasPendingDeletion: "Finish Turning Off Cloud View…"
        case .disabled where isConfigured: "Connect Cloud View…"
        case .checking: "Checking Cloud View…"
        case .provisioning: "Creating Cloud View…"
        case .recovering: "Reconnecting Cloud View…"
        case .needsLogin: "Cloud View Needs Cool Login"
        case .pendingDeletion: "Finish Turning Off Cloud View…"
        case .live: "Open Cloud View"
        default: isConfigured ? "Retry Cloud View" : "Set Up Cloud View…"
        }
    }

    var statusPresentation: CloudViewStatusPresentation? {
        switch phase {
        case .checking:
            CloudViewStatusPresentation(
                title: "Checking Cloud View",
                detail: "Verifying the Cool CLI and login",
                isWorking: true,
                isError: false
            )
        case let .provisioning(step):
            CloudViewStatusPresentation(
                title: "Creating Cloud View",
                detail: step,
                isWorking: true,
                isError: false
            )
        case .recovering:
            CloudViewStatusPresentation(
                title: "Reconnecting Cloud View",
                detail: "Verifying the saved computer",
                isWorking: true,
                isError: false
            )
        case .needsLogin:
            CloudViewStatusPresentation(
                title: "Cloud View paused",
                detail: "Run cool login in Terminal, then retry",
                isWorking: false,
                isError: true
            )
        case let .unavailable(message), let .paused(message), let .needsRepair(message):
            CloudViewStatusPresentation(
                title: "Cloud View paused",
                detail: message,
                isWorking: false,
                isError: true
            )
        case let .pendingDeletion(message):
            CloudViewStatusPresentation(
                title: "Cloud View sync is off",
                detail: message,
                isWorking: false,
                isError: true
            )
        case .deleting:
            CloudViewStatusPresentation(
                title: "Turning off Cloud View",
                detail: "Deleting its Cool Computer",
                isWorking: true,
                isError: false
            )
        case .disabled, .awaitingConsent, .live:
            nil
        }
    }

    func applicationDidWake() {
        guard phase == .live else { return }
        enqueueSnapshot()
    }

    func shutdown() {
        stopBackgroundWork()
        publishTask?.cancel()
        engine?.cancelAllCommands()
    }

    func update(
        sessions: [PresentedSession],
        feeds: [String: [SessionFeedEvent]]
    ) {
        self.sessions = sessions
        self.feeds = feeds
        guard phase == .live else { return }
        scheduleSnapshot(after: 0.35)
    }

    /// Returns true when the caller should present the one-time privacy disclosure.
    func prepareSetup() async -> Bool {
        guard !isBusy else { return false }
        if phase == .live {
            open()
            return false
        }
        if defaults.bool(forKey: DefaultsKey.pendingDeletion) {
            await turnOff()
            return false
        }
        if handle != nil || provisioningIntent != nil {
            await reconnect()
            return false
        }

        phase = .checking
        do {
            guard let engine = resolveEngine() else { throw CoolCLIError.missing }
            _ = try await engine.preflight()
            phase = .awaitingConsent
            return true
        } catch {
            apply(error)
            return false
        }
    }

    func cancelConsent() {
        if phase == .awaitingConsent { phase = .disabled }
    }

    func createCloudView() async {
        guard phase == .awaitingConsent else { return }
        do {
            guard let engine = resolveEngine() else { throw CoolCLIError.missing }
            phase = .provisioning("Checking the next public address")
            _ = try await engine.preflight()

            let localMinimum = max(1, defaults.integer(forKey: DefaultsKey.nextGeneration))
            let generation = try await engine.nextGeneration(localMinimum: localMinimum)
            // Reserve before creation: a failed attempt still advances the human generation.
            defaults.set(generation + 1, forKey: DefaultsKey.nextGeneration)

            let intent = CloudProvisioningIntent(
                generation: generation,
                ownershipMarker: CloudIdentifier.random256BitHex(),
                remoteIDSeed: CloudIdentifier.random256BitHex()
            )
            provisioningIntent = intent
            defaults.set(true, forKey: DefaultsKey.enabled)
            persist(intent)

            phase = .provisioning("Creating \(intent.slug).cool.computer")
            let created = try await engine.createHandle(intent: intent)
            handle = created
            persist(created)
            try await finishProvisioning(created, using: engine, opensWhenReady: true)
        } catch {
            if error is CancellationError { return }
            if let created = handle, !created.ownershipEstablished {
                await rollbackAfterProvisioningFailure(created, originalError: error)
            } else {
                apply(error)
            }
        }
    }

    func retry() async {
        if defaults.bool(forKey: DefaultsKey.pendingDeletion) {
            await turnOff()
        } else if handle != nil {
            await reconnect()
        } else {
            _ = await prepareSetup()
        }
    }

    func open() {
        guard let publicURL else { return }
        NSWorkspace.shared.open(publicURL)
    }

    func copyLink() {
        guard let value = publicURL?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func forgetSavedView() {
        guard canForgetSavedView else { return }
        clearHandle()
    }

    func turnOff() async {
        guard phase != .deleting else { return }
        stopBackgroundWork()
        defaults.set(false, forKey: DefaultsKey.enabled)
        defaults.set(true, forKey: DefaultsKey.pendingDeletion)
        phase = .deleting
        // Let the one write already handed to Cool finish before verification and
        // deletion. No later snapshot can start once the phase leaves `live`.
        await finishActivePublish()
        do {
            guard let engine = resolveEngine() else { throw CoolCLIError.missing }
            _ = try await engine.preflight()
            let deletionHandle: CloudMirrorHandle
            if let handle {
                deletionHandle = handle
            } else if let intent = provisioningIntent {
                // Resolve an uncertain create before clearing its receipt. If no remote
                // result exists, creating and immediately deleting the reserved slug
                // guarantees a delayed create cannot become a silent orphan.
                deletionHandle = try await resolveProvisioning(intent, using: engine)
                self.handle = deletionHandle
                persist(deletionHandle)
            } else {
                clearHandle()
                return
            }
            try await engine.deleteVerified(deletionHandle)
            clearHandle()
        } catch {
            if error is CancellationError { return }
            if isAuthenticationError(error) {
                phase = .pendingDeletion("Run cool login to finish deleting the Cloud View computer.")
            } else if error is CloudMirrorError {
                phase = .needsRepair(errorMessage(error))
            } else {
                phase = .pendingDeletion("Remote cleanup failed. Retry when Cool is available.")
            }
        }
    }

    private func reconnect() async {
        guard !isReconnecting, handle != nil || provisioningIntent != nil else { return }
        isReconnecting = true
        defer { isReconnecting = false }
        stopBackgroundWork()
        phase = .recovering
        do {
            guard let engine = resolveEngine() else { throw CoolCLIError.missing }
            _ = try await engine.preflight()
            let resumed: CloudMirrorHandle
            if let handle {
                if handle.ownershipEstablished {
                    resumed = try await engine.resume(handle)
                } else {
                    try await finishProvisioning(handle, using: engine, opensWhenReady: false)
                    return
                }
            } else if let intent = provisioningIntent {
                phase = .provisioning("Recovering \(intent.slug).cool.computer")
                let recovered = try await resolveProvisioning(intent, using: engine)
                handle = recovered
                persist(recovered)
                try await finishProvisioning(recovered, using: engine, opensWhenReady: false)
                return
            } else {
                return
            }
            self.handle = resumed
            publicURL = resumed.publicURL
            persist(resumed)
            defaults.set(true, forKey: DefaultsKey.enabled)
            defaults.set(false, forKey: DefaultsKey.pendingDeletion)
            phase = .live
            startHeartbeat()
            enqueueSnapshot()
        } catch {
            if error is CancellationError { return }
            if isRetryable(error) {
                stopBackgroundWork()
                phase = .paused(errorMessage(error))
                scheduleRetry()
            } else {
                apply(error)
            }
        }
    }

    private func scheduleSnapshot(after delay: TimeInterval) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.enqueueSnapshot()
        }
    }

    private func enqueueSnapshot() {
        guard phase == .live, let handle else { return }
        do {
            pendingSnapshot = try makeSnapshot(for: handle)
            if publishTask == nil {
                publishTask = Task { [weak self] in
                    await self?.drainSnapshots()
                    self?.publishTask = nil
                }
            }
        } catch {
            phase = .paused(errorMessage(error))
        }
    }

    private func drainSnapshots() async {
        while phase == .live, let data = pendingSnapshot, let handle {
            pendingSnapshot = nil
            do {
                guard let engine = resolveEngine() else { throw CoolCLIError.missing }
                try await engine.publish(data, to: handle)
                retryIndex = 0
            } catch {
                if error is CancellationError { return }
                guard phase == .live else { return }
                pendingSnapshot = data
                if isAuthenticationError(error) {
                    apply(error)
                } else if isRetryable(error) {
                    phase = .paused(errorMessage(error))
                    scheduleRetry()
                } else {
                    apply(error)
                }
                return
            }
        }
    }

    private func finishActivePublish() async {
        let active = publishTask
        await active?.value
        publishTask = nil
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delays: [TimeInterval] = [2, 10, 30, 60]
        let delay = delays[min(retryIndex, delays.count - 1)]
        retryIndex = min(retryIndex + 1, delays.count - 1)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            // `reconnect()` cancels any still-scheduled retry as part of resetting
            // background work. Clear this completed delay first so it cannot cancel
            // the task that is now performing the reconnect.
            self?.retryTask = nil
            await self?.reconnect()
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.enqueueSnapshot()
            }
        }
    }

    private func stopBackgroundWork() {
        debounceTask?.cancel()
        retryTask?.cancel()
        heartbeatTask?.cancel()
        debounceTask = nil
        retryTask = nil
        heartbeatTask = nil
        pendingSnapshot = nil
    }

    private func makeSnapshot(for handle: CloudMirrorHandle) throws -> Data {
        revision &+= 1
        defaults.set(NSNumber(value: revision), forKey: DefaultsKey.revision)
        let cloudSessions = sessions.map { session in
            let eventSnapshots = (feeds[session.id] ?? []).map { event in
                CloudEventSnapshot(
                    id: CloudIdentifier.derived(
                        seed: handle.remoteIDSeed,
                        localID: event.id.uuidString
                    ),
                    kind: event.kind,
                    text: event.text,
                    detail: event.detail,
                    succeeded: event.succeeded
                )
            }

            switch session {
            case let .reported(state):
                return CloudSessionSnapshot(
                    id: CloudIdentifier.derived(seed: handle.remoteIDSeed, localID: state.id),
                    agent: state.agent,
                    activity: state.activity,
                    projectLabel: state.projectLabel,
                    action: state.action,
                    taskPreview: state.taskPreview,
                    actionPreview: state.actionPreview,
                    updatedAt: state.updatedAt,
                    events: eventSnapshots
                )
            case let .detected(detected):
                return CloudSessionSnapshot(
                    id: CloudIdentifier.derived(seed: handle.remoteIDSeed, localID: session.id),
                    agent: detected.agent,
                    activity: .starting,
                    projectLabel: detected.projectLabel,
                    action: .waiting,
                    taskPreview: nil,
                    actionPreview: "hooks not reporting",
                    updatedAt: session.updatedAt,
                    events: []
                )
            }
        }
        return try CloudSnapshotEncoder.encode(
            CloudSnapshot(revision: revision, sessions: cloudSessions)
        )
    }

    private func persist(_ handle: CloudMirrorHandle) {
        guard let data = try? JSONEncoder().encode(handle) else { return }
        defaults.set(data, forKey: DefaultsKey.handle)
    }

    private func persist(_ intent: CloudProvisioningIntent) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        defaults.set(data, forKey: DefaultsKey.provisioningIntent)
    }

    private func clearHandle() {
        stopBackgroundWork()
        handle = nil
        provisioningIntent = nil
        publicURL = nil
        defaults.removeObject(forKey: DefaultsKey.handle)
        defaults.removeObject(forKey: DefaultsKey.provisioningIntent)
        defaults.set(false, forKey: DefaultsKey.enabled)
        defaults.set(false, forKey: DefaultsKey.pendingDeletion)
        phase = .disabled
    }

    private func apply(_ error: Error) {
        stopBackgroundWork()
        if isAuthenticationError(error) {
            phase = .needsLogin
        } else if case CoolCLIError.missing = error {
            phase = .unavailable(errorMessage(error))
        } else if error is CloudMirrorError {
            phase = isConfigured
                ? .needsRepair(errorMessage(error))
                : .paused(errorMessage(error))
        } else {
            phase = .paused(errorMessage(error))
        }
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        if case CoolCLIError.authenticationRequired = error { return true }
        return false
    }

    private func isRetryable(_ error: Error) -> Bool {
        switch error {
        case CoolCLIError.timedOut, CoolCLIError.commandFailed:
            true
        case CloudMirrorError.computerNotReady:
            true
        default:
            false
        }
    }

    private func resolveEngine() -> CloudMirrorEngine? {
        if let engine { return engine }
        guard let runner = CoolCLIClient.discovered(), let viewerHTML else { return nil }
        let discovered = CloudMirrorEngine(runner: runner, viewerHTML: viewerHTML)
        engine = discovered
        return discovered
    }

    private func finishProvisioning(
        _ created: CloudMirrorHandle,
        using engine: CloudMirrorEngine,
        opensWhenReady: Bool
    ) async throws {
        phase = .provisioning("Publishing the public live viewer")
        let initial = try makeSnapshot(for: created)
        let configured = try await engine.configureNew(
            handle: created,
            initialSnapshot: initial
        )
        handle = configured
        publicURL = configured.publicURL
        persist(configured)
        provisioningIntent = nil
        defaults.removeObject(forKey: DefaultsKey.provisioningIntent)
        defaults.set(true, forKey: DefaultsKey.enabled)
        defaults.set(false, forKey: DefaultsKey.pendingDeletion)
        phase = .live
        retryIndex = 0
        startHeartbeat()
        if opensWhenReady { open() }
    }

    private func resolveProvisioning(
        _ intent: CloudProvisioningIntent,
        using engine: CloudMirrorEngine
    ) async throws -> CloudMirrorHandle {
        if let recovered = try await engine.recoverProvisioning(intent) {
            return recovered
        }
        return try await engine.createHandle(intent: intent)
    }

    private func rollbackAfterProvisioningFailure(
        _ created: CloudMirrorHandle,
        originalError: Error
    ) async {
        defaults.set(true, forKey: DefaultsKey.pendingDeletion)
        if isAuthenticationError(originalError) {
            phase = .needsLogin
            return
        }
        do {
            guard let engine = resolveEngine() else { throw CoolCLIError.missing }
            _ = try await engine.preflight()
            try await engine.deleteVerified(created)
            clearHandle()
            apply(originalError)
        } catch {
            if isAuthenticationError(error) {
                phase = .pendingDeletion("Run cool login to finish deleting the Cloud View computer.")
            } else if error is CloudMirrorError {
                phase = .needsRepair(errorMessage(error))
            } else {
                phase = .pendingDeletion("Creation failed and remote cleanup must be retried.")
            }
        }
    }

    private func errorMessage(_ error: Error) -> String {
        if let error = error as? CoolCLIError { return error.userMessage }
        if let error = error as? CloudMirrorError { return error.userMessage }
        if let error = error as? CloudSnapshotEncodingError {
            switch error {
            case .summariesExceedLimit: return "The live snapshot is too large to publish safely."
            }
        }
        return "Cloud View could not complete the request."
    }

    private static func bundledViewerHTML() -> Data? {
        guard let url = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "CloudView"
        ) else { return nil }
        return try? Data(contentsOf: url)
    }
}
