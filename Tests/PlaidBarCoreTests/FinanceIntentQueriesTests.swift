import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Finance App Intent query helpers")
struct FinanceIntentQueriesTests {
    // MARK: - Privacy (D3)

    @Test("Masked snapshot withholds safe-to-spend with a value-free dialog")
    func maskedSnapshotWithholdsSafeToSpend() {
        let resolution = FinanceIntentQueries.safeToSpend(from: snapshot(safeToSpend: 4_321, isMasked: true))
        guard case let .withheld(dialog) = resolution else {
            Issue.record("Expected .withheld, got \(resolution)")
            return
        }
        #expect(!dialog.contains("4,321"))
        #expect(!dialog.contains("4321"))
    }

    @Test("Masked snapshot withholds every query")
    func maskedSnapshotWithholdsEveryQuery() {
        let masked = snapshot(isMasked: true)
        for resolution in [
            FinanceIntentQueries.safeToSpend(from: masked),
            FinanceIntentQueries.totalBalance(from: masked),
            FinanceIntentQueries.nextRecurringBills(from: masked),
            FinanceIntentQueries.creditUtilization(from: masked),
        ] {
            guard case .withheld = resolution else {
                Issue.record("Expected .withheld, got \(resolution)")
                continue
            }
        }
    }

    // MARK: - Unavailable

    @Test("Nil snapshot reports unavailable")
    func nilSnapshotReportsUnavailable() {
        guard case .unavailable = FinanceIntentQueries.safeToSpend(from: nil) else {
            Issue.record("Expected .unavailable for nil snapshot")
            return
        }
    }

    @Test("Empty snapshot reports unavailable")
    func emptySnapshotReportsUnavailable() {
        guard case .unavailable = FinanceIntentQueries.totalBalance(from: .placeholder()) else {
            Issue.record("Expected .unavailable for empty snapshot")
            return
        }
    }

    // MARK: - Values

    @Test("Safe to spend returns the value and a positive dialog")
    func safeToSpendReturnsValue() {
        guard case let .value(value, dialog) = FinanceIntentQueries.safeToSpend(from: snapshot(safeToSpend: 1_500)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 1_500)
        #expect(dialog.contains("safe to spend"))
    }

    @Test("Negative safe to spend reports an over-budget dialog")
    func negativeSafeToSpendReportsOverBudget() {
        guard case let .value(value, dialog) = FinanceIntentQueries.safeToSpend(from: snapshot(safeToSpend: -200)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == -200)
        #expect(dialog.lowercased().contains("over budget"))
    }

    @Test("Total balance returns the value")
    func totalBalanceReturnsValue() {
        guard case let .value(value, _) = FinanceIntentQueries.totalBalance(from: snapshot(totalBalance: 8_400)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 8_400)
    }

    @Test("Mixed-currency balances do not return arbitrary numeric value intents")
    func mixedCurrencyBalancesReturnMessageInsteadOfScalarValues() {
        let mixed = snapshot(
            totalBalance: 8_400,
            currencySubtotals: [
                FinanceSnapshot.CurrencySubtotal(currency: .usd, amount: 5_000),
                FinanceSnapshot.CurrencySubtotal(currency: CurrencyCode("EUR"), amount: 2_000),
            ]
        )

        for resolution in [
            FinanceIntentQueries.safeToSpend(from: mixed),
            FinanceIntentQueries.totalBalance(from: mixed),
            FinanceIntentQueries.showSpending(from: mixed),
        ] {
            guard case let .message(text) = resolution else {
                Issue.record("Expected .message for mixed currencies, got \(resolution)")
                continue
            }
            #expect(text.contains("multiple currencies"))
            #expect(text.contains("USD"))
            #expect(text.contains("EUR"))
        }
    }

    @Test("Credit utilization returns the percent value")
    func creditUtilizationReturnsValue() {
        guard case let .value(value, dialog) = FinanceIntentQueries.creditUtilization(from: snapshot(creditUtilization: 42)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 42)
        #expect(dialog.contains("utilization"))
    }

    @Test("Credit utilization without a known limit reports a message")
    func creditUtilizationWithoutLimitReportsMessage() {
        guard case .message = FinanceIntentQueries.creditUtilization(from: snapshot(creditUtilization: nil)) else {
            Issue.record("Expected .message when no credit limit is known")
            return
        }
    }

    // MARK: - Bills

