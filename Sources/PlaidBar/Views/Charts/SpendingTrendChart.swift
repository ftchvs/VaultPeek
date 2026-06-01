import SwiftUI
import Charts
import PlaidBarCore

struct SpendingTrendChart: View {
    let transactions: [TransactionDTO]

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var dailySpending: [(Date, Double)] {
        let expenses = SpendingSummary.expenseTransactions(from: transactions)

        let grouped = Dictionary(grouping: expenses) { $0.date }
        let results: [(Date, Double)] = grouped.compactMap { dateString, txns in
            guard let date = Formatters.parseTransactionDate(dateString) else { return nil }
            let total = txns.reduce(0.0) { $0 + $1.displayAmount }
            return (date, total)
        }
        return results.sorted { $0.0 < $1.0 }
    }

    private var chartAccessibilityLabel: String {
        let data = dailySpending
        guard let first = data.first, let last = data.last else {
            return "Spending trend chart with no spending data."
        }

        let total = data.reduce(0.0) { $0 + $1.1 }
        let peak = data.max { $0.1 < $1.1 } ?? last
        return "Spending trend chart from \(Self.accessibilityDateFormatter.string(from: first.0)) to \(Self.accessibilityDateFormatter.string(from: last.0)), total \(Formatters.currency(total, format: .full)), peak day \(Self.accessibilityDateFormatter.string(from: peak.0)) at \(Formatters.currency(peak.1, format: .full))."
    }

    var body: some View {
        let data = dailySpending
        if data.isEmpty {
            ContentUnavailableView {
                Label("No Spending Data", systemImage: "chart.line.downtrend.xyaxis")
            } description: {
                Text("Spending trends will appear after syncing transactions.")
            }
            .padding()
        } else {
            Chart(data, id: \.0) { date, amount in
                LineMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Amount", amount)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(SemanticColors.sparkline.gradient)

                AreaMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Amount", amount)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(SemanticColors.sparkline.opacity(0.1).gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Formatters.currency(amount, format: .compact))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 170)
            .padding(.horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartAccessibilityLabel)
        }
    }
}
