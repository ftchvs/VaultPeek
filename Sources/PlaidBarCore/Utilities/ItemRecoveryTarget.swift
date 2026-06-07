import Foundation

public enum ItemRecoveryTarget {
    public static func item(from statuses: [ItemStatus]) -> ItemStatus? {
        statuses.first { $0.status == .error }
            ?? statuses.first { $0.status == .loginRequired }
    }

    public static func itemId(from statuses: [ItemStatus]) -> String? {
        item(from: statuses)?.id
    }

    public static func actionTitle(from statuses: [ItemStatus]) -> String? {
        guard let item = item(from: statuses) else { return nil }
        guard let institutionName = normalizedInstitutionName(item.institutionName) else {
            return "Reconnect Item"
        }
        return "Reconnect \(institutionName)"
    }

    public static func recoveryDetail(from statuses: [ItemStatus]) -> String? {
        guard let item = item(from: statuses) else { return nil }

        switch item.status {
        case .loginRequired:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid requires a fresh \(institutionName) login before account rows can be recovered."
            }
            return "Plaid requires a fresh bank login before account rows can be recovered."
        case .error:
            if let institutionName = normalizedInstitutionName(item.institutionName) {
                return "Plaid reported an item error for \(institutionName). Reconnect it, then refresh balances."
            }
            return "Plaid reported an item error. Reconnect the item, then refresh balances."
        case .connected:
            return nil
        }
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
