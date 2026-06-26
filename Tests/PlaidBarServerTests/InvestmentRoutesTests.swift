import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdTesting
import Logging
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

/// Unit tests for the pure, static mapping helpers in ``InvestmentRoutes``
/// (AND-644). These exercise the Plaid → shared-DTO reduction and the per-item
/// merge without standing up a full Hummingbird app, mirroring how the
/// account/liability mapping is validated.
@Suite("Investment routes mapping")
struct InvestmentRoutesTests {
    private actor PaginatedInvestmentPlaidClient: PlaidClientProtocol {
        private var responses: [PlaidInvestmentTransactionsResponse]
        private var calls: [(count: Int, offset: Int)] = []

        init(responses: [PlaidInvestmentTransactionsResponse]) {
            self.responses = responses
        }

        func createLinkToken(
            clientUserId _: String,
            completionRedirectUri _: String
        ) async throws -> PlaidLinkTokenResponse {
            throw PlaidError.invalidResponse
        }

        func createUpdateLinkToken(
            clientUserId _: String,
            accessToken _: String,
            completionRedirectUri _: String
        ) async throws -> PlaidLinkTokenResponse {
            throw PlaidError.invalidResponse
        }

        func getLinkToken(_: String) async throws -> PlaidLinkTokenGetResponse {
            throw PlaidError.invalidResponse
        }

        func exchangePublicToken(_: String) async throws -> PlaidTokenExchangeResponse {
            throw PlaidError.invalidResponse
        }

        func getAccounts(accessToken _: String) async throws -> PlaidAccountsResponse {
            throw PlaidError.invalidResponse
        }

        func getBalances(accessToken _: String) async throws -> PlaidAccountsResponse {
            throw PlaidError.invalidResponse
        }

        func getInvestmentTransactions(
            accessToken _: String,
            startDate _: String,
            endDate _: String,
            count: Int,
            offset: Int
        ) async throws -> PlaidInvestmentTransactionsResponse {
            calls.append((count: count, offset: offset))
            guard !responses.isEmpty else { throw PlaidError.invalidResponse }
            return responses.removeFirst()
        }

        func syncTransactions(
            accessToken _: String,
            cursor _: String?
        ) async throws -> PlaidTransactionsSyncResponse {
            throw PlaidError.invalidResponse
        }

        func removeItem(accessToken _: String) async throws {
            throw PlaidError.invalidResponse
        }

        func recordedCalls() -> [(count: Int, offset: Int)] {
            calls
        }
    }

    private func item(id: String = "item-1") -> ItemModel {
        ItemModel(id: id, accessToken: "keychain:\(id)", institutionName: "Fidelity")
    }

    private func holdingsResponse() -> PlaidHoldingsResponse {
        PlaidHoldingsResponse(
            accounts: [
                PlaidAccount(
                    accountId: "acct_a",
                    balances: PlaidBalances(available: 42_500, current: 42_500, limit: nil, isoCurrencyCode: "USD", unofficialCurrencyCode: nil),
                    mask: "5520",
                    name: "Fidelity Brokerage",
                    officialName: "Fidelity Individual Brokerage",
                    type: "investment",
                    subtype: "brokerage"
                ),
            ],
            holdings: [
                PlaidHolding(accountId: "acct_a", securityId: "sec_vti", quantity: 90, institutionPrice: 250, institutionValue: 22_500, costBasis: 18_000, isoCurrencyCode: "USD"),
                PlaidHolding(accountId: "acct_a", securityId: "sec_cash", quantity: 2_800, institutionPrice: 1, institutionValue: 2_800, costBasis: 2_800, isoCurrencyCode: "USD"),
            ],
            securities: [
                PlaidSecurity(securityId: "sec_vti", name: "Vanguard Total Market ETF", tickerSymbol: "VTI", type: "etf", closePrice: 250, isoCurrencyCode: "USD"),
                PlaidSecurity(securityId: "sec_cash", name: "Cash Sweep", tickerSymbol: nil, type: "cash", closePrice: 1, isoCurrencyCode: "USD"),
            ],
            item: nil,
            requestId: "req-1"
        )
    }

