import PlaidBarCore
import SwiftUI

/// Canonical 365-day activity heatmap for the dashboard. Renders a
/// GitHub-style week-column grid of daily spending (neutral intensity ramp)
/// or net cashflow (green/red with an explicit Income/Outflow legend), with
/// a segmented metric picker and an active-day count. Meaning never relies
/// on color alone: every cell carries a help/accessibility label with date,
/// amount, and transaction count.
struct BalanceActivityHeatmap: View {
    let transactions: [TransactionDTO]
    var loadState: DashboardLoadState?

    @AppStorage("dashboard.heatmapMode") private var modeRawValue = SpendingHeatmapMode.spending.rawValue

    private let calendar = Calendar.current
    private let spacing: CGFloat = 2
    private let monthLabelHeight: CGFloat = 10
    private let monthLabelWidth: CGFloat = 22

    private var mode: SpendingHeatmapMode {
        SpendingHeatmapMode(rawValue: modeRawValue) ?? .spending
    }

    private func currentLayout() -> SpendingHeatmapLayout {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: mode,
            calendar: calendar
        )
    }

    var body: some View {
        // Derive the layout once per render. The previous computed-property form
        // re-aggregated every transaction on each property access (~8x per body).
        let layout = currentLayout()

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(layout.mode.summaryTitle)
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Heatmap metric", selection: modeBinding) {
                    Text(SpendingHeatmapMode.spending.shortLabel).tag(SpendingHeatmapMode.spending)
                    Text(SpendingHeatmapMode.netCashflow.shortLabel).tag(SpendingHeatmapMode.netCashflow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 116)

                Text(isInitialLoad ? "—" : totalLabel(for: layout))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isInitialLoad ? .secondary : totalTint(for: layout))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                let weeks = max(layout.weekColumns.count, 1)
                let cell = max(5, min(8, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks))))

                ZStack(alignment: .topLeading) {
                    ForEach(layout.monthMarkers) { marker in
                        Text(marker.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: monthLabelWidth, height: monthLabelHeight, alignment: .leading)
                            .offset(x: CGFloat(marker.weekIndex) * (cell + spacing), y: 0)
                    }

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: spacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        BalanceHeatmapCell(
                                            day: day,
                                            peakValue: layout.peakValue,
                                            mode: layout.mode,
                                            size: cell
                                        )
                                    } else {
                                        RoundedRectangle(cornerRadius: Radius.cell)
                                            .fill(.clear)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                    .offset(y: monthLabelHeight + 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: monthLabelHeight + 3 + 7 * 8 + 6 * spacing)
            // First sync in flight: the empty grid dims so it reads as a
            // placeholder, not as a year of zero activity.
            .opacity(isInitialLoad ? 0.45 : 1)

            HStack(spacing: 5) {
                if layout.mode == .spending {
                    Text("Less")
                        .microText()
                        .foregroundStyle(.secondary)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: Radius.cell)
                            .fill(BalanceHeatmapCell.fillColor(
                                intensity: intensity,
                                value: intensity,
                                mode: layout.mode
                            ))
                            .frame(width: 8, height: 8)
                    }

                    Text("More")
                        .microText()
                        .foregroundStyle(.secondary)
                } else {
                    NetLegendKey(label: "Income", tint: SemanticColors.positive)
                    NetLegendKey(label: "Outflow", tint: SemanticColors.negative)
                }

                Spacer()

                Text(isInitialLoad ? "Loading activity" : "\(layout.activeDayCount) active days")
                    .microText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isInitialLoad
                ? (loadState?.loadingAccessibilityLabel ?? "Loading activity heatmap.")
                : "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription)."
        )
    }

    private var isInitialLoad: Bool {
        loadState?.isInitialLoad ?? false
    }

    private var modeBinding: Binding<SpendingHeatmapMode> {
        Binding(
            get: { mode },
            set: { modeRawValue = $0.rawValue }
        )
    }

    private func totalLabel(for layout: SpendingHeatmapLayout) -> String {
        guard layout.mode == .netCashflow else {
            return Formatters.currency(layout.totalValue, format: .compact)
        }
        return cashflowText(for: layout.totalValue)
    }

    private func totalTint(for layout: SpendingHeatmapLayout) -> Color {
        guard layout.mode == .netCashflow else { return .secondary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(layout.totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return .secondary
    }

    private func cashflowText(for value: Double) -> String {
        let displayAmount = SpendingHeatmap.displayCashflowAmount(value)
        let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(displayAmount), format: .compact))"
    }
}

private struct NetLegendKey: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(tint.opacity(0.72))
                .frame(width: 8, height: 8)
            Text(label)
                .microText()
                .foregroundStyle(.secondary)
        }
    }
}

private struct BalanceHeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let mode: SpendingHeatmapMode
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.cell)
            .fill(Self.fillColor(intensity: intensity, value: day.value, mode: mode))
            .frame(width: size, height: size)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var intensity: Double {
        SpendingHeatmap.cellIntensity(for: day, peakValue: peakValue)
    }

    private var helpText: String {
        let amount: String
        if mode == .netCashflow {
            let displayAmount = SpendingHeatmap.displayCashflowAmount(day.value)
            let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
            amount = "\(prefix)\(Formatters.currency(abs(displayAmount), format: .full))"
        } else {
            amount = Formatters.currency(day.value, format: .full)
        }
        return "\(Formatters.displayTransactionDate(day.date)): \(amount) across \(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    static func fillColor(intensity: Double, value: Double, mode: SpendingHeatmapMode) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.06) }

        // Spend mode uses a neutral intensity ramp: green means money-in
        // everywhere else in the app, so green-for-heavy-spending would
        // invert the token semantics. Net mode keeps the green/red pairing
        // with its explicit Income/Outflow legend.
        guard mode == .netCashflow else {
            return Color.primary.opacity(0.14 + (0.6 * intensity))
        }

        let base: Color = value < 0 ? SemanticColors.positive : SemanticColors.negative
        return base.opacity(0.18 + (0.72 * intensity))
    }
}
