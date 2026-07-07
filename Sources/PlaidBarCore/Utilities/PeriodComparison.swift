import Foundation

/// Which two periods a comparison spans. The label is the chip's trailing
/// context ("vs last month"), so period choice and copy stay in lockstep.
public enum ComparisonPeriod: Sendable, Equatable {
    /// The trailing `n` days ending today vs the `n` days immediately before.
    case trailingDays(Int)
    /// Month so far vs the **prior month to the same day**. This is the honest
    /// mid-month compare: the classic misleading delta compares a partial
    /// current month against the *full* prior month, which reads as "spending
    /// way down!" every 1st-through-20th. Truncating the prior window to the
    /// same elapsed days removes that lie.
    case monthToDate
    /// The full current calendar month vs the full prior calendar month.
    case fullMonthOverMonth

    /// Trailing chip copy, e.g. `"vs last month"`. Pairs with
    /// `MetricDeltaChip.make(delta:comparisonLabel:...)`.
    public var comparisonLabel: String {
        switch self {
        case let .trailingDays(days):
            "vs prior \(days) days"
        case .monthToDate:
            "vs last month to date"
        case .fullMonthOverMonth:
            "vs last month"
        }
    }
}

/// The Core period-comparison engine: derives the current/prior date windows
/// for a `ComparisonPeriod` and builds `MetricDelta`s for the domain metrics —
/// always by calling the **existing** aggregation kernels once per window
/// (`CategoryBudgetPlanner.netSpendByCategory`, `IncomeCategoryFlow`,
/// `SpendingSummary.expenseTransactions`), never a second aggregation path.
/// That guarantee matters: a user override or rule that recategorizes a
/// transaction moves the spend in *both* windows, so a delta can never be
/// manufactured by two aggregators disagreeing.
///
/// Everything takes an injected `asOf: Date` and `Calendar` — no hidden
/// `Date()` — matching `CategoryBudgetPlanner` / `BalanceProjector`.
public enum PeriodComparison {
    /// A half-open date window in canonical `yyyy-MM-dd` transaction keys:
    /// `startKey` inclusive, `endKey` **exclusive**. Canonical keys sort
    /// lexicographically, so windowing is a pair of string compares.
    public struct Window: Sendable, Equatable {
        public let startKey: String
        public let endKey: String

        public init(startKey: String, endKey: String) {
            self.startKey = startKey
            self.endKey = endKey
        }
    }

    // MARK: - Windows

