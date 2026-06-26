import Foundation
import Testing
@testable import PlaidBarCore

/// Pins the hero-metric detail copy that the Dashboard and Accounts destinations
/// previously each spelled out inline (byte-identical private `metricDetail` and
/// `accountCountDetail` helpers, now consolidated into Core). Golden strings are
/// the verbatim prior output so the extraction stays behavior-preserving.
@Suite("Destination hero-metric detail copy")
struct DestinationMetricDetailPresentationTests {
    // MARK: - AccountPresentation.accountCountDetail

    @Test("Account-count detail pluralizes, singular for exactly one account")
    func accountCountDetailPluralization() {
        #expect(AccountPresentation.accountCountDetail(0) == "Across 0 accounts")
        #expect(AccountPresentation.accountCountDetail(1) == "Across 1 account")
        #expect(AccountPresentation.accountCountDetail(2) == "Across 2 accounts")
        #expect(AccountPresentation.accountCountDetail(42) == "Across 42 accounts")
    }

    // MARK: - MultiCurrencyBalancePresentation.metricDetail

    @Test("Single-currency aggregation has a converted total, so the fallback copy wins")
    func metricDetailReturnsFallbackWhenTotalAvailable() {
        let aggregation = CurrencyAggregation.aggregate([(amount: 100, currency: .usd)])
        // A single resolved currency yields an exact headline total, so the
        // contextual fallback copy is surfaced verbatim.
        #expect(
            MultiCurrencyBalancePresentation.metricDetail(
                from: aggregation,
                fallback: "Across 3 accounts"
            ) == "Across 3 accounts"
        )
    }

    @Test("Mixed, unpriceable currencies surface the honest disclosure instead of the fallback")
    func metricDetailReturnsDisclosureWhenNoTotal() {
        let aggregation = CurrencyAggregation.aggregate([
            (amount: 100, currency: .usd),
            (amount: 200, currency: CurrencyCode("EUR")),
        ])
        let detail = MultiCurrencyBalancePresentation.metricDetail(
            from: aggregation,
            fallback: "Across 2 accounts"
        )
        // No conversion source → no single total → the per-currency disclosure
        // replaces the fallback. Pinned to the prior inline output verbatim.
        #expect(detail == "Multiple currencies — no conversion rates available. Shown per currency below.")
        #expect(detail != "Across 2 accounts")
    }
}
