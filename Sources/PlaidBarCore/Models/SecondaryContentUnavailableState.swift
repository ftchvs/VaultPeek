import Foundation

public enum SecondaryContentSurface: String, Sendable {
    case accounts
    case credit
    case transactions
    case spending
    case recurring
}

public enum SecondaryContentUnavailableAction: String, Sendable {
    case checkServer
    case addAccount
    case refreshAccounts
    case syncTransactions
    case refresh
    case clearFilters
    case showWiderPeriod
}

public struct SecondaryContentUnavailableState: Equatable, Sendable {
    private static let maxRenderedErrorLength = 240

    public let title: String
    public let detail: String
    public let iconName: String
    public let action: SecondaryContentUnavailableAction
    public let actionTitle: String
    public let actionIconName: String
    public let actionAccessibilityHint: String?

    public init(
        title: String,
        detail: String,
        iconName: String,
        action: SecondaryContentUnavailableAction,
        actionTitle: String,
        actionIconName: String,
        actionAccessibilityHint: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.action = action
        self.actionTitle = actionTitle
        self.actionIconName = actionIconName
        self.actionAccessibilityHint = actionAccessibilityHint
    }

    public static func accounts(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int
    ) -> SecondaryContentUnavailableState {
        if !isDemoMode, !serverConnected {
            return serverOfflineState(detail: "Start PlaidBarServer, then check the connection before account balances can load.")
        }

        if linkedItemCount == 0 {
            return noBankLinkedState(detail: "Connect a Plaid institution before balances can appear here.")
        }

        return SecondaryContentUnavailableState(
            title: "Accounts not loaded",
            detail: "PlaidBar found a linked bank, but no balances are available yet. Refresh accounts to load the latest balances.",
            iconName: "tray",
            action: .refreshAccounts,
            actionTitle: "Refresh Accounts",
            actionIconName: "arrow.clockwise",
            actionAccessibilityHint: "Checks the server for account balances."
        )
    }

    public static func credit(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int
    ) -> SecondaryContentUnavailableState {
        if !isDemoMode, !serverConnected {
            return serverOfflineState(detail: "Start PlaidBarServer, then check the connection before credit utilization can load.")
        }

        if linkedItemCount == 0 {
            return SecondaryContentUnavailableState(
                title: "No bank linked",
                detail: "Link a bank that includes a credit card before utilization can appear here.",
                iconName: "creditcard",
                action: .addAccount,
                actionTitle: "Link Bank",
                actionIconName: "plus.circle",
                actionAccessibilityHint: "Starts Plaid Link so you can connect a bank."
            )
        }

        if accountCount == 0 {
            return SecondaryContentUnavailableState(
                title: "Accounts not loaded",
                detail: "A bank is linked, but balances have not loaded yet. Refresh accounts before checking credit utilization.",
                iconName: "tray",
                action: .refreshAccounts,
                actionTitle: "Refresh Accounts",
                actionIconName: "arrow.clockwise",
                actionAccessibilityHint: "Checks the server for account balances."
            )
        }

        return SecondaryContentUnavailableState(
            title: "No credit card linked",
            detail: "Linked accounts do not include a credit card with utilization data. Link a credit card, or refresh if one was just added.",
            iconName: "creditcard",
            action: .addAccount,
            actionTitle: "Link Credit Card",
            actionIconName: "plus.circle",
            actionAccessibilityHint: "Starts Plaid Link so you can connect a credit card."
        )
    }

    public static func transactions(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        transactionCount: Int,
        hasSearchText: Bool,
        hasActiveFilters: Bool,
        errorMessage: String?
    ) -> SecondaryContentUnavailableState {
        if hasSearchText || hasActiveFilters {
            return SecondaryContentUnavailableState(
                title: "No matching transactions",
                detail: "Synced history is loaded, but nothing matches the current search or filters. Clear them to return to recent transactions.",
                iconName: "magnifyingglass",
                action: .clearFilters,
                actionTitle: "Clear Filters",
                actionIconName: "xmark.circle",
                actionAccessibilityHint: "Removes the current search text and filters."
            )
        }

        if let errorState = recentActionFailure(from: errorMessage) {
            return errorState
        }

        if !isDemoMode, !serverConnected {
            return serverOfflineState(detail: "Start PlaidBarServer, then check the connection before syncing transaction history.")
        }

        if linkedItemCount == 0 {
            return noBankLinkedState(detail: "Connect a Plaid institution before transaction history can sync.")
        }

        if accountCount == 0 {
            return SecondaryContentUnavailableState(
                title: "Accounts not loaded",
                detail: "A bank is linked, but balances have not loaded yet. Refresh accounts before syncing transaction history.",
                iconName: "tray",
                action: .refreshAccounts,
                actionTitle: "Refresh Accounts",
                actionIconName: "arrow.clockwise",
                actionAccessibilityHint: "Checks the server for account balances."
            )
        }

        if syncedItemCount == 0 {
            return SecondaryContentUnavailableState(
                title: "First sync needed",
                detail: "Accounts are loaded, but transaction history has not synced yet. Sync now to load recent activity.",
                iconName: "clock.arrow.circlepath",
                action: .syncTransactions,
                actionTitle: "Sync Transactions",
                actionIconName: "arrow.triangle.2.circlepath",
                actionAccessibilityHint: "Asks the server to sync transaction history."
            )
        }

        return SecondaryContentUnavailableState(
            title: transactionCount == 0 ? "No transaction history" : "No transactions",
            detail: "No transaction rows are available for the linked accounts. Sync again to check for new or recent history.",
            iconName: "list.bullet.rectangle",
            action: .syncTransactions,
            actionTitle: "Sync Transactions",
            actionIconName: "arrow.triangle.2.circlepath",
            actionAccessibilityHint: "Asks the server to sync transaction history."
        )
    }

