import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Formatters")
struct FormattersTests {
    @Test("USD currency renders each format")
    func usdCurrency() {
        #expect(Formatters.currency(12_450.32, format: .full).contains("12,450"))
        #expect(Formatters.currency(12_450, format: .compact).contains("12,450"))
        #expect(Formatters.currency(12_400, format: .abbreviated) == "$12.4K")
        #expect(Formatters.currency(1_500_000, format: .abbreviated) == "$1.5M")
        #expect(Formatters.currency(500, format: .abbreviated) == "$500")
        #expect(Formatters.currency(-2_000, format: .abbreviated) == "-$2.0K")
    }

    @Test("Non-USD currency uses the supplied currency code")
    func nonUsdCurrency() {
        #expect(!Formatters.currency(1_000, format: .full, currencyCode: "EUR").isEmpty)
        #expect(!Formatters.currency(1_000, format: .compact, currencyCode: "EUR").isEmpty)
        // AND-660 #4: an abbreviated non-USD figure separates the currency-code
        // symbol from the magnitude with a non-breaking space (U+00A0) so it does
        // not read as `EUR1.5K`. USD (the `$` glyph) keeps no separator.
        #expect(Formatters.currency(1_500, format: .abbreviated, currencyCode: "EUR") == "EUR\u{00A0}1.5K")
        #expect(Formatters.currency(2_400_000, format: .abbreviated, currencyCode: "GBP") == "GBP\u{00A0}2.4M")
        #expect(Formatters.currency(-3_000, format: .abbreviated, currencyCode: "JPY") == "-JPY\u{00A0}3.0K")
        #expect(Formatters.currency(750, format: .abbreviated, currencyCode: "CAD") == "CAD\u{00A0}750")
        // USD stays byte-identical to the pre-AND-660 output (no separator).
        #expect(Formatters.currency(1_500, format: .abbreviated, currencyCode: "USD") == "$1.5K")
    }

    @Test("Percent formats with the requested precision")
    func percent() {
        #expect(Formatters.percent(42.5, decimals: 1) == "42.5%")
        #expect(Formatters.percent(42, decimals: 0) == "42%")
    }

    // MARK: - signedCurrency (AND-664 #2)

    @Test("signedCurrency prefixes by sign and renders the abs magnitude")
    func signedCurrencySign() {
        // Positive → "+", negative → minusGlyph, zero → no prefix.
        #expect(Formatters.signedCurrency(30, format: .compact) == "+\(Formatters.currency(30, format: .compact))")
        #expect(Formatters.signedCurrency(-30, format: .compact) == "-\(Formatters.currency(30, format: .compact))")
        #expect(Formatters.signedCurrency(0, format: .compact) == Formatters.currency(0, format: .compact))
        // No leading "+0"/"-0" on zero.
        #expect(!Formatters.signedCurrency(0, format: .full).hasPrefix("+"))
        #expect(!Formatters.signedCurrency(0, format: .full).hasPrefix("-"))
    }

    @Test("signedCurrency honors the requested format")
    func signedCurrencyFormat() {
        #expect(Formatters.signedCurrency(-1_234.56, format: .full) == "-\(Formatters.currency(1_234.56, format: .full))")
        #expect(Formatters.signedCurrency(-1_234.56, format: .compact) == "-\(Formatters.currency(1_234.56, format: .compact))")
        // Full and compact differ (decimals), so the two outputs must not be equal.
        #expect(Formatters.signedCurrency(1_234.56, format: .full) != Formatters.signedCurrency(1_234.56, format: .compact))
    }

    @Test("signedCurrency uses the supplied minus glyph for negatives only")
    func signedCurrencyMinusGlyph() {
        // The investment row deliberately uses the typographic U+2212 MINUS SIGN.
        #expect(Formatters.signedCurrency(-50, minusGlyph: "\u{2212}") == "\u{2212}\(Formatters.currency(50, format: .full))")
        // Positive and zero never use the minus glyph.
        #expect(!Formatters.signedCurrency(50, minusGlyph: "\u{2212}").contains("\u{2212}"))
        #expect(!Formatters.signedCurrency(0, minusGlyph: "\u{2212}").contains("\u{2212}"))
        // The default glyph is the ASCII hyphen-minus, distinct from U+2212.
        #expect(Formatters.signedCurrency(-50) != Formatters.signedCurrency(-50, minusGlyph: "\u{2212}"))
        #expect(Formatters.signedCurrency(-50).contains("-"))
    }

    @Test("signedCurrency masks the whole value when masked, regardless of sign")
    func signedCurrencyMasked() {
        for amount in [-99.0, 0.0, 42.0] {
            #expect(Formatters.signedCurrency(amount, masked: true) == PrivacyMaskPresentation.compactValue)
        }
        // Unmasked is never the placeholder for a real amount.
        #expect(Formatters.signedCurrency(42, masked: false) != PrivacyMaskPresentation.compactValue)
    }

