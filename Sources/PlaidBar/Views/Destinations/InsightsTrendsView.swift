import PlaidBarCore
import SwiftUI

/// The **Trends** band of the Insights destination (Epic 7 / AND-585) — the
/// chart canvas. It re-hosts the existing, unchanged chart components and gives
/// each one its audio graph + a `reduceTransparency` text fallback + a non-color
/// alternative (ACCESSIBILITY.md). **Liquid Glass never touches a chart** — the
/// charts render on the standard raised card chrome (a `.clear`-fill surface), and
/// the marks themselves carry no material.
///
/// - **Net worth trend** — ``BalanceTrendChart`` over ``BalanceTrend/evaluate``,
///   self-hides until there is enough recorded history to draw a line.
/// - **Spending by category** — ``SpendDonutChart`` over the override-aware
///   ``SpendDonutModel`` built from ``AppState/categoryDashboardPresentation``.
/// - **Activity heatmap** — a read-only year heatmap built from the existing
///   ``SpendingHeatmapLayout`` Core engine + ``ChartAudioGraph/heatmap`` audio
///   graph (AND-569), with a Reduce Transparency / Privacy Mask text alternative.
struct InsightsTrendsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            netWorthTrendSection
            spendingByCategorySection
            activityHeatmapSection
        }
    }

    // MARK: - Net worth trend

    @ViewBuilder
    private var netWorthTrendSection: some View {
        if let trend = BalanceTrend.evaluate(history: appState.balanceHistory) {
            chartCard(
                title: "Net worth trend",
                systemImage: "chart.xyaxis.line"
            ) {
                if isMasked {
                    maskedChartFallback(
                        message: "Net worth trend hidden while VaultPeek is private.",
                        minHeight: 120
                    )
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // Direction is carried by the signed delta text + the
                        // VoiceOver summary, never by line color alone.
                        Label(trend.deltaText, systemImage: directionGlyph(trend.direction))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(directionTint(trend.direction))
                            .accessibilityHidden(true)

                        BalanceTrendChart(trend: trend)
                            .frame(minHeight: 120)
                    }
                }
            }
            .loadingRedaction(appState.loadState(for: .summaryCards))
        }
    }

    private func directionGlyph(_ direction: BalanceTrend.Direction) -> String {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func directionTint(_ direction: BalanceTrend.Direction) -> Color {
        switch direction {
        case .up: SemanticColors.positive
        case .down: SemanticColors.negative
        case .flat: .secondary
        }
    }

    // MARK: - Spending by category (donut)

    @ViewBuilder
    private var spendingByCategorySection: some View {
        let presentation = appState.categoryDashboardPresentation
        if !presentation.isEmpty {
            chartCard(
                title: "Spending by category",
                systemImage: "chart.pie"
            ) {
                SpendDonutChart(
                    model: SpendDonutModel(presentation: presentation),
                    isPrivacyMasked: isMasked
                )
            }
            .loadingRedaction(appState.loadState(for: .summaryCards))
        }
    }

    // MARK: - Activity heatmap

    @ViewBuilder
    private var activityHeatmapSection: some View {
        let layout = heatmapLayout()
        if layout.activeDayCount > 0 {
            chartCard(
                title: layout.mode.summaryTitle,
                systemImage: "square.grid.3x3.fill"
            ) {
                if isMasked || reduceTransparency {
                    // Reduce Transparency / Privacy Mask text alternative: the
                    // heatmap leans on tinted, translucent cells, so when either
                    // is on we drop to a plain text summary that carries the same
                    // information without relying on color or translucency.
                    heatmapTextAlternative(layout: layout)
                } else {
                    InsightsActivityHeatmapGrid(layout: layout)
                }
            }
            .loadingRedaction(appState.loadState(for: .activityHeatmap))
        }
    }

    private func heatmapLayout() -> SpendingHeatmapLayout {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: appState.transactions,
            startDate: start,
            endDate: end,
            mode: .spending,
            calendar: calendar
        )
    }

    private func heatmapTextAlternative(layout: SpendingHeatmapLayout) -> some View {
        let total = isMasked
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(layout.totalValue, format: .compact)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("\(layout.activeDayCount) active days in the last year", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
            Text(isMasked
                ? "Activity totals are hidden while VaultPeek is private."
                : "\(total) spent across active days. \(layout.mode.semanticDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card chrome

    /// Standard raised card chrome for a chart section. The chart marks never get
    /// a glass treatment; the card surface uses `.glassSurface(.raised)`, whose
    /// `.raised` rank is a `.clear` fill (no material on the chart).
    private func chartCard(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(title, systemImage: systemImage)
                .sectionTitle()
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
    }

    private func maskedChartFallback(message: String, minHeight: CGFloat) -> some View {
        Label(message, systemImage: "eye.slash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .accessibilityLabel(message)
    }
}

/// A read-only year activity heatmap grid built from the existing
/// ``SpendingHeatmapLayout`` Core engine. It carries the ``ChartAudioGraph/heatmap``
/// audio graph (AND-569) and a full text alternative via its VoiceOver label, so
/// meaning never rides on cell color alone. No glass — cells are plain tinted
/// rounded rects. Privacy Mask / Reduce Transparency callers swap this for a text
/// summary upstream; this view is shown only when neither is active.
struct InsightsActivityHeatmapGrid: View {
    let layout: SpendingHeatmapLayout

    private let spacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GeometryReader { proxy in
                let weeks = max(layout.weekColumns.count, 1)
                let cell = max(5, min(9, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks))))
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                cellView(for: day, size: cell)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 7 * 9 + 6 * spacing)

            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription)."
        )
        // VoiceOver audio graph over the active days (AND-569).
        .audioGraph(ChartAudioGraph.heatmap(layout, isPrivacyMasked: false))
    }

    @ViewBuilder
    private func cellView(for day: SpendingHeatmapDay?, size: CGFloat) -> some View {
        if let day {
            let intensity = SpendingHeatmap.cellIntensity(for: day, peakValue: layout.peakValue)
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(Color.primary.opacity(0.12 + 0.6 * intensity))
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(.clear)
                .frame(width: size, height: size)
        }
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text("Less")
                .microText()
                .foregroundStyle(.secondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: Radius.cell)
                    .fill(Color.primary.opacity(0.12 + 0.6 * intensity))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .microText()
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(layout.activeDayCount) active days")
                .microText()
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
