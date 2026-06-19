import Foundation

/// Pure, `Sendable` audio-graph descriptors for VaultPeek's charts (AND-569).
///
/// VoiceOver's *audio graph* (the "Describe Chart" / "Play Audio Graph" rotor
/// action) is driven by `AXChartDescriptor` from the `Accessibility` framework.
/// Those `AX*` reference types live in the UI layer and aren't `Sendable`, so we
/// keep the **data → descriptor-point mapping** here as plain value types that
/// are trivially unit-testable without a host view, and let the thin SwiftUI
/// wrappers (`*AudioGraphDescriptor`) translate these into `AXChartDescriptor`.
///
/// This is the audio-graph analogue of the spoken `accessibilityLabel` each
/// chart already exposes: same data, but scrubbable tone-by-tone instead of a
/// single sentence. Meaning never rides on color (ACCESSIBILITY.md) — the audio
/// graph conveys the series purely through pitch + the labeled axes here.
public enum ChartAudioGraph {
    /// One plotted point in an audio graph. `xValue` is the position the audio
    /// graph scrubs along (numeric); `xLabel` is the human-readable category the
    /// view exposes as the data point's label / categorical x-value; `yValue` is
    /// the pitch-mapped magnitude.
    public struct Point: Sendable, Hashable {
        /// Numeric x position (e.g. a day offset or slice index). Monotonic and
        /// unique within a series so the audio graph scrubs left-to-right.
        public let xValue: Double
        /// Human-readable x label, e.g. a date or a category name. Spoken when the
        /// user lands on the point.
        public let xLabel: String
        /// Pitch-mapped magnitude on the y axis.
        public let yValue: Double
        /// Optional spoken label for the whole point (defaults to `xLabel` when nil).
        public let label: String

        public init(xValue: Double, xLabel: String, yValue: Double, label: String? = nil) {
            self.xValue = xValue
            self.xLabel = xLabel
            self.yValue = yValue
            self.label = label ?? xLabel
        }
    }

    /// A numeric axis: title plus the inclusive value range the audio graph maps
    /// to its pitch / scrub span. `lowerBound <= upperBound` always (the builders
    /// pad a degenerate single-value range so the audio graph has a span to map).
    public struct NumericAxis: Sendable, Hashable {
        public let title: String
        public let lowerBound: Double
        public let upperBound: Double

        public init(title: String, lowerBound: Double, upperBound: Double) {
            self.title = title
            // Guarantee a non-empty, non-inverted range even for flat/empty data.
            if lowerBound <= upperBound {
                self.lowerBound = lowerBound
                self.upperBound = upperBound
            } else {
                self.lowerBound = upperBound
                self.upperBound = lowerBound
            }
        }
    }

    /// Everything a chart needs to build an `AXChartDescriptor`: title, summary,
    /// labeled axes, and the ordered series points. Empty `points` means there is
    /// nothing to sonify — callers should not attach a descriptor in that case.
    public struct Descriptor: Sendable, Hashable {
        public let title: String
        public let summary: String
        public let xAxis: NumericAxis
        public let yAxis: NumericAxis
        public let seriesName: String
        /// True when the series is a continuous line (trend); false for discrete
        /// bars/sectors (donut, heatmap) — maps to `AXDataSeriesDescriptor.isContinuous`.
        public let isContinuous: Bool
        /// True when Privacy Mask is on. The descriptor's point labels + summary are
        /// already built masked by the relevant builder; this flag lets the SwiftUI
        /// bridge also redact the y-axis *value descriptions* VoiceOver speaks while
        /// scrubbing the audio graph (see `yAxisValueDescription(_:isMasked:)`), so a
        /// masked chart never announces an exact figure through any channel (AND-569).
        public let isPrivacyMasked: Bool
        public let points: [Point]

        public init(
            title: String,
            summary: String,
            xAxis: NumericAxis,
            yAxis: NumericAxis,
            seriesName: String,
            isContinuous: Bool,
            isPrivacyMasked: Bool = false,
            points: [Point]
        ) {
            self.title = title
            self.summary = summary
            self.xAxis = xAxis
            self.yAxis = yAxis
            self.seriesName = seriesName
            self.isContinuous = isContinuous
            self.isPrivacyMasked = isPrivacyMasked
            self.points = points
        }

        /// No points to sonify.
        public var isEmpty: Bool { points.isEmpty }
    }

    // MARK: - Y-axis value description (privacy-aware)

    /// The spoken description for a y-axis value in the audio graph.
    ///
    /// VoiceOver reads these as it scrubs the audio graph's value axis, so this is
    /// a *third* place an exact amount can leak — alongside the per-point labels and
    /// the summary, both of which the builders already redact under Privacy Mask.
    /// When `isMasked` is true we return the masked placeholder instead of a
    /// formatted currency figure; the audio graph's *pitch* still conveys relative
    /// magnitude (that's not a figure), so the graph stays usable without speaking a
    /// dollar amount (AND-569).
    public static func yAxisValueDescription(
        _ value: Double,
        isMasked: Bool,
        currencyCode: String = "USD"
    ) -> String {
        isMasked
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(value, format: .full, currencyCode: currencyCode)
    }

    // MARK: - Net-worth trend

