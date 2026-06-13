import Foundation

/// Pure, deterministic category-budget planning (AND-402).
///
/// Mirrors the shape of `SpendingSummary` / `SafeToSpendCalculator`: a stateless
/// `enum` whose functions take an explicit `asOf:` reference date and `Calendar`,
/// so there is no hidden `Date()` and every result is fully testable.
///
/// Two responsibilities:
/// 1. `suggestedBudgets` — propose monthly limits for the top spending categories
///    from trailing *complete*-month history (the read-only wedge: the app can
///    show guardrails before the user has saved any).
/// 2. `presentation` — score a set of limits against the *current* month's spend.
///
/// Spend is computed from **signed** transaction amounts (Plaid convention:
/// positive = money out, negative = money in). Summing the raw amount per
/// category therefore nets refunds against spend automatically — unlike
/// `SpendingSummary`, which uses `displayAmount` (`abs`) and drops every
/// negative-amount transaction as income. Budgets need the netting, so this type
/// aggregates the signed amounts itself. Transfers and the income category are
/// excluded so a paycheck or an own-account move never counts as category spend.
public enum CategoryBudgetPlanner {
    /// How many categories `suggestedBudgets` proposes by default. Kept small so
    /// the surface stays glanceable (HIG / the issue's "avoid every category").
    public static let defaultSuggestionCount = 5
    /// Trailing complete months averaged into a suggestion.
    public static let defaultTrailingMonths = 3

    /// Categories that are never spend: income and transfers (both directions).
    /// A refund keeps its spend category (e.g. a returned purchase stays
    /// `GENERAL_MERCHANDISE`), so it is *not* excluded here — it nets via its
    /// negative amount.
    public static let excludedCategories: Set<SpendingCategory> = [
        .income, .transfer, .transferOut,
    ]

    // MARK: - Suggestions

    /// Suggested monthly limits for the highest-spend categories, derived from the
    /// trailing complete months before the current one (the current, partial month
    /// is excluded so a mid-month snapshot never understates the baseline).
    ///
    /// Each category's trailing net spend is averaged over the window and rounded
    /// up to a sensible limit. Only positive-spend categories qualify, ranked
    /// high-to-low, capped at `topCategories`.
    public static func suggestedBudgets(
        from transactions: [TransactionDTO],
        asOf date: Date,
        calendar: Calendar = .current,
        topCategories: Int = defaultSuggestionCount,
        trailingMonths: Int = defaultTrailingMonths
    ) -> [SpendingCategory: Double] {
        guard topCategories > 0, trailingMonths > 0,
              let currentMonthStart = monthStartDate(asOf: date, calendar: calendar)
        else { return [:] }

        var totals: [SpendingCategory: Double] = [:]
        for monthsBack in 1...trailingMonths {
            guard
                let monthStart = calendar.date(
                    byAdding: .month, value: -monthsBack, to: currentMonthStart
                ),
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            let monthly = netSpendByCategory(
                from: transactions,
                startKey: Formatters.transactionDateString(monthStart),
                endKey: Formatters.transactionDateString(monthEnd)
            )
            // Only positive months feed the baseline — a refund-heavy month should
            // not deflate a category's suggested guardrail below its typical spend.
            for (category, amount) in monthly where amount > 0 {
                totals[category, default: 0] += amount
            }
        }

        var averages: [CategoryAverage] = []
        for (category, total) in totals {
            let average = total / Double(trailingMonths)
            if average > 0 {
                averages.append(CategoryAverage(category: category, average: average))
            }
        }
        averages.sort { lhs, rhs in
            lhs.average != rhs.average
                ? lhs.average > rhs.average
                : lhs.category.displayName < rhs.category.displayName
        }

        var suggestions: [SpendingCategory: Double] = [:]
        for entry in averages.prefix(topCategories) {
            suggestions[entry.category] = roundedSuggestedLimit(entry.average)
        }
        return suggestions
    }

    // MARK: - Progress

