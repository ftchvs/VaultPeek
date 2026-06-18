import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Safe to spend calculator")
struct SafeToSpendCalculatorTests {
    private let now = Formatters.parseTransactionDate("2026-06-13")!
    private let calendar = Calendar(identifier: .gregorian)

    @Test("Cash minus obligations plus income minus buffer reconciles to the breakdown")
    func basicReconciliation() {
        let result = SafeToSpendCalculator.compute(
            accounts: [
                checking(900),
                savings(600),
            ],
            recurringTransactions: [
                recurring("Rent", amount: 500, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
                recurring("Paycheck", amount: 1_000, nextExpectedDate: "2026-06-25", category: .income),
            ],
            inputs: SafeToSpendInputs(safetyBuffer: 200, horizon: .endOfMonth),
            asOf: now,
            calendar: calendar
        )

        #expect(component(result, .startingCash) == 1_500)
        #expect(component(result, .expectedIncome) == 1_000)
        #expect(component(result, .upcomingObligations) == -500)
        #expect(component(result, .safetyBuffer) == -200)
        // 1500 + 1000 - 500 - 200 = 1800
        #expect(result.amount == 1_800)
        // The signed components must always sum to the headline.
        #expect(result.components.reduce(0) { $0 + $1.amount } == result.amount)
        // Recurring income is a dated signal but not a manual override.
        #expect(result.confidence == .lowConfidence)
    }

    @Test("Credit card and loan accounts are excluded from starting cash by default")
    func excludesCreditAccountsByDefault() {
        let result = SafeToSpendCalculator.compute(
            accounts: [
                checking(800),
                AccountDTO(id: "card", itemId: "item", name: "Card", type: .credit, balances: BalanceDTO(current: -300, limit: 2_000)),
                AccountDTO(id: "loan", itemId: "item", name: "Loan", type: .loan, balances: BalanceDTO(current: -5_000)),
                AccountDTO(id: "brokerage", itemId: "item", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 10_000)),
            ],
            recurringTransactions: [],
            inputs: SafeToSpendInputs(manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )

        #expect(component(result, .startingCash) == 800)
        #expect(result.amount == 800)
    }

    @Test("Loan and card payments share their own line, separate from bills, and transfers are ignored")
    func cardPaymentsTrackedSeparatelyAndTransfersIgnored() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(2_000)],
            recurringTransactions: [
                recurring("Card payment", amount: 250, nextExpectedDate: "2026-06-18", category: .subscriptions),
                recurring("Rent", amount: 400, nextExpectedDate: "2026-06-19", category: .billsAndUtilities),
                // A transfer between the user's own accounts must net to zero:
                // it is neither a bill nor income.
                recurring("Move to savings", amount: 700, nextExpectedDate: "2026-06-20", category: .transferOut),
            ],
            inputs: SafeToSpendInputs(manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )

