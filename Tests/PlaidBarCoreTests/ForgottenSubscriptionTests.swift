import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Forgotten subscription finder (AND-497)")
struct ForgottenSubscriptionTests {
    // A fixed "today" close to the streams' last charge so nothing is stale.
    private static let asOf = "2026-05-20"

    @Test("Long-lived low-cost monthly stream at the cycle threshold is forgotten")
    func longLivedLowCostStreamIsForgotten() {
        let stream = Self.recurring(
            averageAmount: 4.99,
            lastDate: "2026-05-10",
            transactionCount: PlaidBarConstants.forgottenSubscriptionMinimumCycles
        )
        #expect(stream.isForgotten(asOf: Self.asOf))
        #expect(stream.flags(asOf: Self.asOf).contains(.forgotten))
    }

    @Test("Stream below the cycle threshold is not forgotten")
    func belowCycleThresholdIsNotForgotten() {
        let stream = Self.recurring(
            averageAmount: 4.99,
            lastDate: "2026-05-10",
            transactionCount: PlaidBarConstants.forgottenSubscriptionMinimumCycles - 1
        )
        #expect(!stream.isForgotten(asOf: Self.asOf))
    }

    @Test("Stream above the cost ceiling is not forgotten")
    func aboveCostCeilingIsNotForgotten() {
        let stream = Self.recurring(
            averageAmount: PlaidBarConstants.forgottenSubscriptionMaxAmount + 0.01,
            lastDate: "2026-05-10",
            transactionCount: 12
        )
        #expect(!stream.isForgotten(asOf: Self.asOf))
    }

    @Test("Weekly/biweekly cadences are too frequent to be forgotten")
    func frequentCadencesAreNotForgotten() {
        for frequency in [RecurringFrequency.weekly, .biweekly] {
            let stream = Self.recurring(
                frequency: frequency,
                averageAmount: 4.99,
                lastDate: "2026-05-18",
                transactionCount: 20
            )
            #expect(!stream.isForgotten(asOf: Self.asOf))
        }
    }

    @Test("Non-subscription categories are not forgotten")
    func unrelatedCategoriesAreNotForgotten() {
        let stream = Self.recurring(
            averageAmount: 4.99,
            lastDate: "2026-05-10",
            transactionCount: 12,
            category: .foodAndDrink
        )
        #expect(!stream.isForgotten(asOf: Self.asOf))
    }

    @Test("Stale streams are reported as stale, never forgotten (stale precedence)")
    func staleStreamsAreNotForgotten() {
        // Last charge two-plus intervals ago -> stale, so forgotten must be false.
        let stream = Self.recurring(
            averageAmount: 4.99,
            lastDate: "2026-02-01",
            transactionCount: 12
        )
        #expect(stream.isStale(asOf: Self.asOf))
        #expect(!stream.isForgotten(asOf: Self.asOf))
        let flags = stream.flags(asOf: Self.asOf)
        #expect(flags.contains(.stale))
        #expect(!flags.contains(.forgotten))
    }

    @Test("flags includes both forgotten and price increase when both hold")
    func forgottenAndPriceIncreaseCombine() {
        let stream = Self.recurring(
            averageAmount: 4.99,
            latestAmount: 6.99,
            trailingAverageAmount: 4.99,
            lastDate: "2026-05-10",
            transactionCount: 12,
            confidence: 0.95
        )
        #expect(stream.hasPriceIncrease)
        let flags = stream.flags(asOf: Self.asOf)
        #expect(flags.contains(.forgotten))
        #expect(flags.contains(.priceIncrease))
    }

    @Test("Detected via RecurringDetector: 8 monthly $4.99 charges flag forgotten")
    func detectorProducesForgottenStream() throws {
        // Build 8 monthly occurrences ending ~10 days before asOf.
        var transactions: [TransactionDTO] = []
        let calendar = Calendar(identifier: .gregorian)
        let asOfDate = try #require(Formatters.parseTransactionDate("2026-05-20"))
        for monthsAgo in 0..<8 {
            let date = calendar.date(byAdding: .day, value: -(10 + monthsAgo * 30), to: asOfDate)!
            transactions.append(
                TransactionDTO(
                    id: "cv-\(monthsAgo)",
                    accountId: "checking",
                    amount: 4.99,
                    date: Formatters.transactionDateString(date),
                    name: "CLOUDVAULT",
                    merchantName: "CloudVault",
                    category: .subscriptions
                )
            )
        }
        let recurring = try #require(RecurringDetector.detect(from: transactions).first)
        #expect(recurring.transactionCount >= PlaidBarConstants.forgottenSubscriptionMinimumCycles)
        #expect(recurring.isForgotten(asOf: asOfDate, calendar: calendar))
    }

