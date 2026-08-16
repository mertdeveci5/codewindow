import Combine
import Sparkle

/// Bridges Sparkle's scheduled-update callbacks into a quiet, persistent panel row.
/// Sparkle calls its UI delegate on the main thread, but the Objective-C protocol
/// does not carry Swift concurrency annotations.
@MainActor
final class UpdateReminder: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published var availableVersion: String?

    private let isPanelManuallyHidden: () -> Bool

    init(isPanelManuallyHidden: @escaping () -> Bool) {
        self.isPanelManuallyHidden = isPanelManuallyHidden
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func shouldLetSparklePresent(immediateFocus: Bool) -> Bool {
        immediateFocus || isPanelManuallyHidden()
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        shouldLetSparklePresent(immediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        availableVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
