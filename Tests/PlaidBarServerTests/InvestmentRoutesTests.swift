import Foundation
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

/// Unit tests for the pure, static mapping helpers in ``InvestmentRoutes``
/// (AND-644). These exercise the Plaid → shared-DTO reduction and the per-item
/// merge without standing up a full Hummingbird app, mirroring how the
/// account/liability mapping is validated.
@Suite("Investment routes mapping")
struct InvestmentRoutesTests {
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
