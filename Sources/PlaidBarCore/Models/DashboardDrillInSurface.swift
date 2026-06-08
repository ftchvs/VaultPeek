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
