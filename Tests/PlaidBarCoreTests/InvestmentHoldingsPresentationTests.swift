import Testing
@testable import PlaidBarCore

@Suite("Investment holdings presentation")
struct InvestmentHoldingsPresentationTests {
    private let securities = [
        SecurityDTO(id: "sec_vti", name: "Vanguard Total Market ETF", tickerSymbol: "VTI", type: "etf", closePrice: 250),
        SecurityDTO(id: "sec_aapl", name: "Apple Inc.", tickerSymbol: "AAPL", type: "equity", closePrice: 200),
        SecurityDTO(id: "sec_cash", name: "Cash Sweep", tickerSymbol: nil, type: "cash", closePrice: 1),
    ]

    // These fixtures are USD positions; the `$` assertions below depend on the
    // currency being explicit (AND-660 — an absent code resolves to the unknown
    // bucket, which renders the bare number, not `$`).
    private func holdings() -> [HoldingDTO] {
        [
            HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 90, institutionPrice: 250, institutionValue: 22_500, costBasis: 18_000, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_aapl", quantity: 50, institutionPrice: 200, institutionValue: 10_000, costBasis: 11_500, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_cash", quantity: 2_800, institutionPrice: 1, institutionValue: 2_800, costBasis: 2_800, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_b", securityId: "sec_vti", quantity: 4, institutionPrice: 250, institutionValue: 1_000, costBasis: 900, isoCurrencyCode: "USD"),
        ]
    }

    // MARK: - HoldingDTO derived values

    @Test("Holding market value prefers institution value, then quantity x price")
    func holdingMarketValue() {
        let explicit = HoldingDTO(accountId: "a", securityId: "s", quantity: 10, institutionPrice: 5, institutionValue: 60)
        #expect(explicit.marketValue == 60)

        let derived = HoldingDTO(accountId: "a", securityId: "s", quantity: 10, institutionPrice: 5, institutionValue: nil)
        #expect(derived.marketValue == 50)

        let unpriced = HoldingDTO(accountId: "a", securityId: "s", quantity: 10, institutionPrice: nil, institutionValue: nil)
        #expect(unpriced.marketValue == 0)
    }

    @Test("Unrealized gain is nil without cost basis and signed with it")
    func holdingUnrealizedGain() {
        let withBasis = HoldingDTO(accountId: "a", securityId: "s", quantity: 1, institutionValue: 1_200, costBasis: 1_000)
        #expect(withBasis.unrealizedGain == 200)

        let loss = HoldingDTO(accountId: "a", securityId: "s", quantity: 1, institutionValue: 800, costBasis: 1_000)
        #expect(loss.unrealizedGain == -200)

        let noBasis = HoldingDTO(accountId: "a", securityId: "s", quantity: 1, institutionValue: 800, costBasis: nil)
        #expect(noBasis.unrealizedGain == nil)
    }

