import Foundation

/// Pure derivation of the short status strings shown in the Settings / Status
/// panels (and folded into menu-bar copy via `MenuBarAnnouncement`).
///
/// Extracted from `AppState` so the wording — especially the multi-branch
/// `diagnosticsSummary` health ladder — is `Sendable` and unit-tested. Each
/// function takes only the values it needs; callers in the app layer pass their
/// already-derived state.
public enum StatusPanelText {

    /// Data-mode label: `"Demo"`, `"Sandbox"`, `"Production"`, or `"Unknown"`.
    public static func mode(isDemoMode: Bool, environment: PlaidEnvironment?) -> String {
        if isDemoMode { return "Demo" }
        switch environment {
        case .sandbox: return "Sandbox"
        case .production: return "Production"
        case nil: return "Unknown"
        }
    }

    /// Whether the server has Plaid credentials: `"Not required"` (demo),
    /// `"Unknown"` (server unreachable), `"Ready"`, or `"Missing"`. A `nil`
    /// `credentialsConfigured` (status not yet known) folds to `"Missing"`.
    public static func serverCredentials(
        isDemoMode: Bool,
        serverConnected: Bool,
        credentialsConfigured: Bool?
    ) -> String {
        if isDemoMode { return "Not required" }
        guard serverConnected else { return "Unknown" }
        return credentialsConfigured == true ? "Ready" : "Missing"
    }

    /// Whether the server can sync: `"Demo data"`, `"Unknown"` (unreachable),
    /// `"Ready"`, or `"No items"`. A `nil` `syncReady` (status not yet known)
    /// folds to `"No items"`.
    public static func serverSyncReadiness(
        isDemoMode: Bool,
        serverConnected: Bool,
        syncReady: Bool?
    ) -> String {
        if isDemoMode { return "Demo data" }
        guard serverConnected else { return "Unknown" }
        return syncReady == true ? "Ready" : "No items"
    }

    /// Background-refresh cadence rendered in whole minutes, e.g. `"15 min"`.
    public static func refreshCadence(interval: TimeInterval) -> String {
        "\(Int(interval / 60)) min"
    }

    /// One-line Plaid health summary. The branch order is significant: a recovery
    /// demo scenario and blocking server issues win over per-item attention, which
    /// in turn wins over the healthy fallback.
    public static func diagnosticsSummary(
        isDemoStatusRecoveryScenario: Bool,
        isDemoMode: Bool,
        serverConnection: ServerConnectionPresentation,
        statusItemCount: Int,
        erroredItemCount: Int,
        needsLoginItemCount: Int
    ) -> String {
        if isDemoStatusRecoveryScenario {
            if erroredItemCount > 0 { return "\(erroredItemCount) demo item\(plural(erroredItemCount)) need attention" }
            if needsLoginItemCount > 0 { return "\(needsLoginItemCount) demo item\(plural(needsLoginItemCount)) need update" }
        }
        if isDemoMode { return serverConnection.diagnosticsSummary }
        switch serverConnection.issue {
        case .offline, .localAuthMissing, .localAuthRejected, .serverModeMismatch:
            return serverConnection.diagnosticsSummary
        case .demo, .syncing, .connected, .error:
            break
        }
        if statusItemCount == 0 { return "No Plaid items connected" }
        if erroredItemCount > 0 { return "\(erroredItemCount) item\(plural(erroredItemCount)) need attention" }
        if needsLoginItemCount > 0 { return "\(needsLoginItemCount) item\(plural(needsLoginItemCount)) need update" }
        if serverConnection.issue == .error { return serverConnection.diagnosticsSummary }
        return "Plaid connection healthy"
    }

    /// `""` for a count of 1, `"s"` otherwise.
    private static func plural(_ count: Int) -> String {
        count == 1 ? "" : "s"
    }
}
