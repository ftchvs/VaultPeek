import Testing
@testable import PlaidBarCore

@Suite("Recurring stream flags")
struct RecurringStreamFlagTests {
    @Test("Detector marks price increase at the relative and absolute thresholds")
    func detectorMarksPriceIncreaseAtThresholds() throws {
        let recurring = try #require(RecurringDetector.detect(from: [
            Self.transaction(id: "one", amount: 10, date: "2026-01-15"),
            Self.transaction(id: "two", amount: 10, date: "2026-02-15"),
            Self.transaction(id: "three", amount: 11, date: "2026-03-15"),
        ]).first)

        #expect(recurring.latestAmount == 11)
        #expect(recurring.trailingAverageAmount == 10)
        #expect(recurring.hasPriceIncrease)
        #expect(recurring.flags(asOf: "2026-03-16") == [RecurringStreamFlag.priceIncrease])
        #expect(abs((recurring.priceIncrease?.absoluteIncrease ?? 0) - 1) < 0.001)
        #expect(abs((recurring.priceIncrease?.relativeIncrease ?? 0) - 0.10) < 0.001)
    }

    @Test("Price increase requires confidence, relative, and absolute thresholds")
    func priceIncreaseRequiresAllThresholds() {
        let lowConfidence = Self.recurring(
            latestAmount: 11,
            trailingAverageAmount: 10,
            confidence: 0.59
        )
        let lowRelativeIncrease = Self.recurring(
            latestAmount: 21.50,
            trailingAverageAmount: 20,
            confidence: 0.9
        )
        let lowAbsoluteIncrease = Self.recurring(
            latestAmount: 5.50,
            trailingAverageAmount: 5,
            confidence: 0.9
        )

        #expect(!lowConfidence.hasPriceIncrease)
        #expect(!lowRelativeIncrease.hasPriceIncrease)
        #expect(!lowAbsoluteIncrease.hasPriceIncrease)
    }

    @Test("Stale stream starts after twice the expected interval")
    func staleStreamStartsAfterTwiceExpectedInterval() {
        let monthly = Self.recurring(lastDate: "2026-03-15")

        #expect(!monthly.isStale(asOf: "2026-05-14"))
        #expect(monthly.isStale(asOf: "2026-05-15"))
    }

    @Test("Flags combine stale and price increase")
    func flagsCombineStaleAndPriceIncrease() {
        let stream = Self.recurring(
            latestAmount: 12,
            trailingAverageAmount: 10,
            lastDate: "2026-03-15",
            confidence: 0.95
        )

        #expect(stream.flags(asOf: "2026-05-15") == [
            RecurringStreamFlag.priceIncrease,
            RecurringStreamFlag.stale,
        ])
    }

    @Test("Estimated monthly total can exclude stale streams")
    func estimatedMonthlyTotalCanExcludeStaleStreams() {
        let active = Self.recurring(
            averageAmount: 30,
            lastDate: "2026-04-15"
        )
        let stale = Self.recurring(
            merchantName: "Dormant Gym",
            averageAmount: 50,
            lastDate: "2026-03-01"
        )

        let asOf = Formatters.parseTransactionDate("2026-05-01")

        #expect(RecurringSummary.estimatedMonthlyTotal(from: [active, stale]) == 80)
        #expect(RecurringSummary.estimatedMonthlyTotal(from: [active, stale], asOf: asOf) == 30)
    }

    private static func transaction(
        id: String,
        amount: Double,
        date: String,
        merchantName: String = "StreamCo"
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: merchantName,
            merchantName: merchantName,
            category: .subscriptions
        )
    }

    private static func recurring(
        merchantName: String = "StreamCo",
        frequency: RecurringFrequency = .monthly,
        averageAmount: Double = 10,
        latestAmount: Double? = nil,
        trailingAverageAmount: Double? = nil,
        lastDate: String = "2026-03-15",
        confidence: Double = 0.9
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchantName,
            frequency: frequency,
            averageAmount: averageAmount,
            latestAmount: latestAmount,
            trailingAverageAmount: trailingAverageAmount,
            lastDate: lastDate,
            nextExpectedDate: "2026-04-15",
            category: .subscriptions,
            transactionCount: 3,
            confidence: confidence
        )
    }
}
