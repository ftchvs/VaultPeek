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
            return "Account"
        case .activity:
            return "Activity"
        case .credit:
            return "Credit"
        case .status:
            return "Status"
        }
    }

    public var iconName: String {
        switch self {
        case .account:
            return "building.columns.fill"
        case .activity:
            return "list.bullet.rectangle"
        case .credit:
            return "creditcard.fill"
        case .status:
            return "waveform.path.ecg"
        }
    }

    public var accessibilitySummary: String {
        switch self {
        case .account:
            return "balances and account metadata"
        case .activity:
            return "recent account transactions"
        case .credit:
            return "credit utilization or debt detail when relevant"
        case .status:
            return "sync freshness and reconnect state"
        }
    }

    public static func surfaces(for account: AccountDTO) -> [DashboardDrillInSurface] {
        allCases.filter { $0.isRelevant(for: account) }
    }

    public func isRelevant(for account: AccountDTO) -> Bool {
        switch self {
        case .account, .activity, .status:
            return true
        case .credit:
            return account.type == .credit || account.type == .loan
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
            return "Reconnect"
        case .remove:
            return "Remove Institution"
        case .settings:
            return "Settings"
        }
    }

    public var iconName: String {
        switch self {
        case .reconnect:
            return "link.badge.plus"
        case .remove:
            return "trash"
        case .settings:
            return "gearshape"
        }
    }

    public var accessibilityHint: String {
        switch self {
        case .reconnect:
            return "Opens Plaid Link update mode for this institution."
        case .remove:
            return "Requires confirmation before disconnecting this Plaid institution and removing its local PlaidBar data."
        case .settings:
            return "Opens PlaidBar settings and local data controls."
        }
    }

    public func accessibilityLabel(accountDisplayName: String) -> String {
        switch self {
        case .reconnect:
            return "Reconnect \(accountDisplayName)"
        case .remove:
            return "Remove institution for \(accountDisplayName)"
        case .settings:
            return "Open PlaidBar settings from \(accountDisplayName)"
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
                accessibilityHint: "Press Return or Space to collapse the account drill-in.",
                accessibilityActionName: "Collapse account details",
                pointerHelp: "Collapse details for \(displayName)"
            )
        }

        return Self(
            accessibilityHint: "Press Return or Space to open the account drill-in below this row.",
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
        var parts = [
            "Selected account drill-in",
            displayName,
            subtitle,
            "\(availableTitle) \(Formatters.currency(availableBalance, format: .full))",
            "\(currentTitle) \(Formatters.currency(currentBalance, format: .full))",
            "\(transactionCount) synced transaction\(transactionCount == 1 ? "" : "s")",
            "\(pendingTransactionCount) pending transaction\(pendingTransactionCount == 1 ? "" : "s")",
            "Sync \(freshnessLabel)"
        ]

        if let utilizationPercent {
            parts.append("Utilization \(Formatters.percent(utilizationPercent, decimals: 0))")
        }

        if let latestTransactionDate {
            parts.append("Latest transaction \(Formatters.displayTransactionDate(latestTransactionDate))")
        }

        return parts.joined(separator: ", ")
    }

    public static func presentation(
        for account: AccountDTO,
        transactions: [TransactionDTO],
        itemStatus: ItemStatus?,
        fallbackFreshnessLabel: String
    ) -> Self {
        let accountTransactions = transactions.filter { $0.accountId == account.id }
        let latestTransactionDate = accountTransactions
            .compactMap { transaction -> (raw: String, parsed: Date)? in
                guard let parsed = Formatters.parseTransactionDate(transaction.date) else { return nil }
                return (transaction.date, parsed)
            }
            .max { $0.parsed < $1.parsed }?
            .raw

        return Self(
            displayName: AccountPresentation.displayName(for: account),
            subtitle: AccountPresentation.subtitle(for: account),
            availableTitle: AccountPresentation.dashboardAvailableTitle(for: account),
            availableBalance: AccountPresentation.availableBalance(for: account),
            currentTitle: AccountPresentation.dashboardCurrentTitle(for: account),
            currentBalance: AccountPresentation.displayBalance(for: account),
            utilizationPercent: account.balances.utilizationPercent,
            limit: account.balances.limit,
            transactionCount: accountTransactions.count,
            pendingTransactionCount: accountTransactions.count(where: \.pending),
            latestTransactionDate: latestTransactionDate,
            syncState: itemStatus?.status,
            freshnessLabel: itemStatus?.lastSync.map(Formatters.relativeDate) ?? fallbackFreshnessLabel
        )
    }
}
