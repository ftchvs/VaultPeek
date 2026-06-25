import Foundation
import PlaidBarCore

/// Drives the **opt-in** sync of review state to the local server (AND-552 —
/// deferred epic AND-524).
///
/// ## Strictly opt-in — the off path sends nothing
///
/// Every entry point first consults the injected `isEnabled` gate (wired to
/// ``ServerSyncedReviewFeatureFlag``, default OFF). When syncing is **off** the
/// service short-circuits and never touches the `ServerClient`, so a not-opted-in
/// user's review state never leaves the device — behavior is byte-identical to
/// before AND-552. Only an explicit, consent-gated opt-in turns this on.
///
/// ## What it does when on
///
/// - `pushAndMerge(local:)` uploads the device's snapshot and returns the server's
///   merged union (per-record last-writer-wins via ``ReviewStateConflictResolver``,
///   applied server-side), so the device converges in one round-trip.
/// - `pull()` fetches the server's stored snapshot.
/// - `disableSync()` clears the server's stored state when the user opts back out,
///   so opting out also removes what was previously synced.
///
/// The service is a `Sendable` `actor` over the `ServerClient` actor; it holds no
/// UI state. Callers (AppState) own the in-memory review metadata/rules and decide
/// when to assemble a snapshot to push or how to apply a pulled one.
actor ReviewSyncService {
    private let serverClient: ServerClient
    private let isEnabled: @Sendable () -> Bool

    /// - Parameters:
    ///   - serverClient: the authenticated localhost client.
    ///   - isEnabled: the opt-in gate. Defaults to the live
    ///     ``ServerSyncedReviewFeatureFlag`` resolution (CLI override → stored
    ///     preference → OFF). Injected so tests drive both paths deterministically.
    init(
        serverClient: ServerClient,
        isEnabled: @escaping @Sendable () -> Bool = { ServerSyncedReviewFeatureFlag.resolved() }
    ) {
        self.serverClient = serverClient
        self.isEnabled = isEnabled
    }

    /// Whether server-synced review is currently enabled (the opt-in gate).
    var syncEnabled: Bool { isEnabled() }

    /// Upload `local` and return the server's merged snapshot — **only when opted
    /// in**. Returns `nil` without making any request when syncing is off, so the
    /// caller leaves its local state exactly as-is.
    func pushAndMerge(local: ReviewStateSnapshotDTO) async throws -> ReviewStateSnapshotDTO? {
        guard ReviewSyncGate.allowsNetwork(isOptedIn: isEnabled()) else { return nil }
        return try await serverClient.putReviewState(local)
    }

    /// Pull the server's stored snapshot — **only when opted in**. Returns `nil`
    /// without making any request when syncing is off.
    func pull() async throws -> ReviewStateSnapshotDTO? {
        guard ReviewSyncGate.allowsNetwork(isOptedIn: isEnabled()) else { return nil }
        return try await serverClient.getReviewState()
    }

    /// Clear the server's stored review state (opt-out / reset). Unlike the read
    /// and write paths this does **not** require the flag to be on — it is the
    /// teardown a user runs *when disabling* sync, so it must work to remove what
    /// was previously uploaded.
    func disableSync() async throws {
        try await serverClient.clearReviewState()
    }
}
