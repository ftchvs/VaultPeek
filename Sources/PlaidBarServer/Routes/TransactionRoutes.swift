import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct TransactionRoutes: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    var maxConcurrentItemRefreshes = AccountRoutes.defaultMaxConcurrentItemRefreshes

    /// Per-item in-flight gate: concurrent `/transactions/sync` requests for the
    /// same item coalesce onto a single sync instead of racing the cursor.
    /// Registered once with the router, so all request handlers share it.
    private let syncCoalescer = ItemSyncCoalescer<ItemSyncResult>()

    // Explicit initializer: a `private` stored property would otherwise lower
    // the synthesized memberwise initializer's access below `internal` and break
    // the App.swift call site.
    init(
        plaidClient: any PlaidClientProtocol,
        tokenStore: TokenStore,
        maxConcurrentItemRefreshes: Int = AccountRoutes.defaultMaxConcurrentItemRefreshes
    ) {
        self.plaidClient = plaidClient
        self.tokenStore = tokenStore
        self.maxConcurrentItemRefreshes = maxConcurrentItemRefreshes
    }

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("transactions")
            .get("sync", use: syncTransactions)
            .post("sync/cursors", use: commitSyncCursors)
    }

    @Sendable
    func syncTransactions(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let itemIdParam = request.uri.queryParameters.get("item_id")
        let items: [ItemModel]

        if let itemIdParam {
            let itemId = String(itemIdParam)
            if let item = try await tokenStore.getItem(id: itemId) {
                items = [item]
            } else {
                throw HTTPError(.notFound, message: "Unknown Plaid item")
            }
        } else {
            items = AccountRoutes.deterministicItems(try await tokenStore.getAllItems())
        }

        let results = try await syncItems(items)
        let attemptedItemCount = results.filter(\.attempted).count
        let successfulItemCount = results.filter(\.succeeded).count

        if Self.shouldFailSync(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid transaction sync failed for every linked item")
        }

        let successfulResults = results.filter(\.succeeded)
        let pendingCursors = successfulResults.reduce(into: [String: String]()) { cursors, result in
            guard let nextCursor = result.nextCursor, !nextCursor.isEmpty else { return }
            cursors[result.itemId] = nextCursor
        }

        let syncResponse = SyncResponse(
            added: successfulResults.flatMap(\.added),
            modified: successfulResults.flatMap(\.modified),
            removed: successfulResults.flatMap(\.removed),
            hasMore: successfulResults.contains(where: \.hasMore),
            pendingCursors: pendingCursors
        )

        let data = try JSONEncoder().encode(syncResponse)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    @Sendable
    func commitSyncCursors(
        request: Request,
        context: some RequestContext
    ) async throws -> HTTPResponse.Status {
        let commitRequest = try await request.decode(as: SyncCursorCommitRequest.self, context: context)
        for (itemId, cursor) in commitRequest.cursors {
            guard let committableCursor = Self.normalizedCommittableCursor(cursor) else { continue }
            // Atomic existence-check + save: closes the TOCTOU between the
            // unknown-item guard and the persist, so a cursor can never be
            // resurrected for an item deleted mid-request.
            let persisted = try await tokenStore.saveSyncCursorIfItemExists(
                itemId: itemId,
                cursor: committableCursor
            )
            guard persisted else {
                throw HTTPError(.badRequest, message: "Cannot commit cursor for unknown item")
            }
        }
        return .ok
    }

    // MARK: - Helpers

    static func shouldFailSync(attemptedItemCount: Int, successfulItemCount: Int) -> Bool {
        attemptedItemCount > 0 && successfulItemCount == 0
    }

    /// Cursor-state preservation guard: an empty or whitespace-only cursor
    /// must never overwrite a stored cursor, otherwise the next sync would
    /// silently restart from the beginning of the item's history.
    static func normalizedCommittableCursor(_ cursor: String) -> String? {
        let trimmed = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct ItemSyncResult: Sendable {
        let itemId: String
        let attempted: Bool
        let succeeded: Bool
        let added: [TransactionDTO]
        let modified: [TransactionDTO]
        let removed: [String]
        let hasMore: Bool
        let nextCursor: String?

        static let skipped = ItemSyncResult(
            itemId: "",
            attempted: false,
            succeeded: false,
            added: [],
            modified: [],
            removed: [],
            hasMore: false,
            nextCursor: nil
        )
    }

    private func syncItems(_ items: [ItemModel]) async throws -> [ItemSyncResult] {
        try await BoundedConcurrency.map(items, limit: maxConcurrentItemRefreshes) { item in
            guard let itemId = item.id else { return .skipped }

            // Coalesce per item: a second concurrent sync for the same item
            // awaits the in-flight result rather than racing its cursor.
            do {
                return try await syncCoalescer.run(itemId: itemId) {
                    try await self.syncItemRecordingStatus(item: item, itemId: itemId)
                }
            } catch PlaidError.credentialsNotConfigured {
                // Setup state affects every item identically: surface the 503
                // credential guidance instead of marking items errored.
                throw PlaidError.credentialsNotConfigured
            }
        }
    }

    /// Performs one item's sync and records the resulting connection status.
    /// Runs through the per-item coalescing gate so concurrent callers for the
    /// same item share a single execution.
    private func syncItemRecordingStatus(item: ItemModel, itemId: String) async throws -> ItemSyncResult {
        do {
            let accessToken = try tokenStore.accessToken(for: item)
            let itemResult = try await syncItem(
                itemId: itemId,
                accessToken: accessToken,
                persistedCursor: try await tokenStore.getSyncCursor(itemId: itemId)
            )
            try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
            return ItemSyncResult(
                itemId: itemId,
                attempted: true,
                succeeded: true,
                added: itemResult.added,
                modified: itemResult.modified,
                removed: itemResult.removed,
                hasMore: false,
                nextCursor: itemResult.nextCursor
            )
        } catch PlaidError.credentialsNotConfigured {
            // Setup state affects every item identically: surface the 503
            // credential guidance instead of marking items errored.
            throw PlaidError.credentialsNotConfigured
        } catch {
            try await tokenStore.updateItemStatus(
                id: itemId,
                status: ItemStatusMapping.status(forAPIError: error).rawValue
            )
            return ItemSyncResult(
                itemId: itemId,
                attempted: true,
                succeeded: false,
                added: [],
                modified: [],
                removed: [],
                hasMore: false,
                nextCursor: nil
            )
        }
    }

    private func syncItem(
        itemId: String,
        accessToken: String,
        persistedCursor: String?
    ) async throws -> (added: [TransactionDTO], modified: [TransactionDTO], removed: [String], nextCursor: String?) {
        var mutationRestartCount = 0

        while true {
            do {
                return try await syncItemPageSequence(
                    itemId: itemId,
                    accessToken: accessToken,
                    persistedCursor: persistedCursor
                )
            } catch let error as PlaidError where Self.isTransactionsSyncMutationDuringPagination(error) {
                mutationRestartCount += 1
                guard mutationRestartCount <= PlaidBarConstants.maxTransactionSyncMutationRestarts else {
                    throw error
                }
                continue
            }
        }
    }

    private func syncItemPageSequence(
        itemId: String,
        accessToken: String,
        persistedCursor: String?
    ) async throws -> (added: [TransactionDTO], modified: [TransactionDTO], removed: [String], nextCursor: String?) {
        var cursor = persistedCursor
        var pageCount = 0
        var added: [TransactionDTO] = []
        var modified: [TransactionDTO] = []
        var removed: [String] = []
        var finalCursor: String?

        while true {
            pageCount += 1
            guard pageCount <= PlaidBarConstants.maxTransactionSyncPages else {
                throw HTTPError(
                    .badGateway,
                    message: "Plaid transaction sync did not finish after \(PlaidBarConstants.maxTransactionSyncPages) pages"
                )
            }

            let response = try await plaidClient.syncTransactions(
                accessToken: accessToken,
                cursor: cursor
            )

            added.append(contentsOf: response.added.map { Self.toDTO($0, itemId: itemId) })
            modified.append(contentsOf: response.modified.map { Self.toDTO($0, itemId: itemId) })
            removed.append(contentsOf: response.removed.map(\.transactionId))

            if !response.nextCursor.isEmpty {
                cursor = response.nextCursor
                finalCursor = response.nextCursor
            }

            guard response.hasMore else {
                return (added, modified, removed, finalCursor)
            }
        }
    }

    private static func isTransactionsSyncMutationDuringPagination(_ error: PlaidError) -> Bool {
        guard case PlaidError.apiError(_, _, let errorCode, _) = error else { return false }
        return errorCode == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION"
    }

    private static func toDTO(_ plaidTx: PlaidTransaction, itemId: String) -> TransactionDTO {
        let category: SpendingCategory? = plaidTx.personalFinanceCategory.flatMap {
            SpendingCategory(rawValue: $0.primary)
        }

        return TransactionDTO(
            id: plaidTx.transactionId,
            itemId: itemId,
            accountId: plaidTx.accountId,
            amount: plaidTx.amount,
            date: plaidTx.date,
            name: plaidTx.name,
            merchantName: plaidTx.merchantName,
            category: category,
            pending: plaidTx.pending,
            pendingTransactionId: plaidTx.pendingTransactionId,
            isoCurrencyCode: plaidTx.isoCurrencyCode,
            isLowConfidenceCategory: Self.isLowConfidence(plaidTx.personalFinanceCategory?.confidenceLevel),
            logoURL: plaidTx.logoUrl
        )
    }

    /// Maps Plaid PFCv2 `confidence_level` to the app-owned low-confidence flag,
    /// keeping the raw Plaid enum string inside the server.
    private static func isLowConfidence(_ confidenceLevel: String?) -> Bool {
        switch confidenceLevel?.uppercased() {
        case "LOW", "UNKNOWN": return true
        default: return false
        }
    }
}
