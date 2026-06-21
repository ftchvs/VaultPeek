import Foundation
import Testing
@testable import PlaidBarCore

/// Privacy-Mask coverage for the first-run snapshot surface (P2 mask-bypass fix).
///
/// `FirstRunSnapshotView` self-dots every figure when Privacy Mask is on
/// (`.masked`, not `.locked`, leaves the card visible). These tests pin the
/// Core-side contract the view depends on: the masked accessibility summary
/// dots currency + percent values, and `PrivacyMaskPresentation` produces the
/// dotted token for every figure the view renders.
@Suite("First-run snapshot privacy mask")
struct FirstRunSnapshotPrivacyTests {
    private let now = Formatters.parseTransactionDate("2026-06-12")!

    private func fullSnapshot() -> FirstRunSnapshot {
        FirstRunSnapshot.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
                AccountDTO(id: "brokerage", itemId: "item-a", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 50_000)),
                AccountDTO(id: "card", itemId: "item-b", name: "Visa", type: .credit, balances: BalanceDTO(current: -1_500, limit: 10_000)),
                AccountDTO(id: "loan", itemId: "item-c", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -7_250)),
            ],
            transactions: [
                expense("rent-internal", amount: 1_200, date: "2026-06-02", name: "Rent"),
                expense("dental-internal", amount: 900, date: "2026-06-12", name: "Dental"),
                expense("laptop-internal", amount: 750, date: "2026-06-11", name: "Laptop"),
            ],
            completionState: readyCompletion(transactionCount: 3),
            now: now
        )
    }

    @Test("Default accessibility summary leaks real figures (unmasked baseline)")
    func unmaskedSummaryShowsFigures() {
        let snapshot = fullSnapshot()
        // The stored summary and the masked accessor with isMasked:false are identical.
        #expect(snapshot.maskedAccessibilitySummary(isMasked: false) == snapshot.accessibilitySummary)
        #expect(snapshot.accessibilitySummary.contains("Net worth $49,450.00"))
        #expect(snapshot.accessibilitySummary.contains("Cash available $8,200.00"))
        #expect(snapshot.accessibilitySummary.contains("Debt $8,750.00"))
        #expect(snapshot.accessibilitySummary.contains("Credit utilization 15%"))
        #expect(snapshot.accessibilitySummary.contains("Month-to-date spend"))
    }

    @Test("Masked accessibility summary dots every currency and percent figure")
    func maskedSummaryDotsFigures() {
        let snapshot = fullSnapshot()
        let masked = snapshot.maskedAccessibilitySummary(isMasked: true)

        // No raw currency tokens or percent magnitudes survive masking.
        #expect(!masked.contains("$"))
        #expect(!masked.contains("49,450"))
        #expect(!masked.contains("8,200"))
        #expect(!masked.contains("8,750"))
        #expect(!masked.contains("15%"))

        // Dotted tokens are present in place of the figures.
        #expect(masked.contains(PrivacyMaskPresentation.compactValue))
        #expect(masked.contains("Net worth \(PrivacyMaskPresentation.compactValue)."))
        #expect(masked.contains("Cash available \(PrivacyMaskPresentation.compactValue)."))
        #expect(masked.contains("Debt \(PrivacyMaskPresentation.compactValue)."))
        #expect(masked.contains("Credit utilization \(PrivacyMaskPresentation.compactValue)."))

        // Non-sensitive scaffolding (counts, state copy) is preserved.
        #expect(masked.contains("First-run money snapshot."))
        #expect(masked.contains("recent large transaction"))
    }

    @Test("Masked rendered tile values dot currency and percent like the view does")
    func maskedTileValuesAreDotted() {
        let snapshot = fullSnapshot()

        // Currency figures the view renders -> dotted when masked.
        #expect(PrivacyMaskPresentation.currency(snapshot.cashAvailable, format: .compact, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        #expect(PrivacyMaskPresentation.currency(snapshot.netWorth, format: .compact, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        #expect(PrivacyMaskPresentation.currency(snapshot.debtTotal, format: .compact, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        if let spend = snapshot.monthToDateSpend {
            #expect(PrivacyMaskPresentation.currency(spend, format: .compact, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        }
        if let utilization = snapshot.creditUtilization {
            // Percent figure -> dotted when masked.
            #expect(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        }

        // Transaction-amount figures -> dotted when masked.
        for transaction in snapshot.largeTransactions {
            #expect(PrivacyMaskPresentation.currency(transaction.amount, format: .compact, isEnabled: true) == PrivacyMaskPresentation.compactValue)
            #expect(PrivacyMaskPresentation.currency(transaction.amount, format: .full, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        }

        // Sanity: unmasked still shows the real values.
        #expect(PrivacyMaskPresentation.currency(snapshot.netWorth, format: .compact, isEnabled: false) != PrivacyMaskPresentation.compactValue)
        if let utilization = snapshot.creditUtilization {
            #expect(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: false).contains("%"))
        }
    }

    private func readyCompletion(transactionCount: Int) -> FirstRunCompletionState {
        FirstRunCompletionState(
            step: .ready,
            title: "Dashboard ready",
            detail: "\(transactionCount) transactions synced. VaultPeek is ready.",
            isReady: true,
            canRetry: false
        )
    }

    private func expense(
        _ id: String,
        amount: Double,
        date: String,
        name: String,
        category: SpendingCategory? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: name,
            category: category
        )
    }
}