    @Test("Forgotten items sort ahead of plain attention and due-soon items")
    func forgottenSortsFirst() {
        let forgotten = Self.recurring(
            merchantName: "CloudVault",
            averageAmount: 4.99,
            lastDate: "2026-05-10",
            nextExpectedDate: "2026-06-10",
            transactionCount: 12
        )
        // A price-increase (attention) stream that is NOT forgotten.
        let attention = Self.recurring(
            merchantName: "BigSaaS",
            averageAmount: 80,
            latestAmount: 100,
            trailingAverageAmount: 80,
            lastDate: "2026-05-15",
            nextExpectedDate: "2026-06-01",
            transactionCount: 5,
            confidence: 0.95
        )
        // A plain due-soon stream with no flags.
        let plain = Self.recurring(
            merchantName: "Plain",
            averageAmount: 40,
            lastDate: "2026-05-18",
            nextExpectedDate: "2026-05-25",
            transactionCount: 4
        )

        let date = Formatters.parseTransactionDate(Self.asOf)!
        let presentation = RecurringObligationsPresentation.make(
            from: [plain, attention, forgotten],
            asOf: date,
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(presentation.items.first?.merchantName == "CloudVault")
        #expect(presentation.items.first?.isForgotten == true)
        #expect(presentation.forgottenCount == 1)
        // attention (flagged but not forgotten) ranks ahead of the plain stream.
        let order = presentation.items.map(\.merchantName)
        #expect(order.firstIndex(of: "BigSaaS")! < order.firstIndex(of: "Plain")!)
    }

    @Test("Surface presentation builds a forgotten callout and per-row flag")
    func surfaceBuildsForgottenCallout() {
        let forgotten = Self.recurring(
            merchantName: "Netflix",
            averageAmount: 9.99,
            lastDate: "2026-05-10",
            nextExpectedDate: "2026-06-10",
            transactionCount: 12,
            category: .entertainment
        )
        let date = Formatters.parseTransactionDate(Self.asOf)!
        let surface = RecurringPaymentsSurfacePresentation.make(
            from: [forgotten],
            asOf: date,
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(surface.forgottenCount == 1)
        #expect(surface.forgottenCalloutText != nil)
        let row = surface.rows.first
        #expect(row?.isForgotten == true)
        // Netflix is in the cancel-guidance map -> a specific (non-generic) link.
        #expect(row?.cancelIsSpecific == true)
        #expect(row?.flagExplanations.contains(where: { $0.contains("forgotten") }) == true)
    }

    @Test("Demo fixtures expose at least one forgotten subscription")
    func demoFixturesExposeForgotten() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let recurring = RecurringDetector.detect(from: DemoFixtures.transactions(now: now, calendar: calendar))
        let forgotten = recurring.filter { $0.isForgotten(asOf: now, calendar: calendar) }
        #expect(!forgotten.isEmpty)
    }

    // MARK: - Helpers

    private static func recurring(
        merchantName: String = "StreamCo",
        frequency: RecurringFrequency = .monthly,
        averageAmount: Double = 4.99,
        latestAmount: Double? = nil,
        trailingAverageAmount: Double? = nil,
        lastDate: String = "2026-05-10",
        nextExpectedDate: String = "2026-06-10",
        transactionCount: Int = 12,
        confidence: Double = 0.9,
        category: SpendingCategory? = .subscriptions
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchantName,
            frequency: frequency,
            averageAmount: averageAmount,
            latestAmount: latestAmount,
            trailingAverageAmount: trailingAverageAmount,
            lastDate: lastDate,
            nextExpectedDate: nextExpectedDate,
            category: category,
            transactionCount: transactionCount,
            confidence: confidence
        )
    }
}
