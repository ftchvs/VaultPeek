import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Multi-currency support (AND-643)")
struct MultiCurrencyTests {
    // MARK: - CurrencyCode

    @Test("Raw Plaid codes normalize to uppercase, trimmed, resolved")
    func currencyCodeNormalization() {
        #expect(CurrencyCode("usd") == CurrencyCode.usd)
        #expect(CurrencyCode("  eur ").rawValue == "EUR")
        #expect(CurrencyCode("EUR").isResolved)
        #expect(CurrencyCode("eur") == CurrencyCode("EUR"))
    }

    @Test("Absent or empty currency code resolves to the unknown bucket, not USD")
    func currencyCodeUnknownFallback() {
        #expect(CurrencyCode(nil) == CurrencyCode.unknown)
        #expect(CurrencyCode("") == CurrencyCode.unknown)
        #expect(CurrencyCode("   ") == CurrencyCode.unknown)
        #expect(!CurrencyCode.unknown.isResolved)
        // Critical invariant: unknown must never equal USD.
        #expect(CurrencyCode.unknown != CurrencyCode.usd)
    }

    @Test("Symbol hint is $ for USD, the code itself for other currencies, empty for unknown")
    func currencyCodeSymbolHint() {
        #expect(CurrencyCode.usd.symbolHint == "$")
        #expect(CurrencyCode("EUR").symbolHint == "EUR")
        #expect(CurrencyCode.unknown.symbolHint == "")
    }

    @Test("Accessible name is text-based (non-color cue) and never empty for resolved codes")
    func currencyCodeAccessibleName() {
        // System-localized name for USD contains 'Dollar' on en locales; at minimum
        // it is non-empty and not color-dependent.
        #expect(!CurrencyCode.usd.accessibleName.isEmpty)
        #expect(CurrencyCode.unknown.accessibleName == "unknown currency")
        // A non-ISO/unknown-to-Locale code still yields its raw token, never empty.
        #expect(!CurrencyCode("XBT").accessibleName.isEmpty)
    }

    @Test("Sorting puts resolved currencies before the unknown bucket, alphabetical within")
    func currencyCodeSorting() {
        let sorted = [CurrencyCode.unknown, CurrencyCode("USD"), CurrencyCode("EUR")].sorted()
        #expect(sorted == [CurrencyCode("EUR"), CurrencyCode("USD"), CurrencyCode.unknown])
    }

