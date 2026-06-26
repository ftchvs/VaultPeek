import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Control Center value control presentation (AND-503)")
struct ControlValuePresentationTests {
    // MARK: - Safe to spend

    @Test("Unmasked safe-to-spend shows a compact currency value")
    func unmaskedSafeToSpendShowsValue() {
        let display = ControlValuePresentation.safeToSpend(from: snapshot(safeToSpend: 1_250))
        #expect(!display.isWithheld)
        #expect(display.value == Formatters.currency(1_250, format: .compact))
        #expect(display.value.contains("1,250"))
        #expect(display.accessibilityLabel.lowercased().contains("safe to spend"))
        #expect(display.systemImage == "dollarsign.circle")
    }

    @Test("Negative safe-to-spend renders the figure and an over-budget label")
    func negativeSafeToSpendIsOverBudget() {
        let display = ControlValuePresentation.safeToSpend(from: snapshot(safeToSpend: -340))
        #expect(!display.isWithheld)
        #expect(display.accessibilityLabel.lowercased().contains("over budget"))
    }

    @Test("Masked safe-to-spend withholds the value and never leaks the figure")
    func maskedSafeToSpendIsWithheld() {
        let display = ControlValuePresentation.safeToSpend(from: snapshot(safeToSpend: 4_321, isMasked: true))
        #expect(display.isWithheld)
        #expect(display.value == ControlValuePresentation.withheldValue)
        #expect(display.value == PrivacyMaskPresentation.compactValue)
        #expect(!display.value.contains("4,321"))
        #expect(!display.accessibilityLabel.contains("4,321"))
        #expect(!display.accessibilityLabel.contains("4321"))
        #expect(display.systemImage == "eye.slash")
        #expect(display.accessibilityLabel.lowercased().contains("privacy mask"))
    }

    @Test("Nil snapshot withholds safe-to-spend as unavailable")
    func nilSafeToSpendIsUnavailable() {
        let display = ControlValuePresentation.safeToSpend(from: nil)
        #expect(display.isWithheld)
        #expect(display.value == ControlValuePresentation.withheldValue)
        #expect(display.systemImage == "lock.shield")
        #expect(display.accessibilityLabel.lowercased().contains("unavailable"))
    }

    @Test("Empty placeholder snapshot withholds safe-to-spend as unavailable")
    func emptySafeToSpendIsUnavailable() {
        let display = ControlValuePresentation.safeToSpend(from: .placeholder())
        #expect(display.isWithheld)
        #expect(display.systemImage == "lock.shield")
    }

    // MARK: - Credit utilization

    @Test("Unmasked credit utilization shows a whole-percent value")
    func unmaskedUtilizationShowsValue() {
        let display = ControlValuePresentation.creditUtilization(from: snapshot(creditUtilization: 42))
        #expect(!display.isWithheld)
        #expect(display.value == Formatters.percent(42, decimals: 0))
        #expect(display.value.contains("42"))
        #expect(display.value.contains("%"))
        #expect(display.systemImage == "creditcard")
    }

    @Test("Mixed-currency credit utilization accessibility names the scoped currency")
    func mixedCurrencyUtilizationNamesScope() {
        let display = ControlValuePresentation.creditUtilization(
            from: snapshot(
                creditUtilization: 90,
                creditUtilizationCurrency: CurrencyCode("EUR"),
                creditUtilizationIsMultiCurrency: true
            )
        )

        #expect(display.value == Formatters.percent(90, decimals: 0))
        #expect(display.accessibilityLabel.contains("highest"))
        #expect(display.accessibilityLabel.contains("EUR"))
    }

    @Test("Masked credit utilization withholds the percent")
    func maskedUtilizationIsWithheld() {
        let display = ControlValuePresentation.creditUtilization(from: snapshot(creditUtilization: 73, isMasked: true))
        #expect(display.isWithheld)
        #expect(display.value == ControlValuePresentation.withheldValue)
        #expect(!display.value.contains("73"))
        #expect(!display.accessibilityLabel.contains("73"))
        #expect(display.systemImage == "eye.slash")
    }

    @Test("No-credit-limit snapshot reports a non-withheld dash, not a fake 0%")
    func noLimitUtilizationShowsDash() {
        // A snapshot with cash balances but no credit limit is non-empty, so this
        // is a real "no credit" answer rather than a setup prompt.
        let display = ControlValuePresentation.creditUtilization(from: snapshot(creditUtilization: nil))
        #expect(!display.isWithheld)
        #expect(display.value == "—")
        #expect(!display.value.contains("0"))
        #expect(display.accessibilityLabel.lowercased().contains("no credit"))
    }

    @Test("Nil snapshot withholds credit utilization as unavailable")
    func nilUtilizationIsUnavailable() {
        let display = ControlValuePresentation.creditUtilization(from: nil)
        #expect(display.isWithheld)
        #expect(display.systemImage == "lock.shield")
    }

    // MARK: - Helpers

    private func snapshot(
        safeToSpend: Double = 1_000,
        totalBalance: Double = 5_000,
        creditUtilization: Double? = 20,
        creditUtilizationCurrency: CurrencyCode? = nil,
        creditUtilizationIsMultiCurrency: Bool = false,
        isMasked: Bool = false
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: safeToSpend,
            totalBalance: totalBalance,
            accountBalances: [
                FinanceSnapshot.AccountBalance(displayName: "Checking", balance: totalBalance),
            ],
            nextRecurringBills: [],
            creditUtilization: creditUtilization,
            creditUtilizationCurrency: creditUtilizationCurrency,
            creditUtilizationIsMultiCurrency: creditUtilizationIsMultiCurrency,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            isMasked: isMasked
        )
    }
}
