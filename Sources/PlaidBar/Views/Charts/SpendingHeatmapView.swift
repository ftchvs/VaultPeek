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

    private var days: [SpendingHeatmapDay] {
        SpendingHeatmap.days(
            from: transactions,
            startDate: startDate,
            endDate: endDate,
            mode: mode,
            calendar: calendar
        )
    }

    private var peakValue: Double {
        max(days.map { abs($0.value) }.max() ?? 0, 1)
    }

    private var totalValue: Double {
        days.reduce(0) { $0 + $1.value }
    }

    private var activeDayCount: Int {
        days.filter { $0.transactionCount > 0 }.count
    }

    private var totalLabel: String {
        guard mode == .netCashflow else {
            return Formatters.currency(totalValue, format: .compact)
        }
        return cashflowText(for: totalValue, format: .compact)
    }

    private var totalTint: Color {
        guard mode == .netCashflow else { return .primary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return .primary
    }

    private var selectedDay: SpendingHeatmapDay? {
        guard let selectedDate else { return nil }
        return days.first { $0.date == selectedDate }
    }

    private var strongestSignals: [SpendingHeatmapSignal] {
        SpendingHeatmap.strongestSignals(from: days, mode: mode)
    }

    private var emptyPresentation: SpendingHeatmapEmptyPresentation {
        SpendingHeatmap.emptyPresentation(transactionCount: transactions.count, mode: mode)
    }

    private var weekColumns: [[SpendingHeatmapDay?]] {
        guard let firstDay = days.first,
              let firstDate = Formatters.parseTransactionDate(firstDay.date) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let padded: [SpendingHeatmapDay?] = Array(repeating: nil, count: leadingEmptyDays) + days.map(Optional.some)
        return stride(from: 0, to: padded.count, by: 7).map { start in
            let week = Array(padded[start..<min(start + 7, padded.count)])
            return week + Array(repeating: nil, count: max(0, 7 - week.count))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

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

            if days.allSatisfy({ $0.transactionCount == 0 }) {
                emptyState
            } else {
                heatmapGrid
                legend
                selectedDaySummary
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Spending heatmap")
                    .sectionTitle()
                Text(mode.semanticDescription)
                    .detailText()
            }

            Spacer()

            Text(totalLabel)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(totalTint)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(Array(weekColumns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: cellSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            HeatmapCell(
                                day: day,
                                peakValue: peakValue,
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
        .accessibilityLabel(accessibilitySummary)
    }

    private var legend: some View {
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

            Text("\(activeDayCount) active days")
                .microText()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legendAccessibilityLabel)
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let selectedDay {
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

    private var accessibilitySummary: String {
        let activeDays = days.filter { $0.transactionCount > 0 }.count
        let signalText = strongestSignals.map(\.accessibilitySummary).joined(separator: " ")
        let signalSuffix = signalText.isEmpty ? "" : " \(signalText)"
        return "\(mode == .spending ? "Spending" : "Net cashflow") heatmap with \(activeDays) active days. Peak day \(Formatters.currency(peakValue, format: .full)). Total \(totalLabel).\(signalSuffix)"
    }

    private var legendAccessibilityLabel: String {
        if mode == .spending {
            return "Spending heatmap legend, lighter cells mean less spending and darker cells mean more spending. \(activeDayCount) active days."
        }
        return "Net cashflow heatmap legend, green cells mean income and red cells mean outflow. \(activeDayCount) active days."
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
        guard day.transactionCount > 0 else { return 0 }
        return min(max(abs(day.value) / peakValue, 0), 1)
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