    @Test("Holding id is stable but does not expose Plaid identifiers")
    func holdingIdentity() {
        let holding = HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 1)
        #expect(holding.id.hasPrefix("holding-"))
        #expect(!holding.id.contains("acct_a"))
        #expect(!holding.id.contains("sec_vti"))
        #expect(holding.id == HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 2).id)
    }

    // MARK: - Rows

    @Test("Rows for an account join securities and sort by descending market value")
    func rowsJoinAndSort() {
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_a",
            holdings: holdings(),
            securities: securities,
            privacyMaskEnabled: false
        )

        // acct_b holding excluded; three acct_a positions, largest first.
        #expect(rows.count == 3)
        #expect(rows.map(\.securityName) == ["Vanguard Total Market ETF", "Apple Inc.", "Cash Sweep"])
        #expect(rows.first?.tickerSymbol == "VTI")
        #expect(rows.first?.marketValueText == "$22,500.00")
        #expect(rows.first?.quantityText == "90 shares")
        #expect(rows.first?.securityTypeLabel == "ETF")
    }

    @Test("Gain row carries a directional cue and a sign-prefixed amount, never color alone")
    func gainDirectionCues() {
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_a",
            holdings: holdings(),
            securities: securities,
            privacyMaskEnabled: false
        )

        let vti = rows.first { $0.tickerSymbol == "VTI" }
        #expect(vti?.gainDirection == .gain)
        #expect(vti?.gainText == "+$4,500.00")
        #expect(vti?.gainDirection?.glyphName == "arrow.up.right")

        let aapl = rows.first { $0.tickerSymbol == "AAPL" }
        #expect(aapl?.gainDirection == .loss)
        #expect(aapl?.gainText == "−$1,500.00")
        #expect(aapl?.gainDirection?.glyphName == "arrow.down.right")

        let cash = rows.first { $0.securityName == "Cash Sweep" }
        #expect(cash?.gainDirection == .flat)
        #expect(cash?.gainText == "$0.00")
    }

    @Test("Privacy Mask hides currency and quantity in rows and labels")
    func privacyMaskHidesRowValues() {
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_a",
            holdings: holdings(),
            securities: securities,
            privacyMaskEnabled: true
        )

        let row = rows.first
        #expect(row?.securityName == "Investment holding")
        #expect(row?.tickerSymbol == nil)
        #expect(row?.securityTypeLabel == nil)
        #expect(row?.marketValueText == PrivacyMaskPresentation.compactValue)
        #expect(row?.quantityText == PrivacyMaskPresentation.compactValue)
        #expect(row?.gainText == PrivacyMaskPresentation.compactValue)
        #expect(row?.accessibilityLabel.contains("Vanguard") == false)
        #expect(row?.accessibilityLabel.contains("VTI") == false)
        #expect(row?.accessibilityLabel.contains("Privacy Mask") == true)
    }

    @Test("A holding whose security is missing still renders with a fallback name")
    func missingSecurityFallback() {
        let orphan = [HoldingDTO(accountId: "acct_a", securityId: "sec_unknown", quantity: 1, institutionValue: 100)]
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_a",
            holdings: orphan,
            securities: [],
            privacyMaskEnabled: false
        )
        #expect(rows.count == 1)
        #expect(rows.first?.securityName == "Unidentified security")
        #expect(rows.first?.securityTypeLabel == nil)
    }

    @Test("Missing-security fallback never renders raw security identifiers")
    func missingSecurityFallbackHidesIdentifier() {
        let rawSecurityID = "raw_security_identifier_123456"
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_a",
            holdings: [HoldingDTO(accountId: "acct_a", securityId: rawSecurityID, quantity: 1, institutionValue: 100)],
            securities: [],
            privacyMaskEnabled: false
        )

        #expect(rows.first?.securityName == "Unidentified security")
        #expect(rows.first?.securityName.contains(rawSecurityID) == false)
        #expect(rows.first?.id.contains(rawSecurityID) == false)
        #expect(rows.first?.id.contains("acct_a") == false)
    }

    // MARK: - Summary

    @Test("Account summary rolls up market value, cost basis, and net gain")
    func summaryRollup() {
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: holdings(),
            accountId: "acct_a",
            privacyMaskEnabled: false
        )

        #expect(summary.holdingsCount == 3)
        #expect(summary.totalMarketValue == 35_300)
        #expect(summary.totalCostBasis == 32_300)
        #expect(summary.totalGain == 3_000)
        #expect(summary.gainDirection == .gain)
        #expect(summary.totalMarketValueText == "$35,300.00")
        #expect(summary.totalGainText == "+$3,000.00")
    }

    @Test("Summary leaves gain nil when no holding reports cost basis")
    func summaryWithoutCostBasis() {
        let noBasis = [
            HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 1, institutionValue: 1_000, costBasis: nil),
            HoldingDTO(accountId: "acct_a", securityId: "sec_aapl", quantity: 1, institutionValue: 500, costBasis: nil),
        ]
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: noBasis,
            accountId: "acct_a",
            privacyMaskEnabled: false
        )
        #expect(summary.totalMarketValue == 1_500)
        #expect(summary.totalCostBasis == nil)
        #expect(summary.totalGain == nil)
        #expect(summary.gainDirection == .flat)
        #expect(summary.totalGainText == nil)
    }

    @Test("Summary mixes basis and no-basis holdings: market value spans all, gain spans basis-only (AND-665)")
    func summaryMixedCostBasis() {
        // Three scoped holdings; only VTI and Cash report a cost basis, AAPL does
        // not. This pins the asymmetry at InvestmentHoldingsPresentation.swift
        // lines 235-249: totalMarketValue covers EVERY holding, while totalGain is
        // computed over ONLY the basis-reporting holdings (their market value minus
        // their basis). AAPL's $10,000 market value contributes to the total but is
        // excluded from the gain numerator so value and basis stay comparable.
        let mixed = [
            HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 90, institutionValue: 22_500, costBasis: 18_000, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_aapl", quantity: 50, institutionValue: 10_000, costBasis: nil, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_cash", quantity: 2_800, institutionValue: 2_800, costBasis: 2_800, isoCurrencyCode: "USD"),
        ]
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: mixed,
            accountId: "acct_a",
            privacyMaskEnabled: false
        )

        // Count and market value span ALL three holdings, including the basisless AAPL.
        #expect(summary.holdingsCount == 3)
        #expect(summary.totalMarketValue == 35_300) // 22_500 + 10_000 + 2_800

        // Cost basis sums only the two holdings that report it.
        #expect(summary.totalCostBasis == 20_800) // 18_000 + 2_800

        // Gain numerator = market value of the BASIS holdings only (22_500 + 2_800),
        // minus the cost basis. AAPL's 10_000 is intentionally NOT in the numerator,
        // so the gain is 4_500 — NOT 14_500 (which a naive totalMarketValue - basis
        // would wrongly produce by counting AAPL's unbacked market value as gain).
        #expect(summary.totalGain == 4_500) // (22_500 + 2_800) - 20_800
        #expect(summary.totalGain != 35_300 - 20_800) // guards against the naive formula
        #expect(summary.gainDirection == .gain)
        #expect(summary.totalMarketValueText == "$35,300.00")
        #expect(summary.totalGainText == "+$4,500.00")
    }

    @Test("Summary masks value and gain under Privacy Mask")
    func summaryPrivacyMask() {
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: holdings(),
            accountId: "acct_a",
            privacyMaskEnabled: true
        )
        #expect(summary.totalMarketValueText == PrivacyMaskPresentation.compactValue)
        #expect(summary.totalGainText == PrivacyMaskPresentation.compactValue)
        #expect(summary.accessibilityLabel.contains("Privacy Mask") == true)
        // Counts are not sensitive and remain visible.
        #expect(summary.holdingsCount == 3)
    }

    @Test("Total market value sums every supplied holding for net-worth inclusion")
    func totalMarketValueAcrossAccounts() {
        let total = InvestmentHoldingsPresentation.totalMarketValue(holdings: holdings())
        // 22_500 + 10_000 + 2_800 (acct_a) + 1_000 (acct_b)
        #expect(total == 36_300)
    }

    // MARK: - Direction + formatting helpers

    @Test("Direction maps sign to gain/loss/flat")
    func directionOfSign() {
        #expect(InvestmentHoldingsPresentation.Direction.of(5) == .gain)
        #expect(InvestmentHoldingsPresentation.Direction.of(-5) == .loss)
        #expect(InvestmentHoldingsPresentation.Direction.of(0) == .flat)
    }

    @Test("Security type label friendly-cases known acronyms and title-cases the rest")
    func securityTypeLabels() {
        #expect(InvestmentHoldingsPresentation.securityTypeLabel("etf") == "ETF")
        #expect(InvestmentHoldingsPresentation.securityTypeLabel("equity") == "Equity")
        #expect(InvestmentHoldingsPresentation.securityTypeLabel("mutual fund") == "Mutual Fund")
        #expect(InvestmentHoldingsPresentation.securityTypeLabel("money market") == "Money Market")
        #expect(InvestmentHoldingsPresentation.securityTypeLabel(nil) == nil)
        #expect(InvestmentHoldingsPresentation.securityTypeLabel("") == nil)
    }

    @Test("Quantity formatting trims trailing zeros but keeps fractional shares")
    func quantityFormatting() {
        // POSIX locale does not insert a grouping separator, keeping the
        // formatted quantity locale-stable across machines.
        #expect(InvestmentHoldingsPresentation.formatQuantity(10) == "10")
        #expect(InvestmentHoldingsPresentation.formatQuantity(2_800) == "2800")
        #expect(InvestmentHoldingsPresentation.formatQuantity(1.5) == "1.5")
        #expect(InvestmentHoldingsPresentation.formatQuantity(0.3333) == "0.3333")
    }

    @Test("Signed currency uses an explicit sign so direction reads without color")
    func signedCurrencyText() {
        #expect(InvestmentHoldingsPresentation.signedCurrency(250, in: .usd, masked: false) == "+$250.00")
        #expect(InvestmentHoldingsPresentation.signedCurrency(-250, in: .usd, masked: false) == "−$250.00")
        #expect(InvestmentHoldingsPresentation.signedCurrency(0, in: .usd, masked: false) == "$0.00")
        #expect(InvestmentHoldingsPresentation.signedCurrency(250, in: .usd, masked: true) == PrivacyMaskPresentation.compactValue)
    }

    // AND-660 #1: a holding/portfolio in a non-USD currency must render and
    // aggregate in that currency — never collapsed into a fabricated `$` total.
    @Test("Signed currency renders the holding's own currency, not $")
    func signedCurrencyNonUSD() {
        // EUR renders as the bare code + native formatting (no `$`).
        let eurGain = InvestmentHoldingsPresentation.signedCurrency(250, in: CurrencyCode("EUR"), masked: false)
        #expect(eurGain.hasPrefix("+"))
        #expect(!eurGain.contains("$"))

        let eurLoss = InvestmentHoldingsPresentation.signedCurrency(-250, in: CurrencyCode("EUR"), masked: false)
        #expect(eurLoss.hasPrefix("\u{2212}")) // typographic minus, not ASCII hyphen
        #expect(!eurLoss.contains("$"))
    }

    @Test("Single-currency EUR holding renders value and gain in EUR, never $")
    func rowsRenderNativeCurrency() {
        let eurHoldings = [
            HoldingDTO(accountId: "acct_eu", securityId: "sec_vti", quantity: 4, institutionPrice: 250, institutionValue: 1_000, costBasis: 900, isoCurrencyCode: "EUR"),
        ]
        let rows = InvestmentHoldingsPresentation.rows(
            forAccount: "acct_eu",
            holdings: eurHoldings,
            securities: securities,
            privacyMaskEnabled: false
        )
        #expect(rows.count == 1)
        // The market value and gain render in EUR — never a dollar glyph. `.full`
        // uses the locale currency symbol (€), so the contract is "no `$`", which
        // mirrors the established MultiCurrencyTests formatter assertions.
        #expect(!(rows.first?.marketValueText.contains("$") ?? true))
        #expect(!(rows.first?.gainText?.contains("$") ?? true))
        #expect(rows.first?.marketValueText.contains("1,000") ?? false)
    }

    @Test("Mixed EUR/USD portfolio never collapses into one fabricated $ total (AND-660)")
    func summaryMixedCurrencyDoesNotCollapse() {
        // Two USD positions + one EUR position. The naive (buggy) behavior summed
        // all three market values into a single scalar and labeled it `$`. With
        // the AND-660 fix the summary groups per currency and the displayed total
        // names both currencies — never a lone `$` figure pretending EUR is USD.
        let mixed = [
            HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 40, institutionPrice: 250, institutionValue: 10_000, costBasis: 9_000, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_aapl", quantity: 25, institutionPrice: 200, institutionValue: 5_000, costBasis: 4_000, isoCurrencyCode: "USD"),
            HoldingDTO(accountId: "acct_a", securityId: "sec_vti", quantity: 8, institutionPrice: 250, institutionValue: 2_000, costBasis: 1_800, isoCurrencyCode: "EUR"),
        ]
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: mixed,
            accountId: "acct_a",
            privacyMaskEnabled: false
        )

        // The aggregation keeps both currencies — it is multi-currency and its
        // per-currency subtotals carry both USD (15,000) and EUR (2,000).
        #expect(summary.isMultiCurrency)
        #expect(summary.marketValueAggregation.subtotals.count == 2)
        let byCurrency = Dictionary(
            uniqueKeysWithValues: summary.marketValueAggregation.subtotals.map { ($0.currency, $0.amount) }
        )
        #expect(byCurrency[CurrencyCode("USD")] == 15_000)
        #expect(byCurrency[CurrencyCode("EUR")] == 2_000)

        // The DISPLAYED total is a per-currency breakdown (e.g. "€2,000.00 ·
        // $15,000.00") — NOT a single `$17,000` figure (the old cross-currency
        // collapse). With no conversion source the headline is unavailable, so both
        // currencies are listed; the USD subtotal keeps its `$`, EUR its own symbol.
        #expect(summary.totalMarketValueText.contains("15,000"))
        #expect(summary.totalMarketValueText.contains("2,000"))
        #expect(summary.totalMarketValueText.contains("·")) // per-currency separator
        #expect(summary.totalMarketValueText != "$17,000.00")
    }
}
