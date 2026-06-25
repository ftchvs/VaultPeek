import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

/// Plaid Investments endpoints (AND-644): holdings + securities and investment
/// transactions. Modeled on ``AccountRoutes`` — the server owns the Plaid
/// access token and only ever ships reduced, secret-free DTOs to the app.
///
/// Both handlers are best-effort per item: an item linked without the
/// `investments` product (most existing links) returns a Plaid product error,
/// which we swallow per item and treat as "no holdings" so a scope gap never
/// fails the whole request. Items *with* the product contribute their holdings.
struct InvestmentRoutes: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    var maxConcurrentItemRefreshes = AccountRoutes.defaultMaxConcurrentItemRefreshes
    var investmentTransactionLookbackDays = 90

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("investments")
            .get("holdings", use: getHoldings)
            .get("transactions", use: getInvestmentTransactions)
    }

    @Sendable
    func getHoldings(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = AccountRoutes.deterministicItems(try await tokenStore.getAllItems())
        let perItem = try await BoundedConcurrency.map(items, limit: maxConcurrentItemRefreshes) { item -> InvestmentsResponse in
            do {
                guard let itemId = item.id else { return InvestmentsResponse() }
                let accessToken = try tokenStore.accessToken(for: item)
                let response = try await plaidClient.getInvestmentHoldings(accessToken: accessToken)
                return Self.investmentsResponse(from: response, item: item, itemId: itemId)
            } catch {
                // A missing `investments` scope (or any per-item failure) yields
                // an empty contribution; the request still succeeds for items
                // that do hold investments.
                return InvestmentsResponse()
            }
        }
        return try Self.jsonResponse(Self.merge(perItem))
    }

    @Sendable
    func getInvestmentTransactions(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let (startDate, endDate) = Self.lookbackWindow(days: investmentTransactionLookbackDays)
        let items = AccountRoutes.deterministicItems(try await tokenStore.getAllItems())
        let perItem = try await BoundedConcurrency.map(items, limit: maxConcurrentItemRefreshes) { item -> [InvestmentTransactionDTO] in
            do {
                let accessToken = try tokenStore.accessToken(for: item)
                let transactions = try await Self.paginatedInvestmentTransactions(
                    plaidClient: plaidClient,
                    accessToken: accessToken,
                    startDate: startDate,
                    endDate: endDate
                )
                return transactions.map(Self.investmentTransactionDTO(from:))
            } catch {
                return []
            }
        }
        return try Self.jsonResponse(perItem.flatMap { $0 })
    }

    // MARK: - Mapping

    static let investmentTransactionsPageSize = 250

    static func paginatedInvestmentTransactions(
        plaidClient: any PlaidClientProtocol,
        accessToken: String,
        startDate: String,
        endDate: String,
        pageSize: Int = investmentTransactionsPageSize
    ) async throws -> [PlaidInvestmentTransaction] {
        let count = max(1, pageSize)
        var offset = 0
        var transactions: [PlaidInvestmentTransaction] = []

        while true {
            let response = try await plaidClient.getInvestmentTransactions(
                accessToken: accessToken,
                startDate: startDate,
                endDate: endDate,
                count: count,
                offset: offset
            )
            transactions.append(contentsOf: response.investmentTransactions)

            if let total = response.totalInvestmentTransactions {
                if transactions.count >= total || response.investmentTransactions.isEmpty {
                    return transactions
                }
            } else if response.investmentTransactions.count < count {
                return transactions
            }

            offset += response.investmentTransactions.count
        }
    }

    // MARK: - Mapping

    /// Reduces a Plaid holdings response to the shared, secret-free
    /// ``InvestmentsResponse`` — investment accounts as ``AccountDTO`` (so they
    /// fold into net worth), holdings, and the joined securities.
    static func investmentsResponse(
        from response: PlaidHoldingsResponse,
        item: ItemModel,
        itemId: String
    ) -> InvestmentsResponse {
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
        let holdings = response.holdings.map { holding in
            HoldingDTO(
                accountId: holding.accountId,
                securityId: holding.securityId,
                quantity: holding.quantity,
                institutionPrice: holding.institutionPrice,
                institutionValue: holding.institutionValue,
                costBasis: holding.costBasis,
                isoCurrencyCode: holding.isoCurrencyCode
            )
        }
        let securities = response.securities.map { security in
            SecurityDTO(
                id: security.securityId,
                name: security.name,
                tickerSymbol: security.tickerSymbol,
                type: security.type,
                closePrice: security.closePrice,
                isoCurrencyCode: security.isoCurrencyCode
            )
        }
        return InvestmentsResponse(accounts: accounts, holdings: holdings, securities: securities)
    }

    static func investmentTransactionDTO(from plaid: PlaidInvestmentTransaction) -> InvestmentTransactionDTO {
        InvestmentTransactionDTO(
            id: plaid.investmentTransactionId,
            accountId: plaid.accountId,
            securityId: plaid.securityId,
            date: plaid.date,
            name: plaid.name,
            quantity: plaid.quantity,
            price: plaid.price,
            amount: plaid.amount,
            fees: plaid.fees,
            type: plaid.type,
            subtype: plaid.subtype,
            isoCurrencyCode: plaid.isoCurrencyCode
        )
    }

    /// Flattens per-item responses into one, de-duplicating accounts and
    /// securities by id (the same security can appear across items).
    static func merge(_ responses: [InvestmentsResponse]) -> InvestmentsResponse {
        var accounts: [AccountDTO] = []
        var seenAccountIds = Set<String>()
        var securities: [SecurityDTO] = []
        var seenSecurityIds = Set<String>()
        var holdings: [HoldingDTO] = []

        for response in responses {
            for account in response.accounts where seenAccountIds.insert(account.id).inserted {
                accounts.append(account)
            }
            for security in response.securities where seenSecurityIds.insert(security.id).inserted {
                securities.append(security)
            }
            holdings.append(contentsOf: response.holdings)
        }
        return InvestmentsResponse(accounts: accounts, holdings: holdings, securities: securities)
    }

    /// `(startDate, endDate)` `YYYY-MM-DD` strings for the lookback window,
    /// computed in the gregorian/POSIX calendar so it is locale-stable.
    static func lookbackWindow(days: Int, now: Date = Date()) -> (String, String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let end = now
        let start = calendar.date(byAdding: .day, value: -max(1, days), to: end) ?? end
        return (formatter.string(from: start), formatter.string(from: end))
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