    @Test("Maps a Plaid holdings response to secret-free shared DTOs")
    func mapsHoldingsResponse() {
        let result = InvestmentRoutes.investmentsResponse(
            from: holdingsResponse(),
            item: item(),
            itemId: "item-1"
        )

        #expect(result.accounts.count == 1)
        let account = try! #require(result.accounts.first)
        #expect(account.id == "acct_a")
        #expect(account.itemId == "item-1")
        #expect(account.type == .investment)
        #expect(account.institutionName == "Fidelity")
        #expect(account.balances.current == 42_500)

        #expect(result.holdings.count == 2)
        let vti = try! #require(result.holdings.first { $0.securityId == "sec_vti" })
        #expect(vti.accountId == "acct_a")
        #expect(vti.marketValue == 22_500)
        #expect(vti.unrealizedGain == 4_500)

        #expect(result.securities.count == 2)
        #expect(result.securities.contains { $0.tickerSymbol == "VTI" })
    }

    @Test("An unknown Plaid account type maps to .other rather than crashing")
    func unknownAccountTypeFallsBack() {
        var response = holdingsResponse()
        response = PlaidHoldingsResponse(
            accounts: [
                PlaidAccount(
                    accountId: "acct_x",
                    balances: PlaidBalances(available: nil, current: 1, limit: nil, isoCurrencyCode: "USD", unofficialCurrencyCode: nil),
                    mask: nil, name: "Mystery", officialName: nil, type: "totally_new_type", subtype: nil
                ),
            ],
            holdings: [], securities: [], item: nil, requestId: nil
        )
        let result = InvestmentRoutes.investmentsResponse(from: response, item: item(), itemId: "item-1")
        #expect(result.accounts.first?.type == .other)
    }

    private func investmentTransaction(id: String) -> PlaidInvestmentTransaction {
        PlaidInvestmentTransaction(
            investmentTransactionId: id,
            accountId: "acct_a",
            securityId: "sec_vti",
            date: "2026-06-01",
            name: "Buy VTI",
            quantity: 10,
            price: 250,
            amount: 2_500,
            fees: 0,
            type: "buy",
            subtype: "buy",
            isoCurrencyCode: "USD"
        )
    }

    private func investmentTransactionsResponse(
        ids: [String],
        total: Int?
    ) -> PlaidInvestmentTransactionsResponse {
        PlaidInvestmentTransactionsResponse(
            accounts: [],
            securities: [],
            investmentTransactions: ids.map(investmentTransaction(id:)),
            totalInvestmentTransactions: total,
            item: nil,
            requestId: nil
        )
    }

    @Test("Investment transactions page until the Plaid total is satisfied")
    func paginatesInvestmentTransactionsUntilTotalIsSatisfied() async throws {
        let client = PaginatedInvestmentPlaidClient(responses: [
            investmentTransactionsResponse(ids: ["itx-1", "itx-2"], total: 3),
            investmentTransactionsResponse(ids: ["itx-3"], total: 3),
        ])

        let transactions = try await InvestmentRoutes.paginatedInvestmentTransactions(
            plaidClient: client,
            accessToken: "keychain:item-1",
            startDate: "2026-03-26",
            endDate: "2026-06-24",
            pageSize: 2
        )

        #expect(transactions.map(\.investmentTransactionId) == ["itx-1", "itx-2", "itx-3"])
        #expect(await client.recordedCalls().map(\.offset) == [0, 2])
        #expect(await client.recordedCalls().map(\.count) == [2, 2])
    }

    @Test("Investment transaction pagination stops on a short page when Plaid omits total")
    func paginatesInvestmentTransactionsWithoutTotalUntilShortPage() async throws {
        let client = PaginatedInvestmentPlaidClient(responses: [
            investmentTransactionsResponse(ids: ["itx-1", "itx-2"], total: nil),
            investmentTransactionsResponse(ids: ["itx-3"], total: nil),
        ])

        let transactions = try await InvestmentRoutes.paginatedInvestmentTransactions(
            plaidClient: client,
            accessToken: "keychain:item-1",
            startDate: "2026-03-26",
            endDate: "2026-06-24",
            pageSize: 2
        )

        #expect(transactions.map(\.investmentTransactionId) == ["itx-1", "itx-2", "itx-3"])
        #expect(await client.recordedCalls().map(\.offset) == [0, 2])
    }

