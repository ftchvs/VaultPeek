import Foundation

/// Pure, deterministic safe-to-spend calculation.
///
/// Mirrors the shape of `RecurringSummary` / `SpendingSummary`: a stateless
/// `enum` with a single `static func compute(...)` that takes an explicit
/// `asOf:` reference date and `Calendar`, so there is no hidden `Date()` and the
/// result is fully testable.
///
/// Conservatism is the design rule. The number leans toward *under*-promising:
/// it prefers the available balance over the current balance (via
/// `BalanceDTO.effectiveBalance`), counts only outflow obligations with a
/// defensible signal, never invents optimistic income, and reports a shortfall
/// honestly instead of clamping to zero. See `SafeToSpend.swift` for the sign
/// convention every component obeys.
public enum SafeToSpendCalculator {
    /// Recurring streams below this confidence are ignored as obligations — a
    /// weakly-detected stream should not silently shrink the spendable number.
    public static let minimumObligationConfidence = 0.5

    public static func compute(
        accounts: [AccountDTO],
        recurringTransactions: [RecurringTransaction],
        cashflow: WealthSummaryPresentation.CashflowSummary? = nil,
        inputs: SafeToSpendInputs = .default,
        pendingHolds: Double = 0,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> SafeToSpendResult {
        let referenceDay = calendar.startOfDay(for: date)
        let horizonEnd = inputs.horizon.endDate(asOf: date, calendar: calendar)

        let startingCash = startingCash(from: accounts, inputs: inputs)

        let obligations = obligations(
            from: recurringTransactions,
            asOf: referenceDay,
            horizonEnd: horizonEnd,
            calendar: calendar
        )

        let income = expectedIncome(
            inputs: inputs,
            recurringTransactions: recurringTransactions,
            cashflow: cashflow,
            asOf: referenceDay,
            horizonEnd: horizonEnd,
            calendar: calendar
        )

        // Pending holds are clamped to non-negative and subtracted. Defaulting to
        // 0 keeps the result byte-identical to today's behavior unless a caller
        // explicitly supplies holds (gated on the safe-to-spend model B decision
        // so `available`-based starting cash never double-subtracts).
        let pendingHoldsTotal = max(pendingHolds, 0)

        var components: [SafeToSpendComponent] = [
            SafeToSpendComponent(kind: .startingCash, label: "Starting cash", amount: startingCash),
            SafeToSpendComponent(kind: .expectedIncome, label: "Expected income", amount: income.amount),
            SafeToSpendComponent(
                kind: .pendingHolds,
                label: "Pending holds",
                amount: -pendingHoldsTotal
            ),
            SafeToSpendComponent(
                kind: .upcomingObligations,
                label: "Upcoming bills",
                amount: -obligations.recurringTotal
            ),
            SafeToSpendComponent(
                kind: .loanPayments,
                label: "Loans & cards",
                amount: -obligations.loanPaymentTotal
            ),
            SafeToSpendComponent(
                kind: .budgetReservations,
                label: "Reserved",
                amount: -inputs.budgetReservations
            ),
            SafeToSpendComponent(
                kind: .safetyBuffer,
                label: "Safety buffer",
                amount: -inputs.safetyBuffer
            ),
        ]

        // Keep components in the fixed declaration order so the breakdown always
        // reads the same way and reconciles to the sum.
        components.sort { lhs, rhs in
            order(of: lhs.kind) < order(of: rhs.kind)
        }

        let amount = components.reduce(0) { $0 + $1.amount }

        let confidence = confidence(
            hasObligationSignal: obligations.hasSignal,
            income: income
        )

        return SafeToSpendResult(
            amount: amount,
            components: components,
            confidence: confidence,
            horizonEnd: horizonEnd
        )
    }

    // MARK: - Starting cash

    private static func startingCash(
        from accounts: [AccountDTO],
        inputs: SafeToSpendInputs
    ) -> Double {
        accounts
            .filter { inputs.includedCashAccountTypes.contains($0.type) }
            // effectiveBalance already prefers `available` over `current`, the
            // conservative choice for spendable cash.
            .reduce(0) { $0 + $1.balances.effectiveBalance }
    }

    // MARK: - Obligations

    private struct Obligations {
        let recurringTotal: Double
        let loanPaymentTotal: Double
        /// Whether any recurring history was usable at all — feeds confidence.
        let hasSignal: Bool
    }

    private static func obligations(
        from recurringTransactions: [RecurringTransaction],
        asOf referenceDay: Date,
        horizonEnd: Date,
        calendar: Calendar
    ) -> Obligations {
        var recurringTotal = 0.0
        var loanPaymentTotal = 0.0
        var hasSignal = false

        for recurring in recurringTransactions {
            guard recurring.confidence >= minimumObligationConfidence else { continue }
            // Recurring detection stores absolute amounts, so inflow vs outflow
            // is read from the category. Skip inflows and own-account transfers
            // so income is never double-counted as a bill and a transfer between
            // the user's own accounts nets to zero here.
            guard isOutflowObligation(recurring.category) else { continue }

            hasSignal = true

            guard let nextDate = Formatters.parseTransactionDate(recurring.nextExpectedDate) else {
                continue
            }
            let nextDay = calendar.startOfDay(for: nextDate)
            // Inclusive of both ends: an obligation due exactly on the horizon
            // edge still falls inside the window.
            guard nextDay >= referenceDay, nextDay <= horizonEnd else { continue }

            let amount = max(recurring.averageAmount, 0)
            if isLoanPayment(recurring.category) {
                loanPaymentTotal += amount
            } else {
                recurringTotal += amount
            }
        }

        return Obligations(
            recurringTotal: recurringTotal,
            loanPaymentTotal: loanPaymentTotal,
            hasSignal: hasSignal
        )
    }

    private static func isOutflowObligation(_ category: SpendingCategory?) -> Bool {
        switch category {
        case .income, .transfer, .transferOut:
            // Inflows and own-account transfers are not spendable-cash outflows.
            return false
        case .none:
            // Uncategorized recurring outflows are still real bills.
            return true
        default:
            return true
        }
    }

    private static func isLoanPayment(_ category: SpendingCategory?) -> Bool {
        // Plaid's LOAN_PAYMENTS bucket (this enum's `.subscriptions` case) covers
        // credit-card payments, loan payments, AND recurring subscriptions — the
        // taxonomy can't separate them at this granularity, so they share one
        // "Loans & cards" line. The total is unaffected (each amount is subtracted
        // exactly once); only the line-item attribution is coarse.
        category == .subscriptions
    }

    // MARK: - Expected income

    private struct ExpectedIncome {
        let amount: Double
        let isManual: Bool
        let hasSignal: Bool
    }

    private static func expectedIncome(
        inputs: SafeToSpendInputs,
        recurringTransactions: [RecurringTransaction],
        cashflow: WealthSummaryPresentation.CashflowSummary?,
        asOf referenceDay: Date,
        horizonEnd: Date,
        calendar: Calendar
    ) -> ExpectedIncome {
        // A manual override is authoritative and carries full confidence.
        if let manual = inputs.manualExpectedIncome {
            return ExpectedIncome(amount: manual, isManual: true, hasSignal: true)
        }

        // Otherwise prefer recurring inflows due within the horizon — a
        // defensible, dated signal.
        let recurringIncome = recurringInflow(
            from: recurringTransactions,
            asOf: referenceDay,
            horizonEnd: horizonEnd,
            calendar: calendar
        )
        if recurringIncome > 0 {
            return ExpectedIncome(amount: recurringIncome, isManual: false, hasSignal: true)
        }

        // Fall back to a horizon-scaled slice of observed cashflow income. This
        // is the softest signal, so it lowers confidence rather than inflating
        // the number.
        if let cashflow, cashflow.income > 0, cashflow.windowDays > 0 {
            // Day count is exclusive of the inclusive `horizonEnd` by one day.
            // Scaling income by the smaller count deliberately under-counts income
            // (the conservative direction), so the asymmetry with the inclusive
            // obligation bound never lets safe-to-spend overstate.
            let horizonDays = max(
                calendar.dateComponents([.day], from: referenceDay, to: horizonEnd).day ?? 0,
                0
            )
            guard horizonDays > 0 else {
                return ExpectedIncome(amount: 0, isManual: false, hasSignal: false)
            }
            let dailyIncome = cashflow.income / Double(cashflow.windowDays)
            let scaled = dailyIncome * Double(horizonDays)
            return ExpectedIncome(amount: max(scaled, 0), isManual: false, hasSignal: true)
        }

        // No defensible income signal: treat as zero and let confidence drop,
        // rather than guessing optimistically.
        return ExpectedIncome(amount: 0, isManual: false, hasSignal: false)
    }

    /// Dated recurring inflow within the horizon.
    ///
    /// NOTE: `RecurringDetector.detect` currently filters income transactions out
    /// before grouping, so no `.income` `RecurringTransaction` is produced by the
    /// running app today — this path is forward-looking (it activates if/when
    /// recurring-income detection lands). In production, income therefore comes
    /// from a manual override or the cashflow estimate, so `.ok` confidence
    /// requires a manual override until then. The unit tests exercise this branch
    /// directly by constructing `.income` streams to lock the calculator contract.
    private static func recurringInflow(
        from recurringTransactions: [RecurringTransaction],
        asOf referenceDay: Date,
        horizonEnd: Date,
        calendar: Calendar
    ) -> Double {
        recurringTransactions.reduce(0) { total, recurring in
            guard recurring.confidence >= minimumObligationConfidence,
                  recurring.category == .income,
                  let nextDate = Formatters.parseTransactionDate(recurring.nextExpectedDate)
            else {
                return total
            }
            let nextDay = calendar.startOfDay(for: nextDate)
            guard nextDay >= referenceDay, nextDay <= horizonEnd else { return total }
            return total + max(recurring.averageAmount, 0)
        }
    }

    // MARK: - Confidence

    private static func confidence(
        hasObligationSignal: Bool,
        income: ExpectedIncome
    ) -> SafeToSpendConfidence {
        // Nothing to stand on: no obligation history and no income signal.
        if !hasObligationSignal, !income.hasSignal {
            return .insufficientData
        }
        // Estimated (non-manual) income softens the upside.
        if income.hasSignal, !income.isManual {
            return .lowConfidence
        }
        return .ok
    }

    // MARK: - Ordering

    private static func order(of kind: SafeToSpendComponentKind) -> Int {
        SafeToSpendComponentKind.allCases.firstIndex(of: kind) ?? 0
    }
}
