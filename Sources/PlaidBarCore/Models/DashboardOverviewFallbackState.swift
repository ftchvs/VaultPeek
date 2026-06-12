import Foundation

/// Presentation for the dashboard overview when neither demo nor synced local
/// data can provide a meaningful first-glance financial snapshot yet.
public struct DashboardOverviewFallbackState: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let iconName: String
    public let actionTitle: String
    public let actionIconName: String

    public init(
        title: String,
        detail: String,
        iconName: String,
        actionTitle: String,
        actionIconName: String
    ) {
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.actionTitle = actionTitle
        self.actionIconName = actionIconName
    }

    public static func evaluate(
        isSetupComplete: Bool,
        isDemoMode: Bool,
        accountCount: Int,
        transactionCount: Int
    ) -> DashboardOverviewFallbackState? {
        guard !isDemoMode else { return nil }
        guard !isSetupComplete, accountCount == 0, transactionCount == 0 else { return nil }

        return DashboardOverviewFallbackState(
            title: "Overview needs data",
            detail: "Demo data is not loaded yet. Start demo mode or connect the VaultPeek companion server to replace the empty overview with balances, activity, and status signals.",
            iconName: "rectangle.stack.badge.play",
            actionTitle: "Choose Data Source",
            actionIconName: "plus.circle"
        )
    }
}
