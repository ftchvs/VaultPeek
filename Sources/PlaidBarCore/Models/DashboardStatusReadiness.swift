import Foundation

public enum DashboardStatusReadinessLevel: String, Codable, Sendable {
    case healthy
    case loading
    case warning
    case blocked
}

public enum DashboardStatusReadinessAction: String, Codable, Sendable {
    case checkServer
    case addAccount
    case refresh
    case reconnect
    case openSettings
    case requestNotificationPermission
    case openNotificationSettings
}

public struct DashboardStatusReadiness: Equatable, Sendable {
    private static let maxRenderedErrorLength = 240

    public let level: DashboardStatusReadinessLevel
    public let title: String
    public let detail: String
    public let primaryAction: DashboardStatusReadinessAction?
    public let primaryActionTitle: String?
    public let primaryActionIconName: String?
    public let secondaryActions: [DashboardStatusReadinessAction]

    public init(
        level: DashboardStatusReadinessLevel,
        title: String,
        detail: String,
        primaryAction: DashboardStatusReadinessAction? = nil,
        primaryActionTitle: String? = nil,
        primaryActionIconName: String? = nil,
        secondaryActions: [DashboardStatusReadinessAction] = []
    ) {
        self.level = level
        self.title = title
        self.detail = detail
        self.primaryAction = primaryAction
        self.primaryActionTitle = primaryActionTitle ?? primaryAction?.defaultTitle
        self.primaryActionIconName = primaryActionIconName ?? primaryAction?.defaultIconName
        self.secondaryActions = secondaryActions
    }

