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

    @Test("Investment mapping preserves unofficial currencies when ISO is absent")
    func mapsUnofficialInvestmentCurrencies() {
        let response = PlaidHoldingsResponse(
            accounts: [
                PlaidAccount(
                    accountId: "acct_crypto",
                    balances: PlaidBalances(available: nil, current: 0.5, limit: nil, isoCurrencyCode: nil, unofficialCurrencyCode: "XBT"),
                    mask: nil,
                    name: "Crypto Brokerage",
                    officialName: nil,
                    type: "investment",
                    subtype: "crypto exchange"
                ),
            ],
            holdings: [
                PlaidHolding(accountId: "acct_crypto", securityId: "sec_btc", quantity: 0.5, institutionPrice: 60_000, institutionValue: 30_000, costBasis: 20_000, isoCurrencyCode: nil, unofficialCurrencyCode: "XBT"),
            ],
            securities: [
                PlaidSecurity(securityId: "sec_btc", name: "Bitcoin", tickerSymbol: "BTC", type: "cryptocurrency", closePrice: 60_000, isoCurrencyCode: nil, unofficialCurrencyCode: "XBT"),
            ],
            item: nil,
            requestId: "req-crypto"
        )

        let result = InvestmentRoutes.investmentsResponse(
            from: response,
            item: item(),
            itemId: "item-1"
        )

        #expect(result.accounts.first?.balances.isoCurrencyCode == "XBT")
        #expect(result.holdings.first?.isoCurrencyCode == "XBT")
        #expect(result.holdings.first?.currency == CurrencyCode("XBT"))
        #expect(result.securities.first?.isoCurrencyCode == "XBT")
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

    @Test("Investment transaction mapping preserves unofficial currency")
    func mapsInvestmentTransactionUnofficialCurrency() {
        let plaid = PlaidInvestmentTransaction(
            investmentTransactionId: "itx-crypto",
            accountId: "acct_crypto",
            securityId: "sec_btc",
            date: "2026-06-01",
            name: "Buy BTC",
            quantity: 0.1,
            price: 60_000,
            amount: 6_000,
            fees: nil,
            type: "buy",
            subtype: "buy",
            isoCurrencyCode: nil,
            unofficialCurrencyCode: "XBT"
        )

        let dto = InvestmentRoutes.investmentTransactionDTO(from: plaid)

        #expect(dto.isoCurrencyCode == "XBT")
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

    /// Wires the real `SetupStateMiddleware` and `InvestmentRoutes` behind the
    /// bearer-token middleware. `seedItem` controls whether a linked item
    /// exists; `credentialDiagnosis` controls whether the middleware's prefix
    /// gate short-circuits.
    ///
    /// With `.missingBoth` (the default) the prefix gate blocks `/api/investments`
    /// before the handler runs, so these tests exercise the *gating*. With
    /// `.configured` the gate passes through to the handler, so the request
    /// actually reaches the credential-less Plaid call — that is the only way to
    /// exercise the handler's `catch PlaidError.credentialsNotConfigured`
    /// re-throw and the middleware's *outer* catch-net that turns it into a 503.
    private func withInvestmentsAPI(
        seedItem: Bool,
        credentialDiagnosis: CredentialSetupDiagnosis = .missingBoth,
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
                credentialDiagnosis: credentialDiagnosis,
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

    @Test("Holdings stays 503 in setup state even when an item is already linked")
    func holdingsGatedByMiddlewareWithLinkedItem() async throws {
        // In `.missingBoth` the prefix gate short-circuits to 503 *before* the
        // handler runs, regardless of whether an item is linked. This guards
        // the prefix-gating only — it does NOT reach the handler re-throw (see
        // `holdingsRethrowsCredentialsNotConfiguredWhenCredentialsConfigured`).
        try await withInvestmentsAPI(seedItem: true) { client in
            let response = try await client.execute(
                uri: "/api/investments/holdings",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Investment transactions stay 503 in setup state even when an item is already linked")
    func transactionsGatedByMiddlewareWithLinkedItem() async throws {
        try await withInvestmentsAPI(seedItem: true) { client in
            let response = try await client.execute(
                uri: "/api/investments/transactions",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }

    // MARK: - Handler re-throw (true guard)
    //
    // The tests above all run with `.missingBoth`, so the prefix gate
    // short-circuits before the handler executes — reverting *only* the
    // handler's `catch PlaidError.credentialsNotConfigured` re-throw would leave
    // them green. The two tests below set `.configured` so the prefix gate is
    // bypassed and the request actually reaches the handler. With a linked item
    // and a Plaid double that throws `credentialsNotConfigured`, the only path
    // to a 503 is: handler re-throws → middleware's *outer* catch converts it.
    // Remove the re-throw clause and the handler's `catch { return … }` swallows
    // the error into a misleading 200-empty, so these tests go red — proving
    // they genuinely guard the re-throw.

    @Test("Holdings re-throws credentialsNotConfigured (reaching the handler) so a linked item surfaces 503, not 200-empty")
    func holdingsRethrowsCredentialsNotConfiguredWhenCredentialsConfigured() async throws {
        try await withInvestmentsAPI(seedItem: true, credentialDiagnosis: .configured) { client in
            let response = try await client.execute(
                uri: "/api/investments/holdings",
                method: .get,
                headers: authHeaders
            )
            // Without the handler re-throw this would be `.ok` with an empty
            // payload (the per-item `catch` swallows the error).
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Investment transactions re-throw credentialsNotConfigured (reaching the handler) so a linked item surfaces 503, not 200-empty")
    func transactionsRethrowCredentialsNotConfiguredWhenCredentialsConfigured() async throws {
        try await withInvestmentsAPI(seedItem: true, credentialDiagnosis: .configured) { client in
            let response = try await client.execute(
                uri: "/api/investments/transactions",
                method: .get,
                headers: authHeaders
            )
            #expect(response.status == .serviceUnavailable)
        }
    }
}
