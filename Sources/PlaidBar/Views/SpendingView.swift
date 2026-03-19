import SwiftUI
import Charts
import PlaidBarCore

struct SpendingView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPeriod: SpendingPeriod = .thisMonth
    @State private var chartType: ChartType = .donut

    enum SpendingPeriod: String, CaseIterable, Sendable {
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30Days = "Last 30 Days"
    }

    enum ChartType: String, CaseIterable, Sendable {
        case donut = "Categories"
        case trend = "Trend"
        case incomeExpense = "In vs Out"
    }

    /// Returns (currentPeriodStart, previousPeriodStart) as formatted date strings.
    /// Computed once per render — both `filteredTransactions` and `previousPeriodSpending` use this.
    private var periodInterval: (current: String, previous: String) {
        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        let previousStart: Date
        switch selectedPeriod {
        case .thisWeek:
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startDate) ?? now
        case .thisMonth:
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
            previousStart = calendar.date(byAdding: .month, value: -1, to: startDate) ?? now
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            previousStart = calendar.date(byAdding: .day, value: -30, to: startDate) ?? now
        }
        return (Self.formatDate(startDate), Self.formatDate(previousStart))
    }

    private var filteredTransactions: [TransactionDTO] {
        let startString = periodInterval.current
        return appState.transactions.filter { $0.date >= startString }
    }

    private var filteredSpending: [(SpendingCategory, Double)] {
        let filtered = filteredTransactions.filter {
            !$0.isIncome && $0.category != .transfer && $0.category != .transferOut
        }

        let grouped = Dictionary(grouping: filtered) { $0.category ?? .other }
        return grouped.map { (category, txns) in
            (category, txns.reduce(0) { $0 + $1.displayAmount })
        }.sorted { $0.1 > $1.1 }
    }

    /// Top 5 categories + "Other" rollup to prevent tiny chart slivers
    private var chartCategories: [(SpendingCategory, Double)] {
        guard filteredSpending.count > 5 else { return filteredSpending }
        let top5 = Array(filteredSpending.prefix(5))
        let otherTotal = filteredSpending.dropFirst(5).reduce(0) { $0 + $1.1 }
        return top5 + [(.other, otherTotal)]
    }

    private var totalFiltered: Double {
        filteredSpending.reduce(0) { $0 + $1.1 }
    }

    // MARK: - Month-over-Month Comparison

    private var previousPeriodSpending: Double {
        let interval = periodInterval
        let filtered = appState.transactions.filter {
            $0.date >= interval.previous && $0.date < interval.current &&
            !$0.isIncome && $0.category != .transfer && $0.category != .transferOut
        }
        return filtered.reduce(0) { $0 + $1.displayAmount }
    }

    private var spendingDelta: Double {
        totalFiltered - previousPeriodSpending
    }

    private var spendingDeltaPercent: Double {
        guard previousPeriodSpending > 0 else { return 0 }
        return (spendingDelta / previousPeriodSpending) * 100
    }

    var body: some View {
        let categories = chartCategories
        let total = totalFiltered
        let prevSpending = previousPeriodSpending
        let delta = spendingDelta
        let deltaPercent = spendingDeltaPercent

        VStack(spacing: Spacing.md) {
            // Period picker
            Picker("Period", selection: $selectedPeriod) {
                ForEach(SpendingPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            // Total — hero amount
            Text(Formatters.currency(total, format: .full))
                .heroBalance()
                .contentTransition(.numericText())
                .animation(.default, value: total)

            // Month-over-month comparison
            if prevSpending > 0 {
                VStack(spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text("\(delta >= 0 ? "+" : "")\(Formatters.currency(abs(delta), format: .full)) (\(Formatters.percent(abs(deltaPercent), decimals: 1)))")
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(delta >= 0 ? SemanticColors.negative : SemanticColors.positive)
                    .contentTransition(.numericText())
                    .animation(.default, value: delta)

                    Text("vs. last period")
                        .microText()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Spending \(delta >= 0 ? "increased" : "decreased") by \(Formatters.currency(abs(delta), format: .full)), \(Formatters.percent(abs(deltaPercent), decimals: 1)) \(delta >= 0 ? "more" : "less") than last period")
            }

            // Chart type picker
            Picker("Chart", selection: $chartType) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)

            // Chart content
            switch chartType {
            case .donut:
                donutChart(categories: categories, total: total)
            case .trend:
                SpendingTrendChart(transactions: filteredTransactions)
            case .incomeExpense:
                IncomeExpenseChart(transactions: filteredTransactions)
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private func donutChart(categories: [(SpendingCategory, Double)], total: Double) -> some View {
        // Category breakdown legend
        VStack(spacing: Spacing.xs) {
            ForEach(categories, id: \.0) { category, amount in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color(hex: category.colorHex) ?? .gray)
                        .frame(width: 10, height: 10)

                    Text(category.displayName)
                        .font(.body)

                    Spacer()

                    Text(Formatters.currency(amount, format: .full))
                        .monospacedDigit()

                    Text(total > 0 ? Formatters.percent(amount / total * 100, decimals: 0) : "\u{2014}")
                        .microText()
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xxs)
            }
        }

        // Donut chart
        if !categories.isEmpty && total > 0 {
            Chart(categories, id: \.0) { category, amount in
                SectorMark(
                    angle: .value("Amount", amount),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                .annotation(position: .overlay) {
                    if amount / total > 0.1 {
                        Text(Formatters.percent(amount / total * 100, decimals: 0))
                            .microText()
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 170)
            .padding(.horizontal, Spacing.lg)
        }
    }

    private static func formatDate(_ date: Date) -> String {
        Formatters.transactionDateString(date)
    }
}

// MARK: - Color from Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