    @Test("Investment transaction mapping carries the security, amount, and type")
    func mapsInvestmentTransaction() {
        let plaid = PlaidInvestmentTransaction(
            investmentTransactionId: "itx-1",
            accountId: "acct_a",
            securityId: "sec_vti",
            date: "2026-06-01",
            name: "Buy VTI",
            quantity: 10,
            price: 250,
            amount: 2_500,
            fees: 0,
            type: "buy",
            subtype: "buy",
            isoCurrencyCode: "USD"
        )
        let dto = InvestmentRoutes.investmentTransactionDTO(from: plaid)
        #expect(dto.id == "itx-1")
        #expect(dto.securityId == "sec_vti")
        #expect(dto.amount == 2_500)
        #expect(dto.type == "buy")
    }

    @Test("Merge de-duplicates accounts and securities by id across items")
    func mergeDeduplicates() {
        let a = InvestmentsResponse(
            accounts: [AccountDTO(id: "acct_a", itemId: "item-1", name: "A", type: .investment, balances: BalanceDTO(current: 1))],
            holdings: [HoldingDTO(accountId: "acct_a", securityId: "sec_shared", quantity: 1, institutionValue: 1)],
            securities: [SecurityDTO(id: "sec_shared", name: "Shared", tickerSymbol: "SHR")]
        )
        let b = InvestmentsResponse(
            accounts: [
                AccountDTO(id: "acct_a", itemId: "item-1", name: "A dup", type: .investment, balances: BalanceDTO(current: 1)),
                AccountDTO(id: "acct_b", itemId: "item-2", name: "B", type: .investment, balances: BalanceDTO(current: 2)),
            ],
            holdings: [HoldingDTO(accountId: "acct_b", securityId: "sec_shared", quantity: 2, institutionValue: 2)],
            securities: [SecurityDTO(id: "sec_shared", name: "Shared", tickerSymbol: "SHR")]
        )

        let merged = InvestmentRoutes.merge([a, b])
        #expect(merged.accounts.map(\.id) == ["acct_a", "acct_b"])
        #expect(merged.securities.count == 1)
        // Holdings are NOT de-duplicated — each is a distinct position.
        #expect(merged.holdings.count == 2)
    }

    @Test("Lookback window produces an ordered YYYY-MM-DD range of the requested length")
    func lookbackWindow() {
        let now = ISO8601DateFormatter().date(from: "2026-06-24T12:00:00Z")!
        let (start, end) = InvestmentRoutes.lookbackWindow(days: 90, now: now)
        #expect(end == "2026-06-24")
        #expect(start == "2026-03-26")
        #expect(start < end)
    }
}

/// Setup-state behavior for the Investments routes (AND-661, AND-644 follow-up).
///
/// With no Plaid credentials configured, holdings and investment transactions
/// must surface the setup-state `503` (so the app shows the credential-guidance
/// state) instead of a misleading empty-but-successful `200`. This mirrors how
/// `AccountRoutes` is gated: the `SetupStateMiddleware` prefix list blocks the
/// route before the handler runs, and — as a safety net for any item already
/// linked — the handler re-throws `PlaidError.credentialsNotConfigured` rather
/// than swallowing it into an empty contribution.
@Suite("Investment routes setup state")
struct InvestmentRoutesSetupStateTests {
    private let apiToken = "local-investments-token"

