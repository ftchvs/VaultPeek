import SwiftUI
import PlaidBarCore

struct SpendingHeatmapView: View {
    let transactions: [TransactionDTO]
    let startDate: Date
    let endDate: Date
    let cellSize: CGFloat
    let showModePicker: Bool

    @State private var mode: SpendingHeatmapMode = .spending
    @State private var selectedDate: String?

    private let calendar = Calendar.current

    private func currentLayout() -> SpendingHeatmapLayout {
        SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: startDate,
            endDate: endDate,
            mode: mode,
            calendar: calendar
        )
    }

    private var emptyPresentation: SpendingHeatmapEmptyPresentation {
        SpendingHeatmap.emptyPresentation(transactionCount: transactions.count, mode: mode)
    }

    var body: some View {
        // Derive the layout once per render. The previous computed-property form
        // re-aggregated every transaction on each property access.
        let layout = currentLayout()

        VStack(alignment: .leading, spacing: Spacing.md) {
            header(for: layout)

            if showModePicker {
                Picker("Heatmap metric", selection: $mode) {
                    Text(SpendingHeatmapMode.spending.shortLabel).tag(SpendingHeatmapMode.spending)
                    Text(SpendingHeatmapMode.netCashflow.shortLabel).tag(SpendingHeatmapMode.netCashflow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 236)
                .onChange(of: mode) { _, _ in
                    selectedDate = nil
                }
                .accessibilityLabel("Heatmap metric")
                .accessibilityValue(mode == .spending ? "Spend" : "Net cashflow")
            }

            if layout.activeDayCount == 0 {
                emptyState
            } else {
                heatmapGrid(for: layout)
                legend(for: layout)
                selectedDaySummary(for: layout)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func totalLabel(for layout: SpendingHeatmapLayout) -> String {
        guard mode == .netCashflow else {
            return Formatters.currency(layout.totalValue, format: .compact)
        }
        return cashflowText(for: layout.totalValue, format: .compact)
    }

    private func totalTint(for layout: SpendingHeatmapLayout) -> Color {
        guard mode == .netCashflow else { return .primary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(layout.totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return .primary
    }

    private func selectedDay(in layout: SpendingHeatmapLayout) -> SpendingHeatmapDay? {
        guard let selectedDate else { return nil }
        return layout.days.first { $0.date == selectedDate }
    }

    private func header(for layout: SpendingHeatmapLayout) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Spending heatmap")
                    .sectionTitle()
                Text(mode.semanticDescription)
                    .detailText()
            }

            Spacer()

            Text(totalLabel(for: layout))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(totalTint(for: layout))
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    private func heatmapGrid(for layout: SpendingHeatmapLayout) -> some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: cellSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            HeatmapCell(
                                day: day,
                                peakValue: layout.peakValue,
                                mode: mode,
                                isSelected: selectedDate == day.date,
                                size: cellSize
                            )
                            .onTapGesture {
                                selectedDate = selectedDate == day.date ? nil : day.date
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.clear)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilitySummary(for: layout))
    }

    private func legend(for layout: SpendingHeatmapLayout) -> some View {
        HStack(spacing: Spacing.xs) {
            if mode == .spending {
                Text("Less")
                    .microText()
                    .foregroundStyle(.secondary)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(HeatmapCell.fillColor(intensity: intensity, value: intensity, mode: mode))
                        .frame(width: 13, height: 13)
                }

                Text("More")
                    .microText()
                    .foregroundStyle(.secondary)
            } else {
                HeatmapLegendKey(label: "Income", tint: SemanticColors.positive, size: 13)
                HeatmapLegendKey(label: "Outflow", tint: SemanticColors.negative, size: 13)
            }

            Spacer()

            Text("\(layout.activeDayCount) active days")
                .microText()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legendAccessibilityLabel(for: layout))
    }

    @ViewBuilder
    private func selectedDaySummary(for layout: SpendingHeatmapLayout) -> some View {
        if let selectedDay = selectedDay(in: layout) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: mode == .spending ? "calendar" : "arrow.left.arrow.right")
                    .foregroundStyle(SemanticColors.brand)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(Formatters.displayTransactionDate(selectedDay.date))
                        .font(.caption.weight(.semibold))
                    Text("\(dayValueText(selectedDay)) across \(selectedDay.transactionCount) transaction\(selectedDay.transactionCount == 1 ? "" : "s")")
                        .detailText()
                }

                Spacer()
            }
            .padding(Spacing.sm)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(selectedDayAccessibilityLabel(selectedDay))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyPresentation.title, systemImage: emptyPresentation.systemImage)
        } description: {
            Text(emptyPresentation.description)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(emptyPresentation.title). \(emptyPresentation.description)")
    }

    private func accessibilitySummary(for layout: SpendingHeatmapLayout) -> String {
        let signalText = SpendingHeatmap.strongestSignals(from: layout.days, mode: mode)
            .map(\.accessibilitySummary)
            .joined(separator: " ")
        let signalSuffix = signalText.isEmpty ? "" : " \(signalText)"
        return "\(mode == .spending ? "Spending" : "Net cashflow") heatmap with \(layout.activeDayCount) active days. Peak day \(Formatters.currency(layout.peakValue, format: .full)). Total \(totalLabel(for: layout)).\(signalSuffix)"
    }

    private func legendAccessibilityLabel(for layout: SpendingHeatmapLayout) -> String {
        if mode == .spending {
            return "Spending heatmap legend, lighter cells mean less spending and darker cells mean more spending. \(layout.activeDayCount) active days."
        }
        return "Net cashflow heatmap legend, green cells mean income and red cells mean outflow. \(layout.activeDayCount) active days."
    }

    private func selectedDayAccessibilityLabel(_ day: SpendingHeatmapDay) -> String {
        "\(Formatters.displayTransactionDate(day.date)), \(dayValueText(day)) across \(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    private func dayValueText(_ day: SpendingHeatmapDay) -> String {
        guard mode == .netCashflow else {
            return Formatters.currency(day.value, format: .full)
        }
        return cashflowText(for: day.value, format: .full)
    }

    private func cashflowText(for value: Double, format: CurrencyFormat) -> String {
        let displayAmount = SpendingHeatmap.displayCashflowAmount(value)
        let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(displayAmount), format: format))"
    }

    private var cellSpacing: CGFloat {
        cellSize >= 16 ? 5 : Spacing.xs
    }
}

private struct HeatmapLegendKey: View {
    let label: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint.opacity(0.72))
                .frame(width: size, height: size)
            Text(label)
                .microText()
                .foregroundStyle(.secondary)
        }
    }
}

private struct HeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let mode: SpendingHeatmapMode
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Self.fillColor(intensity: intensity, value: day.value, mode: mode))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.primary, lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
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
        return "\(Formatters.displayTransactionDate(day.date)): \(amount), \(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    static func fillColor(intensity: Double, value: Double, mode: SpendingHeatmapMode) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.08) }

        let base: Color
        if mode == .netCashflow && value < 0 {
            base = SemanticColors.positive
        } else {
            base = mode == .netCashflow ? SemanticColors.negative : SemanticColors.positive
        }

        return base.opacity(0.18 + (0.72 * intensity))
    }
}