    @Test("CurrencyCode round-trips through Codable; unknown encodes as empty")
    func currencyCodeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let resolved = try decoder.decode(CurrencyCode.self, from: encoder.encode(CurrencyCode("GBP")))
        #expect(resolved == CurrencyCode("GBP"))
        let unknown = try decoder.decode(CurrencyCode.self, from: encoder.encode(CurrencyCode.unknown))
        #expect(unknown == CurrencyCode.unknown)
    }

    // MARK: - Formatter

    @Test("Formatter renders native currency for resolved codes")
    func formatterNativeCurrency() {
        let usd = Formatters.currency(8_000, in: .usd, format: .full)
        #expect(usd.contains("8,000"))
        #expect(usd.contains("$"))
        // A non-USD code renders without a $ symbol (its identity is preserved).
        let eur = Formatters.currency(1_200, in: CurrencyCode("EUR"), format: .full)
        #expect(eur.contains("1,200"))
        #expect(!eur.contains("$"))
    }

    @Test("Unknown currency formats the bare number with no symbol")
    func formatterUnknownCurrency() {
        let text = Formatters.currency(500, in: .unknown, format: .full)
        #expect(text == "500.00")
        #expect(!text.contains("$"))
    }

    // MARK: - DTO accessors

    @Test("BalanceDTO and TransactionDTO expose normalized currency")
    func dtoCurrencyAccessors() {
        let balance = BalanceDTO(current: 100, isoCurrencyCode: "gbp")
        #expect(balance.currency == CurrencyCode("GBP"))
        let noCode = BalanceDTO(current: 100, isoCurrencyCode: nil)
        #expect(noCode.currency == CurrencyCode.unknown)
        let tx = TransactionDTO(id: "t1", accountId: "a1", amount: 10, date: "2026-06-01", name: "x", isoCurrencyCode: "EUR")
        #expect(tx.currency == CurrencyCode("EUR"))
    }

    @Test("Account row amounts render in the account's native currency")
    func accountRowAmountUsesNativeCurrency() {
        let account = depository(name: "Euro Savings", current: 2_000, currency: "EUR")
        let text = AccountPresentation.rowAmountText(for: account, format: .compact)

        #expect(text.contains("2,000"))
        #expect(!text.contains("$"))
    }

    // MARK: - Static conversion source

    @Test("Static rate table converts via the base and prices identity at 1")
    func staticConversionRates() {
        let rates = StaticCurrencyConversionRates.sampleOffline
        #expect(rates.rate(from: .usd, to: .usd) == 1)
        // 1 EUR = 1.08 USD per the stub table.
        #expect(rates.rate(from: CurrencyCode("EUR"), to: .usd) == 1.08)
        // Cross pair routed through USD base: EUR→GBP = 1.08 / 1.27.
        let eurToGbp = rates.rate(from: CurrencyCode("EUR"), to: CurrencyCode("GBP"))
        #expect(eurToGbp != nil)
        #expect(abs((eurToGbp ?? 0) - (1.08 / 1.27)) < 1e-9)
        // An unlisted currency cannot be priced.
        #expect(rates.rate(from: CurrencyCode("CHF"), to: .usd) == nil)
    }

    @Test("Static rate table returns nil when the target currency's stored rate is zero (AND-665)")
    func staticConversionZeroTargetRateIsNil() {
        // Exercises the divide-by-zero guard at CurrencyAggregation.swift line 75
        // (`toInBase != 0`). A currency stored with a 0 base rate would otherwise
        // produce a division by zero when used as the conversion target; the guard
        // must yield nil so callers fall back to per-currency subtotals rather than
        // an infinite/NaN figure.
        let rates = StaticCurrencyConversionRates(
            base: .usd,
            unitsOfBasePerCurrency: [
                CurrencyCode("EUR"): 1.08,
                CurrencyCode("ZRO"): 0, // pathological: priced at 0 units of base
            ]
        )

        // Converting TO the zero-rate currency divides by zero → guarded to nil.
        #expect(rates.rate(from: .usd, to: CurrencyCode("ZRO")) == nil)
        #expect(rates.rate(from: CurrencyCode("EUR"), to: CurrencyCode("ZRO")) == nil)
        // And convert(...) propagates that nil rather than producing an Inf/NaN amount.
        #expect(rates.convert(100, from: .usd, to: CurrencyCode("ZRO")) == nil)

        // The guard is scoped to the *target*: converting FROM the zero-rate currency
        // is well-defined (numerator 0) and stays priced, so a real foreign target is
        // still handled rather than over-guarded.
        #expect(rates.rate(from: CurrencyCode("ZRO"), to: .usd) == 0)
        // Identity still prices at 1 even for the zero-rate currency.
        #expect(rates.rate(from: CurrencyCode("ZRO"), to: CurrencyCode("ZRO")) == 1)
    }

    @Test("NoConversionSource prices only identity")
    func noConversionSource() {
        let source = NoConversionSource()
        #expect(source.rate(from: .usd, to: .usd) == 1)
        #expect(source.rate(from: CurrencyCode("EUR"), to: .usd) == nil)
    }

    // MARK: - Aggregation

    @Test("Single-currency aggregate is exact, not converted")
    func aggregateSingleCurrencyExact() {
        let result = CurrencyAggregation.aggregate(
            [(amount: 3_000, currency: .usd), (amount: 5_000, currency: .usd)]
        )
        #expect(result.subtotals.count == 1)
        #expect(result.subtotals.first?.amount == 8_000)
        #expect(!result.isMultiCurrency)
        #expect(result.convertedTotal == .exact(amount: 8_000, currency: .usd))
    }

    @Test("Empty input yields an exact zero in the reporting currency")
    func aggregateEmpty() {
        let result = CurrencyAggregation.aggregate([], reportingCurrency: .usd)
        #expect(result.subtotals.isEmpty)
        #expect(result.convertedTotal == .exact(amount: 0, currency: .usd))
    }

    @Test("Mixed currencies with no conversion source → subtotals only, total unavailable")
    func aggregateMixedNoRatesIsUnavailable() {
        let result = CurrencyAggregation.aggregate([
            (amount: 8_000, currency: .usd),
            (amount: 1_200, currency: CurrencyCode("EUR")),
        ])
        #expect(result.isMultiCurrency)
        #expect(result.subtotals.count == 2)
        #expect(result.convertedTotal == .unavailable)
        // Native subtotals are intact regardless.
        #expect(result.subtotals.contains { $0.currency == CurrencyCode("EUR") && $0.amount == 1_200 })
    }

    @Test("Mixed currencies, all priceable → converted total with empty unpriced list")
    func aggregateMixedAllPriceable() {
        let result = CurrencyAggregation.aggregate(
            [
                (amount: 1_000, currency: .usd),
                (amount: 1_000, currency: CurrencyCode("EUR")),
            ],
            reportingCurrency: .usd,
            conversionSource: StaticCurrencyConversionRates.sampleOffline
        )
        guard case let .converted(amount, currency, unpriced) = result.convertedTotal else {
            Issue.record("expected converted total")
            return
        }
        #expect(currency == .usd)
        #expect(unpriced.isEmpty)
        // 1000 USD + 1000 EUR*1.08 = 2080 USD.
        #expect(abs(amount - 2_080) < 1e-6)
    }

    @Test("Mixed currencies, some unpriceable → partial converted total lists the remainder")
    func aggregateMixedPartiallyPriceable() {
        let result = CurrencyAggregation.aggregate(
            [
                (amount: 1_000, currency: .usd),
                (amount: 1_000, currency: CurrencyCode("EUR")),
                (amount: 500, currency: CurrencyCode("CHF")), // not in the stub table
            ],
            reportingCurrency: .usd,
            conversionSource: StaticCurrencyConversionRates.sampleOffline
        )
        guard case let .converted(amount, _, unpriced) = result.convertedTotal else {
            Issue.record("expected converted total over the priceable subset")
            return
        }
        #expect(unpriced == [CurrencyCode("CHF")])
        // Converted figure excludes CHF: 1000 + 1000*1.08 = 2080.
        #expect(abs(amount - 2_080) < 1e-6)
        // But CHF is still present as a native subtotal.
        #expect(result.subtotals.contains { $0.currency == CurrencyCode("CHF") && $0.amount == 500 })
    }

    @Test("Mixed unknown-only currencies with no rates stay subtotals-only")
    func aggregateUnknownBucketUnavailable() {
        let result = CurrencyAggregation.aggregate([
            (amount: 1, currency: .unknown),
            (amount: 2, currency: CurrencyCode("EUR")),
        ])
        #expect(result.convertedTotal == .unavailable)
        #expect(result.subtotals.count == 2)
    }

    // MARK: - Presentation

    @Test("Net worth across currencies signs debt negative and keeps currencies separate")
    func netWorthMultiCurrency() {
        let accounts = [
            depository(name: "US Checking", current: 5_000, currency: "USD"),
            depository(name: "Euro Savings", current: 2_000, currency: "EUR"),
            credit(name: "US Card", current: 800, limit: 3_000, currency: "USD"),
        ]
        let result = MultiCurrencyBalancePresentation.netWorth(accounts: accounts)
        // USD subtotal: 5000 assets - 800 debt = 4200; EUR: 2000.
        let usd = result.subtotals.first { $0.currency == .usd }
        let eur = result.subtotals.first { $0.currency == CurrencyCode("EUR") }
        #expect(usd?.amount == 4_200)
        #expect(eur?.amount == 2_000)
        // No rates supplied → no single headline number.
        #expect(result.convertedTotal == .unavailable)
    }

    @Test("Subtotal rows carry native formatting and a text currency label; mask hides figures only")
    func subtotalRowsAccessibilityAndMask() {
        let aggregation = CurrencyAggregation.aggregate([
            (amount: 8_000, currency: .usd),
            (amount: 1_200, currency: CurrencyCode("EUR")),
        ])
        let rows = MultiCurrencyBalancePresentation.subtotalRows(from: aggregation)
        let eurRow = rows.first { $0.currency == CurrencyCode("EUR") }
        #expect(eurRow != nil)
        #expect(eurRow?.formattedAmount.contains("1,200") == true)
        // Currency identity is in the spoken label as text (non-color cue).
        #expect(eurRow?.accessibilityLabel.contains(CurrencyCode("EUR").accessibleName) == true)

        let masked = MultiCurrencyBalancePresentation.subtotalRows(
            from: aggregation,
            privacyMaskEnabled: true
        )
        // Figure hidden, currency still visible.
        #expect(masked.allSatisfy { $0.formattedAmount == PrivacyMaskPresentation.compactValue })
        #expect(masked.contains { $0.currency == CurrencyCode("EUR") })
    }

    @Test("Headline discloses exact, approximate-with-remainder, and unavailable states in words")
    func headlineDisclosures() {
        // Exact (single currency).
        let exact = MultiCurrencyBalancePresentation.headline(
            from: CurrencyAggregation.aggregate([(amount: 100, currency: .usd)])
        )
        #expect(exact.formattedTotal != nil)
        #expect(exact.disclosure.lowercased().contains("all accounts"))

        // Converted with an unpriced remainder.
        let partial = MultiCurrencyBalancePresentation.headline(
            from: CurrencyAggregation.aggregate(
                [
                    (amount: 1_000, currency: .usd),
                    (amount: 1_000, currency: CurrencyCode("EUR")),
                    (amount: 500, currency: CurrencyCode("CHF")),
                ],
                conversionSource: StaticCurrencyConversionRates.sampleOffline
            )
        )
        #expect(partial.formattedTotal != nil)
        #expect(partial.disclosure.lowercased().contains("approximate"))
        #expect(partial.disclosure.contains(CurrencyCode("CHF").accessibleName))

        // Unavailable (mixed, no rates) → no headline number, subtotals-only note.
        let unavailable = MultiCurrencyBalancePresentation.headline(
            from: CurrencyAggregation.aggregate([
                (amount: 1, currency: .usd),
                (amount: 2, currency: CurrencyCode("EUR")),
            ])
        )
        #expect(unavailable.formattedTotal == nil)
        #expect(unavailable.disclosure.lowercased().contains("per currency"))
    }

    @Test("Menu bar shows the dominant currency's subtotal (no fabricated $ sum) for mixed currencies")
    func menuBarMixedCurrencyShowsDominantSubtotal() {
        // USD subtotal 5,000 dominates the EUR 2,000 subtotal by absolute value.
        let accounts = [
            depository(name: "US Checking", current: 5_000, currency: "USD"),
            depository(name: "Euro Savings", current: 2_000, currency: "EUR"),
        ]

        let text = MenuBarSummary.text(
            mode: .netWorth,
            accounts: accounts,
            transactions: [],
            currencyFormat: .compact
        )

        // Dominant USD subtotal in its own symbol + the non-color "+" marker; the
        // EUR figure is never blind-summed into the dollar number.
        #expect(text == "$5,000+")
        #expect(!text.contains("7,000")) // no fabricated 5000 + 2000 cross-currency sum
        #expect(!text.contains("€")) // the headline figure is the dollar one, not euro
    }

    @Test("Mixed-currency glance names the dominant subtotal for VoiceOver and notes the others")
    func menuBarMixedCurrencyAccessibilityLabel() {
        let accounts = [
            depository(name: "US Checking", current: 5_000, currency: "USD"),
            depository(name: "Euro Savings", current: 2_000, currency: "EUR"),
        ]
        let aggregation = MultiCurrencyBalancePresentation.netWorth(accounts: accounts)
        let glance = MultiCurrencyBalancePresentation.glance(from: aggregation, format: .compact)

        // Visible figure carries the dominant USD subtotal + non-color marker...
        #expect(glance.text == "$5,000+")
        // ...and the spoken label names the dominant currency in words (not the "+"
        // glyph) and discloses that other currencies are shown separately.
        #expect(!glance.accessibilityLabel.isEmpty)
        #expect(glance.accessibilityLabel.contains("$5,000"))
        #expect(glance.accessibilityLabel.lowercased().contains("subtotal"))
        #expect(glance.accessibilityLabel.lowercased().contains("other currencies"))
        // The accessible value text path used by the menu bar matches the glance.
        let spoken = MenuBarSummary.accessibleValueText(
            mode: .netWorth,
            accounts: accounts,
            transactions: [],
            currencyFormat: .compact
        )
        #expect(spoken == glance.accessibilityLabel)
    }

    @Test("Dominant subtotal is picked by absolute magnitude, including negative debt")
    func menuBarDominantPicksByAbsoluteValue() {
        // EUR net worth is strongly negative (debt); it dominates the small USD
        // asset by absolute value, so the glance shows the EUR figure.
        let accounts = [
            depository(name: "US Checking", current: 500, currency: "USD"),
            credit(name: "Euro Card", current: 9_000, limit: 12_000, currency: "EUR"),
        ]
        let aggregation = MultiCurrencyBalancePresentation.netWorth(accounts: accounts)
        let dominant = MultiCurrencyBalancePresentation.dominantSubtotal(in: aggregation)
        #expect(dominant?.currency == CurrencyCode("EUR"))

        let text = MenuBarSummary.text(
            mode: .netWorth,
            accounts: accounts,
            transactions: [],
            currencyFormat: .compact
        )
        // EUR debt subtotal of -9,000 rendered in EUR's own currency formatting,
        // plus the marker. Critically: never coerced into a "$" figure. (The exact
        // symbol — "€" vs "EUR" — is locale-dependent, so assert the *absence* of $
        // and the dominant-currency pick rather than a brittle symbol literal.)
        #expect(text.hasSuffix("+"))
        #expect(!text.contains("$"))
        // The figure equals EUR's native formatting of the dominant subtotal.
        let expectedFigure = Formatters.currency(dominant!.amount, in: CurrencyCode("EUR"), format: .compact)
        #expect(text == expectedFigure + "+")
    }

    @Test("Single-USD menu-bar text is byte-identical to the legacy formatter (no regression)")
    func menuBarSingleUSDByteIdentical() {
        let accounts = [
            depository(name: "US Checking", current: 5_000, currency: "USD"),
            depository(name: "US Savings", current: 3_000, currency: "USD"),
            credit(name: "US Card", current: 800, limit: 3_000, currency: "USD"),
        ]

        for format in [CurrencyFormat.compact, .full, .abbreviated] {
            let glanceText = MenuBarSummary.text(
                mode: .netWorth,
                accounts: accounts,
                transactions: [],
                currencyFormat: format
            )
            // Legacy behavior: a single scalar net-cash figure in USD via the
            // pre-multi-currency formatter path.
            let legacy = Formatters.currency(
                MenuBarSummary.netCash(from: accounts),
                format: format
            )
            #expect(glanceText == legacy)
            #expect(!glanceText.hasSuffix("+")) // no mixed-currency marker for single-currency
            // Spoken value also equals the visible single figure for VoiceOver.
            let spoken = MenuBarSummary.accessibleValueText(
                mode: .netWorth,
                accounts: accounts,
                transactions: [],
                currencyFormat: format
            )
            #expect(spoken.contains(legacy))
        }
    }

    // MARK: - Helpers

    private func depository(name: String, current: Double, currency: String) -> AccountDTO {
        AccountDTO(
            id: name,
            itemId: "item",
            name: name,
            type: .depository,
            balances: BalanceDTO(available: current, current: current, isoCurrencyCode: currency)
        )
    }

    private func credit(name: String, current: Double, limit: Double, currency: String) -> AccountDTO {
        AccountDTO(
            id: name,
            itemId: "item",
            name: name,
            type: .credit,
            balances: BalanceDTO(current: current, limit: limit, isoCurrencyCode: currency)
        )
    }
}
