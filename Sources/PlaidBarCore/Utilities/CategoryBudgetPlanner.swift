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
    ///
    /// `metadata`/`rules` are forwarded to `netSpendByCategory` so user overrides,
    /// rule recategorizations, and exclusions move the scored spend (AND-526). Both
    /// default to `nil`, preserving the legacy raw-category scoring for existing
    /// callers.
    public static func presentation(
        budgets: [SpendingCategory: Double],
        transactions: [TransactionDTO],
        asOf date: Date,
        calendar: Calendar = .current,
        areSuggested: Bool = false,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
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
            endKey: Formatters.transactionDateString(nextMonthStart),
            metadata: metadata,
            rules: rules,
            splits: splits
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

        return CategoryBudgetPresentation(items: items)
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

    /// The dashboard's combined view: explicit (user/server) budgets always
    /// appear, history-derived suggestions fill only the categories the user has
    /// not explicitly budgeted, and the union is re-ranked together. With no
    /// explicit budgets the suggestions stand alone.
    ///
    /// `metadata`/`rules` (AND-526) are forwarded to the current-month spend
    /// scoring of both the explicit and suggested halves so overrides /
    /// recategorizations / exclusions move the dashboard totals. The
    /// *suggested limits* themselves still derive from raw trailing history (a
    /// guardrail baseline), but the spend they are scored against is
    /// override-aware. Both default to `nil`, preserving legacy scoring.
    public static func mergedPresentation(
        explicitBudgets: [SpendingCategory: Double],
        transactions: [TransactionDTO],
        asOf date: Date,
        calendar: Calendar = .current,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> CategoryBudgetPresentation {
        let suggested = presentation(
            budgets: suggestedBudgets(from: transactions, asOf: date, calendar: calendar)
                .filter { explicitBudgets[$0.key] == nil },
            transactions: transactions,
            asOf: date,
            calendar: calendar,
            areSuggested: true,
            metadata: metadata,
            rules: rules,
            splits: splits
        )

        guard !explicitBudgets.isEmpty else { return suggested }

        let explicit = presentation(
            budgets: explicitBudgets,
            transactions: transactions,
            asOf: date,
            calendar: calendar,
            metadata: metadata,
            rules: rules,
            splits: splits
        )
        return merge(explicit: explicit, suggested: suggested)
    }

    /// Combine an explicit-budget presentation with a suggestion presentation:
    /// explicit items win on identity, suggestions fill the rest, and the union
    /// is re-ranked attention-first, then by spend pressure, then explicit-before-
    /// suggested, then category name. `internal` so the ranking is unit-testable.
    static func merge(
        explicit: CategoryBudgetPresentation,
        suggested: CategoryBudgetPresentation
    ) -> CategoryBudgetPresentation {
        let explicitCategoryIds = Set(explicit.items.map(\.id))
        let items = (explicit.items + suggested.items.filter { !explicitCategoryIds.contains($0.id) })
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return statusRank(lhs.status) < statusRank(rhs.status)
                }
                // Spend pressure: heavier first. The `!=` guard is an exact Double
                // compare, which is intentional — only items whose fractions are
                // bit-equal fall through to the explicit-before-suggested tiebreaker.
                if lhs.fractionUsed != rhs.fractionUsed {
                    return lhs.fractionUsed > rhs.fractionUsed
                }
                if lhs.isSuggested != rhs.isSuggested {
                    return !lhs.isSuggested
                }
                return lhs.category.displayName < rhs.category.displayName
            }
        return CategoryBudgetPresentation(items: items)
    }

    // MARK: - Override-aware spend (AND-546)

    /// Override-aware net spend per category for a month, **always** resolving
    /// per-transaction user category overrides, recategorization rules, and
    /// budget-exclusions before bucketing.
    ///
    /// This is the v2-foundation fix for the long-standing override-unaware default
    /// in ``netSpendByCategory``: that function's *default* path (both `metadata`
    /// and `rules` `nil`) buckets purely by raw Plaid category, so a user who
    /// recategorized a transaction or excluded it from budgets sees spend land in
    /// the wrong category. The v1 default is intentionally left unchanged for
    /// backward compatibility (a v1, not-opted-in user keeps identical behavior);
    /// this entrypoint is the explicit, override-aware surface v2 callers use.
    ///
    /// It threads `metadata`/`rules` through to ``netSpendByCategory`` (forcing the
    /// resolved path even when both are empty, by passing `rules` non-nil), so the
    /// full ``EffectiveCategoryResolver`` precedence applies: user override → rule →
    /// confident Plaid → `.other`, with transfers and excluded rows dropped and
    /// income never counted.
    ///
    /// - Parameters:
    ///   - month: the budgeted month as `YYYY-MM` (first-of-month). Spend is summed
    ///     over `[month-01, nextMonth-01)`.
    ///   - calendar: the calendar used to derive the month bounds (no hidden
    ///     `Date()`).
    /// - Returns: signed net spend per category for the month, override-aware.
    /// - Parameter splits: per-transaction category splits (AND-550). **Defaults to
    ///   empty**, preserving the un-split behavior exactly. When a transaction has a
    ///   *valid* split here, its parent is replaced by its allocation rows — each
    ///   bucketed by the allocation's own category and respecting the allocation's
    ///   own exclude flag — so rollups count the **parts, not the parent**. A
    ///   transaction with no (or a malformed) split is unchanged.
    public static func overrideAwareSpend(
        transactions: [TransactionDTO],
        month: String,
        metadata: [TransactionReviewMetadata] = [],
        rules: [TransactionRule] = [],
        splits: [TransactionSplit] = [],
        calendar: Calendar = .current
    ) -> [SpendingCategory: Double] {
        guard
            let monthStart = monthStartDate(fromMonthKey: month, calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return [:] }

        // Pass `rules` non-nil so `netSpendByCategory` takes the resolved path even
        // when both collections are empty — that's the whole point of this surface:
        // resolution always runs, never the raw-Plaid legacy bucketing.
        return netSpendByCategory(
            from: transactions,
            startKey: Formatters.transactionDateString(monthStart),
            endKey: Formatters.transactionDateString(nextMonthStart),
            metadata: metadata,
            rules: rules,
            splits: splits
        )
    }

    // MARK: - Internals

    /// Net signed spend per category within `[startKey, endKey)`, excluding income
    /// and transfers. Pending transactions are included — they represent committed
    /// spend, and the sync layer (`TransactionSyncReducer`) reconciles a pending
    /// row into its posted form, so there is no double-count here.
    ///
    /// ## Override-aware aggregation (AND-526)
    ///
    /// When `metadata` and/or `rules` are supplied, spend is bucketed by each
    /// transaction's *effective* (override-aware) budget category rather than its
    /// raw Plaid category, via `EffectiveCategoryResolver.resolve`:
    /// - a user `userCategory` override (or a matching rule's category) moves the
    ///   spend to the chosen category;
    /// - a row the user (or a rule) `excludedFromBudgets`, or a row resolved as a
    ///   transfer, is dropped entirely;
    /// - a row with no confident effective category (no override/rule, and a
    ///   `.other`/absent/low-confidence Plaid category) **falls back** to its raw
    ///   Plaid bucket — or `.other` when Plaid gave nothing — rather than being
    ///   dropped, matching the legacy bucket and the spend precedence (user
    ///   override → rule → raw Plaid → `.other`). An on-device NL suggestion is
    ///   still display-only and never counted: it stays on
    ///   `Resolution.suggestedCategory`, so an unreviewed guess never inflates a
    ///   bucket — the row simply keeps its raw-Plaid/`.other` attribution until the
    ///   user approves the suggestion.
    ///
    /// Both params **default to `nil`, which preserves the legacy behavior
    /// exactly** (bucket by `transaction.category ?? .other`, drop income /
    /// transfers) — so existing callers and tests are unchanged. Passing a
    /// non-nil-but-empty collection opts into resolved mode, where a transaction
    /// with no metadata and no matching rule resolves to its confident Plaid
    /// category (matching the legacy bucket for confidently-categorized rows).
    ///
    /// Review metadata stored under a charge's `pendingTransactionId` is carried
    /// into its posted replacement (mirrors `TransactionReviewInbox.evaluate`), so
    /// a category/transfer decision made while a charge was pending survives the
    /// pending→posted id change. The NL categorizer is intentionally *not* invoked
    /// — the budget surface excludes NL suggestions — so this stays pure and
    /// cheap.
    static func netSpendByCategory(
        from transactions: [TransactionDTO],
        startKey: String,
        endKey: String,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> [SpendingCategory: Double] {
        // Shares the one override-aware bucketing loop with `SpendingSummary`
        // (AND-664 #1). The budget surface windows the rows itself (`dateRange`),
        // keeps the **signed** amount so refunds net (identity selector), and drops
        // any row that *resolved* to an excluded bucket — e.g. an override to
        // `.income` — via `excludePostResolution: true`.
        OverrideAwareSpendKernel.bucketedSpend(
            from: transactions,
            metadata: metadata,
            rules: rules,
            splitIndex: TransactionSplitResolver.index(splits),
            dateRange: (start: startKey, end: endKey),
            amount: { $0 },
            excludePostResolution: true
        )
    }

    /// First instant of the month containing `date`, in `calendar`.
    static func monthStartDate(asOf date: Date, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    /// First instant of a `YYYY-MM` month key in `calendar`. Returns `nil` for a
    /// malformed key (wrong length, non-numeric, out-of-range month) so a bad month
    /// degrades to "no spend" rather than a crash. Used by ``overrideAwareSpend``.
    static func monthStartDate(fromMonthKey month: String, calendar: Calendar) -> Date? {
        let parts = month.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4,
              parts[1].count == 2,
              let year = Int(parts[0]),
              let monthValue = Int(parts[1]),
              (1...12).contains(monthValue)
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: monthValue))
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
