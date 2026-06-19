import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the AND-559 committed-recurring rollup. The helper must:
/// - sum each stream's monthly-equivalent cost into its category,
/// - normalize non-monthly cadences via `RecurringFrequency.monthlyMultiplier`,
/// - skip streams with no category, a transfer category, or a non-positive amount,
/// - and only ever map a category to a strictly-positive amount (absent == none).
@Suite("Recurring commitment rollup (AND-559)")
struct RecurringCommitmentTests {
    private func stream(
        _ merchant: String,
        amount: Double,
        frequency: RecurringFrequency,
        category: SpendingCategory?
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchant,
            frequency: frequency,
            averageAmount: amount,
            lastDate: "2026-06-01",
            nextExpectedDate: "2026-07-01",
            category: category,
            transactionCount: 6,
            confidence: 0.9
        )
    }

    @Test("A monthly stream commits its full amount to its category")
    func monthlyStream() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Netflix", amount: 15, frequency: .monthly, category: .subscriptions),
        ])
        #expect(result[.subscriptions] == 15)
    }

    @Test("A weekly stream is normalized to a monthly-equivalent cost")
    func weeklyNormalized() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Coffee plan", amount: 10, frequency: .weekly, category: .foodAndDrink),
        ])
        let expected = 10 * (52.0 / 12.0)
        #expect(abs((result[.foodAndDrink] ?? 0) - expected) < 0.0001)
    }

    @Test("An annual stream is spread across twelve months")
    func annualNormalized() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Insurance", amount: 1200, frequency: .annual, category: .billsAndUtilities),
        ])
        #expect(abs((result[.billsAndUtilities] ?? 0) - 100) < 0.0001)
    }

    @Test("Multiple streams in one category sum together")
    func sameCategorySums() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Netflix", amount: 15, frequency: .monthly, category: .subscriptions),
            stream("Spotify", amount: 12, frequency: .monthly, category: .subscriptions),
        ])
        #expect(result[.subscriptions] == 27)
    }

    @Test("Streams with no category are skipped (no ghost segment)")
    func nilCategorySkipped() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Unknown", amount: 30, frequency: .monthly, category: nil),
        ])
        #expect(result.isEmpty)
    }

    @Test("Transfer streams never count as category commitment")
    func transferSkipped() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Savings move", amount: 500, frequency: .monthly, category: .transfer),
            stream("Card payment", amount: 300, frequency: .monthly, category: .transferOut),
        ])
        #expect(result.isEmpty)
    }

    @Test("Non-positive amounts are ignored")
    func nonPositiveSkipped() {
        let result = RecurringCommitment.monthlyByCategory([
            stream("Zero", amount: 0, frequency: .monthly, category: .subscriptions),
            stream("Negative", amount: -10, frequency: .monthly, category: .subscriptions),
        ])
        #expect(result.isEmpty)
    }

    @Test("Empty input yields an empty map")
    func emptyInput() {
        #expect(RecurringCommitment.monthlyByCategory([]).isEmpty)
    }
}
