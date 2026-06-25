import Foundation

/// Pure decision for whether an opt-in review-sync operation may touch the network
/// (AND-552).
///
/// The app's `ReviewSyncService` is in the (untestable) `@main` app target, so the
/// security-critical "**when not opted in, send nothing**" rule lives here as a
/// pure `Sendable` predicate that the service delegates to — the same pattern as
/// ``ReviewStoragePersistencePolicy`` keeping the demo-mode persistence guard out
/// of the app target. The decision is a function of the opt-in flag alone, so it
/// is exhaustively unit-testable without a server or a running app.
public enum ReviewSyncGate {
    /// What a sync entry point is allowed to do for the current opt-in state.
    public enum Action: Sendable, Equatable {
        /// Syncing is enabled — the caller may perform the network operation.
        case proceed
        /// Syncing is disabled — the caller must do nothing and leave local state
        /// untouched. **No review data leaves the device.**
        case skip
    }

    /// The action for a read/write sync operation given whether the user has opted
    /// in. `false` ⇒ ``Action/skip`` (the default, local-first path) so a
    /// not-opted-in user never makes a request.
    public static func action(isOptedIn: Bool) -> Action {
        isOptedIn ? .proceed : .skip
    }

    /// Whether a read/write sync operation may run. Convenience over
    /// ``action(isOptedIn:)`` for a simple `guard`.
    public static func allowsNetwork(isOptedIn: Bool) -> Bool {
        action(isOptedIn: isOptedIn) == .proceed
    }
}
