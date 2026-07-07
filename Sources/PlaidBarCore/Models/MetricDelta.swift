import Foundation

/// One period-over-period comparison of a single metric — the shared "so what?"
/// vocabulary behind every delta chip and comparison baseline in the app.
///
/// `MetricDelta` deliberately classifies movement **more strictly** than
/// `BalanceTrend`: the trend's ±0.005 gate answers "did the line move at all?"
/// (raw movement, so a sparkline never draws a false flat), while this type
/// answers "is the movement worth a chip?" — a `direction` here is `.flat`
/// unless the change clears **both** the absolute and the relative
/// `Threshold`, so a $2 wiggle on an $800 baseline never earns an arrow.
/// `BalanceTrend` is intentionally left untouched; the two gates serve
/// different questions.
public struct MetricDelta: Sendable, Equatable {
    /// How to read the metric's movement: is a rise good news or bad news?
    public enum Polarity: Sendable, Equatable {
        /// Rising is good (income, net worth, savings).
        case higherIsBetter
        /// Rising is bad (spend, debt, utilization).
        case lowerIsBetter
        /// Movement carries no judgement (counts, informational figures).
        case neutral
    }

    /// Direction × polarity, resolved for presentation: which way should the
    /// chip *feel*? Flat movement is always neutral.
    public enum Sentiment: Sendable, Equatable {
        case positive
        case negative
        case neutral
    }

    /// Significance gates a change must clear before it is classified as
    /// movement. Both gates must pass: `minimumAbsolute` kills sub-dollar
    /// noise, `minimumRelative` kills tiny wiggles on large baselines.
    public struct Threshold: Sendable, Equatable {
        /// Smallest absolute change (in the metric's own unit) that counts.
        public let minimumAbsolute: Double
        /// Smallest change relative to the previous magnitude that counts
        /// (fraction, e.g. `0.01` = 1%). Waived when the previous magnitude is
        /// itself below `minimumAbsolute` — there is no meaningful baseline to
        /// be relative to.
        public let minimumRelative: Double

        public init(minimumAbsolute: Double = 1.0, minimumRelative: Double = 0.01) {
            self.minimumAbsolute = minimumAbsolute
            self.minimumRelative = minimumRelative
        }

        /// The default gate for currency metrics: at least $1 and at least 1%.
        public static let currency = Threshold()
    }

    /// The metric's value in the current period.
    public let current: Double
    /// The metric's value in the comparison period.
    public let previous: Double
    /// Signed change, always `current - previous`.
    public let delta: Double
    /// Signed percent change (`+14.0` = up 14%), measured against the previous
    /// magnitude. `nil` when the previous magnitude is below
    /// `Threshold.minimumAbsolute` — a near-zero baseline would produce a fake
    /// "+4,800%" style figure, so no percentage is claimed at all.
    public let percentChange: Double?
    /// Chip-worthy direction. `.flat` unless the change cleared **both**
    /// threshold gates. Reuses `GlanceSnapshot.ChangeDirection` so the glyph
    /// convention (▲/▼/■) is defined exactly once.
    public let direction: GlanceSnapshot.ChangeDirection
    /// How to read the movement (rise good vs rise bad vs no judgement).
    public let polarity: Polarity

    public init(
        current: Double,
        previous: Double,
        delta: Double,
        percentChange: Double?,
        direction: GlanceSnapshot.ChangeDirection,
        polarity: Polarity
    ) {
        self.current = current
        self.previous = previous
        self.delta = delta
        self.percentChange = percentChange
        self.direction = direction
        self.polarity = polarity
    }

    /// Direction × polarity: `.up` on a `higherIsBetter` metric is positive,
    /// `.up` on a `lowerIsBetter` metric (spend rising) is negative, and flat
    /// or `neutral`-polarity movement is always neutral.
    public var sentiment: Sentiment {
        switch (direction, polarity) {
        case (.flat, _), (_, .neutral):
            return .neutral
        case (.up, .higherIsBetter), (.down, .lowerIsBetter):
            return .positive
        case (.up, .lowerIsBetter), (.down, .higherIsBetter):
            return .negative
        }
    }

    /// The shared direction glyph (▲/▼/■) — same characters as
    /// `GlanceSnapshot.ChangeDirection.glyph`, by construction.
    public var glyph: String {
        direction.glyph
    }

    /// Signed currency text for the delta, byte-identical to
    /// `Formatters.signedCurrency` output (`+$420`, `-$63`, `$0`).
    public func signedText(format: CurrencyFormat = .full) -> String {
        Formatters.signedCurrency(delta, format: format)
    }

    /// Signed percent text (`+14%`, `-8%`) via the existing percent formatter,
    /// or `nil` when no honest percentage exists (see `percentChange`).
    public func percentText(decimals: Int = 0) -> String? {
        percentChange.map { change in
            change > 0
                ? "+\(Formatters.percent(change, decimals: decimals))"
                : Formatters.percent(change, decimals: decimals)
        }
    }

    /// Classify a period-over-period change.
    ///
    /// The change registers as movement (`.up`/`.down`) only when it clears
    /// **both** `threshold` gates; otherwise `direction` is `.flat`. The
    /// relative gate is waived when the previous magnitude is below
    /// `threshold.minimumAbsolute` (no meaningful baseline), which is also
    /// exactly when `percentChange` is withheld.
    public static func evaluate(
        current: Double,
        previous: Double,
        polarity: Polarity,
        threshold: Threshold = .currency
    ) -> MetricDelta {
        let delta = current - previous
        let previousMagnitude = abs(previous)
        let hasBaseline = previousMagnitude >= threshold.minimumAbsolute

        let percentChange: Double? = hasBaseline
            ? (delta / previousMagnitude) * 100
            : nil

        let clearsAbsolute = abs(delta) >= threshold.minimumAbsolute
        let clearsRelative = !hasBaseline || abs(delta) >= threshold.minimumRelative * previousMagnitude
        let direction: GlanceSnapshot.ChangeDirection = (clearsAbsolute && clearsRelative)
            ? .evaluate(delta)
            : .flat

        return MetricDelta(
            current: current,
            previous: previous,
            delta: delta,
            percentChange: percentChange,
            direction: direction,
            polarity: polarity
        )
    }
}
