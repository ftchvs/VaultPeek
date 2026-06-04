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
    public let itemSyncLabel: String?
    public let statusFilterSubtitle: String
    public let recoveryDetailLabel: String?

    public init(
        level: AccountConnectionLevel,
        rowLabel: String,
        detailLabel: String,
        signalLabel: String,
        iconName: String,
        showsRecoveryActions: Bool,
        recoveryActionTitle: String?,
        itemSyncLabel: String? = nil,
        statusFilterSubtitle: String? = nil,
        recoveryDetailLabel: String? = nil
    ) {
        self.level = level
        self.rowLabel = rowLabel
        self.detailLabel = detailLabel
        self.signalLabel = signalLabel
        self.iconName = iconName
        self.showsRecoveryActions = showsRecoveryActions
        self.recoveryActionTitle = recoveryActionTitle
        self.itemSyncLabel = itemSyncLabel
        self.statusFilterSubtitle = statusFilterSubtitle ?? detailLabel
        self.recoveryDetailLabel = recoveryDetailLabel
    }

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        isSyncStale: Bool,
        statusSyncText: String,
        itemStatus: ItemConnectionStatus?,
        institutionName: String? = nil,
        itemLastSyncRelative: String? = nil
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
                itemLastSyncRelative: itemLastSyncRelative,
                unknownItem: false
            )
        case .loginRequired:
            let itemSyncLabel = itemSyncLabel(itemLastSyncRelative)
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
                recoveryActionTitle: reconnectActionTitle(institutionName: institutionName),
                itemSyncLabel: itemSyncLabel,
                statusFilterSubtitle: "Login required • \(itemSyncLabel)",
                recoveryDetailLabel: loginRecoveryDetailLabel(institutionName: institutionName)
            )
        case .error:
            let itemSyncLabel = itemSyncLabel(itemLastSyncRelative)
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
                recoveryActionTitle: reconnectActionTitle(institutionName: institutionName),
                itemSyncLabel: itemSyncLabel,
                statusFilterSubtitle: "Item error • \(itemSyncLabel)",
                recoveryDetailLabel: errorRecoveryDetailLabel(institutionName: institutionName)
            )
        case nil:
            return AccountConnectionPresentation.synced(
                isSyncStale: isSyncStale,
                statusSyncText: statusSyncText,
                itemLastSyncRelative: itemLastSyncRelative,
                unknownItem: true
            )
        }
    }

    private static func synced(
        isSyncStale: Bool,
        statusSyncText: String,
        itemLastSyncRelative: String?,
        unknownItem: Bool
    ) -> AccountConnectionPresentation {
        let itemSyncLabel = itemSyncLabel(itemLastSyncRelative)

        if unknownItem {
            return AccountConnectionPresentation(
                level: .unknown,
                rowLabel: "Item unknown",
                detailLabel: "Item status unavailable",
                signalLabel: "Unknown",
                iconName: "link.circle.fill",
                showsRecoveryActions: false,
                recoveryActionTitle: nil,
                itemSyncLabel: itemSyncLabel
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
                recoveryActionTitle: "Refresh",
                itemSyncLabel: itemSyncLabel,
                statusFilterSubtitle: "Stale sync • \(itemSyncLabel)",
                recoveryDetailLabel: "This item has stale Plaid data. Refresh to pull current balances and transactions."
            )
        }

        return AccountConnectionPresentation(
            level: .healthy,
            rowLabel: statusSyncText,
            detailLabel: statusSyncText,
            signalLabel: "Fresh",
            iconName: "checkmark.circle.fill",
            showsRecoveryActions: false,
            recoveryActionTitle: nil,
            itemSyncLabel: itemSyncLabel,
            statusFilterSubtitle: "Healthy • \(itemSyncLabel)"
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

    private static func loginRecoveryDetailLabel(institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            return "Plaid requires a fresh bank login. Reconnect this item, then refresh."
        }
        return "Plaid requires a fresh \(institutionName) login. Reconnect this item, then refresh."
    }

    private static func errorRecoveryDetailLabel(institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            return "Plaid reported an item error. Reconnect this item, then refresh."
        }
        return "Plaid reported an item error for \(institutionName). Reconnect this item, then refresh."
    }

    private static func itemSyncLabel(_ itemLastSyncRelative: String?) -> String {
        guard let itemLastSyncRelative, !itemLastSyncRelative.isEmpty else {
            return "No sync recorded"
        }
        return "Last sync \(itemLastSyncRelative)"
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
