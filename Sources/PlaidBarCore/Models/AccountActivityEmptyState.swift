import Foundation

public struct AccountActivityEmptyState: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let iconName: String
    public let tone: DashboardAccountEmptyStateTone

    public var accessibilityLabel: String {
        "\(title). \(detail)"
    }

    public init(
        title: String,
        detail: String,
        iconName: String,
        tone: DashboardAccountEmptyStateTone
    ) {
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.tone = tone
    }

    public static func evaluate(
        transactionCount: Int,
        isDemoMode: Bool,
        isInitialLoad: Bool = false,
        serverConnected: Bool,
        connectionLevel: AccountConnectionLevel,
        accountDisplayName: String
    ) -> AccountActivityEmptyState? {
        guard transactionCount == 0 else { return nil }

        if isDemoMode {
            return AccountActivityEmptyState(
                title: "No demo activity",
                detail: "\(accountDisplayName) has no sample transactions in the local demo fixture.",
                iconName: "play.circle",
                tone: .secondary
            )
        }

        // The first sync outranks offline/stale messaging: activity that has
        // not arrived yet reads as loading, not as a degraded connection.
        if isInitialLoad {
            return AccountActivityEmptyState(
                title: "Loading activity",
                detail: "Syncing recent transactions for \(accountDisplayName).",
                iconName: "arrow.triangle.2.circlepath",
                tone: .loading
            )
        }

        guard serverConnected else {
            return AccountActivityEmptyState(
                title: "Server offline",
                detail: "Start the VaultPeek companion server, then refresh to load recent activity for \(accountDisplayName).",
                iconName: "server.rack",
                tone: .offline
            )
        }

        switch connectionLevel {
        case .loginRequired:
            return AccountActivityEmptyState(
                title: "Reconnect to sync activity",
                detail: "Plaid needs a fresh bank login before VaultPeek can update transactions for \(accountDisplayName).",
                iconName: "person.crop.circle.badge.exclamationmark",
                tone: .warning
            )
        case .error:
            return AccountActivityEmptyState(
                title: "Item error blocks activity",
                detail: "Reconnect this institution, then refresh transactions for \(accountDisplayName).",
                iconName: "exclamationmark.triangle.fill",
                tone: .warning
            )
        case .stale:
            return AccountActivityEmptyState(
                title: "Activity may be stale",
                detail: "Refresh VaultPeek to pull the latest transactions for \(accountDisplayName).",
                iconName: "clock.badge.exclamationmark",
                tone: .warning
            )
        case .unknown:
            return AccountActivityEmptyState(
                title: "Item status unavailable",
                detail: "Refresh account status before trusting activity for \(accountDisplayName).",
                iconName: "link.circle",
                tone: .secondary
            )
        case .demo, .offline:
            return AccountActivityEmptyState(
                title: "No recent activity",
                detail: "\(accountDisplayName) has no recent synced transactions.",
                iconName: "tray",
                tone: .secondary
            )
        case .healthy:
            return AccountActivityEmptyState(
                title: "No recent activity",
                detail: "\(accountDisplayName) is linked, but no recent transactions are synced for this account.",
                iconName: "tray",
                tone: .healthy
            )
        }
    }
}
