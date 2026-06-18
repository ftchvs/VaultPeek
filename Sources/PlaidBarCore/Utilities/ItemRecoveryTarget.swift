import Foundation

public enum ItemRecoveryTarget {
    public static func item(from statuses: [ItemStatus]) -> ItemStatus? {
        statuses.first { $0.status == .error }
            ?? statuses.first { $0.status.needsUpdateMode }
    }

    public static func itemId(from statuses: [ItemStatus]) -> String? {
        item(from: statuses)?.id
    }

    public static func actionTitle(from statuses: [ItemStatus]) -> String? {
        guard let item = item(from: statuses) else { return nil }
        guard let institutionName = normalizedInstitutionName(item.institutionName) else {
            return actionFallback(for: item.status)
        }
        return "\(actionVerb(for: item.status)) \(institutionName)"
    }

    public static func recoveryDetail(from statuses: [ItemStatus]) -> String? {
        guard let item = item(from: statuses) else { return nil }

        switch item.status {
        case .loginRequired:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid requires a fresh \(institutionName) login before account rows can be recovered."
            }
            return "Plaid requires a fresh bank login before account rows can be recovered."
        case .pendingExpiration:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid says \(institutionName) login will expire soon. Update it before account rows stop syncing."
            }
            return "Plaid says this login will expire soon. Update the item before account rows stop syncing."
        case .pendingDisconnect:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid says \(institutionName) needs renewed consent before account rows stop syncing."
            }
            return "Plaid says this item needs renewed consent before account rows stop syncing."
        case .permissionRevoked:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid says \(institutionName) permission was revoked. Update it to restore account rows."
            }
            return "Plaid says item permission was revoked. Update it to restore account rows."
        case .newAccountsAvailable:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "\(institutionName) has newly available accounts. Update it to choose what VaultPeek can access."
            }
            return "New accounts are available. Update the item to choose what VaultPeek can access."
        case .error:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid reported an item error for \(institutionName). Reconnect it, then refresh balances."
            }
            return "Plaid reported an item error. Reconnect the item, then refresh balances."
        case .connected, .loginRepaired, .providerOutage:
            // .providerOutage is a non-actionable transient outage and is never
            // selected as a recovery target by item(from:), so it carries no
            // reconnect detail here.
            return nil
        }
    }

    private static func actionVerb(for status: ItemConnectionStatus) -> String {
        switch status {
        case .newAccountsAvailable:
            "Update"
        case .connected, .loginRepaired, .loginRequired, .pendingExpiration, .pendingDisconnect, .permissionRevoked, .providerOutage, .error:
            "Reconnect"
        }
    }

    private static func actionFallback(for status: ItemConnectionStatus) -> String {
        switch status {
        case .newAccountsAvailable:
            "Update Item"
        case .connected, .loginRepaired, .loginRequired, .pendingExpiration, .pendingDisconnect, .permissionRevoked, .providerOutage, .error:
            "Reconnect Item"
        }
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