    /// Equivalence: each consolidated call site (AND-664 #2) must render exactly
    /// what its prior hand-rolled `prefix + currency(abs(...))` produced. This pins
    /// the per-site parameterization (format / glyph / mask) against a fresh
    /// re-derivation of the old inline logic.
    @Test("Consolidated signed-currency sites render identically to their old inline logic")
    func consolidatedSitesUnchanged() {
        func oldFull(_ a: Double) -> String {
            let p = a > 0 ? "+" : a < 0 ? "-" : ""
            return "\(p)\(Formatters.currency(abs(a), format: .full))"
        }
        func oldCompact(_ a: Double) -> String {
            let p = a > 0 ? "+" : a < 0 ? "-" : ""
            return "\(p)\(Formatters.currency(abs(a), format: .compact))"
        }
        func oldInvestment(_ a: Double, masked: Bool) -> String {
            guard !masked else { return PrivacyMaskPresentation.compactValue }
            let m = Formatters.currency(abs(a), format: .full)
            if a > 0 { return "+\(m)" }
            if a < 0 { return "\u{2212}\(m)" }
            return m
        }

        for amount in [-1_234.56, -1.0, 0.0, 1.0, 4_545.0, 99_999.99] {
            // LocalAIInsightBuilder / FigureProvenance / MainPopover.cashflowText /
            // SafeToSpendCard.amountText (compact, ASCII minus).
            #expect(Formatters.signedCurrency(amount, format: .compact) == oldCompact(amount))
            // SpendingHeatmap.amountText / LocalInsightModelPrompt.signedMoney /
            // SyncHistoryDiff.signedCurrency / AccountDetailFlyout delta (full, ASCII minus).
            #expect(Formatters.signedCurrency(amount, format: .full) == oldFull(amount))
            // InvestmentHoldingsPresentation.signedCurrency (full, U+2212, maskable).
            #expect(Formatters.signedCurrency(amount, format: .full, minusGlyph: "\u{2212}", masked: false) == oldInvestment(amount, masked: false))
            #expect(Formatters.signedCurrency(amount, format: .full, minusGlyph: "\u{2212}", masked: true) == oldInvestment(amount, masked: true))
        }

        // The public LocalAIDeterministicSummary delegate keeps its compact output.
        #expect(LocalAIDeterministicSummary.signedCurrency(-12.5) == oldCompact(-12.5))
        #expect(LocalAIDeterministicSummary.signedCurrency(12.5) == oldCompact(12.5))
    }

    @Test("Display date special-cases today and yesterday")
    func displayDate() throws {
        #expect(Formatters.displayDate(Date()) == "Today")
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        #expect(Formatters.displayDate(yesterday) == "Yesterday")
        let old = try #require(Formatters.parseTransactionDate("2020-01-15"))
        #expect(Formatters.displayDate(old) != "Today")
        #expect(Formatters.displayDate(old) != "Yesterday")
    }

    @Test("Canonical transaction date keys are validated structurally")
    func canonicalKey() {
        #expect(Formatters.isCanonicalTransactionDateKey("2026-06-14"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026/06/14"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026-6-4"))
        #expect(!Formatters.isCanonicalTransactionDateKey("not-a-date"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026-06-1x"))
    }

    @Test("Transaction dates round-trip through parse and format")
    func transactionDateRoundTrip() throws {
        let date = try #require(Formatters.parseTransactionDate("2026-06-14"))
        #expect(Formatters.transactionDateString(date) == "2026-06-14")
        #expect(Formatters.parseTransactionDate("garbage") == nil)
    }

    @Test("displayTransactionDate falls back to the raw string when unparseable")
    func displayTransactionDate() {
        #expect(Formatters.displayTransactionDate("not-a-date") == "not-a-date")
    }

    @Test("relativeDate produces a non-empty relative string")
    func relativeDate() {
        #expect(!Formatters.relativeDate(Date().addingTimeInterval(-3_600)).isEmpty)
    }

    @Test("percentFromShare renders a whole-number percent from a 0...1 fraction")
    func percentFromShare() {
        // Pins the exact output of the previously-inline percentText(_:) helpers.
        #expect(Formatters.percentFromShare(0) == "0%")
        #expect(Formatters.percentFromShare(1) == "100%")
        #expect(Formatters.percentFromShare(0.5) == "50%")
        // Rounds to the nearest whole percent.
        #expect(Formatters.percentFromShare(0.4267) == "43%")
        #expect(Formatters.percentFromShare(0.4234) == "42%")
        // Half rounds away from zero (Double.rounded() default).
        #expect(Formatters.percentFromShare(0.005) == "1%")
    }
}
