import Foundation

/// Response from server's /api/transactions/sync
public struct SyncResponse: Codable, Sendable {
    public let added: [TransactionDTO]
    public let modified: [TransactionDTO]
    public let removed: [String]  // transaction IDs
    public let hasMore: Bool
    public let nextCursor: String?
    public let pendingCursors: [String: String]

    public init(
        added: [TransactionDTO],
        modified: [TransactionDTO],
        removed: [String],
        hasMore: Bool,
        nextCursor: String? = nil,
        pendingCursors: [String: String] = [:]
    ) {
        self.added = added
        self.modified = modified
        self.removed = removed
        self.hasMore = hasMore
        self.nextCursor = nextCursor
        self.pendingCursors = pendingCursors
    }

    enum CodingKeys: String, CodingKey {
        case added
        case modified
        case removed
        case hasMore
        case nextCursor
        case pendingCursors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        added = try container.decode([TransactionDTO].self, forKey: .added)
        modified = try container.decode([TransactionDTO].self, forKey: .modified)
        removed = try container.decode([String].self, forKey: .removed)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        pendingCursors = try container.decodeIfPresent([String: String].self, forKey: .pendingCursors) ?? [:]
    }
}

public struct SyncCursorCommitRequest: Codable, Sendable {
    public let cursors: [String: String]

    public init(cursors: [String: String]) {
        self.cursors = cursors
    }
}
