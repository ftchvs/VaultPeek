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
        case .loginRequired, .pendingExpiration, .pendingDisconnect, .permissionRevoked, .newAccountsAvailable:
            let itemSyncLabel = itemSyncLabel(itemLastSyncRelative)
            return AccountConnectionPresentation(
                level: .loginRequired,
                rowLabel: repairActionTitle(status: itemStatus, institutionName: institutionName),
                detailLabel: repairDetailLabel(status: itemStatus, institutionName: institutionName),
                signalLabel: repairSignalLabel(status: itemStatus),
                iconName: repairIconName(status: itemStatus),
                showsRecoveryActions: true,
                recoveryActionTitle: repairActionTitle(status: itemStatus, institutionName: institutionName),
                itemSyncLabel: itemSyncLabel,
                statusFilterSubtitle: "\(repairSubtitle(status: itemStatus)) • \(itemSyncLabel)",
                recoveryDetailLabel: repairRecoveryDetailLabel(status: itemStatus, institutionName: institutionName)
            )
        case .loginRepaired:
            return AccountConnectionPresentation.synced(
                isSyncStale: isSyncStale,
                statusSyncText: statusSyncText,
                itemLastSyncRelative: itemLastSyncRelative,
                unknownItem: false
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

    private static func repairActionTitle(status: ItemConnectionStatus?, institutionName: String?) -> String {
        guard status == .newAccountsAvailable else {
            return reconnectActionTitle(institutionName: institutionName)
        }
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            return "Update Item"
        }
        return "Update \(institutionName)"
    }

    private static func repairDetailLabel(status: ItemConnectionStatus?, institutionName: String?) -> String {
        switch status {
        case .pendingExpiration:
            return itemDetailLabel(institutionName: institutionName, fallback: "Login expiring", suffix: "login expiring")
        case .pendingDisconnect:
            return itemDetailLabel(institutionName: institutionName, fallback: "Consent needed", suffix: "consent needed")
        case .permissionRevoked:
            return itemDetailLabel(institutionName: institutionName, fallback: "Permission revoked", suffix: "permission revoked")
        case .newAccountsAvailable:
            return itemDetailLabel(institutionName: institutionName, fallback: "New accounts available", suffix: "new accounts available")
        case .connected, .loginRepaired, .loginRequired, .error, nil:
            return itemDetailLabel(institutionName: institutionName, fallback: "Login required", suffix: "login required")
        }
    }

    private static func repairSignalLabel(status: ItemConnectionStatus?) -> String {
        switch status {
        case .pendingExpiration:
            "Expiring"
        case .pendingDisconnect:
            "Consent"
        case .permissionRevoked:
            "Revoked"
        case .newAccountsAvailable:
            "New"
        case .connected, .loginRepaired, .loginRequired, .error, nil:
            "Login"
        }
    }

    private static func repairSubtitle(status: ItemConnectionStatus?) -> String {
        switch status {
        case .pendingExpiration:
            "Login expiring"
        case .pendingDisconnect:
            "Consent needed"
        case .permissionRevoked:
            "Permission revoked"
        case .newAccountsAvailable:
            "New accounts available"
        case .connected, .loginRepaired, .loginRequired, .error, nil:
            "Login required"
        }
    }

    private static func repairIconName(status: ItemConnectionStatus?) -> String {
        switch status {
        case .pendingExpiration:
            "clock.badge.exclamationmark.fill"
        case .pendingDisconnect, .permissionRevoked:
            "hand.raised.fill"
        case .newAccountsAvailable:
            "plus.circle.fill"
        case .connected, .loginRepaired, .loginRequired, .error, nil:
            "person.crop.circle.badge.exclamationmark.fill"
        }
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

    private static func repairRecoveryDetailLabel(status: ItemConnectionStatus?, institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else {
            switch status {
            case .pendingExpiration:
                return "Plaid says this login will expire soon. Reconnect this item to keep sync healthy."
            case .pendingDisconnect:
                return "Plaid says this item needs renewed consent. Reconnect this item to keep sync healthy."
            case .permissionRevoked:
                return "Plaid says permission was revoked. Reconnect this item to restore access."
            case .newAccountsAvailable:
                return "New accounts are available. Update this item to choose what VaultPeek can access."
            case .connected, .loginRepaired, .loginRequired, .error, nil:
                return loginRecoveryDetailLabel(institutionName: nil)
            }
        }

        switch status {
        case .pendingExpiration:
            return "Plaid says \(institutionName) login will expire soon. Reconnect this item to keep sync healthy."
        case .pendingDisconnect:
            return "Plaid says \(institutionName) needs renewed consent. Reconnect this item to keep sync healthy."
        case .permissionRevoked:
            return "Plaid says \(institutionName) permission was revoked. Reconnect this item to restore access."
        case .newAccountsAvailable:
            return "\(institutionName) has newly available accounts. Update this item to choose what VaultPeek can access."
        case .connected, .loginRepaired, .loginRequired, .error, nil:
            return loginRecoveryDetailLabel(institutionName: institutionName)
        }
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
