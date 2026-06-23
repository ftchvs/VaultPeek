import Foundation

public enum PlaidBarConstants {
    public static let defaultServerPort: Int = 8484
    public static let defaultServerHost: String = "127.0.0.1"
    public static let serverPortEnvironmentVariable: String = "PLAIDBAR_SERVER_PORT"

    public static var serverBaseURL: String {
        serverBaseURL(environment: ProcessInfo.processInfo.environment)
    }

    public static var serverPort: Int {
        serverPort(environment: ProcessInfo.processInfo.environment)
    }

    public static func serverBaseURL(environment: [String: String]) -> String {
        "http://\(defaultServerHost):\(serverPort(environment: environment))"
    }

    public static func serverPort(environment: [String: String]) -> Int {
        guard let rawPort = environment[serverPortEnvironmentVariable]?.trimmedNonEmpty,
              let port = Int(rawPort),
              (1...65_535).contains(port) else {
            return defaultServerPort
        }
        return port
    }

    // Refresh intervals
    public static let backgroundRefreshInterval: TimeInterval = 15 * 60  // 15 minutes
    public static let transactionSyncInterval: TimeInterval = 30 * 60    // 30 minutes
    public static let minimumBackgroundRefreshInterval: TimeInterval = 5 * 60

    public static func normalizedBackgroundRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite,
              interval >= minimumBackgroundRefreshInterval else {
            return backgroundRefreshInterval
        }
        return interval
    }

    // Display
    public static let creditUtilizationWarningThreshold: Double = 30.0
    public static let maxRecentTransactions: Int = 50

    /// Recency window (days) for large-transaction OS notifications. Without it, a
    /// fresh install's ~90-day import would fire one alert per historical large
    /// charge (the delivered-dedup set is empty on first sync). Mirrors
    /// AttentionQueue's `unusualSpendingWindowDays`.
    public static let largeTransactionNotificationWindowDays: Int = 7

    /// Page size for the virtualized large-history transaction list (AND-567).
    /// One page of rows is read at a time from the disposable per-transaction
    /// cache; the next page loads when the user scrolls near the end. Chosen large
    /// enough that a single page fills the visible list yet small enough that a
    /// multi-thousand-row history never materializes all rows at once.
    public static let transactionPageSize: Int = 50

    // Forgotten-subscription heuristic (AND-497).
    // A recurring stream is "easy to forget" when it has run for many cycles
    // (so it has slipped into the background) yet costs little each cycle (so it
    // never draws attention on a statement). Tuned for monthly-or-rarer streams.
    /// Minimum number of observed charges before a stream is old enough to have
    /// been forgotten.
    public static let forgottenSubscriptionMinimumCycles: Int = 6
    /// Maximum per-charge amount for a stream to count as "easy to forget".
    /// Larger charges are noticed, so they are never flagged as forgotten.
    public static let forgottenSubscriptionMaxAmount: Double = 20.0

    // Projected balance forecast (AND-498).
    /// Default forward horizon (days) for the projected-balance line.
    public static let projectedBalanceDefaultHorizonDays: Int = 30
    /// Minimum balance snapshots required before a forecast is shown.
    public static let projectedBalanceMinimumHistoryPoints: Int = 2
    public static let initialSyncDays: Int = 90
    public static let maxTransactionSyncPages: Int = 100
    public static let maxTransactionSyncMutationRestarts: Int = 2

    // Keychain
    public static let keychainServiceName: String = "com.ftchvs.PlaidBar"
    public static let keychainServerTokenKey: String = "server-auth-token"

    // App Info
    public static let appVersion: String = "1.0.0"
    public static let appName: String = "VaultPeek"

    // System search
    /// Core Spotlight domain used for VaultPeek account-name results. Kept in Core
    /// so the app and WidgetKit/Control Center extension clear the same index when
    /// Privacy Mask or App Lock engages.
    public static let accountSpotlightDomainIdentifier = "com.ftchvs.PlaidBar.accounts"

    // Repository
    public static let repositoryURL: String = "https://github.com/ftchvs/VaultPeek"

    /// Builds an absolute URL to a file on the default branch of the repository.
    /// Pass a repo-relative path (e.g. `"docs/privacy.md"`); leading slashes are ignored.
    public static func repositoryFileURL(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(repositoryURL)/blob/main/\(trimmed)"
    }

    // Plaid
    public static var plaidSandboxRedirectUri: String {
        "http://localhost:\(serverPort)/oauth/callback"
    }

    /// Plaid's consumer-facing privacy portal, where users review what data a
    /// connected app can access.
    public static let plaidPrivacyURL: String = "https://my.plaid.com/"

    /// Plaid's data deletion / connection-management portal, where users revoke
    /// or delete the bank connections VaultPeek created.
    public static let plaidDataDeletionURL: String = "https://my.plaid.com/"
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
