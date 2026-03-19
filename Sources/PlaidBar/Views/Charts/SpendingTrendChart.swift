import SwiftUI
import Charts
import PlaidBarCore

struct SpendingTrendChart: View {
    let transactions: [TransactionDTO]

    private var dailySpending: [(Date, Double)] {
        let expenses = transactions.filter {
            !$0.isIncome && $0.category != .transfer && $0.category != .transferOut
        }

        let grouped = Dictionary(grouping: expenses) { $0.date }
        let results: [(Date, Double)] = grouped.compactMap { dateString, txns in
            guard let date = Formatters.parseTransactionDate(dateString) else { return nil }
            let total = txns.reduce(0.0) { $0 + $1.displayAmount }
            return (date, total)
        }
        return results.sorted { $0.0 < $1.0 }
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
        }
    }
}
