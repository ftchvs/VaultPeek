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

        for item in items {
            let response = try await plaidClient.getAccounts(
                accessToken: item.accessToken
            )
            let accounts = response.accounts.map { account in
                AccountDTO(
                    id: account.accountId,
                    itemId: item.id ?? "",
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

        return try Self.jsonResponse(allAccounts)
    }

    @Sendable
    func getBalances(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = try await tokenStore.getAllItems()
        var allAccounts: [AccountDTO] = []

        for item in items {
            let response = try await plaidClient.getBalances(
                accessToken: item.accessToken
            )
            let accounts = response.accounts.map { account in
                AccountDTO(
                    id: account.accountId,
                    itemId: item.id ?? "",
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

        // Remove from Plaid first
        if let item = try await tokenStore.getItem(id: itemId) {
            try? await plaidClient.removeItem(accessToken: item.accessToken)
        }

        // Remove from local storage
        try await tokenStore.deleteItem(id: itemId)

        return Response(status: .noContent)
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
}
