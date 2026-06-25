import Foundation

/// Response from server's /api/transactions/sync
public struct SyncResponse: Codable, Sendable {
    public let added: [TransactionDTO]
    public let modified: [TransactionDTO]
    public let removed: [String]  // transaction IDs
    public let hasMore: Bool
    public let pendingCursors: [String: String]
    public let pendingCursorUpdatedAts: [String: Date]

    public init(
        added: [TransactionDTO],
        modified: [TransactionDTO],
        removed: [String],
        hasMore: Bool,
        pendingCursors: [String: String] = [:],
        pendingCursorUpdatedAts: [String: Date] = [:]
    ) {
        self.added = added
        self.modified = modified
        self.removed = removed
        self.hasMore = hasMore
        self.pendingCursors = pendingCursors
        self.pendingCursorUpdatedAts = pendingCursorUpdatedAts
    }

    enum CodingKeys: String, CodingKey {
        case added
        case modified
        case removed
        case hasMore
        case pendingCursors
        case pendingCursorUpdatedAts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        added = try container.decode([TransactionDTO].self, forKey: .added)
        modified = try container.decode([TransactionDTO].self, forKey: .modified)
        removed = try container.decode([String].self, forKey: .removed)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
        pendingCursors = try container.decodeIfPresent([String: String].self, forKey: .pendingCursors) ?? [:]
        pendingCursorUpdatedAts = try container.decodeIfPresent(
            [String: Date].self,
            forKey: .pendingCursorUpdatedAts
        ) ?? [:]
    }
}

public struct SyncCursorCommitRequest: Codable, Sendable {
    public let cursors: [String: String]
    public let cursorUpdatedAts: [String: Date]

    public init(cursors: [String: String], cursorUpdatedAts: [String: Date] = [:]) {
        self.cursors = cursors
        self.cursorUpdatedAts = cursorUpdatedAts
    }

    enum CodingKeys: String, CodingKey {
        case cursors
        case cursorUpdatedAts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursors = try container.decode([String: String].self, forKey: .cursors)
        cursorUpdatedAts = try container.decodeIfPresent([String: Date].self, forKey: .cursorUpdatedAts) ?? [:]
    }
}
