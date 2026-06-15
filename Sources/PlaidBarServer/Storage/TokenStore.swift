import FluentKit
import HummingbirdFluent
import Foundation
import Logging
import PlaidBarCore

actor TokenStore {
    private let fluent: Fluent
    private let logger: Logger

    init(fluent: Fluent, logger: Logger = Logger(label: "com.ftchvs.plaidbar-server.token-store")) {
        self.fluent = fluent
        self.logger = logger
    }

    // Serializes managed-item inserts so the institution-limit check and the
    // insert are not interleaved by actor reentrancy at `await` points (Fluent
    // calls suspend, so an actor method alone is not atomic across them). The
    // companion server is a single local process, so an in-process FIFO gate
    // fully orders managed inserts.
    private var managedInsertLocked = false
    private var managedInsertWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Items

    func saveItem(
        id: String,
        accessToken: String,
        institutionId: String?,
        institutionName: String?,
        providerID: ProviderID = .plaid,
        origin: ItemOrigin = .bringYourOwn
    ) async throws {
        let storedAccessToken = try PlaidTokenVault.store(
            accessToken: accessToken,
            itemId: id
        )
        let item = ItemModel(
            id: id,
            accessToken: storedAccessToken,
            institutionId: institutionId,
            institutionName: institutionName,
            providerID: providerID,
            origin: origin
        )
        try await item.save(on: fluent.db())
    }

    /// Atomically enforces the managed institution limit and persists the item.
    /// The count read and the insert run under an in-process serialization lock,
    /// so two concurrent managed link completions cannot both observe
    /// `count < limit` and both insert (a TOCTOU overshoot of the cap). Throws
    /// `ManagedLinkEnforcementError.limitReached` when already at capacity, which
    /// the OAuth callback maps to a spent-but-not-stored result (the user re-links).
    func saveManagedItemEnforcingLimit(
        id: String,
        accessToken: String,
        institutionId: String?,
        institutionName: String?,
        providerID: ProviderID = .plaid,
        institutionLimit: Int
    ) async throws {
        await acquireManagedInsertLock()
        let outcome: Result<Void, Error>
        do {
            let existingInstitutionKeys = try await activeInstitutionKeys(origin: .managed)
            let incomingInstitutionKey = institutionId ?? id
            if existingInstitutionKeys.count >= institutionLimit,
               !existingInstitutionKeys.contains(incomingInstitutionKey) {
                outcome = .failure(ManagedLinkEnforcementError.limitReached)
            } else {
                try await saveItem(
                    id: id,
                    accessToken: accessToken,
                    institutionId: institutionId,
                    institutionName: institutionName,
                    providerID: providerID,
                    origin: .managed
                )
                outcome = .success(())
            }
        } catch {
            outcome = .failure(error)
        }
        releaseManagedInsertLock()
        try outcome.get()
    }

    private func acquireManagedInsertLock() async {
        if !managedInsertLocked {
            managedInsertLocked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            managedInsertWaiters.append(continuation)
        }
        // Resumed: the lock was handed off to us; `managedInsertLocked` stays true.
    }

    private func releaseManagedInsertLock() {
        if managedInsertWaiters.isEmpty {
            managedInsertLocked = false
        } else {
            managedInsertWaiters.removeFirst().resume()
        }
    }

    func getItem(id: String) async throws -> ItemModel? {
        try await ItemModel.find(id, on: fluent.db())
    }

    func getAllItems() async throws -> [ItemModel] {
        try await ItemModel.query(on: fluent.db()).all()
    }

    func getAllItems(providerID: ProviderID) async throws -> [ItemModel] {
        try await ItemModel.query(on: fluent.db())
            .filter(\.$provider == providerID.rawValue)
            .all()
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
                "Failed to delete Plaid access token from Keychain: \(String(describing: error))"
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

    func activeInstitutionCount(origin: ItemOrigin) async throws -> Int {
        try await activeInstitutionKeys(origin: origin).count
    }

    private func activeInstitutionKeys(origin: ItemOrigin) async throws -> Set<String> {
        let items = try await ItemModel.query(on: fluent.db())
            .filter(\.$origin == origin.rawValue)
            .all()
        let activeInstitutionKeys = items.compactMap { item -> String? in
            if item.status == ItemConnectionStatus.pendingDisconnect.rawValue {
                return nil
            }
            return item.institutionId ?? item.id
        }
        return Set(activeInstitutionKeys)
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

/// Raised when a managed bank-link insert would exceed the plan's institution
/// limit at the moment of insertion (after the entitlement pre-check), closing
/// the check-then-insert race.
enum ManagedLinkEnforcementError: Error, Equatable {
    case limitReached
}
