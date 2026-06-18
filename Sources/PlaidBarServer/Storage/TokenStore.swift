import FluentKit
import HummingbirdFluent
import Foundation
import Logging
import PlaidBarCore

actor TokenStore {
    private let fluent: Fluent
    private let logger: Logger
    /// Keychain service the access-token bytes are stored under. Defaults to the
    /// single production service; injectable so tests can isolate their writes
    /// to a throwaway service and never touch real token entries.
    private let keychainService: String

    init(
        fluent: Fluent,
        logger: Logger = Logger(label: "com.ftchvs.plaidbar-server.token-store"),
        keychainService: String = LocalDataStore.plaidAccessTokenKeychainService
    ) {
        self.fluent = fluent
        self.logger = logger
        self.keychainService = keychainService
    }

    // Serializes managed-item inserts so the institution-limit check and the
    // insert are not interleaved by actor reentrancy at `await` points (Fluent
    // calls suspend, so an actor method alone is not atomic across them). The
    // companion server is a single local process, so an in-process FIFO gate
    // fully orders managed inserts.
    private var managedInsertLocked = false
    private var managedInsertWaiters: [CheckedContinuation<Void, Never>] = []

    // Serializes item deletion against conditional cursor saves so a sync
    // cursor cannot be resurrected for an item that was concurrently deleted.
    // `deleteItem` and `saveSyncCursorIfItemExists` both straddle several
    // suspending Fluent calls (find -> mutate), so an actor method alone is not
    // atomic across them; an in-process FIFO gate fully orders them.
    private var cursorWriteLocked = false
    private var cursorWriteWaiters: [CheckedContinuation<Void, Never>] = []

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
            itemId: id,
            service: keychainService
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

    private func acquireCursorWriteLock() async {
        if !cursorWriteLocked {
            cursorWriteLocked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cursorWriteWaiters.append(continuation)
        }
        // Resumed: the lock was handed off to us; `cursorWriteLocked` stays true.
    }

    private func releaseCursorWriteLock() {
        if cursorWriteWaiters.isEmpty {
            cursorWriteLocked = false
        } else {
            cursorWriteWaiters.removeFirst().resume()
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
        // Serialize the row removal against `saveSyncCursorIfItemExists` so a
        // concurrent sync cannot resurrect a `sync_cursors` row after the item
        // is gone.
        await acquireCursorWriteLock()
        let outcome: Result<ItemModel?, Error>
        do {
            guard let item = try await ItemModel.find(id, on: fluent.db()) else {
                releaseCursorWriteLock()
                return
            }
            if let cursor = try await SyncCursorModel.find(id, on: fluent.db()) {
                try await cursor.delete(on: fluent.db())
            }
            try await item.delete(on: fluent.db())
            outcome = .success(item)
        } catch {
            outcome = .failure(error)
        }
        releaseCursorWriteLock()

        let item = try outcome.get()
        guard let item else { return }
        do {
            try PlaidTokenVault.delete(storedToken: item.accessToken, fallbackItemId: id, service: keychainService)
        } catch {
            // Best-effort: the SQLite item/cursor rows are already gone, so a
            // Keychain-delete failure leaves only an orphaned token entry
            // (reclaimed later by `pruneOrphanedKeychainTokens`). Log enough to
            // diagnose — the item id is an opaque identifier, never token
            // material — without aborting the delete.
            logger.warning(
                "Failed to delete Plaid access token from Keychain for item \(id): \(String(describing: error))"
            )
        }
    }

    func pruneOrphanedKeychainTokens() async throws {
        let referencedItemIds = Set(try await getAllItems().compactMap(\.id))
        try PlaidTokenVault.deleteOrphanedTokens(referencedItemIds: referencedItemIds, service: keychainService)
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

    /// Atomically persists a sync cursor only while the owning item still
    /// exists, returning `false` (a no-op) if the item was deleted. The
    /// existence check and the save run under the cursor-write lock, serialized
    /// against `deleteItem`, so a concurrent deletion cannot interleave between
    /// the check and the save and resurrect a `sync_cursors` row for a gone
    /// item.
    @discardableResult
    func saveSyncCursorIfItemExists(itemId: String, cursor: String) async throws -> Bool {
        await acquireCursorWriteLock()
        let outcome: Result<Bool, Error>
        do {
            if try await ItemModel.find(itemId, on: fluent.db()) != nil {
                try await saveSyncCursor(itemId: itemId, cursor: cursor)
                outcome = .success(true)
            } else {
                outcome = .success(false)
            }
        } catch {
            outcome = .failure(error)
        }
        releaseCursorWriteLock()
        return try outcome.get()
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
        try PlaidTokenVault.resolve(storedToken: item.accessToken, service: keychainService)
    }
}

/// Raised when a managed bank-link insert would exceed the plan's institution
/// limit at the moment of insertion (after the entitlement pre-check), closing
/// the check-then-insert race.
enum ManagedLinkEnforcementError: Error, Equatable {
    case limitReached
}