    /// Score `budgets` against the current month's spend. Non-positive limits are
    /// dropped. Items are ordered attention-first (over, then nearing), then by
    /// spend pressure, then category name.
    public static func presentation(
        budgets: [SpendingCategory: Double],
        transactions: [TransactionDTO],
        asOf date: Date,
        calendar: Calendar = .current,
        areSuggested: Bool = false
    ) -> CategoryBudgetPresentation {
        let positiveBudgets = budgets.filter { $0.value > 0 }
        guard
            !positiveBudgets.isEmpty,
            let monthStart = monthStartDate(asOf: date, calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return .empty }

        let spendByCategory = netSpendByCategory(
            from: transactions,
            startKey: Formatters.transactionDateString(monthStart),
            endKey: Formatters.transactionDateString(nextMonthStart)
        )

        let items = positiveBudgets
            .map { category, limit in
                CategoryBudgetPresentation.Item(
                    category: category,
                    monthlyLimit: limit,
                    spent: spendByCategory[category] ?? 0,
                    isSuggested: areSuggested
                )
            }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return statusRank(lhs.status) < statusRank(rhs.status)
                }
                if lhs.fractionUsed != rhs.fractionUsed {
                    return lhs.fractionUsed > rhs.fractionUsed
                }
                return lhs.category.displayName < rhs.category.displayName
            }

        return CategoryBudgetPresentation(
            items: items,
            totalLimit: items.reduce(0) { $0 + $1.monthlyLimit },
            totalSpent: items.reduce(0) { $0 + $1.spent },
            overBudgetCount: items.reduce(0) { $0 + ($1.status == .over ? 1 : 0) },
            nearingCount: items.reduce(0) { $0 + ($1.status == .nearing ? 1 : 0) }
        )
    }

    /// Convenience for the read-only slice: suggest limits from history and score
    /// them against the current month in one call. Items are flagged `isSuggested`.
    public static func suggestedPresentation(
        from transactions: [TransactionDTO],
        asOf date: Date,
        calendar: Calendar = .current,
        topCategories: Int = defaultSuggestionCount,
        trailingMonths: Int = defaultTrailingMonths
    ) -> CategoryBudgetPresentation {
        let budgets = suggestedBudgets(
            from: transactions,
            asOf: date,
            calendar: calendar,
            topCategories: topCategories,
            trailingMonths: trailingMonths
        )
        return presentation(
            budgets: budgets,
            transactions: transactions,
            asOf: date,
            calendar: calendar,
            areSuggested: true
        )
    }

    // MARK: - Internals

    /// Net signed spend per category within `[startKey, endKey)`, excluding income
    /// and transfers. Pending transactions are included — they represent committed
    /// spend, and the sync layer (`TransactionSyncReducer`) reconciles a pending
    /// row into its posted form, so there is no double-count here.
    static func netSpendByCategory(
        from transactions: [TransactionDTO],
        startKey: String,
        endKey: String
    ) -> [SpendingCategory: Double] {
        var totals: [SpendingCategory: Double] = [:]
        for transaction in transactions {
            if transaction.date < startKey || transaction.date >= endKey { continue }
            let category = transaction.category ?? .other
            if excludedCategories.contains(category) { continue }
            totals[category, default: 0] += transaction.amount
        }
        return totals
    }

    /// First instant of the month containing `date`, in `calendar`.
    static func monthStartDate(asOf date: Date, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    /// Round a trailing-average spend up to a tidy monthly limit. Larger spends
    /// round to coarser steps so suggestions read as round numbers, never to the
    /// cent.
    static func roundedSuggestedLimit(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let step: Double = value < 100 ? 10 : (value < 500 ? 25 : 50)
        return (value / step).rounded(.up) * step
    }

    /// A category's trailing average spend, used to rank suggestions. A named
    /// type (rather than an inline labeled tuple) keeps the ranking pipeline
    /// fast to type-check.
    private struct CategoryAverage {
        let category: SpendingCategory
        let average: Double
    }

    /// Attention-first ordering: over (0) before nearing (1) before under (2).
    private static func statusRank(_ status: CategoryBudgetStatus) -> Int {
        switch status {
        case .over: 0
        case .nearing: 1
        case .under: 2
        }
    }
}
