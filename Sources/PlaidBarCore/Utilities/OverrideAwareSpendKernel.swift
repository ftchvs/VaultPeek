import Foundation

/// The single override-aware spend-bucketing loop shared by ``SpendingSummary``
/// and ``CategoryBudgetPlanner`` (AND-664 #1).
///
/// Before this type, the two surfaces carried two byte-for-byte copies of the
/// same loop — split-row expansion, the legacy raw-Plaid bucket, the
/// override/rule/transfer resolution, and the pending→posted metadata
/// carry-forward — differing only in (a) the **amount selector** (`SpendingSummary`
/// uses the `abs` magnitude convention; `CategoryBudgetPlanner` keeps the **signed**
/// amount so refunds net), (b) an **inline date filter** (the budget surface filters
/// by `[start, end)`; the summary surface pre-filters its input), and (c) whether a
/// resolved category that lands on an excluded bucket (e.g. a user override **to**
/// `.income`) is dropped post-resolution. Keeping two copies is what let an
/// override-unaware-spend bug land twice historically; this kernel is the one place
/// the loop lives.
///
/// It is parameterized so each call site reproduces its prior behavior exactly:
/// the only knobs are the amount selector, the optional date range, and the
/// `excludePostResolution` flag. Everything else — split handling, the
/// `excludedCategories` drops in the legacy and split paths, the resolver
/// precedence (user override → rule → confident Plaid → `.other`), and the
/// pending-id carry-forward — is shared and identical for both.
enum OverrideAwareSpendKernel {
    /// Bucket `transactions` into signed-or-magnitude spend per effective category.
    ///
    /// - Parameters:
    ///   - transactions: rows to aggregate. Callers that need an income/transfer
    ///     pre-filter (``SpendingSummary``) apply it before calling; the budget
    ///     surface passes the raw set and relies on `dateRange` + the
    ///     `excludedCategories` drops instead.
    ///   - metadata/rules: when **both** are `nil` the legacy raw-Plaid bucketing
    ///     runs (byte-identical to the pre-extraction default path). A non-nil value
    ///     (even an empty array) opts into the resolved, override-aware path.
    ///   - splitIndex: pre-built split lookup (`TransactionSplitResolver.index`).
    ///   - dateRange: when set, a row is skipped unless
    ///     `start <= transaction.date < end` (the budget surface's inline filter).
    ///     `nil` disables the inline filter (the summary surface, whose caller has
    ///     already windowed the rows).
    ///   - amount: maps a raw split-row amount to the value summed —
    ///     `abs` for the magnitude convention, identity for signed netting.
    ///   - excludePostResolution: when `true`, a resolved un-split row whose final
    ///     category is in `CategoryBudgetPlanner.excludedCategories` (e.g. an
    ///     override to `.income`) is dropped — the budget surface's behavior. When
    ///     `false` the summary surface keeps it (its income/transfer rows are
    ///     already pre-filtered out, and an override-to-income is counted as before).
    static func bucketedSpend(
        from transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata]?,
        rules: [TransactionRule]?,
        splitIndex: [String: TransactionSplit],
        dateRange: (start: String, end: String)?,
        amount: (Double) -> Double,
        excludePostResolution: Bool
    ) -> [SpendingCategory: Double] {
        let excluded = CategoryBudgetPlanner.excludedCategories

        // Legacy path: no review state supplied → bucket by raw Plaid category.
        // Split-aware: a transaction with a valid split contributes its allocation
        // rows (each by its own category, honoring its exclude flag). With no splits
        // this is byte-identical to the pre-extraction grouping.
        guard metadata != nil || rules != nil else {
            var totals: [SpendingCategory: Double] = [:]
            for transaction in transactions {
                if let dateRange,
                   transaction.date < dateRange.start || transaction.date >= dateRange.end {
                    continue
                }
                for row in TransactionSplitResolver.spendRows(
                    for: transaction, splitsByTransactionId: splitIndex
                ) {
                    if row.isSplitExcluded { continue }
                    let category = row.category ?? .other
                    // Income/transfer allocations are never spend.
                    if excluded.contains(category) { continue }
                    totals[category, default: 0] += amount(row.amount)
                }
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
            if let dateRange,
               transaction.date < dateRange.start || transaction.date >= dateRange.end {
                continue
            }

            for row in TransactionSplitResolver.spendRows(
                for: transaction, splitsByTransactionId: splitIndex
            ) {
                // A split allocation already declared its category and exclude flag,
                // so it bypasses per-parent override/rule resolution and buckets by
                // its own category. Income/transfer allocations are never counted.
                if row.isSplitAllocation {
                    if row.isSplitExcluded { continue }
                    let category = row.category ?? .other
                    if excluded.contains(category) { continue }
                    totals[category, default: 0] += amount(row.amount)
                    continue
                }

                // Un-split row: the override-aware path. Carry pending-phase review
                // metadata into the posted charge — prefer the transaction's own
                // record, then the carried-forward pending record.
                let effectiveMetadata = metadataById[transaction.id]
                    ?? transaction.pendingTransactionId.flatMap { metadataById[$0] }

                let resolution = EffectiveCategoryResolver.resolve(
                    transaction: transaction,
                    metadata: effectiveMetadata,
                    rules: activeRules
                )

                // Drop excluded rows (explicit user/rule exclusion or transfers).
                if resolution.excludedFromBudgets || resolution.isTransfer { continue }

                // No *confident* override/rule/Plaid category → fall back to the raw
                // Plaid bucket (or `.other`), matching the legacy bucket and the
                // spend precedence. A display-only NL suggestion is never counted: it
                // lives on `resolution.suggestedCategory`, not the aggregation
                // category, so an unapproved guess keeps the raw-Plaid/`.other`
                // attribution until approved.
                let category = resolution.category ?? (transaction.category ?? .other)

                // The budget surface also drops a category that *resolved* to an
                // excluded bucket (e.g. an override to `.income`); the summary
                // surface keeps its (already income/transfer pre-filtered) rows.
                if excludePostResolution, excluded.contains(category) { continue }

                totals[category, default: 0] += amount(row.amount)
            }
        }
        return totals
    }
}
