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
        #expect(Formatters.currency(1_500, format: .abbreviated, currencyCode: "EUR") == "EUR1.5K")
    }

    @Test("Percent formats with the requested precision")
    func percent() {
        #expect(Formatters.percent(42.5, decimals: 1) == "42.5%")
        #expect(Formatters.percent(42, decimals: 0) == "42%")
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
}
