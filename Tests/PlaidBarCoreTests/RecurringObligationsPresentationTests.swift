import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Recurring Obligations Presentation")
struct RecurringObligationsPresentationTests {
    private static let asOf = Formatters.parseTransactionDate("2026-05-01")!

    private func recurring(
        merchantName: String,
        frequency: RecurringFrequency = .monthly,
        averageAmount: Double = 10,
        latestAmount: Double? = nil,
        trailingAverageAmount: Double? = nil,
        lastDate: String = "2026-04-15",
        nextExpectedDate: String = "2026-05-15",
        confidence: Double = 0.9
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchantName,
            frequency: frequency,
            averageAmount: averageAmount,
            latestAmount: latestAmount,
            trailingAverageAmount: trailingAverageAmount,
            lastDate: lastDate,
            nextExpectedDate: nextExpectedDate,
            category: .subscriptions,
            transactionCount: 3,
            confidence: confidence
        )
    }

    @Test("Empty input yields an empty, zeroed presentation")
    func emptyInput() {
        let presentation = RecurringObligationsPresentation.make(from: [], asOf: Self.asOf)

        #expect(presentation.isEmpty)
        #expect(presentation.count == 0)
        #expect(presentation.estimatedMonthlyTotal == 0)
        #expect(presentation.attentionCount == 0)
    }

    @Test("Flagged obligations sort ahead of clean ones, then by soonest due")
    func attentionFirstThenSoonestDue() {
        let clean = recurring(merchantName: "Spotify", nextExpectedDate: "2026-05-10")
        let cleanLater = recurring(merchantName: "iCloud", nextExpectedDate: "2026-05-20")
        // Price increase → flagged, but due last; must still sort first.
        let flagged = recurring(
            merchantName: "Gym",
            latestAmount: 22,
            trailingAverageAmount: 20,
            nextExpectedDate: "2026-05-28",
            confidence: 0.95
        )

        let presentation = RecurringObligationsPresentation.make(
            from: [clean, cleanLater, flagged],
            asOf: Self.asOf
        )

        #expect(presentation.items.map(\.merchantName) == ["Gym", "Spotify", "iCloud"])
        #expect(presentation.items.first?.hasPriceIncrease == true)
    }

    @Test("Attention count includes price-increase and missing (stale) streams")
    func attentionCountCountsFlaggedStreams() {
        let priceUp = recurring(
            merchantName: "Gym",
            latestAmount: 22,
            trailingAverageAmount: 20,
            confidence: 0.95
        )
        // lastDate far in the past → stale/missing relative to asOf 2026-05-01.
        let missing = recurring(merchantName: "Dormant", lastDate: "2026-01-01")
        let healthy = recurring(merchantName: "Spotify")

        let presentation = RecurringObligationsPresentation.make(
            from: [priceUp, missing, healthy],
            asOf: Self.asOf
        )

        #expect(presentation.attentionCount == 2)
        #expect(presentation.items.first { $0.merchantName == "Dormant" }?.isStale == true)
        #expect(presentation.items.first { $0.merchantName == "Spotify" }?.needsAttention == false)
    }

    @Test("Estimated monthly total excludes stale streams and matches RecurringSummary")
    func estimatedMonthlyTotalExcludesStale() {
        let active = recurring(merchantName: "Active", averageAmount: 30, lastDate: "2026-04-20")
        let stale = recurring(merchantName: "Dormant", averageAmount: 50, lastDate: "2026-01-01")

        let presentation = RecurringObligationsPresentation.make(from: [active, stale], asOf: Self.asOf)

        // Only the active monthly stream counts toward the total.
        #expect(presentation.estimatedMonthlyTotal == 30)
        #expect(
            presentation.estimatedMonthlyTotal
                == RecurringSummary.estimatedMonthlyTotal(from: [active, stale], asOf: Self.asOf)
        )
    }

    @Test("Monthly-equivalent normalizes weekly and annual cadences")
    func monthlyEquivalentNormalizesCadence() {
        let weekly = recurring(merchantName: "Coffee", frequency: .weekly, averageAmount: 5)
        let annual = recurring(merchantName: "Domain", frequency: .annual, averageAmount: 120)

        let presentation = RecurringObligationsPresentation.make(from: [weekly, annual], asOf: Self.asOf)

        let coffee = try! #require(presentation.items.first { $0.merchantName == "Coffee" })
        let domain = try! #require(presentation.items.first { $0.merchantName == "Domain" })

        #expect(abs(coffee.monthlyEquivalent - 5 * (52.0 / 12.0)) < 0.001)
        #expect(abs(domain.monthlyEquivalent - 10) < 0.001) // 120 / 12
    }

    @Test("Confidence bands map to high/medium/low at the documented thresholds")
    func confidenceLevelThresholds() {
        #expect(RecurringConfidenceLevel(confidence: 0.85) == .high)
        #expect(RecurringConfidenceLevel(confidence: 0.80) == .high)
        #expect(RecurringConfidenceLevel(confidence: 0.70) == .medium)
        #expect(RecurringConfidenceLevel(confidence: 0.60) == .medium)
        #expect(RecurringConfidenceLevel(confidence: 0.59) == .low)
    }

    @Test("countLabel pluralizes only the noun (0 / 1 / many)")
    func countLabelGrammar() {
        let none = RecurringObligationsPresentation.make(from: [], asOf: Self.asOf)
        #expect(none.countLabel == "0 recurring charges")

        let one = RecurringObligationsPresentation.make(from: [recurring(merchantName: "Spotify")], asOf: Self.asOf)
        #expect(one.countLabel == "1 recurring charge")

        let many = RecurringObligationsPresentation.make(
            from: [recurring(merchantName: "Spotify"), recurring(merchantName: "iCloud")],
            asOf: Self.asOf
        )
        #expect(many.countLabel == "2 recurring charges")
    }

    @Test("detailLine appends the attention clause only when something is flagged")
    func detailLineAttentionClause() {
        // No flags → just the count phrase.
        let clean = RecurringObligationsPresentation.make(
            from: [recurring(merchantName: "Spotify"), recurring(merchantName: "iCloud")],
            asOf: Self.asOf
        )
        #expect(clean.attentionCount == 0)
        #expect(clean.detailLine == "2 recurring charges")

        // One flagged (price increase) → mid-dot attention clause.
        let flagged = RecurringObligationsPresentation.make(
            from: [
                recurring(merchantName: "Gym", latestAmount: 22, trailingAverageAmount: 20, confidence: 0.95),
                recurring(merchantName: "Spotify"),
            ],
            asOf: Self.asOf
        )
        #expect(flagged.attentionCount == 1)
        // "N need attention" is intentionally NOT pluralized on N (pre-existing copy).
        #expect(flagged.detailLine == "2 recurring charges · 1 need attention")

        // Multiple flagged → clause carries the count; still no verb pluralization.
        let multiFlagged = RecurringObligationsPresentation.make(
            from: [
                recurring(merchantName: "Gym", latestAmount: 22, trailingAverageAmount: 20, confidence: 0.95),
                recurring(merchantName: "Dormant", lastDate: "2026-01-01"),
                recurring(merchantName: "Spotify"),
            ],
            asOf: Self.asOf
        )
        #expect(multiFlagged.attentionCount == 2)
        #expect(multiFlagged.detailLine == "3 recurring charges · 2 need attention")
    }

    @Test("Stream flags expose label + icon so they never read through color alone")
    func flagDisplayMetadata() {
        #expect(RecurringStreamFlag.priceIncrease.label == "Price up")
        #expect(!RecurringStreamFlag.priceIncrease.iconName.isEmpty)
        #expect(RecurringStreamFlag.stale.label == "Missing")
        #expect(!RecurringStreamFlag.stale.iconName.isEmpty)
        #expect(RecurringStreamFlag.priceIncrease.accessibilityDescription == "price increased")
    }
}
