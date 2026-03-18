import Foundation

/// Response from server's /api/transactions/sync
public struct SyncResponse: Codable, Sendable {
    public let added: [TransactionDTO]
    public let modified: [TransactionDTO]
    public let removed: [String]  // transaction IDs
    public let hasMore: Bool
    public let nextCursor: String?

    public init(
        added: [TransactionDTO],
        modified: [TransactionDTO],
        removed: [String],
        hasMore: Bool,
        nextCursor: String? = nil
    ) {
        self.added = added
        self.modified = modified
        self.removed = removed
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }
}
