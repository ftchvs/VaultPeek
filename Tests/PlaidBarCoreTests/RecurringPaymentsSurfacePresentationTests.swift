import Testing
@testable import PlaidBarCore

@Suite("Recurring Payments Surface Presentation")
struct RecurringPaymentsSurfacePresentationTests {
    private static let asOf = Formatters.parseTransactionDate("2026-05-01")!

    @Test("Rows expose merchant, amount, cadence, dates, confidence, and monthly equivalent")
    func rowPresentationIncludesRequiredFields() throws {
        let presentation = RecurringPaymentsSurfacePresentation.make(
            from: [
                Self.recurring(
                    merchantName: "StreamCo",
                    frequency: .annual,
                    averageAmount: 120,
                    lastDate: "2026-04-01",
                    nextExpectedDate: "2027-04-01",
                    confidence: 0.85
                ),
            ],
            asOf: Self.asOf
        )

        let row = try! #require(presentation.rows.first)

        #expect(row.merchantName == "StreamCo")
        #expect(row.amountText == "$120")
        #expect(row.frequencyText == "Annual")
        #expect(row.lastChargeText.contains("Apr"))
        #expect(row.nextExpectedText.contains("2027"))
        #expect(row.confidenceText == "Confident")
        #expect(row.monthlyEquivalentText == "$10/mo")
        #expect(row.accessibilityLabel.contains("monthly equivalent"))
    }

    @Test("Estimated monthly total excludes stale streams")
    func monthlyTotalTextExcludesStaleStreams() {
        let presentation = RecurringPaymentsSurfacePresentation.make(
            from: [
                Self.recurring(merchantName: "Active", averageAmount: 30, lastDate: "2026-04-15"),
                Self.recurring(merchantName: "Dormant", averageAmount: 50, lastDate: "2026-01-01"),
            ],
            asOf: Self.asOf
        )

        #expect(presentation.estimatedMonthlyTotalText == "$30")
        #expect(presentation.summaryText.contains("2 detected streams"))
        #expect(presentation.attentionCount == 1)
    }

    @Test("Changed and stale streams include explanatory text")
    func flagExplanationsDescribeChangedAndStaleStreams() throws {
        let presentation = RecurringPaymentsSurfacePresentation.make(
            from: [
                Self.recurring(
                    merchantName: "Gym",
                    latestAmount: 22,
                    trailingAverageAmount: 20,
                    confidence: 0.95
                ),
                Self.recurring(merchantName: "Old Plan", lastDate: "2026-01-01"),
            ],
            asOf: Self.asOf
        )

        let gym = try! #require(presentation.rows.first { $0.merchantName == "Gym" })
        let oldPlan = try! #require(presentation.rows.first { $0.merchantName == "Old Plan" })

        #expect(gym.flagExplanations.contains("Latest charge is higher than the prior pattern."))
        #expect(oldPlan.flagExplanations.contains("Expected charge has not appeared recently."))
        #expect(gym.needsAttention)
        #expect(oldPlan.needsAttention)
    }

    @Test("Empty and low-confidence states use honest, non-alarming copy")
    func emptyAndLowConfidenceCopy() throws {
        let empty = RecurringPaymentsSurfacePresentation.make(from: [], asOf: Self.asOf)

        #expect(empty.isEmpty)
        #expect(empty.emptyTitle == "No recurring payments detected")
        #expect(empty.emptyDetail.contains("after it sees a repeated merchant pattern"))
        #expect(empty.summaryText == "No recurring payments detected yet.")

        let lowConfidence = RecurringPaymentsSurfacePresentation.make(
            from: [
                Self.recurring(merchantName: "Maybe Cloud", confidence: 0.45),
            ],
            asOf: Self.asOf
        )
        let row = try! #require(lowConfidence.rows.first)

        #expect(lowConfidence.lowConfidenceCount == 1)
        #expect(lowConfidence.summaryText.contains("1 low confidence"))
        #expect(row.confidenceText == "Low confidence")
        #expect(row.flagExplanations.contains("Pattern is still low confidence."))
        #expect(!row.needsAttention)
    }

    private static func recurring(
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
}