    @Test("Next bills lists merchants and amounts")
    func nextBillsListsMerchants() {
        let bills = [
            FinanceSnapshot.UpcomingBill(merchantName: "Netflix", amount: 15.99, nextExpectedDate: "2026-07-02"),
            FinanceSnapshot.UpcomingBill(merchantName: "Gym", amount: 40, nextExpectedDate: "2026-07-05"),
        ]
        guard case let .message(text) = FinanceIntentQueries.nextRecurringBills(from: snapshot(bills: bills)) else {
            Issue.record("Expected .message")
            return
        }
        #expect(text.contains("Netflix"))
        #expect(text.contains("Gym"))
    }

    @Test("Next bills summarizes the remainder beyond the spoken cap")
    func nextBillsSummarizesRemainder() {
        let bills = (0..<5).map { index in
            FinanceSnapshot.UpcomingBill(
                merchantName: "Bill\(index)",
                amount: Double(index + 1),
                nextExpectedDate: "2026-07-0\(index + 1)"
            )
        }
        guard case let .message(text) = FinanceIntentQueries.nextRecurringBills(from: snapshot(bills: bills)) else {
            Issue.record("Expected .message")
            return
        }
        // 5 bills, cap 3 spoken → "Plus 2 more."
        #expect(text.contains("2 more"))
    }

    @Test("No bills reports a no-bills message, not unavailable")
    func noBillsReportsMessage() {
        // A snapshot with balances but no bills is non-empty, so this is a real
        // "no upcoming bills" answer rather than a setup prompt.
        guard case let .message(text) = FinanceIntentQueries.nextRecurringBills(from: snapshot(bills: [])) else {
            Issue.record("Expected .message for non-empty snapshot with no bills")
            return
        }
        #expect(text.lowercased().contains("no upcoming bills"))
    }

    // MARK: - Show spending (AND-586)

    @Test("Show spending returns the period total and names top categories")
    func showSpendingReturnsValue() {
        let categories = [
            FinanceSnapshot.CategorySpend(category: .foodAndDrink, amount: 320),
            FinanceSnapshot.CategorySpend(category: .shopping, amount: 180),
        ]
        guard case let .value(value, dialog) = FinanceIntentQueries.showSpending(
            from: snapshot(periodSpending: 500, categories: categories)
        ) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 500)
        #expect(dialog.contains("Food & Drink"))
        #expect(dialog.lowercased().contains("top categories"))
    }

    @Test("Show spending reports the total even with no categorized spend")
    func showSpendingWithoutCategories() {
        guard case let .value(value, dialog) = FinanceIntentQueries.showSpending(
            from: snapshot(periodSpending: 120, categories: [])
        ) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 120)
        #expect(dialog.contains("120") || dialog.lowercased().contains("spent"))
    }

    @Test("Masked snapshot withholds show-spending without leaking a figure")
    func showSpendingMaskedWithholds() {
        let categories = [FinanceSnapshot.CategorySpend(category: .travel, amount: 999)]
        guard case let .withheld(dialog) = FinanceIntentQueries.showSpending(
            from: snapshot(isMasked: true, periodSpending: 999, categories: categories)
        ) else {
            Issue.record("Expected .withheld")
            return
        }
        #expect(!dialog.contains("999"))
        #expect(!dialog.contains("Travel"))
    }

    @Test("Nil snapshot reports unavailable for show-spending")
    func showSpendingNilUnavailable() {
        guard case .unavailable = FinanceIntentQueries.showSpending(from: nil) else {
            Issue.record("Expected .unavailable")
            return
        }
    }

    // MARK: - Helpers

    private func snapshot(
        safeToSpend: Double = 1_000,
        totalBalance: Double = 5_000,
        bills: [FinanceSnapshot.UpcomingBill] = [],
        creditUtilization: Double? = 20,
        isMasked: Bool = false,
        periodSpending: Double = 0,
        categories: [FinanceSnapshot.CategorySpend] = [],
        currencySubtotals: [FinanceSnapshot.CurrencySubtotal] = []
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: safeToSpend,
            totalBalance: totalBalance,
            accountBalances: [
                FinanceSnapshot.AccountBalance(displayName: "Checking", balance: totalBalance),
            ],
            currencySubtotals: currencySubtotals,
            nextRecurringBills: bills,
            creditUtilization: creditUtilization,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            isMasked: isMasked,
            periodSpending: periodSpending,
            topSpendingCategories: categories
        )
    }
}
