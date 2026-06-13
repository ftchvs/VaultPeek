import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Local Insight Model Runtime Tests")
struct LocalInsightModelRuntimeTests {
    @Test("Output validator accepts clean summaries and caps length")
    func validatorAcceptsAndCapsCleanSummary() {
        let prompt = LocalInsightPromptBuilder.make(from: input())
        let output = "Dining led spending this month, with groceries close behind. Net cashflow stayed positive after income."

        let result = LocalInsightModelOutputValidator.validate(
            output,
            prompt: prompt,
            maxCharacters: 42
        )

        #expect(result == .accepted(String(output.prefix(42))))
    }

    @Test("Output validator rejects empty, garbage, and echoed prompt output")
    func validatorRejectsUnsafeOutput() {
        let prompt = LocalInsightPromptBuilder.make(from: input())

        #expect(LocalInsightModelOutputValidator.validate("   ", prompt: prompt) == .rejected(.empty))
        #expect(LocalInsightModelOutputValidator.validate("!!!!!!!!!?????", prompt: prompt) == .rejected(.garbage))
        #expect(LocalInsightModelOutputValidator.validate(prompt.user, prompt: prompt) == .rejected(.echoedPrompt))
        #expect(LocalInsightModelOutputValidator.validate("Period: Last Month. Totals: expenses are listed.", prompt: prompt) == .rejected(.echoedPrompt))
    }

    @Test("Runtime falls back when no model is configured")
    func runtimeFallsBackWithoutModel() async {
        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: nil,
            fallbackSummary: { _ in "deterministic fallback" }
        )

        #expect(result.summary == "deterministic fallback")
        #expect(result.usedModelOutput == false)
        #expect(result.fallbackReason == .noModel)
    }

    @Test("Runtime accepts valid model output")
    func runtimeAcceptsValidModelOutput() async {
        let model = StubLocalInsightModel(result: .success("Food spending was the largest driver this month. Net cashflow stayed positive."))

        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: model,
            fallbackSummary: { _ in "deterministic fallback" }
        )

        #expect(result.summary == "Food spending was the largest driver this month. Net cashflow stayed positive.")
        #expect(result.usedModelOutput == true)
        #expect(result.fallbackReason == nil)
    }

    @Test("Runtime falls back when model output is invalid")
    func runtimeFallsBackForInvalidModelOutput() async {
        let model = StubLocalInsightModel(result: .success("Period: Last Month. Totals: expenses were listed."))

        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: model,
            fallbackSummary: { _ in "deterministic fallback" }
        )

        #expect(result.summary == "deterministic fallback")
        #expect(result.usedModelOutput == false)
        #expect(result.fallbackReason == .invalidOutput)
    }

    @Test("Runtime falls back on model error")
    func runtimeFallsBackForModelError() async {
        let model = StubLocalInsightModel(result: .failure(StubModelError()))

        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: model,
            fallbackSummary: { _ in "deterministic fallback" }
        )

        #expect(result.summary == "deterministic fallback")
        #expect(result.usedModelOutput == false)
        #expect(result.fallbackReason == .modelError)
    }

    @Test("Runtime falls back when model exceeds timeout")
    func runtimeFallsBackForTimeout() async {
        let model = DelayedLocalInsightModel(
            output: "Food spending was the largest driver this month.",
            delayNanoseconds: 20_000_000
        )

        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: model,
            fallbackSummary: { _ in "deterministic fallback" },
            configuration: LocalInsightModelGenerationConfiguration(timeoutNanoseconds: 1_000_000)
        )

        #expect(result.summary == "deterministic fallback")
        #expect(result.usedModelOutput == false)
        #expect(result.fallbackReason == .timeout)
    }

    @Test("Runtime timeout returns without waiting for cancellation-ignoring models")
    func runtimeTimeoutDoesNotWaitForCancellationIgnoringModel() async {
        let model = CancellationIgnoringLocalInsightModel(
            output: "Food spending was the largest driver this month.",
            delaySeconds: 0.2
        )
        let startedAt = Date()

        let result = await LocalInsightModelRuntime.generateSummary(
            input: input(),
            model: model,
            fallbackSummary: { _ in "deterministic fallback" },
            configuration: LocalInsightModelGenerationConfiguration(timeoutNanoseconds: 1_000_000)
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(result.summary == "deterministic fallback")
        #expect(result.usedModelOutput == false)
        #expect(result.fallbackReason == .timeout)
        #expect(elapsed < 0.15)
    }

    private func input() -> LocalAIActivitySummaryInput {
        let current = LocalAIActivityMetrics(
            transactionCount: 4,
            incomeTotal: 3000,
            expenseTotal: 420,
            netCashflow: 2580,
            incomeTransactionIds: [],
            expenseTransactionIds: [],
            transferTransactionIds: [],
            categoryTotals: [
                LocalAICategoryTotal(
                    category: .foodAndDrink,
                    totalAmount: 240,
                    transactionCount: 2,
                    transactionIds: [],
                    evidence: []
                ),
            ],
            topExpenses: [
                LocalAITransactionInsightItem(
                    transactionId: "redacted-test-transaction",
                    accountId: "redacted-test-account",
                    date: "2026-06-10",
                    displayName: "Grocery Demo",
                    amount: 120,
                    effectiveCategory: .foodAndDrink,
                    plaidCategory: .foodAndDrink,
                    categorySource: .plaidCategory,
                    pending: false,
                    evidence: []
                ),
            ],
            topIncome: []
        )

        return LocalAIActivitySummaryInput(
            window: .lastMonth,
            currentRange: LocalAIInsightDateRange(startDate: "2026-05-13", endDate: "2026-06-11"),
            priorRange: nil,
            accountSnapshot: LocalAIAccountSnapshot(
                accountCount: 1,
                accountIds: [],
                cashTotal: 3000,
                debtTotal: 0,
                creditUtilization: nil
            ),
            current: current,
            prior: nil,
            recurringSnapshot: LocalAIRecurringSnapshot(estimatedMonthlyTotal: 0, items: []),
            evidence: []
        )
    }
}

private struct StubLocalInsightModel: LocalInsightModel {
    let result: Result<String, Error>

    func summarize(_ prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        try result.get()
    }
}

private struct DelayedLocalInsightModel: LocalInsightModel {
    let output: String
    let delayNanoseconds: UInt64

    func summarize(_ prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return output
    }
}

private struct CancellationIgnoringLocalInsightModel: LocalInsightModel {
    let output: String
    let delaySeconds: TimeInterval

    func summarize(_ prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(delaySeconds)
        while Date() < deadline {
            _ = 1 + 1
        }
        return output
    }
}

private struct StubModelError: Error {}
