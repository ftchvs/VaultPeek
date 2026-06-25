import Foundation

public struct SpendingPeriodSummary: Sendable {
    public let currentTotal: Double
    public let previousTotal: Double
    public let delta: Double
    public let deltaPercent: Double
    public let categories: [(SpendingCategory, Double)]

    public init(
        currentTotal: Double,
        previousTotal: Double,
        categories: [(SpendingCategory, Double)]
    ) {
        self.currentTotal = currentTotal
        self.previousTotal = previousTotal
        self.delta = currentTotal - previousTotal
        self.deltaPercent = previousTotal > 0 ? (delta / previousTotal) * 100 : 0
        self.categories = categories
    }
}

public enum SpendingSummary {
    /// Period summary of spend. `metadata`/`rules` (AND-527) are optional and
    /// default to `nil`, which reproduces the legacy raw-`transaction.category`
    /// behavior. When supplied, the current-period category breakdown resolves the
    /// *effective* category (user override → rule → raw Plaid → `.other`) and drops
    /// excluded/transfer rows via `EffectiveCategoryResolver`, so a recategorization
    /// in the Review Inbox moves the summarized totals to match the dashboard.
    public static func periodSummary(
        from transactions: [TransactionDTO],
        currentStart: String,
        previousStart: String,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> SpendingPeriodSummary {
        let currentExpenses = expenseTransactions(
            from: transactions,
            startingAt: currentStart
        )
        let previousExpenses = expenseTransactions(
            from: transactions,
            startingAt: previousStart,
            endingBefore: currentStart
        )

        let categories = spendingByCategory(
            from: currentExpenses,
            metadata: metadata,
            rules: rules,
            splits: splits
        )
        let currentTotal = categories.reduce(0) { $0 + $1.1 }
        let previousTotal = previousExpenses.reduce(0) { $0 + $1.displayAmount }

        return SpendingPeriodSummary(
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            categories: categories
        )
    }

    /// Spend grouped by category, descending. `metadata`/`rules` (AND-527) are
    /// optional and default to `nil` → the legacy path buckets by raw
    /// `transaction.category ?? .other`. When supplied, each row is resolved to its
    /// *effective* category via the persisted-only `EffectiveCategoryResolver`
    /// (user override → rule → raw Plaid → `.other`, NL suggestions excluded), and
    /// excluded/transfer rows drop out — so the summary matches the override-aware
    /// dashboard. Pending-phase review metadata stored under a charge's
    /// `pendingTransactionId` is carried into its posted replacement (mirrors
    /// `CategoryBudgetPlanner.netSpendByCategory`).
    public static func spendingByCategory(
        from transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = []
    ) -> [(SpendingCategory, Double)] {
        let expenses = expenseTransactions(from: transactions)
        let splitIndex = TransactionSplitResolver.index(splits)

        // Legacy path: no review state supplied → bucket by raw Plaid category.
        // Split-aware: a transaction with a valid split contributes its allocation
        // rows (each by its own category, honoring its exclude flag). With no
        // splits this is byte-identical to the pre-AND-550 grouping.
        guard metadata != nil || rules != nil else {
            var totals: [SpendingCategory: Double] = [:]
            for transaction in expenses {
                for row in TransactionSplitResolver.spendRows(
                    for: transaction, splitsByTransactionId: splitIndex
                ) {
                    if row.isSplitExcluded { continue }
                    let category = row.category ?? .other
                    // Use the magnitude so a split allocation matches the legacy
                    // `displayAmount` convention this summary uses.
                    totals[category, default: 0] += abs(row.amount)
                }
            }
            return totals.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        }

        let metadataById = Dictionary(
            (metadata ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeRules = rules ?? []

        var totals: [SpendingCategory: Double] = [:]
        for transaction in expenses {
            for row in TransactionSplitResolver.spendRows(
                for: transaction, splitsByTransactionId: splitIndex
            ) {
                // A split allocation already declared its category and exclude flag,
                // so it bypasses per-parent override/rule resolution and buckets by
                // its own category.
                if row.isSplitAllocation {
                    if row.isSplitExcluded { continue }
                    let category = row.category ?? .other
                    totals[category, default: 0] += abs(row.amount)
                    continue
                }

                // Un-split row: the existing override-aware path, unchanged.
                // Carry pending-phase review metadata into the posted charge (mirrors
                // `CategoryBudgetPlanner.netSpendByCategory`): prefer the transaction's
                // own record, then the carried-forward pending record.
                let effectiveMetadata = metadataById[transaction.id]
                    ?? transaction.pendingTransactionId.flatMap { metadataById[$0] }

                let resolution = EffectiveCategoryResolver.resolve(
                    transaction: transaction,
                    metadata: effectiveMetadata,
                    rules: activeRules
                )

                // Drop excluded rows (explicit user/rule exclusion or transfers) — the
                // override surface can re-classify a row as a transfer the raw Plaid
                // category did not flag.
                if resolution.excludedFromBudgets || resolution.isTransfer { continue }

                // Fall back to the raw Plaid bucket (or `.other`) when no confident
                // override/rule/Plaid category resolved, matching the legacy bucket —
                // a display-only NL suggestion is never counted (it lives on
                // `resolution.suggestedCategory`, not on the aggregation category).
                let category = resolution.category ?? (transaction.category ?? .other)
                totals[category, default: 0] += abs(row.amount)
            }
        }

        return totals.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    public static func expenseTransactions(
        from transactions: [TransactionDTO],
        startingAt startDate: String? = nil,
        endingBefore endDate: String? = nil
    ) -> [TransactionDTO] {
        transactions.filter { transaction in
            if let startDate, transaction.date < startDate { return false }
            if let endDate, transaction.date >= endDate { return false }
            return !transaction.isIncome
                && transaction.category != .transfer
                && transaction.category != .transferOut
        }
    }
}
