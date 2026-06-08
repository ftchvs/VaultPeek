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
