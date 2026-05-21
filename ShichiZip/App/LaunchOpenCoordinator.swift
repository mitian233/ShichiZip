import Foundation

/// Tracks launch-time and external-open state shared by `AppDelegate`.
@MainActor
final class LaunchOpenCoordinator {
    private var initialFileManagerSuppressed = false
    private var inFlightOpenCount = 0
    private var awaitingLaunchOpenDelivery = false

    /// `true` when the auto-presented initial file manager should be skipped.
    var shouldSuppressInitialFileManager: Bool {
        initialFileManagerSuppressed || inFlightOpenCount > 0 || awaitingLaunchOpenDelivery
    }

    /// `true` while an external open is in flight or its launch payload has
    /// not yet been delivered; the process must stay alive across the
    /// last-window-closed boundary in that interval.
    var shouldKeepProcessAlive: Bool {
        inFlightOpenCount > 0 || awaitingLaunchOpenDelivery
    }

    /// Record that the launch Apple Event promised a forthcoming open.
    func noteLaunchExpectsExternalOpen() {
        awaitingLaunchOpenDelivery = true
        initialFileManagerSuppressed = true
    }

    /// Suppress the initial file manager without recording an in-flight open.
    func suppressInitialFileManager() {
        initialFileManagerSuppressed = true
        awaitingLaunchOpenDelivery = false
    }

    /// Begin an external-open operation. Pair with `endExternalOpen()`.
    func beginExternalOpen() {
        initialFileManagerSuppressed = true
        awaitingLaunchOpenDelivery = false
        inFlightOpenCount += 1
    }

    func endExternalOpen() {
        inFlightOpenCount = max(0, inFlightOpenCount - 1)
    }
}
