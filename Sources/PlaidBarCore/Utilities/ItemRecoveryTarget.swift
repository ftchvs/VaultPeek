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
        guard let institutionName = item.institutionName, !institutionName.isEmpty else {
            return "Reconnect Item"
        }
        return "Reconnect \(institutionName)"
    }
}
