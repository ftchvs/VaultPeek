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
    public let recoveryActionTitle: String?

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        isSyncStale: Bool,
        statusSyncText: String,
        itemStatus: ItemConnectionStatus?,
        institutionName: String? = nil
    ) -> AccountConnectionPresentation {
        if isDemoMode {
            return AccountConnectionPresentation(
                level: .demo,
                rowLabel: "Demo",
                detailLabel: "Demo data",
                signalLabel: "Demo",
                iconName: "play.circle.fill",
                showsRecoveryActions: false,
                recoveryActionTitle: nil
            )
        }

        guard serverConnected else {
            return AccountConnectionPresentation(
                level: .offline,
                rowLabel: "Server offline",
                detailLabel: "Server offline",
                signalLabel: "Offline",
                iconName: "server.rack",
                showsRecoveryActions: false,
                recoveryActionTitle: nil
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
                rowLabel: reconnectActionTitle(institutionName: institutionName),
                detailLabel: itemDetailLabel(
                    institutionName: institutionName,
                    fallback: "Login required",
                    suffix: "login required"
                ),
                signalLabel: "Login",
                iconName: "person.crop.circle.badge.exclamationmark.fill",
                showsRecoveryActions: true,
                recoveryActionTitle: reconnectActionTitle(institutionName: institutionName)
            )
        case .error:
            return AccountConnectionPresentation(
                level: .error,
                rowLabel: itemDetailLabel(
                    institutionName: institutionName,
                    fallback: "Item error",
                    suffix: "item error"
                ),
                detailLabel: itemDetailLabel(
                    institutionName: institutionName,
                    fallback: "Item error",
                    suffix: "item error"
                ),
                signalLabel: "Error",
                iconName: "exclamationmark.triangle.fill",
                showsRecoveryActions: true,
                recoveryActionTitle: reconnectActionTitle(institutionName: institutionName)
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
                showsRecoveryActions: false,
                recoveryActionTitle: nil
            )
        }

        if isSyncStale {
            let staleLabel = "Stale • \(statusSyncText)"
            return AccountConnectionPresentation(
                level: .stale,
                rowLabel: staleLabel,
                detailLabel: "Last sync \(statusSyncText)",
                signalLabel: "Stale",
                iconName: "clock.badge.exclamationmark.fill",
                showsRecoveryActions: true,
                recoveryActionTitle: "Refresh"
            )
        }

        return AccountConnectionPresentation(
            level: .healthy,
            rowLabel: statusSyncText,
            detailLabel: statusSyncText,
            signalLabel: "Fresh",
            iconName: "checkmark.circle.fill",
            showsRecoveryActions: false,
            recoveryActionTitle: nil
        )
    }

    private static func reconnectActionTitle(institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            return "Reconnect Item"
        }
        return "Reconnect \(institutionName)"
    }

    private static func itemDetailLabel(
        institutionName: String?,
        fallback: String,
        suffix: String
    ) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            return fallback
        }
        return "\(institutionName) \(suffix)"
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