    /// The current and prior windows for `period`, or `nil` when the calendar
    /// math cannot produce them (e.g. non-positive trailing days).
    ///
    /// The two windows **never overlap**. For `.trailingDays` and
    /// `.fullMonthOverMonth` they are exactly adjacent
    /// (`prior.endKey == current.startKey`). For `.monthToDate` the prior
    /// window is truncated to the same elapsed day count (clamped to the prior
    /// month's own length), so on short-month boundaries a gap before the
    /// current month start is deliberate — that truncation is the whole point
    /// of the honest mid-month compare.
    public static func windows(
        for period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> (current: Window, prior: Window)? {
        let today = calendar.startOfDay(for: date)
        // Windows are end-exclusive, so "through today" means ending at the
        // start of tomorrow.
        guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        switch period {
        case let .trailingDays(days):
            guard days > 0,
                  let currentStart = calendar.date(byAdding: .day, value: -days, to: dayAfter),
                  let priorStart = calendar.date(byAdding: .day, value: -days, to: currentStart)
            else { return nil }
            return (
                current: window(from: currentStart, to: dayAfter),
                prior: window(from: priorStart, to: currentStart)
            )

        case .monthToDate:
            guard let monthStart = CategoryBudgetPlanner.monthStartDate(asOf: today, calendar: calendar),
                  let priorMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart),
                  let elapsedDays = calendar.dateComponents([.day], from: monthStart, to: dayAfter).day,
                  elapsedDays > 0,
                  let priorEndUnclamped = calendar.date(byAdding: .day, value: elapsedDays, to: priorMonthStart)
            else { return nil }
            // Clamp: the prior window never spills past its own month (a
            // March 31st compare covers all 28/29 days of February, no more).
            let priorEnd = min(priorEndUnclamped, monthStart)
            return (
                current: window(from: monthStart, to: dayAfter),
                prior: window(from: priorMonthStart, to: priorEnd)
            )

        case .fullMonthOverMonth:
            guard let monthStart = CategoryBudgetPlanner.monthStartDate(asOf: today, calendar: calendar),
                  let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  let priorMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)
            else { return nil }
            return (
                current: window(from: monthStart, to: nextMonthStart),
                prior: window(from: priorMonthStart, to: monthStart)
            )
        }
    }

    private static func window(from start: Date, to end: Date) -> Window {
        Window(
            startKey: Formatters.transactionDateString(start),
            endKey: Formatters.transactionDateString(end)
        )
    }

    // MARK: - Domain deltas

    /// Total net spend delta (polarity: lower is better). Spend per window is
    /// the sum of `CategoryBudgetPlanner.netSpendByCategory` — the one
    /// override-aware spend kernel — so `metadata`/`rules`/`splits` move both
    /// windows identically.
    public static func totalSpendDelta(
        transactions: [TransactionDTO],
        period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = [],
        threshold: MetricDelta.Threshold = .currency
    ) -> MetricDelta? {
        guard let windows = windows(for: period, asOf: date, calendar: calendar) else { return nil }
        let current = netSpend(
            transactions: transactions, window: windows.current,
            metadata: metadata, rules: rules, splits: splits
        ).values.reduce(0, +)
        let prior = netSpend(
            transactions: transactions, window: windows.prior,
            metadata: metadata, rules: rules, splits: splits
        ).values.reduce(0, +)
        return MetricDelta.evaluate(
            current: current, previous: prior, polarity: .lowerIsBetter, threshold: threshold
        )
    }

    /// Total income delta (polarity: higher is better). Income per window
    /// reuses `IncomeCategoryFlow.incomeSources` — the existing inflow gate
    /// (money in, own-account transfers excluded) — summed over its nodes.
    public static func incomeDelta(
        transactions: [TransactionDTO],
        period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current,
        threshold: MetricDelta.Threshold = .currency
    ) -> MetricDelta? {
        guard let windows = windows(for: period, asOf: date, calendar: calendar) else { return nil }
        return MetricDelta.evaluate(
            current: incomeTotal(transactions: transactions, window: windows.current),
            previous: incomeTotal(transactions: transactions, window: windows.prior),
            polarity: .higherIsBetter,
            threshold: threshold
        )
    }

    /// Per-category spend deltas (polarity: lower is better) across the union
    /// of categories present in either window. `netSpendByCategory` is called
    /// once per window, so an override or rule recategorizing a prior-window
    /// transaction moves both sides of every delta.
    public static func categorySpendDeltas(
        transactions: [TransactionDTO],
        period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current,
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil,
        splits: [TransactionSplit] = [],
        threshold: MetricDelta.Threshold = .currency
    ) -> [SpendingCategory: MetricDelta] {
        guard let windows = windows(for: period, asOf: date, calendar: calendar) else { return [:] }
        let current = netSpend(
            transactions: transactions, window: windows.current,
            metadata: metadata, rules: rules, splits: splits
        )
        let prior = netSpend(
            transactions: transactions, window: windows.prior,
            metadata: metadata, rules: rules, splits: splits
        )

        var deltas: [SpendingCategory: MetricDelta] = [:]
        for category in Set(current.keys).union(prior.keys) {
            deltas[category] = MetricDelta.evaluate(
                current: current[category] ?? 0,
                previous: prior[category] ?? 0,
                polarity: .lowerIsBetter,
                threshold: threshold
            )
        }
        return deltas
    }

    /// Net-worth delta (polarity: higher is better) from recorded balance
    /// history: `current` is the latest snapshot, `previous` is the latest
    /// snapshot **before** the prior window's exclusive end (the boundary
    /// between the windows for adjacent periods).
    ///
    /// Returns `nil` when history does not reach back to the prior window —
    /// a young install must never show a zero-baseline "+$48K since last
    /// month" chip built from its own first sync.
    public static func netWorthDelta(
        history: [BalanceSnapshot],
        period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current,
        threshold: MetricDelta.Threshold = .currency
    ) -> MetricDelta? {
        guard let windows = windows(for: period, asOf: date, calendar: calendar),
              let priorBoundary = Formatters.parseTransactionDate(windows.prior.endKey)
        else { return nil }

        let sorted = history.sorted { $0.date < $1.date }
        guard let latest = sorted.last,
              let previous = sorted.last(where: { $0.date < priorBoundary })
        else { return nil }

        return MetricDelta.evaluate(
            current: latest.balance,
            previous: previous.balance,
            polarity: .higherIsBetter,
            threshold: threshold
        )
    }

    /// Normalized (0...1) daily expense buckets over the current window, for a
    /// spark strip under a spend hero number. Windowing and expense
    /// classification reuse `SpendingSummary.expenseTransactions`;
    /// normalization reuses `AccountSparkline.normalize`.
    ///
    /// Returns `nil` when the window cannot be built or contains no expense
    /// activity — an all-zero spark would draw a meaningless mid-line.
    public static func dailySpendSpark(
        transactions: [TransactionDTO],
        period: ComparisonPeriod,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [Double]? {
        guard let windows = windows(for: period, asOf: date, calendar: calendar),
              let start = Formatters.parseTransactionDate(windows.current.startKey),
              let end = Formatters.parseTransactionDate(windows.current.endKey)
        else { return nil }

        let expenses = SpendingSummary.expenseTransactions(
            from: transactions,
            startingAt: windows.current.startKey,
            endingBefore: windows.current.endKey
        )
        guard !expenses.isEmpty else { return nil }

        var byDay: [String: Double] = [:]
        for expense in expenses {
            byDay[expense.date, default: 0] += expense.displayAmount
        }

        var series: [Double] = []
        var day = start
        while day < end {
            series.append(byDay[Formatters.transactionDateString(day)] ?? 0)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return AccountSparkline.normalize(series)
    }

    // MARK: - Kernel plumbing

    /// Windowed, override-aware net spend per category — a direct pass-through
    /// to `CategoryBudgetPlanner.netSpendByCategory` (the one spend kernel).
    private static func netSpend(
        transactions: [TransactionDTO],
        window: Window,
        metadata: [TransactionReviewMetadata]?,
        rules: [TransactionRule]?,
        splits: [TransactionSplit]
    ) -> [SpendingCategory: Double] {
        CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: window.startKey,
            endKey: window.endKey,
            metadata: metadata,
            rules: rules,
            splits: splits
        )
    }

    /// Windowed total income — the sum of `IncomeCategoryFlow.incomeSources`
    /// nodes over the window's transactions (reusing its inflow gate).
    private static func incomeTotal(
        transactions: [TransactionDTO],
        window: Window
    ) -> Double {
        let windowed = transactions.filter {
            $0.date >= window.startKey && $0.date < window.endKey
        }
        return IncomeCategoryFlow.incomeSources(from: windowed).reduce(0) { $0 + $1.amount }
    }
}
