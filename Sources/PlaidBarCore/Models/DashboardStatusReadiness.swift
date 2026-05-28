import Foundation

public enum DashboardStatusReadinessLevel: String, Codable, Sendable {
    case healthy
    case warning
    case blocked
}

public enum DashboardStatusReadinessAction: String, Codable, Sendable {
    case checkServer
    case addAccount
    case refresh
    case reconnect
    case openSettings
}

public struct DashboardStatusReadiness: Equatable, Sendable {
    public let level: DashboardStatusReadinessLevel
    public let title: String
    public let detail: String
    public let primaryAction: DashboardStatusReadinessAction?
    public let secondaryActions: [DashboardStatusReadinessAction]

    public init(
        level: DashboardStatusReadinessLevel,
        title: String,
        detail: String,
        primaryAction: DashboardStatusReadinessAction? = nil,
        secondaryActions: [DashboardStatusReadinessAction] = []
    ) {
        self.level = level
        self.title = title
        self.detail = detail
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        credentialsConfigured: Bool?,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        needsLoginItemCount: Int,
        erroredItemCount: Int,
        isSyncStale: Bool,
        lastSyncRelative: String?,
        errorMessage: String?
    ) -> DashboardStatusReadiness {
        if isDemoMode {
            return DashboardStatusReadiness(
                level: .healthy,
                title: "Demo data ready",
                detail: "Local demo accounts are loaded. Connect a real institution when you are ready.",
                primaryAction: .addAccount,
                secondaryActions: [.openSettings]
            )
        }

        if !serverConnected {
            return DashboardStatusReadiness(
                level: .blocked,
                title: "Server offline",
                detail: "Start PlaidBarServer, then check the connection from this dashboard.",
                primaryAction: .checkServer,
                secondaryActions: [.openSettings]
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

        if linkedItemCount == 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "No institution linked",
                detail: "Connect a Plaid institution before this dashboard can show balances and transactions.",
                primaryAction: .addAccount,
                secondaryActions: [.refresh]
            )
        }

        if accountCount == 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Balances not loaded",
                detail: "The server has linked items, but account balances have not loaded into the dashboard yet.",
                primaryAction: .refresh,
                secondaryActions: [.addAccount]
            )
        }

        if erroredItemCount > 0 {
            return DashboardStatusReadiness(
                level: .blocked,
                title: "\(erroredItemCount) item\(erroredItemCount == 1 ? "" : "s") need attention",
                detail: "A linked institution reported an error. Reconnect it, then refresh the dashboard.",
                primaryAction: .reconnect,
                secondaryActions: [.refresh, .openSettings]
            )
        }

        if needsLoginItemCount > 0 {
            return DashboardStatusReadiness(
                level: .warning,
                title: "\(needsLoginItemCount) item\(needsLoginItemCount == 1 ? "" : "s") need login",
                detail: "One or more institutions need an updated login before sync can stay healthy.",
                primaryAction: .reconnect,
                secondaryActions: [.refresh]
            )
        }

        if syncedItemCount < linkedItemCount {
            return DashboardStatusReadiness(
                level: .warning,
                title: "First sync incomplete",
                detail: "\(syncedItemCount) of \(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") have completed transaction sync.",
                primaryAction: .refresh,
                secondaryActions: [.openSettings]
            )
        }

        if isSyncStale {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Sync is stale",
                detail: "Last sync: \(lastSyncRelative ?? "never"). Refresh now to pull current balances and transactions.",
                primaryAction: .refresh,
                secondaryActions: [.openSettings]
            )
        }

        if let errorMessage, !errorMessage.isEmpty {
            return DashboardStatusReadiness(
                level: .warning,
                title: "Recent action failed",
                detail: errorMessage,
                primaryAction: .refresh,
                secondaryActions: [.openSettings]
            )
        }

        return DashboardStatusReadiness(
            level: .healthy,
            title: "Plaid sync healthy",
            detail: "\(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") connected. Last sync: \(lastSyncRelative ?? "just now").",
            primaryAction: .refresh,
            secondaryActions: [.addAccount]
        )
    }
}
