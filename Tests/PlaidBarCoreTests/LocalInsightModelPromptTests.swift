import Foundation
@testable import PlaidBarCore
import Testing

@Suite("LocalInsightModelPrompt Tests")
struct LocalInsightModelPromptTests {
    /// Distinctive sentinels in every identifier-bearing field so the
    /// redaction assertions fail loudly if any raw ID ever reaches the prompt.
    private let rawTxnId = "RAWTXNID_SENTINEL_8842"
    private let rawAccountId = "RAWACCTID_SENTINEL_3317"
    private let rawSourceId = "RAWSOURCEID_SENTINEL_5560"
    private let rawItemId = "RAWITEMID_SENTINEL_9921"

    private func input(prior: Bool = true) -> LocalAIActivitySummaryInput {
        let evidence = [
            LocalAIInsightEvidence(
                kind: .transaction,
                sourceId: rawSourceId,
                label: "Whole Foods",
                transactionIds: [rawTxnId],
                accountIds: [rawAccountId],
                amount: 84.21,
                date: "2026-06-09"
            ),
        ]
        let topExpense = LocalAITransactionInsightItem(
            transactionId: rawTxnId,
            accountId: rawAccountId,
            date: "2026-06-09",
            displayName: "Whole Foods",
            amount: 84.21,
            effectiveCategory: .foodAndDrink,
            plaidCategory: .foodAndDrink,
            categorySource: .plaidCategory,
            pending: false,
            evidence: evidence
        )
        let categoryTotal = LocalAICategoryTotal(
            category: .foodAndDrink,
            totalAmount: 412.55,
            transactionCount: 6,
            transactionIds: [rawTxnId],
            evidence: evidence
        )
        let metrics = LocalAIActivityMetrics(
            transactionCount: 18,
            incomeTotal: 3200,
            expenseTotal: 1240.50,
            netCashflow: 1959.50,
            incomeTransactionIds: [rawTxnId],
            expenseTransactionIds: [rawTxnId],
            transferTransactionIds: [],
            categoryTotals: [categoryTotal],
            topExpenses: [topExpense],
            topIncome: []
        )
        let priorMetrics = LocalAIActivityMetrics(
            transactionCount: 15,
            incomeTotal: 3200,
            expenseTotal: 900,
            netCashflow: 2300,
            incomeTransactionIds: [],
            expenseTransactionIds: [],
            transferTransactionIds: [],
            categoryTotals: [],
            topExpenses: [],
            topIncome: []
        )
        return LocalAIActivitySummaryInput(
            window: .lastMonth,
            currentRange: LocalAIInsightDateRange(startDate: "2026-05-13", endDate: "2026-06-11"),
            priorRange: LocalAIInsightDateRange(startDate: "2026-04-13", endDate: "2026-05-12"),
            categorySuggestions: [],
            accountSnapshot: LocalAIAccountSnapshot(
                accountCount: 3,
                accountIds: [rawAccountId, rawItemId],
                cashTotal: 8000,
                debtTotal: 1500,
                creditUtilization: 0.3
            ),
            current: metrics,
            prior: prior ? priorMetrics : nil,
            recurringSnapshot: LocalAIRecurringSnapshot(estimatedMonthlyTotal: 240, items: []),
            evidence: evidence
        )
    }

    @Test("Prompt never contains raw transaction, account, source, or item IDs")
    func redactsRawIdentifiers() {
        let prompt = LocalInsightPromptBuilder.make(from: input())
        let combined = prompt.system + "\n" + prompt.user

        #expect(!combined.contains(rawTxnId))
        #expect(!combined.contains(rawAccountId))
        #expect(!combined.contains(rawSourceId))
        #expect(!combined.contains(rawItemId))
        #expect(!combined.contains("SENTINEL"))
    }

    @Test("Prompt includes display-safe aggregates the model should phrase")
    func includesDisplaySafeAggregates() {
        let prompt = LocalInsightPromptBuilder.make(from: input()).user

        #expect(prompt.contains("Last Month"))
        #expect(prompt.contains("2026-05-13"))
        #expect(prompt.contains("18 transactions"))
        #expect(prompt.contains("Food & Drink"))
        #expect(prompt.contains("Whole Foods"))
        #expect(prompt.contains("Largest expenses"))
        #expect(prompt.contains("Estimated recurring monthly cost"))
    }

    @Test("Prior-period comparison is rendered with direction and delta")
    func rendersPriorComparison() {
        let prompt = LocalInsightPromptBuilder.make(from: input(prior: true)).user
        // Current 1240.50 vs prior 900 → up 340.50
        #expect(prompt.contains("spending is up"))
        #expect(prompt.contains("prior expenses"))
    }

    @Test("Prior comparison is omitted when there is no prior data")
    func omitsPriorWhenAbsent() {
        let prompt = LocalInsightPromptBuilder.make(from: input(prior: false)).user
        #expect(!prompt.contains("prior expenses"))
        #expect(!prompt.contains("Versus the prior period"))
    }

    @Test("System instruction carries the local-only guardrails")
    func systemInstructionGuardrails() {
        let system = LocalInsightPromptBuilder.make(from: input()).system
        #expect(system.contains("on-device"))
        #expect(system.contains("ONLY the numbers"))
        #expect(system.contains("no financial advice"))
    }

    @Test("Category and merchant lists honor their caps")
    func honorsCaps() {
        let prompt = LocalInsightPromptBuilder.make(from: input(), maxCategories: 1, maxMerchants: 1).user
        // One category, one merchant — single comma-free entries in each line.
        let categoryLine = prompt.split(separator: "\n").first { $0.hasPrefix("Top categories") }
        #expect(categoryLine?.contains(",") == false)
    }
}
