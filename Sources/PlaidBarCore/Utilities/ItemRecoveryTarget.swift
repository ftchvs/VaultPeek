import Foundation

public enum ItemRecoveryTarget {
    public static func itemId(from statuses: [ItemStatus]) -> String? {
        statuses.first { $0.status == .error }?.id
            ?? statuses.first { $0.status == .loginRequired }?.id
    }
}