    /// Audio graph for the net-worth trend line. The x axis is a day index over
    /// the covered span (each point also labeled with its date); the y axis is
    /// the recorded net-worth balance. Continuous, since the chart is a line.
    ///
    /// Returns a descriptor with no points when fewer than two snapshots exist —
    /// the line chart itself isn't drawn below `BalanceTrend.requiredPointCount`,
    /// so there is nothing to sonify.
    public static func trend(_ trend: BalanceTrend, currencyCode: String = "USD") -> Descriptor {
        let points = trend.points.enumerated().map { index, snapshot in
            Point(
                xValue: Double(index),
                xLabel: Formatters.displayDate(snapshot.date),
                yValue: snapshot.balance,
                label: "\(Formatters.displayDate(snapshot.date)), "
                    + Formatters.currency(snapshot.balance, format: .full, currencyCode: currencyCode)
            )
        }

        let balances = trend.points.map(\.balance)
        let yAxis = NumericAxis(
            title: "Net worth",
            lowerBound: balances.min() ?? 0,
            upperBound: balances.max() ?? 0
        )
        let xAxis = NumericAxis(
            title: "Day",
            lowerBound: 0,
            upperBound: Double(max(points.count - 1, 0))
        )

        return Descriptor(
            title: "Net worth trend",
            summary: trend.accessibilitySummary,
            xAxis: xAxis,
            yAxis: yAxis,
            seriesName: "Net worth",
            isContinuous: true,
            points: points
        )
    }

    // MARK: - Spend donut

    /// Audio graph for the spend-by-category donut. Each slice becomes one
    /// discrete point: x is the slice's rank index (spend-heaviest first, labeled
    /// with the group title), y is the slice's spend amount. Discrete series.
    ///
    /// When Privacy Mask is on, amounts are still sonified (the pitch conveys
    /// *relative* magnitude, not an exact figure) but the spoken summary omits the
    /// dollar total — matching how the donut's spoken label hides exact amounts.
    public static func donut(_ model: SpendDonutModel, isPrivacyMasked: Bool = false) -> Descriptor {
        let points = model.slices.enumerated().map { index, slice in
            Point(
                xValue: Double(index),
                xLabel: slice.title,
                yValue: slice.amount,
                label: isPrivacyMasked
                    ? "\(slice.title), \(slice.shareText)"
                    : "\(slice.title), \(slice.amountText), \(slice.shareText)"
            )
        }

        let amounts = model.slices.map(\.amount)
        let yAxis = NumericAxis(
            title: "Spend",
            lowerBound: 0,
            upperBound: amounts.max() ?? 0
        )
        let xAxis = NumericAxis(
            title: "Category rank",
            lowerBound: 0,
            upperBound: Double(max(points.count - 1, 0))
        )

        let summary: String = if isPrivacyMasked {
            "Spending by category across \(model.sliceCount) "
                + "\(model.sliceCount == 1 ? "group" : "groups"). Amounts hidden while Privacy Mask is on."
        } else {
            model.accessibilityLabel
        }

        return Descriptor(
            title: "Spending by category",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            seriesName: "Spend by category",
            isContinuous: false,
            isPrivacyMasked: isPrivacyMasked,
            points: points
        )
    }

    // MARK: - Activity heatmap

    /// Audio graph for the 365-day activity heatmap. Only days with activity are
    /// sonified (silent days carry no information and would flood the graph with
    /// zero-pitch noise). x is a day index across the active days (each labeled
    /// with its date), y is the day's signed value in the active mode. Discrete.
    ///
    /// When Privacy Mask is on, the per-point spoken label drops the exact amount
    /// but keeps the date + transaction count, mirroring the heatmap's masked
    /// header total. Returns no points when there is no activity.
    public static func heatmap(
        _ layout: SpendingHeatmapLayout,
        isPrivacyMasked: Bool = false
    ) -> Descriptor {
        let activeDays = layout.days.filter { $0.transactionCount > 0 }

        let points = activeDays.enumerated().map { index, day -> Point in
            let dateText = Formatters.displayTransactionDate(day.date)
            let amountText = SpendingHeatmap.amountText(for: day, mode: layout.mode)
            let countText = SpendingHeatmap.transactionText(for: day)
            let label = isPrivacyMasked
                ? "\(dateText), \(countText)"
                : "\(dateText), \(amountText), \(countText)"
            return Point(
                xValue: Double(index),
                xLabel: dateText,
                yValue: day.value,
                label: label
            )
        }

        let values = activeDays.map(\.value)
        let yAxis = NumericAxis(
            title: layout.mode == .spending ? "Spend" : "Net cashflow",
            lowerBound: values.min() ?? 0,
            upperBound: values.max() ?? 0
        )
        let xAxis = NumericAxis(
            title: "Active day",
            lowerBound: 0,
            upperBound: Double(max(points.count - 1, 0))
        )

        let summary = "\(layout.mode.summaryTitle) heatmap with \(layout.activeDayCount) active "
            + "\(layout.activeDayCount == 1 ? "day" : "days"). \(layout.mode.semanticDescription)."

        return Descriptor(
            title: layout.mode.summaryTitle,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            seriesName: layout.mode.shortLabel,
            isContinuous: false,
            isPrivacyMasked: isPrivacyMasked,
            points: points
        )
    }
}
