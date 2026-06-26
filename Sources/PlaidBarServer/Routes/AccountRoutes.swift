import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct AccountRoutes: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    var maxConcurrentItemRefreshes = Self.defaultMaxConcurrentItemRefreshes

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("accounts")
            .get(use: listAccounts)
            .get("balances", use: getBalances)
            .get("liabilities", use: listLiabilities)
            .delete("{itemId}", use: removeItem)
    }

    @Sendable
    func listAccounts(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = Self.deterministicItems(try await tokenStore.getAllItems())
        let results = try await refreshAccounts(items: items) { accessToken in
            try await plaidClient.getAccounts(accessToken: accessToken)
        }
        let attemptedItemCount = results.filter(\.attempted).count
        let successfulItemCount = results.filter(\.succeeded).count

        if Self.shouldFailRefresh(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid account refresh failed for every linked item")
        }

        return try Self.jsonResponse(results.flatMap(\.accounts))
    }

    @Sendable
    func getBalances(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = Self.deterministicItems(try await tokenStore.getAllItems())
        let results = try await refreshAccounts(items: items) { accessToken in
            try await plaidClient.getBalances(accessToken: accessToken)
        }
        let attemptedItemCount = results.filter(\.attempted).count
        let successfulItemCount = results.filter(\.succeeded).count

        if Self.shouldFailRefresh(attemptedItemCount: attemptedItemCount, successfulItemCount: successfulItemCount) {
            throw HTTPError(.badGateway, message: "Plaid balance refresh failed for every linked item")
        }

        return try Self.jsonResponse(results.flatMap(\.accounts))
    }

    /// Per-card liabilities (purchase APR, statement balance, minimum payment,
    /// next due date) from Plaid `/liabilities/get`. Best-effort: items linked
    /// without the `liabilities` product (the new-links-only rollout) return a
    /// Plaid product error, which we swallow per item and treat as "no
    /// liabilities" so the card keeps its honest utilization-only view. A scope
    /// gap never fails the whole request.
    @Sendable
    func listLiabilities(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = Self.deterministicItems(try await tokenStore.getAllItems())
        let perItem = try await BoundedConcurrency.map(items, limit: maxConcurrentItemRefreshes) { item -> [LiabilityDTO] in
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                let response = try await plaidClient.getLiabilities(accessToken: accessToken)
                return (response.liabilities?.credit ?? []).compactMap(Self.liabilityDTO(from:))
            } catch {
                return []
            }
        }
        return try Self.jsonResponse(perItem.flatMap { $0 })
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
            } catch PlaidError.credentialsNotConfigured {
                // Revocation cannot run in setup state; keep the local item
                // untouched and surface the 503 credential guidance.
                throw PlaidError.credentialsNotConfigured
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

    static var defaultMaxConcurrentItemRefreshes: Int {
        let rawValue = ProcessInfo.processInfo.environment["PLAIDBAR_MAX_CONCURRENT_ITEM_REFRESHES"]
        return rawValue.flatMap(Int.init).map { max(1, $0) } ?? 4
    }

    // MARK: - Helpers

    private struct AccountRefreshResult: Sendable {
        let attempted: Bool
        let succeeded: Bool
        let accounts: [AccountDTO]

        static let skipped = AccountRefreshResult(attempted: false, succeeded: false, accounts: [])
    }

    private func refreshAccounts(
        items: [ItemModel],
        fetch: @escaping @Sendable (String) async throws -> PlaidAccountsResponse
    ) async throws -> [AccountRefreshResult] {
        try await BoundedConcurrency.map(items, limit: maxConcurrentItemRefreshes) { item in
            guard let itemId = item.id else { return .skipped }

            do {
                let accessToken = try tokenStore.accessToken(for: item)
                let response = try await fetch(accessToken)
                try await tokenStore.updateItemStatus(id: itemId, status: ItemConnectionStatus.connected.rawValue)
                return AccountRefreshResult(
                    attempted: true,
                    succeeded: true,
                    accounts: Self.accountDTOs(from: response, item: item, itemId: itemId)
                )
            } catch PlaidError.credentialsNotConfigured {
                // Setup state affects every item identically: surface the 503
                // credential guidance instead of marking items errored and
                // reporting a misleading per-item refresh failure.
                throw PlaidError.credentialsNotConfigured
            } catch {
                try await tokenStore.updateItemStatus(id: itemId, forAPIError: error)
                return AccountRefreshResult(attempted: true, succeeded: false, accounts: [])
            }
        }
    }

    private static func accountDTOs(
        from response: PlaidAccountsResponse,
        item: ItemModel,
        itemId: String
    ) -> [AccountDTO] {
        response.accounts.map { account in
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
                    // Plaid sets exactly one of iso/unofficial. Prefer the ISO
                    // code; fall back to the unofficial code (crypto, points,
                    // some neobanks) so non-ISO balances still carry a native
                    // currency identity for multi-currency display (AND-643).
                    isoCurrencyCode: account.balances.isoCurrencyCode
                        ?? account.balances.unofficialCurrencyCode
                ),
                institutionName: item.institutionName
            )
        }
    }

    /// Reduces a Plaid credit liability to the fields VaultPeek surfaces,
    /// pulling the purchase APR out of the `aprs` array (which may be empty
    /// when the issuer does not report APR).
    private static func liabilityDTO(from credit: PlaidCreditLiability) -> LiabilityDTO? {
        guard let accountId = credit.accountId else { return nil }
        let purchaseApr = credit.aprs?.first { $0.aprType == "purchase_apr" }?.aprPercentage
        return LiabilityDTO(
            accountId: accountId,
            purchaseAprPercentage: purchaseApr,
            nextPaymentDueDate: credit.nextPaymentDueDate,
            // Plaid's `is_overdue` is nullable / limited-availability; when it is
            // absent, infer overdue from a due date already in the past so a
            // past-due card still carries the "Overdue" wording.
            isOverdue: credit.isOverdue ?? Self.isPastDue(credit.nextPaymentDueDate)
        )
    }

    private static func isPastDue(_ yyyymmdd: String?) -> Bool {
        guard let yyyymmdd else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let due = formatter.date(from: yyyymmdd) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    static func deterministicItems(_ items: [ItemModel]) -> [ItemModel] {
        items.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return (lhs.id ?? "") < (rhs.id ?? "")
            }
        }
    }

    private static func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
        let data = try JSONEncoder().encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

}
