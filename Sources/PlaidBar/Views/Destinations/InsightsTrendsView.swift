import PlaidBarCore
import SwiftUI

/// The **Trends** column of the Insights window canvas (Epic 7 / AND-585; AND-624) —
/// the chart cards. It re-hosts the existing, unchanged chart components at the
/// window (desk-distance) scale and gives each one its audio graph + a
/// `reduceTransparency` text fallback + a non-color alternative (ACCESSIBILITY.md).
/// **Liquid Glass never touches a chart** — each chart sits on a quiet, *solid*
/// ``WindowSection`` card (data stays solid), and the marks carry no
/// material.
///
/// - **Net worth trend** — ``BalanceTrendChart`` over ``BalanceTrend/evaluate``,
///   self-hides until there is enough recorded history to draw a line.
/// - **Spending by category** — ``SpendDonutChart`` over the override-aware
///   ``SpendDonutModel`` built from ``AppState/categoryDashboardPresentation``.
/// - **Activity heatmap** — a read-only year heatmap built from the existing
///   ``SpendingHeatmapLayout`` Core engine + ``ChartAudioGraph/heatmap`` audio
///   graph (AND-569), with a Reduce Transparency / Privacy Mask text alternative.
///
/// At most three cards, so the column reads as calm comfortable density rather than
/// a tight stack (AND-624).
struct InsightsTrendsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            netWorthTrendSection
            spendingByCategorySection
            activityHeatmapSection
        }
    }

    // MARK: - Net worth trend

    @ViewBuilder
    private var netWorthTrendSection: some View {
        if let trend = BalanceTrend.evaluate(history: appState.balanceHistory) {
            WindowSection("Net worth trend", systemImage: "chart.xyaxis.line") {
                // Direction is carried by the signed delta text + the VoiceOver
                // summary, never by line color alone (ACCESSIBILITY.md).
                Label(trend.deltaText, systemImage: directionGlyph(trend.direction))
                    .windowDataText()
                    .foregroundStyle(directionTint(trend.direction))
                    .accessibilityHidden(true)
            } content: {
                if isMasked {
                    maskedChartFallback(
                        message: "Net worth trend hidden while VaultPeek is private.",
                        minHeight: 160
                    )
                } else {
                    BalanceTrendChart(trend: trend)
                        .frame(minHeight: 160)
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
            WindowSection("Spending by category", systemImage: "chart.pie") {
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
            WindowSection(layout.mode.summaryTitle, systemImage: "square.grid.3x3.fill") {
                Text("Last 365 days")
                    .windowSupportingText()
            } content: {
                if isMasked || reduceTransparency {
                    // Reduce Transparency / Privacy Mask text alternative: the
                    // heatmap leans on tinted, translucent cells, so when either
                    // is on we drop to a plain text summary that carries the same
                    // information without relying on color or translucency.
                    heatmapTextAlternative(layout: layout)
                } else {
                    InsightsActivityHeatmapGrid(layout: layout, isPrivacyMasked: isMasked)
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
        return VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            Label(isMasked ? "Activity summary hidden" : "\(layout.activeDayCount) active days in the last year", systemImage: "calendar")
                .windowBodyText()
            Text(isMasked
                ? "Activity totals are hidden while VaultPeek is private."
                : "\(total) spent across active days. \(layout.mode.semanticDescription)")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: WindowMetrics.heatmapHeroMinHeight, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func maskedChartFallback(message: String, minHeight: CGFloat) -> some View {
        Label(message, systemImage: "eye.slash")
            .windowBodyText()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .accessibilityLabel(message)
    }
}

/// A read-only year activity heatmap grid built from the existing
/// ``SpendingHeatmapLayout`` Core engine, rendered at **desk-distance scale**
/// (larger cells than the popover's glance-scale grid) so it reads as a comfortable
/// window instrument. It carries the ``ChartAudioGraph/heatmap`` audio graph
/// (AND-569) and a full text alternative via its VoiceOver label, so meaning never
/// rides on cell color alone. No glass — cells are plain tinted rounded rects.
/// Privacy Mask / Reduce Transparency callers swap this for a text summary upstream;
/// this view is shown only when neither is active.
struct InsightsActivityHeatmapGrid: View {
    let layout: SpendingHeatmapLayout
    /// Whether Privacy Mask is active. The parent only renders this grid when
    /// masking is OFF (the masked branch shows a text alternative), so this is
    /// `false` in practice — but it is threaded honestly into the per-cell label
    /// source so the affordance never leaks a value if the grid is ever shown
    /// while masked (defense in depth; single Core label source).
    var isPrivacyMasked: Bool = false

    private let spacing: CGFloat = 3
    /// Desk-distance cell bounds. `preferredMinCell` is the comfortable
    /// window-instrument size; when the Trends column is narrower than 53 weeks
    /// at that size, cells shrink toward `hardMinCell` (the popover's glance
    /// floor) so the grid *fits its column* instead of overflowing under the
    /// neighboring Planning & Review column. `.clipped()` backstops the
    /// impossible remainder.
    private let hardMinCell: CGFloat = 4
    private let maxCell: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            GeometryReader { proxy in
                let weeks = max(layout.weekColumns.count, 1)
                let cell = max(
                    hardMinCell,
                    min(maxCell, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks)))
                )
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
                .clipped()
            }
            .frame(height: 7 * maxCell + 6 * spacing)

            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription)."
        )
        // VoiceOver audio graph over the active days (AND-569).
        .audioGraph(ChartAudioGraph.heatmap(layout, isPrivacyMasked: isPrivacyMasked))
    }

    @ViewBuilder
    private func cellView(for day: SpendingHeatmapDay?, size: CGFloat) -> some View {
        if let day {
            let intensity = SpendingHeatmap.cellIntensity(for: day, peakValue: layout.peakValue)
            // Per-cell textual affordance: the cell's meaning otherwise rides on
            // tint/opacity alone (ACCESSIBILITY.md). The label is the single Core
            // source (date + masked value + count), so pointer-hover and VoiceOver
            // get the same sentence and Privacy Mask is honored (AND-671).
            let label = SpendingHeatmap.cellLabel(for: day, mode: layout.mode, isPrivacyMasked: isPrivacyMasked)
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(Color.primary.opacity(0.12 + 0.6 * intensity))
                .frame(width: size, height: size)
                .help(label)
                .accessibilityLabel(label)
        } else {
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(.clear)
                .frame(width: size, height: size)
        }
    }

    private var legend: some View {
        HStack(spacing: WindowMetrics.xs) {
            Text("Less")
                .windowSupportingText()
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: Radius.cell)
                    .fill(Color.primary.opacity(0.12 + 0.6 * intensity))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .windowSupportingText()

            Spacer()

            Text("\(layout.activeDayCount) active days")
                .windowSupportingText()
        }
        .accessibilityHidden(true)
    }
}
