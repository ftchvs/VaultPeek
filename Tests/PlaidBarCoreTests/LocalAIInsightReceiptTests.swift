@testable import PlaidBarCore
import Testing

@Suite("Local AI Insight Receipt Tests")
struct LocalAIInsightReceiptTests {
    @Test("Receipt presents local evidence without raw source identifiers")
    func receiptPresentsDisplaySafeEvidence() {
        let input = makeInput(transactionCount: 2, includeCategorySuggestion: false)
        let summary = LocalAIActivitySummary(
            window: .last7days,
            availability: Self.disabledAvailability,
            input: input,
            generatedSummary: "accountSecretIdentifier and transactionSecretIdentifier should not appear in the receipt headline.",
            generatedBullets: [],
            evidence: input.evidence
        )

        let receipt = LocalAIInsightReceipt.make(summary: summary, availability: Self.disabledAvailability)

        #expect(receipt.title == "Local Insight Receipt")
        #expect(receipt.localOnlyBadge == "Local-only")
        #expect(receipt.timeWindow == "2026-06-05 to 2026-06-11")
        #expect(receipt.evidenceChips.map(\.id).contains("transactions"))
        #expect(receipt.evidenceChips.contains { $0.id == "window" && $0.value == "2026-06-05 to 2026-06-11" })
        #expect(receipt.evidenceChips.map(\.id).contains("top-category"))
        #expect(receipt.confidence.contains("Deterministic confidence"))
        #expect(receipt.limitations.contains { $0.contains("raw IDs and Plaid payloads are excluded") })
        #expect(!receipt.headline.contains("accountSecretIdentifier"))
        #expect(!receipt.headline.contains("transactionSecretIdentifier"))
        #expect(!receipt.accessibilitySummary.contains("accountSecretIdentifier"))
        #expect(!receipt.accessibilitySummary.contains("transactionSecretIdentifier"))
    }

    @Test("Receipt redacts recurring evidence ids and longest overlapping ids first")
    func receiptRedactsRecurringAndOverlappingIdentifiers() {
        let input = makeInput(
            transactionCount: 2,
            includeCategorySuggestion: false,
            recurringSourceId: "subscriptionSecretIdentifierLong",
            extraEvidenceSourceId: "subscriptionSecretIdentifier"
        )
        let summary = LocalAIActivitySummary(
            window: .last7days,
            availability: Self.disabledAvailability,
            input: input,
            generatedSummary: "subscriptionSecretIdentifierLong and subscriptionSecretIdentifier must both be hidden.",
            generatedBullets: [],
            evidence: input.evidence
        )

        let receipt = LocalAIInsightReceipt.make(summary: summary, availability: Self.disabledAvailability)

        #expect(!receipt.headline.contains("subscriptionSecretIdentifierLong"))
        #expect(!receipt.headline.contains("subscriptionSecretIdentifier"))
        #expect(!receipt.headline.contains("Long"))
        #expect(receipt.headline.contains("[redacted] and [redacted]"))
    }

    @Test("Receipt explains unavailable local runtime without cloud fallback")
    func receiptExplainsUnavailableLocalRuntime() {
        let unavailable = LocalAIAvailability(
            state: .unavailable,
            runtimeName: "local-runtime",
            detail: "Local runtime is not reachable. Cloud models are not supported."
        )

        let receipt = LocalAIInsightReceipt.make(summary: nil, availability: unavailable)

        #expect(receipt.unavailableState == "Configured local runtime is unavailable. Cloud AI fallback is not supported.")
        #expect(receipt.limitations.contains { $0.contains("Cloud models are not supported") })
        #expect(receipt.limitations.contains { $0.contains("will not call a cloud AI service") })
        #expect(receipt.reversibleActionCopy.contains("No insight action is available yet"))
    }

