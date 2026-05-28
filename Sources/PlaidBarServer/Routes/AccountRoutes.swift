import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct AccountRoutes: Sendable {
    let plaidClient: PlaidClient
    let tokenStore: TokenStore

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("accounts")
            .get(use: listAccounts)
            .get("balances", use: getBalances)
            .delete("{itemId}", use: removeItem)
    }

    @Sendable
    func listAccounts(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = try await tokenStore.getAllItems()
        var allAccounts: [AccountDTO] = []
        var attemptedItemCount = 0
        var successfulItemCount = 0

        for item in items {
            guard let itemId = item.id else { continue }
            attemptedItemCount += 1

            let response: PlaidAccountsResponse
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                response = try await plaidClient.getAccounts(
                    accessToken: accessToken
                )
                try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
                successfulItemCount += 1
            } catch {
                try await tokenStore.updateItemStatus(id: itemId, status: itemStatus(for: error).rawValue)
                continue
            }

            let accounts = response.accounts.map { account in
                AccountDTO(
                    id: account.accountId,
                    itemId: itemId,
                    name: account.name,
                    officialName: account.officialName,
                    type: AccountType(rawValue: account.type) ?? .other,
                    subtype: account.subtype,
                    mask: account.mask,
                    balances: BalanceDTO(
                        available: account.balances.available,
                        current: account.balances.current,
                        limit: account.balances.limit,
                        isoCurrencyCode: account.balances.isoCurrencyCode
                    ),
                    institutionName: item.institutionName
                )
            }
            allAccounts.append(contentsOf: accounts)
        }

        if Self.shouldFailRefresh(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid account refresh failed for every linked item")
        }

        return try Self.jsonResponse(allAccounts)
    }

    @Sendable
    func getBalances(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = try await tokenStore.getAllItems()
        var allAccounts: [AccountDTO] = []
        var attemptedItemCount = 0
        var successfulItemCount = 0

        for item in items {
            guard let itemId = item.id else { continue }
            attemptedItemCount += 1

            let response: PlaidAccountsResponse
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                response = try await plaidClient.getBalances(
                    accessToken: accessToken
                )
                try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
                successfulItemCount += 1
            } catch {
                try await tokenStore.updateItemStatus(id: itemId, status: itemStatus(for: error).rawValue)
                continue
            }

            let accounts = response.accounts.map { account in
                AccountDTO(
                    id: account.accountId,
                    itemId: itemId,
                    name: account.name,
                    officialName: account.officialName,
                    type: AccountType(rawValue: account.type) ?? .other,
                    subtype: account.subtype,
                    mask: account.mask,
                    balances: BalanceDTO(
                        available: account.balances.available,
                        current: account.balances.current,
                        limit: account.balances.limit,
                        isoCurrencyCode: account.balances.isoCurrencyCode
                    ),
                    institutionName: item.institutionName
                )
            }
            allAccounts.append(contentsOf: accounts)
        }

        if Self.shouldFailRefresh(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid balance refresh failed for every linked item")
        }

        return try Self.jsonResponse(allAccounts)
    }

    @Sendable
    func removeItem(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        guard let itemId = context.parameters.get("itemId") else {
            throw HTTPError(.badRequest, message: "Missing itemId parameter")
        }

        // Remove from Plaid first so a failed revocation keeps the local token
        // available for retry instead of leaving an orphaned Plaid Item active.
        if let item = try await tokenStore.getItem(id: itemId) {
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                try await plaidClient.removeItem(accessToken: accessToken)
            } catch {
                guard Self.canDeleteLocalItemAfterPlaidRemoveError(error) else {
                    try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.error.rawValue)
                    throw HTTPError(.badGateway, message: "Plaid item removal failed; local item was kept for retry")
                }
            }
        }

        // Remove from local storage
        try await tokenStore.deleteItem(id: itemId)

        return Response(status: .noContent)
    }

    static func canDeleteLocalItemAfterPlaidRemoveError(_ error: Error) -> Bool {
        if case PlaidError.apiError(_, _, let errorCode, _) = error {
            return errorCode == "INVALID_ACCESS_TOKEN"
                || errorCode == "ITEM_NOT_FOUND"
                || errorCode == "ITEM_NOT_ACCESSIBLE"
        }
        return false
    }

    static func shouldFailRefresh(attemptedItemCount: Int, successfulItemCount: Int) -> Bool {
        attemptedItemCount > 0 && successfulItemCount == 0
    }

    // MARK: - Helpers

    private static func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
        let data = try JSONEncoder().encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
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
