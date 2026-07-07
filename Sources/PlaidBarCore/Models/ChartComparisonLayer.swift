import Foundation

/// A horizontal reference line for a chart: the value, a short label, the
/// preformatted (mask-aware) value text, and a spoken description. Pure value
/// type so the chart view does no math or formatting of its own.
///
/// The numeric `value` stays real even under Privacy Mask — a baseline is only
/// ever drawn *inside* a chart whose own series is already governed by the
/// same mask state, so the line's position leaks nothing the chart does not.
/// Only the rendered *text* is masked.
public struct ChartBaseline: Sendable, Equatable {
    /// The y-value the line sits at.
    public let value: Double
    /// Short label, e.g. `"Daily average"`.
    public let label: String
    /// Preformatted value text, already mask-aware (`"$84"` or `"••••"`).
    public let valueText: String
    /// Spoken description with no glyphs, already mask-aware.
    public let accessibilityText: String

    public init(value: Double, label: String, valueText: String, accessibilityText: String) {
        self.value = value
        self.label = label
        self.valueText = valueText
        self.accessibilityText = accessibilityText
    }
}

/// A prior-period series overlaid on the current period's axis: each prior
/// point is date-shifted **forward by the window length**, so day 1 of the
/// prior window lands on day 1 of the current window and the two lines
/// compare visually day-for-day.
public struct GhostSeries: Sendable, Equatable {
    /// Prior-period balance points, dates shifted onto the current axis.
    public let points: [BalanceSnapshot]
    /// Legend label, e.g. `"Previous 90 days"`.
    public let label: String
    /// Spoken summary of what the ghost line shows (never color/dash alone —
    /// ACCESSIBILITY.md).
    public let accessibilitySummary: String

    public init(points: [BalanceSnapshot], label: String, accessibilitySummary: String) {
        self.points = points
        self.label = label
        self.accessibilitySummary = accessibilitySummary
    }
}

/// Builds the prior-window ghost overlay for the net-worth trend chart by
/// reusing `BalanceTrend.evaluate` on the window immediately before the
/// current one — same windowing, same `requiredPointCount` honesty gate: when
/// the prior window has too few recorded points for an honest line, there is
/// no ghost at all rather than a misleading one.
public enum BalanceTrendComparison {
    /// The prior window's trend points shifted forward by `windowDays` so they
    /// overlay the current window's axis, or `nil` when the prior window lacks
    /// `BalanceTrend.requiredPointCount` points.
    public static func evaluate(
        history: [BalanceSnapshot],
        now: Date,
        windowDays: Int = 90,
        calendar: Calendar = .current
    ) -> GhostSeries? {
        guard windowDays > 0,
              let priorEnd = calendar.date(
                  byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)
              ),
              let priorTrend = BalanceTrend.evaluate(
                  history: history,
                  now: priorEnd,
                  windowDays: windowDays,
                  calendar: calendar
              )
        else { return nil }

        var shifted: [BalanceSnapshot] = []
        shifted.reserveCapacity(priorTrend.points.count)
        for point in priorTrend.points {
            guard let date = calendar.date(byAdding: .day, value: windowDays, to: point.date) else {
                return nil
            }
            shifted.append(BalanceSnapshot(date: date, balance: point.balance))
        }

        let movement: String
        switch priorTrend.direction {
        case .up:
            movement = "rose \(Formatters.currency(abs(priorTrend.delta), format: .full))"
        case .down:
            movement = "fell \(Formatters.currency(abs(priorTrend.delta), format: .full))"
        case .flat:
            movement = "held steady"
        }

        return GhostSeries(
            points: shifted,
            label: "Previous \(windowDays) days",
            accessibilitySummary:
            "Previous \(windowDays)-day period, overlaid for comparison: net worth \(movement) over that period."
        )
    }
}

public extension PeriodComparison {
    /// Average of `values` as a chart baseline, or `nil` when there is nothing
    /// to average. `valueText`/`accessibilityText` are mask-aware; the numeric
    /// value stays real for drawing (see `ChartBaseline`).
    static func averageBaseline(
        values: [Double],
        label: String,
        isMasked: Bool
    ) -> ChartBaseline? {
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let valueText = isMasked
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(average, format: .compact)
        let accessibilityText = isMasked
            ? "\(label): hidden while Privacy Mask is on."
            : "\(label): \(Formatters.currency(average, format: .full))."
        return ChartBaseline(
            value: average,
            label: label,
            valueText: valueText,
            accessibilityText: accessibilityText
        )
    }
}
