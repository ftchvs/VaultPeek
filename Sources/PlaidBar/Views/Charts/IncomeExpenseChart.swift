import SwiftUI
import Charts
import PlaidBarCore

struct IncomeExpenseChart: View {
    let transactions: [TransactionDTO]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private struct MonthlyData: Identifiable {
        var id: Date { month }
        let month: Date
        let label: String
        let income: Double
        let expenses: Double
    }

    private var monthlyData: [MonthlyData] {
        let calendar = Calendar.current

        // Group transactions by month
        let grouped = Dictionary(grouping: transactions) { tx -> Date in
            guard let date = Formatters.parseTransactionDate(tx.date) else {
                return Date()
            }
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }

        return grouped.map { monthStart, txns in
            let income = txns.filter(\.isIncome).reduce(0.0) { $0 + $1.displayAmount }
            let expenses = txns.filter { !$0.isIncome && $0.category != .transfer && $0.category != .transferOut }
                .reduce(0.0) { $0 + $1.displayAmount }
            return MonthlyData(
                month: monthStart,
                label: Self.monthFormatter.string(from: monthStart),
                income: income,
                expenses: expenses
            )
        }.sorted { $0.month < $1.month }
    }

    var body: some View {
        let data = monthlyData
        if data.isEmpty {
            ContentUnavailableView {
                Label("No Data", systemImage: "chart.bar")
            } description: {
                Text("Income and expense data will appear after syncing.")
            }
            .padding()
        } else {
            Chart(data) { data in
                BarMark(
                    x: .value("Month", data.label),
                    y: .value("Amount", data.income)
                )
                .foregroundStyle(SemanticColors.income)
                .position(by: .value("Type", "Income"))

                BarMark(
                    x: .value("Month", data.label),
                    y: .value("Amount", data.expenses)
                )
                .foregroundStyle(SemanticColors.negative.opacity(0.7))
                .position(by: .value("Type", "Expenses"))
            }
            .chartForegroundStyleScale([
                "Income": SemanticColors.income,
                "Expenses": SemanticColors.negative.opacity(0.7),
            ])
            .chartLegend(position: .bottom, spacing: Spacing.sm)
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
