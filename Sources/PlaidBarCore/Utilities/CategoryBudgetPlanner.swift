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
        rules: [TransactionRule]? = nil
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
            rules: rules
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
        rules: [TransactionRule]? = nil
    ) -> CategoryBudgetPresentation {
        let suggested = presentation(
            budgets: suggestedBudgets(from: transactions, asOf: date, calendar: calendar)
                .filter { explicitBudgets[$0.key] == nil },
            transactions: transactions,
            asOf: date,
            calendar: calendar,
            areSuggested: true,
            metadata: metadata,
            rules: rules
        )

        guard !explicitBudgets.isEmpty else { return suggested }

        let explicit = presentation(
            budgets: explicitBudgets,
            transactions: transactions,
            asOf: date,
            calendar: calendar,
            metadata: metadata,
            rules: rules
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
        rules: [TransactionRule]? = nil
    ) -> [SpendingCategory: Double] {
        // Legacy path: no review state supplied → bucket by raw Plaid category.
        guard metadata != nil || rules != nil else {
            var totals: [SpendingCategory: Double] = [:]
            for transaction in transactions {
                if transaction.date < startKey || transaction.date >= endKey { continue }
                let category = transaction.category ?? .other
                if excludedCategories.contains(category) { continue }
                totals[category, default: 0] += transaction.amount
            }
            return totals
        }

        let metadataById = Dictionary(
            (metadata ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeRules = rules ?? []

        var totals: [SpendingCategory: Double] = [:]
        for transaction in transactions {
            if transaction.date < startKey || transaction.date >= endKey { continue }

            // Carry pending-phase review metadata into the posted charge: Plaid
            // re-posts a previously-pending charge under a new id that links back
            // via `pendingTransactionId`. Prefer the transaction's own record;
            // fall back to the carried-forward pending record (mirrors
            // `TransactionReviewInbox.evaluate`).
            let effectiveMetadata = metadataById[transaction.id]
                ?? transaction.pendingTransactionId.flatMap { metadataById[$0] }

            let resolution = EffectiveCategoryResolver.resolve(
                transaction: transaction,
                metadata: effectiveMetadata,
                rules: activeRules
            )

            // Drop excluded rows (explicit user/rule exclusion or transfers).
            if resolution.excludedFromBudgets || resolution.isTransfer { continue }
            // No *confident* override/rule/Plaid category (the row is `.other`, has
            // no Plaid category, or Plaid flagged it low/unknown). Per the spend
            // precedence (user override → rule → raw Plaid → `.other`),
            // such a row must **fall back** to its raw Plaid bucket — or `.other`
            // when Plaid gave nothing — not vanish from totals. A display-only NL
            // suggestion is still never counted here: it lives on
            // `resolution.suggestedCategory`, not on the aggregation category, so an
            // unapproved guess keeps the row in raw-Plaid/`.other` until approved.
            let category = resolution.category ?? (transaction.category ?? .other)
            // Income never counts as category spend even if it survived resolution
            // (the resolver does not classify income as transfer/excluded).
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
