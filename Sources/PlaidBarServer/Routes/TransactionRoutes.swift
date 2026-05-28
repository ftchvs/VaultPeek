import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct TransactionRoutes: Sendable {
    let plaidClient: PlaidClient
    let tokenStore: TokenStore

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
                items = []
            }
        } else {
            items = try await tokenStore.getAllItems()
        }

        var allAdded: [TransactionDTO] = []
        var allModified: [TransactionDTO] = []
        var allRemoved: [String] = []
        var hasMore = false
        var latestCursor: String?
        var pendingCursors: [String: String] = [:]
        var attemptedItemCount = 0
        var successfulItemCount = 0

        for item in items {
            guard let itemId = item.id else { continue }
            attemptedItemCount += 1

            let cursor = try await tokenStore.getSyncCursor(itemId: itemId)
            let response: PlaidTransactionsSyncResponse
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                response = try await plaidClient.syncTransactions(
                    accessToken: accessToken,
                    cursor: cursor
                )
                try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
                successfulItemCount += 1
            } catch {
                try await tokenStore.updateItemStatus(id: itemId, status: itemStatus(for: error).rawValue)
                continue
            }

            allAdded.append(contentsOf: response.added.map { Self.toDTO($0, itemId: itemId) })
            allModified.append(contentsOf: response.modified.map { Self.toDTO($0, itemId: itemId) })
            allRemoved.append(contentsOf: response.removed.map(\.transactionId))

            if !response.nextCursor.isEmpty {
                latestCursor = response.nextCursor
                pendingCursors[itemId] = response.nextCursor
            }

            if response.hasMore {
                hasMore = true
            }
        }

        if Self.shouldFailSync(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid transaction sync failed for every linked item")
        }

        let syncResponse = SyncResponse(
            added: allAdded,
            modified: allModified,
            removed: allRemoved,
            hasMore: hasMore,
            nextCursor: latestCursor,
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
            let trimmedCursor = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCursor.isEmpty else { continue }
            guard try await tokenStore.getItem(id: itemId) != nil else {
                throw HTTPError(.badRequest, message: "Cannot commit cursor for unknown item")
            }
            try await tokenStore.saveSyncCursor(itemId: itemId, cursor: trimmedCursor)
        }
        return .ok
    }

    // MARK: - Helpers

    static func shouldFailSync(attemptedItemCount: Int, successfulItemCount: Int) -> Bool {
        attemptedItemCount > 0 && successfulItemCount == 0
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