    public static func evaluate(
        isDemoMode: Bool,
        isInitialLoad: Bool = false,
        serverConnected: Bool,
        credentialsConfigured: Bool?,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        needsLoginItemCount: Int,
        erroredItemCount: Int,
        isSyncStale: Bool,
        lastSyncRelative: String?,
        errorMessage: String?,
        notificationsEnabled: Bool = false,
        notificationPermission: NotificationPermissionPresentation? = nil
    ) -> DashboardStatusReadiness {
        if isDemoMode {
            return DashboardStatusReadiness(
                level: .healthy,
                title: "Demo data ready",
                detail: "Local demo accounts are loaded. Connect a real institution when you are ready.",
                primaryAction: .addAccount,
                primaryActionTitle: "Connect Bank",
                secondaryActions: [.openSettings]
            )
        }

        // The boot handshake outranks offline/stale verdicts: warning and
        // blocked tints are reserved for states the user can act on, not for
        // an in-flight first load.
        if isInitialLoad {
            return DashboardStatusReadiness(
                level: .loading,
                title: "Loading financial data",
                detail: "Connecting to the local VaultPeek server and fetching the latest balances and transactions."
            )
        }

        if let authError = localServerAuthError(from: errorMessage) {
            return DashboardStatusReadiness(
                level: .blocked,
                title: authError.title,
                detail: authError.detail,
                primaryAction: .openSettings
            )
        }

        if !serverConnected {
            return DashboardStatusReadiness(
                level: .blocked,
                title: "Server offline",
                detail: "Start the VaultPeek companion server, then check the connection from this dashboard.",
                primaryAction: .checkServer
            )
        }

        if credentialsConfigured == false {
            return DashboardStatusReadiness(
                level: .blocked,
                title: "Plaid credentials missing",
                detail: "The server is reachable, but Plaid credentials are not configured.",
                primaryAction: .openSettings
            )
        }

        if erroredItemCount > 0 {
            return DashboardStatusReadiness(
                level: .blocked,
                title: itemRecoveryTitle(
                    count: erroredItemCount,
                    singularAction: "needs attention",
                    pluralAction: "need attention"
                ),
                detail: "A linked institution reported an error. Reconnect it, then refresh the dashboard.",
                primaryAction: .reconnect
            )
        }

        if needsLoginItemCount > 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: itemRecoveryTitle(
                    count: needsLoginItemCount,
                    singularAction: "needs login",
                    pluralAction: "need login"
                ),
                detail: "One or more institutions need an updated login before sync can stay healthy.",
                primaryAction: .reconnect
            )
        }

        if let modeMismatch = serverModeMismatchError(from: errorMessage) {
            return DashboardStatusReadiness(
                level: .blocked,
                title: modeMismatch.title,
                detail: modeMismatch.detail,
                primaryAction: .checkServer
            )
        }

        if let errorMessage = userFacingErrorDetail(from: errorMessage) {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Recent action failed",
                detail: errorMessage,
                primaryAction: .refresh
            )
        }

        if linkedItemCount == 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "No institution linked",
                detail: "Connect a Plaid institution before this dashboard can show balances and transactions.",
                primaryAction: .addAccount,
                primaryActionTitle: "Connect Bank"
            )
        }

        if accountCount == 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Balances not loaded",
                detail: "The server has linked items, but account balances have not loaded into the dashboard yet.",
                primaryAction: .refresh,
                primaryActionTitle: "Load Balances"
            )
        }

        if syncedItemCount == 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "First sync needed",
                detail: "Accounts are loaded, but no linked item has completed transaction sync yet. Refresh to run the first sync.",
                primaryAction: .refresh,
                primaryActionTitle: "Run First Sync"
            )
        }

        if syncedItemCount < linkedItemCount {
            return DashboardStatusReadiness(
                level: .warning,
                title: "First sync incomplete",
                detail: "\(syncedItemCount) of \(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") have completed transaction sync. Refresh to finish the remaining item\(linkedItemCount - syncedItemCount == 1 ? "" : "s").",
                primaryAction: .refresh,
                primaryActionTitle: "Finish Sync"
            )
        }

        if isSyncStale {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Sync is stale",
                detail: "Last sync: \(lastSyncRelative ?? "never"). Refresh now to pull current balances and transactions.",
                primaryAction: .refresh,
                primaryActionTitle: "Refresh Now"
            )
        }

        if let notificationRecovery = notificationPermissionRecovery(
            notificationsEnabled: notificationsEnabled,
            permission: notificationPermission
        ) {
            return notificationRecovery
        }

        return DashboardStatusReadiness(
            level: .healthy,
            title: "Plaid sync healthy",
            detail: "\(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") connected. Last sync: \(lastSyncRelative ?? "just now").",
            primaryAction: .refresh,
            primaryActionTitle: "Refresh Data",
            secondaryActions: [.addAccount]
        )
    }

    private static func localServerAuthError(from message: String?) -> (title: String, detail: String)? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()

        if normalized.contains("auth token is unavailable") {
            return (
                "Local server auth missing",
                "VaultPeek cannot read the local app-server auth token. Restart the VaultPeek companion server, then check the connection again."
            )
        }

        if normalized.contains("plaidbar server returned 401") ||
            normalized.contains("plaidbar server returned 403") ||
            normalized.contains("vaultpeek companion server returned 401") ||
            normalized.contains("vaultpeek companion server returned 403") {
            return (
                "Local server auth rejected",
                "VaultPeek reached the local server, but the app-server auth token was rejected. Restart the VaultPeek companion server so the local token is regenerated."
            )
        }

        return nil
    }

    private static func userFacingErrorDetail(from message: String?) -> String? {
        UserFacingError.sanitizedDetail(from: message, maxLength: maxRenderedErrorLength)
    }

    private static func serverModeMismatchError(from message: String?) -> (title: String, detail: String)? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let lowercased = normalized.lowercased()

        guard lowercased.contains("server is running in"),
              lowercased.contains("not sandbox") || lowercased.contains("not production")
        else {
            return nil
        }

        return (
            "Server mode mismatch",
            UserFacingError.sanitizedDetail(from: normalized, maxLength: maxRenderedErrorLength) ?? normalized
        )
    }

    private static func itemRecoveryTitle(
        count: Int,
        singularAction: String,
        pluralAction: String
    ) -> String {
        "\(count) item\(count == 1 ? "" : "s") \(count == 1 ? singularAction : pluralAction)"
    }

    private static func notificationPermissionRecovery(
        notificationsEnabled: Bool,
        permission: NotificationPermissionPresentation?
    ) -> DashboardStatusReadiness? {
        guard notificationsEnabled,
              let permission,
              permission.shouldDisableNotifications
        else { return nil }

        switch permission.recoveryAction {
        case .requestPermission:
            return DashboardStatusReadiness(
                level: .warning,
                title: "Notification permission not requested",
                detail: "Local alerts are enabled, but macOS permission has not been requested yet.",
                primaryAction: .requestNotificationPermission,
                primaryActionTitle: permission.recoveryActionTitle,
                primaryActionIconName: permission.recoveryActionIconName,
                secondaryActions: [.openSettings]
            )
        case .openSystemSettings:
            return DashboardStatusReadiness(
                level: .warning,
                title: "Notifications blocked",
                detail: "Local alerts are enabled, but macOS is blocking VaultPeek notifications. Enable VaultPeek in System Settings to recover alerts.",
                primaryAction: .openNotificationSettings,
                primaryActionTitle: permission.recoveryActionTitle,
                primaryActionIconName: permission.recoveryActionIconName,
                secondaryActions: [.openSettings]
            )
        case .checkAgain:
            return DashboardStatusReadiness(
                level: .warning,
                title: "Notification permission unknown",
                detail: permission.detail,
                primaryAction: .requestNotificationPermission,
                primaryActionTitle: "Check Permission",
                primaryActionIconName: "arrow.clockwise",
                secondaryActions: [.openSettings]
            )
        case .runBundledApp:
            return DashboardStatusReadiness(
                level: .warning,
                title: "Notification identity unavailable",
                detail: permission.detail,
                primaryAction: .openSettings,
                primaryActionTitle: permission.recoveryActionTitle,
                primaryActionIconName: permission.recoveryActionIconName
            )
        case nil:
            return DashboardStatusReadiness(
                level: .warning,
                title: "Notifications unavailable",
                detail: permission.detail,
                primaryAction: .openSettings
            )
        }
    }
}

public extension DashboardStatusReadinessAction {
    var defaultTitle: String {
        switch self {
        case .checkServer: "Check Server"
        case .addAccount: "Add Account"
        case .refresh: "Refresh"
        case .reconnect: "Reconnect"
        case .openSettings: "Settings"
        case .requestNotificationPermission: "Request Permission"
        case .openNotificationSettings: "Open System Settings"
        }
    }

    var defaultIconName: String {
        switch self {
        case .checkServer: "server.rack"
        case .addAccount: "plus.circle"
        case .refresh: "arrow.clockwise"
        case .reconnect: "link.badge.plus"
        case .openSettings: "gearshape"
        case .requestNotificationPermission: "bell.badge"
        case .openNotificationSettings: "gearshape"
        }
    }
}
