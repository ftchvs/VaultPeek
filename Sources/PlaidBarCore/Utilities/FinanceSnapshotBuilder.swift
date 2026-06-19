import Foundation

/// Builds a display-safe ``FinanceSnapshot`` for the App Group from raw account,
/// transaction, and recurring data — reusing the existing core math so the
/// numbers App Intents read match the popover exactly (AND-512).
///
/// Math reuse (no duplication):
/// - `safeToSpend` ← ``SafeToSpendCalculator/compute(accounts:recurringTransactions:cashflow:inputs:pendingHolds:asOf:calendar:)``
/// - `totalBalance` ← sum of the included cash/depository balances (the same set
///   used to build `accountBalances`), matching the intent's "spendable balance
///   across linked accounts" — not net worth.
/// - `creditUtilization` ← ``WealthSummaryPresentation`` credit-utilization rule
///   (recomputed from the same depository/credit balances)
/// - `nextRecurringBills` ← the supplied recurring streams, filtered to dated
///   outflows within the horizon and sorted soonest-first.
public enum FinanceSnapshotBuilder {
    /// Recurring outflow streams below this confidence are treated as noise, in
    /// line with ``SafeToSpendCalculator/minimumObligationConfidence``.
    public static let minimumBillConfidence = SafeToSpendCalculator.minimumObligationConfidence

    public static func make(
        accounts: [AccountDTO],
        recurringTransactions: [RecurringTransaction],
        cashflow: WealthSummaryPresentation.CashflowSummary? = nil,
        safeToSpendInputs: SafeToSpendInputs = .default,
        pendingHolds: Double = 0,
        isMasked: Bool,
        creditUtilizationThreshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> FinanceSnapshot {
        let safeToSpend = SafeToSpendCalculator.compute(
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            cashflow: cashflow,
            inputs: safeToSpendInputs,
            pendingHolds: pendingHolds,
            asOf: generatedAt,
            calendar: calendar
        )

        // Only the included cash/depository accounts — the same set that powers
        // `accountBalances` below. The balance intent describes "spendable balance
        // across linked accounts", so this deliberately excludes investments and
        // does NOT subtract credit/loan debt (that would be net worth, not cash).
        let includedCashAccounts = accounts
            .filter { safeToSpendInputs.includedCashAccountTypes.contains($0.type) }

        let totalBalance = includedCashAccounts
            .reduce(0) { $0 + $1.balances.effectiveBalance }

        let accountBalances = includedCashAccounts
            .map { account in
                FinanceSnapshot.AccountBalance(
                    displayName: account.name,
                    balance: account.balances.effectiveBalance,
                    isoCurrencyCode: account.balances.isoCurrencyCode
                )
            }

        let bills = upcomingBills(
            from: recurringTransactions,
            inputs: safeToSpendInputs,
            asOf: generatedAt,
            calendar: calendar
        )

        let utilization = creditUtilizationPercent(from: accounts)

        let currencyCode = accounts
            .compactMap { $0.balances.isoCurrencyCode }
            .first ?? "USD"

        // Defense in depth: a masked snapshot must be value-free *on disk*, not
        // merely withheld at read time. If anyone bypasses the read-time gate
        // (`FinanceIntentQueries`) the file itself carries no real figures — only
        // the flag, timestamp, and currency code survive.
        if isMasked {
            return FinanceSnapshot(
                safeToSpend: 0,
                totalBalance: 0,
                accountBalances: [],
                nextRecurringBills: [],
                creditUtilization: nil,
                isoCurrencyCode: currencyCode,
                generatedAt: generatedAt,
                isMasked: true
            )
        }

        return FinanceSnapshot(
            safeToSpend: safeToSpend.amount,
            totalBalance: totalBalance,
            accountBalances: accountBalances,
            nextRecurringBills: bills,
            creditUtilization: utilization,
            isoCurrencyCode: currencyCode,
            generatedAt: generatedAt,
            isMasked: isMasked
        )
    }

    // MARK: - Upcoming bills

    private static func upcomingBills(
        from recurringTransactions: [RecurringTransaction],
        inputs: SafeToSpendInputs,
        asOf date: Date,
        calendar: Calendar
    ) -> [FinanceSnapshot.UpcomingBill] {
        let referenceDay = calendar.startOfDay(for: date)
        let horizonEnd = inputs.horizon.endDate(asOf: date, calendar: calendar)

        let dated: [(bill: FinanceSnapshot.UpcomingBill, due: Date)] = recurringTransactions.compactMap { recurring in
            guard recurring.confidence >= minimumBillConfidence else { return nil }
            // Outflows only — mirror SafeToSpendCalculator's obligation filter so
            // income and own-account transfers never show up as a "bill".
            guard isOutflow(recurring.category) else { return nil }
            guard let nextDate = Formatters.parseTransactionDate(recurring.nextExpectedDate) else { return nil }
            let nextDay = calendar.startOfDay(for: nextDate)
            guard nextDay >= referenceDay, nextDay <= horizonEnd else { return nil }
            let amount = max(recurring.averageAmount, 0)
            guard amount > 0 else { return nil }
            return (
                FinanceSnapshot.UpcomingBill(
                    merchantName: recurring.merchantName,
                    amount: amount,
                    nextExpectedDate: recurring.nextExpectedDate
                ),
                nextDay
            )
        }

        return dated
            .sorted { $0.due < $1.due }
            .map(\.bill)
    }

    private static func isOutflow(_ category: SpendingCategory?) -> Bool {
        switch category {
        case .income, .transfer, .transferOut:
            return false
        default:
            return true
        }
    }

    // MARK: - Credit utilization

    /// Aggregate credit utilization (0–100), nil when no credit limit is known.
    /// Same rule as ``WealthSummaryPresentation`` (`used / limit * 100`).
    private static func creditUtilizationPercent(from accounts: [AccountDTO]) -> Double? {
        let creditBalances = accounts
            .filter { $0.type == .credit }
            .map(\.balances)

        let totalLimit = creditBalances.reduce(0) { $0 + max($1.limit ?? 0, 0) }
        guard totalLimit > 0 else { return nil }

        let usedCredit = creditBalances.reduce(0) { $0 + abs($1.current ?? 0) }
        return (usedCredit / totalLimit) * 100
    }
}
