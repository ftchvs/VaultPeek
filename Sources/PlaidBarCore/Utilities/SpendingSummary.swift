import Foundation

/// Deprecated proto-version of the period-comparison vocabulary — prefer
/// `PeriodComparison` + `MetricDelta` for any new comparison surface, so
/// exactly one delta vocabulary exists. This shim now derives its delta
/// fields from an embedded ``MetricDelta`` (absorbed rather than duplicated);
/// the legacy field names are kept for existing call sites.
///
/// One deliberate tightening from the legacy math: `deltaPercent` is `0` when
/// the previous total's magnitude is below `MetricDelta.Threshold.currency`'s
/// absolute gate — the legacy formula exploded a sub-dollar baseline into a
/// fake multi-thousand percent figure.
public struct SpendingPeriodSummary: Sendable {
    /// The canonical comparison (spend: lower is better).
    public let metric: MetricDelta
    public let categories: [(SpendingCategory, Double)]

    public var currentTotal: Double { metric.current }
    public var previousTotal: Double { metric.previous }
    public var delta: Double { metric.delta }
    public var deltaPercent: Double {
        previousTotal > 0 ? (metric.percentChange ?? 0) : 0
    }

    public init(
        currentTotal: Double,
        previousTotal: Double,
        categories: [(SpendingCategory, Double)]
    ) {
        metric = MetricDelta.evaluate(
            current: currentTotal,
            previous: previousTotal,
            polarity: .lowerIsBetter
        )
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
        // Shares the one override-aware bucketing loop with `CategoryBudgetPlanner`
        // (AND-664 #1). The summary surface windows its own input via
        // `expenseTransactions` (so no inline `dateRange`), uses the `abs` magnitude
        // convention (its rows are display amounts, not signed), and — because that
        // pre-filter already drops income/transfers — does **not** drop a row that
        // *resolved* to an excluded bucket (`excludePostResolution: false`),
        // preserving the legacy behavior exactly.
        let totals = OverrideAwareSpendKernel.bucketedSpend(
            from: expenseTransactions(from: transactions),
            metadata: metadata,
            rules: rules,
            splitIndex: TransactionSplitResolver.index(splits),
            dateRange: nil,
            amount: abs,
            excludePostResolution: false
        )
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