    @Test("Receipt makes category hint action reversible and non-mutating")
    func receiptExplainsReversibleCategoryHintAction() {
        let input = makeInput(transactionCount: 1, includeCategorySuggestion: true)
        let summary = LocalAIActivitySummary(
            window: .last7days,
            availability: Self.disabledAvailability,
            input: input,
            generatedSummary: "categoryEvidenceSecretIdentifier categoryEvidenceTransactionSecret categoryEvidenceAccountSecret",
            generatedBullets: [],
            evidence: input.evidence
        )

        let receipt = LocalAIInsightReceipt.make(summary: summary, availability: Self.disabledAvailability)

        #expect(receipt.evidenceChips.contains { $0.id == "category-hints" && $0.value == "1" })
        #expect(receipt.reversibleActionCopy.contains("reversible"))
        #expect(receipt.reversibleActionCopy.contains("does not mutate raw Plaid records"))
        #expect(!receipt.headline.contains("categoryEvidenceSecretIdentifier"))
        #expect(!receipt.headline.contains("categoryEvidenceTransactionSecret"))
        #expect(!receipt.headline.contains("categoryEvidenceAccountSecret"))
    }

    private static let disabledAvailability = LocalAIAvailability(
        state: .disabled,
        detail: "No local AI runtime is configured. VaultPeek is using deterministic local summaries and category hints only."
    )

    private func makeInput(
        transactionCount: Int,
        includeCategorySuggestion: Bool,
        recurringSourceId: String? = nil,
        extraEvidenceSourceId: String? = nil
    ) -> LocalAIActivitySummaryInput {
        var evidence = [
            LocalAIInsightEvidence(
                kind: .transaction,
                sourceId: "transactionSecretIdentifier",
                label: "Display-safe category evidence",
                transactionIds: ["transactionSecretIdentifier"],
                accountIds: ["accountSecretIdentifier"],
                amount: 42,
                date: "2026-06-11"
            ),
        ]
        if let extraEvidenceSourceId {
            evidence.append(LocalAIInsightEvidence(
                kind: .localHeuristic,
                sourceId: extraEvidenceSourceId,
                label: "Overlapping source id evidence"
            ))
        }
        let categoryTotal = LocalAICategoryTotal(
            category: .foodAndDrink,
            totalAmount: 42,
            transactionCount: transactionCount,
            transactionIds: ["transactionSecretIdentifier"],
            evidence: evidence
        )
        let current = LocalAIActivityMetrics(
            transactionCount: transactionCount,
            incomeTotal: 0,
            expenseTotal: 42,
            netCashflow: -42,
            incomeTransactionIds: [],
            expenseTransactionIds: ["transactionSecretIdentifier"],
            transferTransactionIds: [],
            categoryTotals: [categoryTotal],
            topExpenses: [],
            topIncome: []
        )
        let suggestions = includeCategorySuggestion
            ? [
                LocalAICategorySuggestion(
                    transactionId: "transactionSecretIdentifier",
                    suggestedCategory: .foodAndDrink,
                    confidence: 0.91,
                    evidence: [
                        LocalAIInsightEvidence(
                            kind: .plaidCategory,
                            sourceId: "categoryEvidenceSecretIdentifier",
                            label: "Category suggestion evidence",
                            transactionIds: ["categoryEvidenceTransactionSecret"],
                            accountIds: ["categoryEvidenceAccountSecret"]
                        ),
                    ]
                ),
            ]
            : []

        let recurringItems: [LocalAIRecurringInsightItem]
        if let recurringSourceId {
            recurringItems = [
                LocalAIRecurringInsightItem(
                    id: recurringSourceId,
                    merchantName: "Streaming Demo",
                    frequency: .monthly,
                    estimatedMonthlyAmount: 12,
                    category: .entertainment,
                    transactionCount: 1,
                    confidence: 0.9,
                    evidence: [
                        LocalAIInsightEvidence(
                            kind: .recurringTransaction,
                            sourceId: recurringSourceId,
                            label: "Recurring local evidence",
                            transactionIds: [recurringSourceId],
                            accountIds: ["accountSecretIdentifier"]
                        ),
                    ]
                ),
            ]
        } else {
            recurringItems = []
        }

        return LocalAIActivitySummaryInput(
            window: .last7days,
            currentRange: LocalAIInsightDateRange(startDate: "2026-06-05", endDate: "2026-06-11"),
            priorRange: nil,
            categorySuggestions: suggestions,
            accountSnapshot: LocalAIAccountSnapshot(
                accountCount: 1,
                accountIds: ["accountSecretIdentifier"],
                cashTotal: 100,
                debtTotal: 0,
                creditUtilization: nil
            ),
            current: current,
            prior: nil,
            recurringSnapshot: LocalAIRecurringSnapshot(estimatedMonthlyTotal: recurringItems.isEmpty ? 0 : 12, items: recurringItems),
            evidence: evidence
        )
    }
}
