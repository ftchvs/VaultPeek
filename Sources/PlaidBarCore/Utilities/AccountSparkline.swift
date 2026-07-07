import Foundation

/// Pure, presentation-agnostic source for the per-account dashboard row
/// sparkline (AND-379). Given an account's recorded balance history, it
/// produces a normalized 0...1 series and a trend direction so the row view
/// can render a tiny glance line without doing any math of its own.
///
/// Direction is delegated to `BalanceTrend.evaluate`, so the row sparkline,
/// the net-worth header sparkline, and the wealth fly-out all classify
/// up/down/flat identically — there is one source of truth for "which way did
/// the balance move".
///
/// The series degrades gracefully: when history has fewer than the required
/// points inside the window (the same gate `BalanceTrend` applies), it returns
/// `nil` so the row renders no line at all rather than a misleading one.
public enum AccountSparkline {
    /// Minimum recorded points required before a row will draw a sparkline.
    /// Matches `BalanceTrend.requiredPointCount` so "enough data for a trend"
    /// and "enough data for a sparkline" stay the same judgement.
    public static let defaultMinimumPointCount = BalanceTrend.requiredPointCount

    /// A render-ready sparkline: the trend direction plus the balance series
    /// normalized into 0...1 (lowest balance → 0, highest → 1). A flat series
    /// (no spread between min and max) collapses to a mid-line so the row draws
    /// a calm horizontal stroke instead of dividing by zero.
    public struct Series: Sendable, Equatable {
        public let direction: BalanceTrend.Direction
        /// Balance points normalized to 0...1, oldest first. Always at least
        /// `minimumPointCount` long when produced via `evaluate`.
        public let normalizedValues: [Double]

        public init(direction: BalanceTrend.Direction, normalizedValues: [Double]) {
            self.direction = direction
            self.normalizedValues = normalizedValues
        }

        /// Indexed points for charting: `(x: position, y: normalized value)`,
        /// oldest at x = 0. Convenience for a hidden-axis `Chart`.
        public var indexedPoints: [(x: Int, y: Double)] {
            normalizedValues.enumerated().map { (x: $0.offset, y: $0.element) }
        }
    }

    /// Builds a normalized sparkline series for an account's balance history,
    /// or `nil` when there is too little history to draw an honest line.
    ///
    /// - Parameters:
    ///   - history: Recorded balance snapshots for a single account.
    ///   - minimumPointCount: Fewest in-window points that may render a line.
    ///     Clamped to at least `BalanceTrend.requiredPointCount`, because a
    ///     direction itself needs two points.
    ///   - now: Upper bound of the window (defaults to the current date).
    ///   - windowDays: Trailing window the series is drawn from.
    ///   - calendar: Calendar used for the window math (testable).
    public static func evaluate(
        history: [BalanceSnapshot],
        minimumPointCount: Int = defaultMinimumPointCount,
        now: Date = Date(),
        windowDays: Int = 90,
        calendar: Calendar = .current
    ) -> Series? {
        // Reuse the trend evaluator: it owns the windowing, sorting, and the
        // up/down/flat classification, so the sparkline never drifts from the
        // delta arrow shown next to it. A nil trend means insufficient data.
        guard let trend = BalanceTrend.evaluate(
            history: history,
            now: now,
            windowDays: windowDays,
            calendar: calendar
        ) else {
            return nil
        }

        let effectiveMinimum = max(minimumPointCount, BalanceTrend.requiredPointCount)
        let balances = trend.points.map(\.balance)
        guard balances.count >= effectiveMinimum else { return nil }

        return Series(
            direction: trend.direction,
            normalizedValues: normalize(balances)
        )
    }

    /// Maps balances onto 0...1 by min/max. A zero-spread (flat) series maps to
    /// a constant mid-line so the chart draws a level stroke, not a NaN.
    /// Public so every spark strip normalizes identically — this is also the
    /// normalizer behind `GlanceSnapshot`'s sparkline and
    /// `PeriodComparison.dailySpendSpark`.
    public static func normalize(_ balances: [Double]) -> [Double] {
        guard let minimum = balances.min(), let maximum = balances.max() else {
            return []
        }
        let spread = maximum - minimum
        guard spread > 0 else {
            return balances.map { _ in 0.5 }
        }
        return balances.map { ($0 - minimum) / spread }
    }
}
