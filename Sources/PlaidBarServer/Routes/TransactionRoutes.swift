import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct TransactionRoutes: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    var maxConcurrentItemRefreshes = AccountRoutes.defaultMaxConcurrentItemRefreshes

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
            nextCursor: successfulResults.last(where: { ($0.nextCursor?.isEmpty == false) })?.nextCursor,
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
            guard try await tokenStore.getItem(id: itemId) != nil else {
                throw HTTPError(.badRequest, message: "Cannot commit cursor for unknown item")
            }
            try await tokenStore.saveSyncCursor(itemId: itemId, cursor: committableCursor)
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

            do {
                let cursor = try await tokenStore.getSyncCursor(itemId: itemId)
                let accessToken = try tokenStore.accessToken(for: item)
                let response = try await plaidClient.syncTransactions(
                    accessToken: accessToken,
                    cursor: cursor
                )
                try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
                return ItemSyncResult(
                    itemId: itemId,
                    attempted: true,
                    succeeded: true,
                    added: response.added.map { Self.toDTO($0, itemId: itemId) },
                    modified: response.modified.map { Self.toDTO($0, itemId: itemId) },
                    removed: response.removed.map(\.transactionId),
                    hasMore: response.hasMore,
                    nextCursor: response.nextCursor.isEmpty ? nil : response.nextCursor
                )
            } catch PlaidError.credentialsNotConfigured {
                // Setup state affects every item identically: surface the 503
                // credential guidance instead of marking items errored.
                throw PlaidError.credentialsNotConfigured
            } catch {
                try await tokenStore.updateItemStatus(id: itemId, status: itemStatus(for: error).rawValue)
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
            isoCurrencyCode: plaidTx.isoCurrencyCode
        )
    }

    private func itemStatus(for error: Error) -> ItemConnectionStatus {
        if case PlaidError.apiError(_, _, let errorCode, _) = error,
           errorCode == "ITEM_LOGIN_REQUIRED" {
            return .loginRequired
        }
        return .error
    }
}
