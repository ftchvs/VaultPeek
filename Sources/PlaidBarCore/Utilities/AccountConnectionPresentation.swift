import Foundation

public enum AccountConnectionLevel: Sendable, Equatable {
    case demo
    case offline
    case healthy
    case stale
    case loginRequired
    case error
    case unknown
}

public struct AccountConnectionPresentation: Sendable, Equatable {
    public let level: AccountConnectionLevel
    public let rowLabel: String
    public let detailLabel: String
    public let signalLabel: String
    public let iconName: String
    public let showsRecoveryActions: Bool

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        isSyncStale: Bool,
        statusSyncText: String,
        itemStatus: ItemConnectionStatus?
    ) -> AccountConnectionPresentation {
        if isDemoMode {
            return AccountConnectionPresentation(
                level: .demo,
                rowLabel: "Demo",
                detailLabel: "Demo data",
                signalLabel: "Demo",
                iconName: "play.circle.fill",
                showsRecoveryActions: false
            )
        }

        guard serverConnected else {
            return AccountConnectionPresentation(
                level: .offline,
                rowLabel: "Server offline",
                detailLabel: "Server offline",
                signalLabel: "Offline",
                iconName: "server.rack",
                showsRecoveryActions: false
            )
        }

        switch itemStatus {
        case .connected:
            return AccountConnectionPresentation.synced(
                isSyncStale: isSyncStale,
                statusSyncText: statusSyncText,
                unknownItem: false
            )
        case .loginRequired:
            return AccountConnectionPresentation(
                level: .loginRequired,
                rowLabel: "Reconnect",
                detailLabel: "Login required",
                signalLabel: "Login",
                iconName: "person.crop.circle.badge.exclamationmark.fill",
                showsRecoveryActions: true
            )
        case .error:
            return AccountConnectionPresentation(
                level: .error,
                rowLabel: "Item error",
                detailLabel: "Item error",
                signalLabel: "Error",
                iconName: "exclamationmark.triangle.fill",
                showsRecoveryActions: true
            )
        case nil:
            return AccountConnectionPresentation.synced(
                isSyncStale: isSyncStale,
                statusSyncText: statusSyncText,
                unknownItem: true
            )
        }
    }

    private static func synced(
        isSyncStale: Bool,
        statusSyncText: String,
        unknownItem: Bool
    ) -> AccountConnectionPresentation {
        if unknownItem {
            return AccountConnectionPresentation(
                level: .unknown,
                rowLabel: "Item unknown",
                detailLabel: "Item status unavailable",
                signalLabel: "Unknown",
                iconName: "link.circle.fill",
                showsRecoveryActions: false
            )
        }

        if isSyncStale {
            return AccountConnectionPresentation(
                level: .stale,
                rowLabel: statusSyncText,
                detailLabel: statusSyncText,
                signalLabel: "Stale",
                iconName: "clock.badge.exclamationmark.fill",
                showsRecoveryActions: true
            )
        }

        return AccountConnectionPresentation(
            level: .healthy,
            rowLabel: statusSyncText,
            detailLabel: statusSyncText,
            signalLabel: "Fresh",
            iconName: "checkmark.circle.fill",
            showsRecoveryActions: false
        )
    }
}
