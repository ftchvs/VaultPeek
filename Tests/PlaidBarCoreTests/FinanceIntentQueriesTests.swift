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

    // MARK: - Helpers

    private func snapshot(
        safeToSpend: Double = 1_000,
        totalBalance: Double = 5_000,
        bills: [FinanceSnapshot.UpcomingBill] = [],
        creditUtilization: Double? = 20,
        isMasked: Bool = false
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: safeToSpend,
            totalBalance: totalBalance,
            accountBalances: [
                FinanceSnapshot.AccountBalance(displayName: "Checking", balance: totalBalance),
            ],
            nextRecurringBills: bills,
            creditUtilization: creditUtilization,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            isMasked: isMasked
        )
    }
}
