import Foundation

/// Describes the account-scoped surfaces that remain inside the selected-row
/// drill-in instead of becoming competing first-level dashboard tabs.
public enum DashboardDrillInSurface: String, CaseIterable, Sendable, Equatable {
    case account
    case activity
    case credit
    case status

    public var title: String {
        switch self {
        case .account:
            "Account"
        case .activity:
            "Activity"
        case .credit:
            "Credit"
        case .status:
            "Status"
        }
    }

    public var iconName: String {
        switch self {
        case .account:
            "building.columns.fill"
        case .activity:
            "list.bullet.rectangle"
        case .credit:
            "creditcard.fill"
        case .status:
            "waveform.path.ecg"
        }
    }

    public var accessibilitySummary: String {
        switch self {
        case .account:
            "balances and account metadata"
        case .activity:
            "recent account transactions"
        case .credit:
            "credit utilization or debt detail when relevant"
        case .status:
            "sync freshness and reconnect state"
        }
    }

    public static func surfaces(for account: AccountDTO) -> [DashboardDrillInSurface] {
        allCases.filter { $0.isRelevant(for: account) }
    }

    public func isRelevant(for account: AccountDTO) -> Bool {
        switch self {
        case .account, .activity, .status:
            true
        case .credit:
            account.type == .credit || account.type == .loan
        }
    }
}

/// Display-safe action copy for account drill-ins. Destructive actions stay
/// explicit so the SwiftUI layer can gate them with confirmation before it
/// calls the local server.
public enum DashboardDrillInAction: String, CaseIterable, Sendable, Equatable {
    case reconnect
    case remove
    case settings

    public var title: String {
        switch self {
        case .reconnect:
            "Reconnect"
        case .remove:
            "Remove Institution"
        case .settings:
            "Settings"
        }
    }

    public var iconName: String {
        switch self {
        case .reconnect:
            "link.badge.plus"
        case .remove:
            "trash"
        case .settings:
            "gearshape"
        }
    }

    public var accessibilityHint: String {
        switch self {
        case .reconnect:
            "Opens Plaid Link update mode for this institution."
        case .remove:
            "Requires confirmation before disconnecting this Plaid institution and removing its local VaultPeek data."
        case .settings:
            "Opens VaultPeek settings and local data controls."
        }
    }

    public func accessibilityLabel(accountDisplayName: String) -> String {
        switch self {
        case .reconnect:
            "Reconnect \(accountDisplayName)"
        case .remove:
            "Remove institution for \(accountDisplayName)"
        case .settings:
            "Open VaultPeek settings from \(accountDisplayName)"
        }
    }

    public static var accountDrillInActions: [DashboardDrillInAction] {
        [.reconnect, .remove, .settings]
    }

    public static func accountDrillInActions(isDemoMode: Bool) -> [DashboardDrillInAction] {
        accountDrillInActions.filter { action in
            !isDemoMode || action == .settings
        }
    }
}

/// Keeps the row-to-drill-in activation path explicit and reusable across
/// pointer, keyboard, and assistive-technology affordances.
public struct DashboardAccountDrillInPath: Sendable, Equatable {
    public let accessibilityHint: String
    public let accessibilityActionName: String
    public let pointerHelp: String

    public static func presentation(for account: AccountDTO, isSelected: Bool) -> Self {
        let displayName = AccountPresentation.displayName(for: account)
        if isSelected {
            return Self(
                accessibilityHint: "Press Return or Space to close the account details panel.",
                accessibilityActionName: "Close account details",
                pointerHelp: "Close details for \(displayName)"
            )
        }

        return Self(
            accessibilityHint: "Press Return or Space to open the account details panel beside the dashboard.",
            accessibilityActionName: "Open account details",
            pointerHelp: "Open details for \(displayName)"
        )
    }
}

/// Display-safe summary values for the selected account drill-in.
///
/// This keeps the popover's account, activity, credit/limit, freshness, and
/// sync-state facts in one testable presentation model without exposing raw
/// account IDs, item IDs, tokens, or Plaid payloads.
public struct DashboardAccountDrillInSummary: Sendable, Equatable {
    public let displayName: String
    public let subtitle: String
    public let availableTitle: String
    public let availableBalance: Double
    public let currentTitle: String
    public let currentBalance: Double
    public let utilizationPercent: Double?
    public let limit: Double?
    public let transactionCount: Int
    public let pendingTransactionCount: Int
    public let latestTransactionDate: String?
    public let syncState: ItemConnectionStatus?
    public let freshnessLabel: String

    public var accessibilityLabel: String {
        accessibilityLabel(privacyMaskEnabled: false)
    }

    public func accessibilityLabel(privacyMaskEnabled: Bool) -> String {
        var parts = [
            "Selected account drill-in",
            displayName,
            subtitle,
            "\(availableTitle) \(PrivacyMaskPresentation.currency(availableBalance, format: .full, isEnabled: privacyMaskEnabled))",
            "\(currentTitle) \(PrivacyMaskPresentation.currency(currentBalance, format: .full, isEnabled: privacyMaskEnabled))",
            "Sync \(freshnessLabel)",
        ]

        if !privacyMaskEnabled {
            parts.append("\(transactionCount) synced transaction\(transactionCount == 1 ? "" : "s")")
            parts.append("\(pendingTransactionCount) pending transaction\(pendingTransactionCount == 1 ? "" : "s")")
        }

        if let utilizationPercent {
            parts.append("Utilization \(PrivacyMaskPresentation.percent(utilizationPercent, decimals: 0, isEnabled: privacyMaskEnabled))")
        }

        if let latestTransactionDate, !privacyMaskEnabled {
            parts.append("Latest transaction \(Formatters.displayTransactionDate(latestTransactionDate))")
        }

        return parts.joined(separator: ", ")
    }

    public static func presentation(
        for account: AccountDTO,
        transactions: [TransactionDTO],
        itemStatus: ItemStatus?,
        fallbackFreshnessLabel: String,
        privacyMaskEnabled: Bool = false
    ) -> Self {
        presentation(
            for: account,
            activitySnapshot: AccountTransactionFeed.activitySnapshot(forAccountId: account.id, in: transactions),
            itemStatus: itemStatus,
            fallbackFreshnessLabel: fallbackFreshnessLabel,
            privacyMaskEnabled: privacyMaskEnabled
        )
    }

    public static func presentation(
        for account: AccountDTO,
        activitySnapshot: AccountTransactionFeed.AccountActivitySnapshot,
        itemStatus: ItemStatus?,
        fallbackFreshnessLabel: String,
        privacyMaskEnabled: Bool = false
    ) -> Self {
        Self(
            displayName: AccountPresentation.displayName(for: account),
            subtitle: AccountPresentation.subtitle(for: account, privacyMaskEnabled: privacyMaskEnabled),
            availableTitle: AccountPresentation.dashboardAvailableTitle(for: account),
            availableBalance: AccountPresentation.availableBalance(for: account),
            currentTitle: AccountPresentation.dashboardCurrentTitle(for: account),
            currentBalance: AccountPresentation.displayBalance(for: account),
            utilizationPercent: account.balances.utilizationPercent,
            limit: account.balances.limit,
            transactionCount: activitySnapshot.transactionCount,
            pendingTransactionCount: activitySnapshot.pendingTransactionCount,
            latestTransactionDate: activitySnapshot.latestTransactionDate,
            syncState: itemStatus?.status,
            freshnessLabel: itemStatus?.lastSync.map(Formatters.relativeDate) ?? fallbackFreshnessLabel
        )
    }
}
