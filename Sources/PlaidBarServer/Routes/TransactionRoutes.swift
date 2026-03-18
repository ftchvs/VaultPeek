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

        for item in items {
            guard let itemId = item.id else { continue }

            let cursor = try await tokenStore.getSyncCursor(itemId: itemId)
            let response = try await plaidClient.syncTransactions(
                accessToken: item.accessToken,
                cursor: cursor
            )

            allAdded.append(contentsOf: response.added.map { Self.toDTO($0) })
            allModified.append(contentsOf: response.modified.map { Self.toDTO($0) })
            allRemoved.append(contentsOf: response.removed.map(\.transactionId))

            if !response.nextCursor.isEmpty {
                try await tokenStore.saveSyncCursor(
                    itemId: itemId,
                    cursor: response.nextCursor
                )
                latestCursor = response.nextCursor
            }

            if response.hasMore {
                hasMore = true
            }
        }

        let syncResponse = SyncResponse(
            added: allAdded,
            modified: allModified,
            removed: allRemoved,
            hasMore: hasMore,
            nextCursor: latestCursor
        )

        let data = try JSONEncoder().encode(syncResponse)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    // MARK: - Helpers

    private static func toDTO(_ plaidTx: PlaidTransaction) -> TransactionDTO {
        let category: SpendingCategory? = plaidTx.personalFinanceCategory.flatMap {
            SpendingCategory(rawValue: $0.primary)
        }

        return TransactionDTO(
            id: plaidTx.transactionId,
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
}