        #expect(component(result, .loanPayments) == -250)
        #expect(component(result, .upcomingObligations) == -400)
        // Transfer excluded entirely — 2000 - 250 - 400 = 1350, not 650.
        #expect(result.amount == 1_350)
    }

    @Test("Low-confidence recurring streams are ignored as obligations")
    func lowConfidenceStreamsAreConservative() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Maybe-bill", amount: 300, nextExpectedDate: "2026-06-20", category: .billsAndUtilities, confidence: 0.3),
            ],
            // No manual income override either, so there is genuinely no signal
            // (a manual override — even 0 — would count as an authoritative one).
            inputs: .default,
            asOf: now,
            calendar: calendar
        )

        // The weakly-detected stream neither reduces cash nor counts as signal.
        #expect(component(result, .upcomingObligations) == 0)
        #expect(result.amount == 1_000)
        // No usable obligation history and no income signal → insufficient.
        #expect(result.confidence == .insufficientData)
    }

    @Test("No recurring data and no income signal yields insufficient data")
    func insufficientDataState() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(500)],
            recurringTransactions: [],
            inputs: .default,
            asOf: now,
            calendar: calendar
        )

        #expect(result.amount == 500)
        #expect(result.confidence == .insufficientData)
    }

    @Test("Estimated cashflow income lowers confidence but is never fabricated optimistically")
    func estimatedCashflowIncomeLowersConfidence() {
        let cashflow = WealthSummaryPresentation.CashflowSummary(
            windowDays: 30,
            income: 3_000,
            spending: 1_000,
            net: 2_000,
            transactionCount: 10
        )

        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Rent", amount: 400, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
            ],
            cashflow: cashflow,
            inputs: SafeToSpendInputs(horizon: .endOfMonth),
            asOf: now,
            calendar: calendar
        )

        // Horizon = 2026-06-13 .. 2026-06-30 inclusive end = 17 days ahead.
        // Daily income 3000/30 = 100, scaled by 17 days = 1700.
        #expect(component(result, .expectedIncome) == 1_700)
        #expect(result.confidence == .lowConfidence)
    }

    @Test("Manual income override is authoritative and keeps full confidence")
    func manualIncomeOverrideIsAuthoritative() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Rent", amount: 400, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(horizon: .endOfMonth, manualExpectedIncome: 2_500),
            asOf: now,
            calendar: calendar
        )

        #expect(component(result, .expectedIncome) == 2_500)
        // 1000 + 2500 - 400 = 3100
        #expect(result.amount == 3_100)
        #expect(result.confidence == .ok)
    }

    @Test("Buffer larger than available cash produces an honest negative result")
    func bufferLargerThanCashGoesNegative() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(300)],
            recurringTransactions: [
                recurring("Rent", amount: 100, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(safetyBuffer: 1_000, manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )

        // 300 + 0 - 100 - 1000 = -800. Reported honestly, not clamped.
        #expect(result.amount == -800)
        #expect(component(result, .safetyBuffer) == -1_000)
    }

    @Test("An obligation due exactly on the horizon edge is included; one past it is excluded")
    func horizonBoundaryIsInclusive() {
        let onEdge = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                // 2026-06-30 is the inclusive end-of-month edge.
                recurring("Edge bill", amount: 200, nextExpectedDate: "2026-06-30", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(horizon: .endOfMonth, manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )
        #expect(component(onEdge, .upcomingObligations) == -200)
        #expect(onEdge.amount == 800)

        let pastEdge = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Next month bill", amount: 200, nextExpectedDate: "2026-07-01", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(horizon: .endOfMonth, manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )
        // Outside the window: not subtracted, but the stream is still a signal.
        #expect(component(pastEdge, .upcomingObligations) == 0)
        #expect(pastEdge.amount == 1_000)
    }

    @Test("Visible components keep cash and income lines but drop zero subtractions")
    func visibleComponentsDropZeroSubtractions() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(500)],
            recurringTransactions: [],
            inputs: SafeToSpendInputs(manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )

        let kinds = result.visibleComponents.map(\.kind)
        #expect(kinds.contains(.startingCash))
        #expect(kinds.contains(.expectedIncome))
        #expect(!kinds.contains(.safetyBuffer))
        #expect(!kinds.contains(.upcomingObligations))
    }

    @Test("Fixed-day horizon clamps to at least one day")
    func fixedDayHorizon() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Soon bill", amount: 100, nextExpectedDate: "2026-06-15", category: .billsAndUtilities),
                recurring("Later bill", amount: 100, nextExpectedDate: "2026-06-25", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(horizon: .days(5), manualExpectedIncome: 0),
            asOf: now,
            calendar: calendar
        )

        // Horizon end = 2026-06-18; only the 06-15 bill is inside the window.
        #expect(component(result, .upcomingObligations) == -100)
        #expect(result.horizonEnd == Formatters.parseTransactionDate("2026-06-18")!)
    }

    // MARK: - Fixtures

    @Test("Pending holds argument yields a negated pendingHolds component (AND-499)")
    func pendingHoldsComponentIsNegated() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [],
            inputs: SafeToSpendInputs(manualExpectedIncome: 0),
            pendingHolds: 86.40,
            asOf: now,
            calendar: calendar
        )
        #expect(component(result, .pendingHolds) == -86.40)
        // 1000 + 0 - 86.40 = 913.60
        #expect(abs(result.amount - 913.60) < 0.001)
    }

    @Test("Signed components still reconcile to amount with the pending line present")
    func pendingHoldsReconciles() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [
                recurring("Rent", amount: 500, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
            ],
            inputs: SafeToSpendInputs(safetyBuffer: 100, manualExpectedIncome: 200),
            pendingHolds: 50,
            asOf: now,
            calendar: calendar
        )
        #expect(result.components.reduce(0) { $0 + $1.amount } == result.amount)
        #expect(result.components.contains { $0.kind == .pendingHolds })
    }

    @Test("Default pending argument leaves the result identical to today's behavior")
    func pendingHoldsDefaultIsSourceCompatible() {
        let accounts = [checking(900), savings(600)]
        let recurring = [
            recurring("Rent", amount: 500, nextExpectedDate: "2026-06-20", category: .billsAndUtilities),
        ]
        let inputs = SafeToSpendInputs(safetyBuffer: 200, horizon: .endOfMonth)

        let withDefault = SafeToSpendCalculator.compute(
            accounts: accounts, recurringTransactions: recurring,
            inputs: inputs, asOf: now, calendar: calendar
        )
        let explicitZero = SafeToSpendCalculator.compute(
            accounts: accounts, recurringTransactions: recurring,
            inputs: inputs, pendingHolds: 0, asOf: now, calendar: calendar
        )
        #expect(withDefault.amount == explicitZero.amount)
        // A zero pending line never appears in the visible breakdown.
        #expect(!withDefault.visibleComponents.contains { $0.kind == .pendingHolds })
    }

    @Test("Pending holds slot in the fixed display order between income and obligations")
    func pendingHoldsDisplayOrder() {
        let order = SafeToSpendComponentKind.allCases
        let incomeIdx = order.firstIndex(of: .expectedIncome)!
        let pendingIdx = order.firstIndex(of: .pendingHolds)!
        let obligationsIdx = order.firstIndex(of: .upcomingObligations)!
        #expect(incomeIdx < pendingIdx)
        #expect(pendingIdx < obligationsIdx)
    }

    @Test("Negative pending holds are clamped to zero")
    func pendingHoldsClamped() {
        let result = SafeToSpendCalculator.compute(
            accounts: [checking(1_000)],
            recurringTransactions: [],
            inputs: SafeToSpendInputs(manualExpectedIncome: 0),
            pendingHolds: -500,
            asOf: now,
            calendar: calendar
        )
        #expect(component(result, .pendingHolds) == 0)
        #expect(result.amount == 1_000)
    }

    private func component(_ result: SafeToSpendResult, _ kind: SafeToSpendComponentKind) -> Double {
        result.components.first { $0.kind == kind }?.amount ?? 0
    }

    private func checking(_ available: Double) -> AccountDTO {
        AccountDTO(
            id: "checking",
            itemId: "item",
            name: "Checking",
            type: .depository,
            balances: BalanceDTO(available: available, current: available + 50)
        )
    }

    private func savings(_ available: Double) -> AccountDTO {
        AccountDTO(
            id: "savings",
            itemId: "item",
            name: "Savings",
            type: .depository,
            balances: BalanceDTO(available: available, current: available)
        )
    }

    private func recurring(
        _ merchant: String,
        amount: Double,
        nextExpectedDate: String,
        category: SpendingCategory?,
        confidence: Double = 0.9
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchant,
            frequency: .monthly,
            averageAmount: amount,
            lastDate: "2026-05-20",
            nextExpectedDate: nextExpectedDate,
            category: category,
            transactionCount: 4,
            confidence: confidence
        )
    }
}
