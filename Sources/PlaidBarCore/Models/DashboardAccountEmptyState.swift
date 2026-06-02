import Foundation

public enum DashboardAccountFilterKind: String, CaseIterable, Sendable {
    case all = "All"
    case cash = "Cash"
    case credit = "Credit"
    case savings = "Savings"
    case debt = "Debt"
    case status = "Status"
}

public enum DashboardAccountEmptyStateTone: String, Sendable {
    case brand
    case healthy
    case offline
    case secondary
    case warning
}

public enum DashboardAccountEmptyStateAction: String, Sendable {
    case checkServer
    case refresh
    case sync
}

public struct DashboardAccountEmptyState: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let iconName: String
    public let tone: DashboardAccountEmptyStateTone
    public let showsAddAccount: Bool
    public let action: DashboardAccountEmptyStateAction
    public let actionTitle: String
    public let actionIconName: String

    public init(
        title: String,
        detail: String,
        iconName: String,
        tone: DashboardAccountEmptyStateTone,
        showsAddAccount: Bool,
        action: DashboardAccountEmptyStateAction,
        actionTitle: String,
        actionIconName: String
    ) {
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.tone = tone
        self.showsAddAccount = showsAddAccount
        self.action = action
        self.actionTitle = actionTitle
        self.actionIconName = actionIconName
    }

    public static func evaluate(
        filter: DashboardAccountFilterKind,
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int,
        degradedItemCount: Int
    ) -> DashboardAccountEmptyState {
        if !isDemoMode, !serverConnected {
            return DashboardAccountEmptyState(
                title: "Server offline",
                detail: "Start PlaidBarServer, then check the connection again.",
                iconName: "server.rack",
                tone: .offline,
                showsAddAccount: false,
                action: .checkServer,
                actionTitle: "Check Server",
                actionIconName: "server.rack"
            )
        }

        if linkedItemCount == 0 {
            return DashboardAccountEmptyState(
                title: "No bank linked",
                detail: "Connect a Plaid institution to show balances in this menu bar dashboard.",
                iconName: "building.columns",
                tone: .brand,
                showsAddAccount: serverConnected,
                action: .refresh,
                actionTitle: "Check Status",
                actionIconName: "arrow.clockwise"
            )
        }

        if filter == .status, degradedItemCount > 0 {
            return DashboardAccountEmptyState(
                title: "\(degradedItemCount) item\(degradedItemCount == 1 ? "" : "s") \(degradedItemCount == 1 ? "needs" : "need") attention",
                detail: "A linked institution needs recovery, but no matching account rows are loaded. Reconnect or refresh from the status panel above.",
                iconName: "exclamationmark.triangle.fill",
                tone: .warning,
                showsAddAccount: false,
                action: .refresh,
                actionTitle: "Refresh",
                actionIconName: "arrow.clockwise"
            )
        }

        if accountCount == 0 {
            return DashboardAccountEmptyState(
                title: "No account data",
                detail: "The server has linked items, but balances have not loaded yet.",
                iconName: "tray",
                tone: .warning,
                showsAddAccount: false,
                action: .sync,
                actionTitle: "Sync Balances",
                actionIconName: "arrow.clockwise"
            )
        }

        if filter == .status {
            return DashboardAccountEmptyState(
                title: "No accounts need attention",
                detail: "Every linked item looks healthy. Switch filters to inspect balances.",
                iconName: "checkmark.circle.fill",
                tone: .healthy,
                showsAddAccount: false,
                action: .refresh,
                actionTitle: "Refresh",
                actionIconName: "arrow.clockwise"
            )
        }

        return DashboardAccountEmptyState(
            title: "No \(filter.rawValue.lowercased()) accounts",
            detail: "This filter has no matching linked accounts. Switch filters or add another institution.",
            iconName: "line.3.horizontal.decrease.circle",
            tone: .secondary,
            showsAddAccount: false,
            action: .refresh,
            actionTitle: "Refresh Data",
            actionIconName: "arrow.clockwise"
        )
    }
}
