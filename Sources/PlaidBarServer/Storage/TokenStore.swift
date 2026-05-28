import FluentKit
import HummingbirdFluent
import Foundation
import Logging

actor TokenStore {
    private let fluent: Fluent
    private let logger: Logger

    init(fluent: Fluent, logger: Logger = Logger(label: "com.ftchvs.plaidbar-server.token-store")) {
        self.fluent = fluent
        self.logger = logger
    }

    // MARK: - Items

    func saveItem(
        id: String,
        accessToken: String,
        institutionId: String?,
        institutionName: String?
    ) async throws {
        let storedAccessToken = try PlaidTokenVault.store(
            accessToken: accessToken,
            itemId: id
        )
        let item = ItemModel(
            id: id,
            accessToken: storedAccessToken,
            institutionId: institutionId,
            institutionName: institutionName
        )
        try await item.save(on: fluent.db())
    }

    func getItem(id: String) async throws -> ItemModel? {
        try await ItemModel.find(id, on: fluent.db())
    }

    func getAllItems() async throws -> [ItemModel] {
        try await ItemModel.query(on: fluent.db()).all()
    }

    func deleteItem(id: String) async throws {
        guard let item = try await ItemModel.find(id, on: fluent.db()) else { return }
        if let cursor = try await SyncCursorModel.find(id, on: fluent.db()) {
            try await cursor.delete(on: fluent.db())
        }
        try await item.delete(on: fluent.db())
        do {
            try PlaidTokenVault.delete(storedToken: item.accessToken, fallbackItemId: id)
        } catch {
            logger.warning(
                "Failed to delete Plaid access token from Keychain for item \(id): \(String(describing: error))"
            )
        }
    }

    func pruneOrphanedKeychainTokens() async throws {
        let referencedItemIds = Set(try await getAllItems().compactMap(\.id))
        try PlaidTokenVault.deleteOrphanedTokens(referencedItemIds: referencedItemIds)
    }

    func updateItemStatus(id: String, status: String) async throws {
        guard let item = try await ItemModel.find(id, on: fluent.db()) else { return }
        item.status = status
        try await item.save(on: fluent.db())
    }

    // MARK: - Sync Cursors

    func getSyncCursor(itemId: String) async throws -> String? {
        try await SyncCursorModel.find(itemId, on: fluent.db())?.cursor
    }

    func saveSyncCursor(itemId: String, cursor: String) async throws {
        if let existing = try await SyncCursorModel.find(itemId, on: fluent.db()) {
            existing.cursor = cursor
            try await existing.save(on: fluent.db())
        } else {
            let model = SyncCursorModel(itemId: itemId, cursor: cursor)
            try await model.save(on: fluent.db())
        }
    }

    // MARK: - Stats

    func itemCount() async throws -> Int {
        try await ItemModel.query(on: fluent.db()).count()
    }

    func lastSyncDate() async throws -> Date? {
        try await SyncCursorModel.query(on: fluent.db())
            .sort(\.$updatedAt, .descending)
            .first()?
            .updatedAt
    }

    func syncedItemCount() async throws -> Int {
        try await SyncCursorModel.query(on: fluent.db()).count()
    }

    nonisolated func accessToken(for item: ItemModel) throws -> String {
        try PlaidTokenVault.resolve(storedToken: item.accessToken)
    }
}
