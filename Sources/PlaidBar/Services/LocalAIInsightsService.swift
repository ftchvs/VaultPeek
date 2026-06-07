import Foundation
import PlaidBarCore

struct LocalAIInsightsService {
    private enum EnvironmentKeys {
        static let localRuntime = "PLAIDBAR_LOCAL_AI_RUNTIME"
    }

    var availability: LocalAIAvailability {
        let runtime = ProcessInfo.processInfo.environment[EnvironmentKeys.localRuntime]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let runtime, !runtime.isEmpty, runtime.lowercased() != "disabled" else {
            return LocalAIAvailability(
                state: .disabled,
                detail: "No local AI runtime is configured. PlaidBar is using deterministic local summaries only."
            )
        }

        return LocalAIAvailability(
            state: .unavailable,
            runtimeName: runtime,
            detail: "Local runtime '\(runtime)' is configured, but this build has no model adapter yet. Cloud models are not supported."
        )
    }

    func activitySummaries(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        anchorDate: Date = Date()
    ) -> [LocalAIActivitySummary] {
        let inputs = LocalAIInsightInputBuilder.buildInputs(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            anchorDate: anchorDate
        )

        return inputs.map { input in
            LocalAIActivitySummary(
                window: input.window,
                availability: availability,
                input: input,
                generatedSummary: summaryText(for: input),
                generatedBullets: bullets(for: input),
                evidence: input.evidence
            )
        }
    }

    private func summaryText(for input: LocalAIActivitySummaryInput) -> String {
        let expenseText = Formatters.currency(input.current.expenseTotal, format: .compact)
        let incomeText = Formatters.currency(input.current.incomeTotal, format: .compact)
        let netText = signedCurrency(input.current.netCashflow)
        return "\(input.window.displayName): \(expenseText) expenses, \(incomeText) income, \(netText) net cashflow."
    }

    private func bullets(for input: LocalAIActivitySummaryInput) -> [String] {
        var bullets: [String] = []

        if let topCategory = input.current.categoryTotals.first {
            bullets
                .append(
                    "\(topCategory.category.displayName) led expenses at \(Formatters.currency(topCategory.totalAmount, format: .compact)) from \(topCategory.transactionCount) transaction\(topCategory.transactionCount == 1 ? "" : "s")."
                )
        }

        if let topExpense = input.current.topExpenses.first {
            bullets
                .append(
                    "Largest outflow was \(topExpense.displayName) at \(Formatters.currency(topExpense.amount, format: .compact))."
                )
        }

        if let prior = input.prior, prior.expenseTotal > 0 {
            let delta = input.current.expenseTotal - prior.expenseTotal
            let direction = delta >= 0 ? "up" : "down"
            bullets
                .append(
                    "Expenses are \(direction) \(Formatters.currency(abs(delta), format: .compact)) versus the comparison window."
                )
        }

        if input.current.netCashflow != 0 {
            bullets.append("Net cashflow is \(signedCurrency(input.current.netCashflow)) after income and expenses.")
        }

        if input.recurringSnapshot.estimatedMonthlyTotal > 0 {
            bullets
                .append(
                    "Recurring charges estimate \(Formatters.currency(input.recurringSnapshot.estimatedMonthlyTotal, format: .compact)) per month."
                )
        }

        if bullets.isEmpty {
            bullets.append("No transaction activity is available for this local summary window.")
        }

        return Array(bullets.prefix(4))
    }

    private func signedCurrency(_ amount: Double) -> String {
        let prefix = amount > 0 ? "+" : amount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(amount), format: .compact))"
    }
}
