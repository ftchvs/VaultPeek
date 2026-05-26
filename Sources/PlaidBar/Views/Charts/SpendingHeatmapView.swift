import SwiftUI
import PlaidBarCore

struct SpendingHeatmapView: View {
    let transactions: [TransactionDTO]
    let startDate: Date
    let endDate: Date

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

    private var totalLabel: String {
        guard mode == .netCashflow else {
            return Formatters.currency(totalValue, format: .compact)
        }
        let prefix = totalValue > 0 ? "+" : totalValue < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(totalValue), format: .compact))"
    }

    private var selectedDay: SpendingHeatmapDay? {
        guard let selectedDate else { return nil }
        return days.first { $0.date == selectedDate }
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

            Picker("Heatmap metric", selection: $mode) {
                Text("Spend").tag(SpendingHeatmapMode.spending)
                Text("Net").tag(SpendingHeatmapMode.netCashflow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, _ in
                selectedDate = nil
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
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Spending heatmap")
                    .sectionTitle()
                Text(mode == .spending ? "Daily outflow intensity" : "Money out minus money in")
                    .detailText()
            }

            Spacer()

            Text(totalLabel)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(mode == .netCashflow && totalValue < 0 ? SemanticColors.positive : .primary)
        }
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            ForEach(Array(weekColumns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            HeatmapCell(
                                day: day,
                                peakValue: peakValue,
                                mode: mode,
                                isSelected: selectedDate == day.date
                            )
                            .onTapGesture {
                                selectedDate = selectedDate == day.date ? nil : day.date
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.clear)
                                .frame(width: 13, height: 13)
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

            Spacer()
        }
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
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Heatmap Data", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Daily spending intensity will appear after syncing transactions.")
        }
        .frame(height: 150)
    }

    private var accessibilitySummary: String {
        let activeDays = days.filter { $0.transactionCount > 0 }.count
        return "Spending heatmap with \(activeDays) active days. Peak day \(Formatters.currency(peakValue, format: .full))."
    }

    private func dayValueText(_ day: SpendingHeatmapDay) -> String {
        guard mode == .netCashflow else {
            return Formatters.currency(day.value, format: .full)
        }
        let prefix = day.value > 0 ? "+" : day.value < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(day.value), format: .full))"
    }
}

private struct HeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let mode: SpendingHeatmapMode
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Self.fillColor(intensity: intensity, value: day.value, mode: mode))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.primary, lineWidth: 1.5)
                }
            }
            .frame(width: 13, height: 13)
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
            let prefix = day.value > 0 ? "+" : day.value < 0 ? "-" : ""
            amount = "\(prefix)\(Formatters.currency(abs(day.value), format: .full))"
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
            base = SemanticColors.brand
        }

        return base.opacity(0.18 + (0.72 * intensity))
    }
}