    /// A Plaid double whose investment calls fail as if credentials were never
    /// configured — the exact error the real `PlaidClient` throws in setup state.
    private struct CredentialLessPlaidClient: PlaidClientProtocol {
        func createLinkToken(clientUserId _: String, completionRedirectUri _: String) async throws -> PlaidLinkTokenResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func createUpdateLinkToken(clientUserId _: String, accessToken _: String, completionRedirectUri _: String) async throws -> PlaidLinkTokenResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func getLinkToken(_: String) async throws -> PlaidLinkTokenGetResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func exchangePublicToken(_: String) async throws -> PlaidTokenExchangeResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func getAccounts(accessToken _: String) async throws -> PlaidAccountsResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func getBalances(accessToken _: String) async throws -> PlaidAccountsResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func getInvestmentHoldings(accessToken _: String) async throws -> PlaidHoldingsResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func getInvestmentTransactions(accessToken _: String, startDate _: String, endDate _: String, count _: Int, offset _: Int) async throws -> PlaidInvestmentTransactionsResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func syncTransactions(accessToken _: String, cursor _: String?) async throws -> PlaidTransactionsSyncResponse {
            throw PlaidError.credentialsNotConfigured
        }

        func removeItem(accessToken _: String) async throws {
            throw PlaidError.credentialsNotConfigured
        }
    }

    private var authHeaders: HTTPFields {
        var headers = HTTPFields()
        headers[.authorization] = "Bearer \(apiToken)"
        return headers
    }

    /// Wires the real `SetupStateMiddleware` (in `missingBoth` setup state) and
    /// `InvestmentRoutes` behind the bearer-token middleware. `seedItem` controls
    /// whether a linked item exists, so we exercise both the prefix gating (no
    /// items: middleware blocks before the handler) and the handler re-throw
    /// (one item: the credential-less Plaid call is reached and must propagate).
    private func withInvestmentsAPI(
        seedItem: Bool,
        _ body: @Sendable (any TestClientProtocol) async throws -> Void
    ) async throws {
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.investments-setup")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.memory), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            if seedItem {
                // A direct (non-`keychain:`) token resolves without Keychain, so
                // `accessToken(for:)` succeeds and the credential-less Plaid call
                // is the failure under test, not token resolution.
                try await ItemModel(
                    id: "item-1",
                    accessToken: "plaintext-access-token",
                    institutionName: "Fidelity"
                ).save(on: fluent.db())
            }

            let router = Router()
            let api = router.group("api")
            api.add(middleware: APITokenMiddleware(authToken: apiToken))
            api.add(middleware: SetupStateMiddleware(
                credentialDiagnosis: .missingBoth,
                plaidEnvironment: .sandbox
            ))
            InvestmentRoutes(
                plaidClient: CredentialLessPlaidClient(),
                tokenStore: TokenStore(fluent: fluent)
            ).register(with: api)

            let app = Application(router: router, logger: logger)
            try await app.test(.router) { client in
                try await body(client)
            }
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError { throw bodyError }
    }

    @Test("Holdings returns 503 setup state (not 200-empty) when no items are linked")
    func holdingsGatedByMiddlewareWithoutItems() async throws {
        try await withInvestmentsAPI(seedItem: false) { client in
            let response = try await client.execute(
                uri: "/api/investments/holdings",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Investment transactions return 503 setup state (not 200-empty) when no items are linked")
    func transactionsGatedByMiddlewareWithoutItems() async throws {
        try await withInvestmentsAPI(seedItem: false) { client in
            let response = try await client.execute(
                uri: "/api/investments/transactions",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Holdings re-throws credentialsNotConfigured for a linked item instead of swallowing it into 200-empty")
    func holdingsRethrowsCredentialsNotConfiguredForLinkedItem() async throws {
        // With an item present the handler reaches the credential-less Plaid
        // call; the regression is swallowing the error into an empty 200. The
        // re-throw surfaces through the middleware catch-net as the setup 503.
        try await withInvestmentsAPI(seedItem: true) { client in
            let response = try await client.execute(
                uri: "/api/investments/holdings",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Investment transactions re-throw credentialsNotConfigured for a linked item instead of swallowing it into 200-empty")
    func transactionsRethrowCredentialsNotConfiguredForLinkedItem() async throws {
        try await withInvestmentsAPI(seedItem: true) { client in
            let response = try await client.execute(
                uri: "/api/investments/transactions",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }
}