    public static func spendingActivity(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        transactionCount: Int,
        errorMessage: String?
    ) -> SecondaryContentUnavailableState {
        if let errorState = recentActionFailure(from: errorMessage) {
            return errorState
        }

        if !isDemoMode, !serverConnected {
            return serverOfflineState(detail: "Start PlaidBarServer, then check the connection before spending activity can sync.")
        }

        if linkedItemCount == 0 {
            return noBankLinkedState(detail: "Connect a Plaid institution before spending and cashflow charts can populate.")
        }

        if accountCount == 0 {
            return SecondaryContentUnavailableState(
                title: "Accounts not loaded",
                detail: "A bank is linked, but balances have not loaded yet. Refresh accounts before syncing spending activity.",
                iconName: "tray",
                action: .refreshAccounts,
                actionTitle: "Refresh Accounts",
                actionIconName: "arrow.clockwise",
                actionAccessibilityHint: "Checks the server for account balances."
            )
        }

        return SecondaryContentUnavailableState(
            title: syncedItemCount == 0 || transactionCount == 0 ? "No synced activity" : "No spending activity",
            detail: "Spending views need synced transactions. Sync transaction history to build the heatmap, trend, and cashflow views.",
            iconName: "chart.bar.xaxis",
            action: .syncTransactions,
            actionTitle: "Sync Transactions",
            actionIconName: "arrow.triangle.2.circlepath",
            actionAccessibilityHint: "Asks the server to sync transaction history."
        )
    }

    public static func spendingPeriod(
        periodLabel: String,
        canShowWiderPeriod: Bool
    ) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState(
            title: "No activity in \(periodLabel)",
            detail: canShowWiderPeriod
                ? "No synced transactions fall inside this period. Show a wider window to inspect older history."
                : "No synced transactions fall inside this period. Refresh to check for newly synced history.",
            iconName: "calendar.badge.clock",
            action: canShowWiderPeriod ? .showWiderPeriod : .refresh,
            actionTitle: canShowWiderPeriod ? "Show 90 Days" : "Refresh",
            actionIconName: canShowWiderPeriod ? "calendar" : "arrow.clockwise",
            actionAccessibilityHint: canShowWiderPeriod
                ? "Changes the spending period to 90 days."
                : "Reloads the dashboard data."
        )
    }

    public static func recurring(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        transactionCount: Int,
        errorMessage: String?
    ) -> SecondaryContentUnavailableState {
        if let errorState = recentActionFailure(from: errorMessage) {
            return errorState
        }

        if !isDemoMode, !serverConnected {
            return serverOfflineState(detail: "Start PlaidBarServer, then check the connection before detecting recurring charges.")
        }

        if linkedItemCount == 0 {
            return noBankLinkedState(detail: "Connect a Plaid institution before recurring charges can be detected.")
        }

        if accountCount == 0 {
            return SecondaryContentUnavailableState(
                title: "Accounts not loaded",
                detail: "A bank is linked, but balances have not loaded yet. Refresh accounts before detecting recurring charges.",
                iconName: "tray",
                action: .refreshAccounts,
                actionTitle: "Refresh Accounts",
                actionIconName: "arrow.clockwise",
                actionAccessibilityHint: "Checks the server for account balances."
            )
        }

        if syncedItemCount == 0 || transactionCount == 0 {
            return SecondaryContentUnavailableState(
                title: "No synced transactions",
                detail: "Recurring detection needs transaction history. Sync transactions so PlaidBar can look for repeated charges.",
                iconName: "tray",
                action: .syncTransactions,
                actionTitle: "Sync Transactions",
                actionIconName: "arrow.triangle.2.circlepath",
                actionAccessibilityHint: "Asks the server to sync transaction history."
            )
        }

        return SecondaryContentUnavailableState(
            title: "No recurring charges found",
            detail: "No repeated merchant charges were detected. PlaidBar usually needs at least 2 months of history before marking a charge as recurring.",
            iconName: "arrow.clockwise",
            action: .syncTransactions,
            actionTitle: "Sync Latest Transactions",
            actionIconName: "arrow.triangle.2.circlepath",
            actionAccessibilityHint: "Checks for newer transactions that may complete a recurring pattern."
        )
    }

    private static func serverOfflineState(detail: String) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState(
            title: "Server offline",
            detail: detail,
            iconName: "server.rack",
            action: .checkServer,
            actionTitle: "Check Connection",
            actionIconName: "server.rack",
            actionAccessibilityHint: "Checks whether PlaidBarServer is reachable."
        )
    }

    private static func noBankLinkedState(detail: String) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState(
            title: "No bank linked",
            detail: detail,
            iconName: "building.columns",
            action: .addAccount,
            actionTitle: "Link Bank",
            actionIconName: "plus.circle",
            actionAccessibilityHint: "Starts Plaid Link so you can connect a bank."
        )
    }

    private static func recentActionFailure(from message: String?) -> SecondaryContentUnavailableState? {
        guard let detail = userFacingErrorDetail(from: message) else { return nil }
        return SecondaryContentUnavailableState(
            title: "Recent action failed",
            detail: detail,
            iconName: "exclamationmark.triangle.fill",
            action: .refresh,
            actionTitle: "Try Again",
            actionIconName: "arrow.clockwise",
            actionAccessibilityHint: "Reloads the dashboard data."
        )
    }

    private static func userFacingErrorDetail(from message: String?) -> String? {
        guard let message else { return nil }

        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !normalized.isEmpty else { return nil }
        guard normalized.count > maxRenderedErrorLength else { return normalized }

        return "\(normalized.prefix(maxRenderedErrorLength))..."
    }
}
