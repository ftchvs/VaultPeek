import SwiftUI
import Charts
import PlaidBarCore

struct SpendingView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPeriod: SpendingPeriod = .last90Days
    @State private var breakdownType: BreakdownType = .categories

    enum SpendingPeriod: String, CaseIterable, Sendable {
        case thisWeek = "Week"
        case thisMonth = "Month"
        case last30Days = "30D"
        case last90Days = "90D"
    }

    enum BreakdownType: String, CaseIterable, Sendable {
        case categories = "Categories"
        case trend = "Trend"
        case incomeExpense = "Flow"
    }

    /// Returns current/previous period starts for filtering and comparisons.
    /// Computed once per render — both `filteredTransactions` and `previousPeriodSpending` use this.
    private var periodInterval: (currentDate: Date, previousDate: Date, current: String, previous: String) {
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
        case .last90Days:
            startDate = calendar.date(byAdding: .day, value: -90, to: now) ?? now
            previousStart = calendar.date(byAdding: .day, value: -90, to: startDate) ?? now
        }
        return (startDate, previousStart, Self.formatDate(startDate), Self.formatDate(previousStart))
    }

    private var filteredTransactions: [TransactionDTO] {
        let startString = periodInterval.current
        return appState.transactions.filter { $0.date >= startString }
    }

    private var filteredSpending: [(SpendingCategory, Double)] {
        spendingSummary.categories
    }

    /// Top 5 categories + "Other" rollup to prevent tiny chart slivers
    private var chartCategories: [(SpendingCategory, Double)] {
        guard filteredSpending.count > 5 else { return filteredSpending }
        let top5 = Array(filteredSpending.prefix(5))
        let otherTotal = filteredSpending.dropFirst(5).reduce(0) { $0 + $1.1 }
        return top5 + [(.other, otherTotal)]
    }

    private var totalFiltered: Double {
        spendingSummary.currentTotal
    }

    // MARK: - Month-over-Month Comparison

    private var previousPeriodSpending: Double {
        spendingSummary.previousTotal
    }

    private var spendingDelta: Double {
        spendingSummary.delta
    }

    private var spendingDeltaPercent: Double {
        spendingSummary.deltaPercent
    }

    private var spendingSummary: SpendingPeriodSummary {
        let interval = periodInterval
        return SpendingSummary.periodSummary(
            from: appState.transactions,
            currentStart: interval.current,
            previousStart: interval.previous
        )
    }

    var body: some View {
        let categories = chartCategories
        let total = totalFiltered
        let prevSpending = previousPeriodSpending
        let delta = spendingDelta
        let deltaPercent = spendingDeltaPercent

        VStack(spacing: Spacing.md) {
            periodPicker

            if appState.transactions.isEmpty {
                emptyTransactionState
            } else if filteredTransactions.isEmpty {
                emptyPeriodState
            } else {
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

                SpendingHeatmapView(
                    transactions: filteredTransactions,
                    startDate: periodInterval.currentDate,
                    endDate: Date(),
                    cellSize: 14,
                    showModePicker: true
                )
                .padding(.top, Spacing.xs)

                Divider()
                    .padding(.horizontal, Spacing.lg)

                Picker("Breakdown", selection: $breakdownType) {
                    ForEach(BreakdownType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Spacing.lg)

                switch breakdownType {
                case .categories:
                    donutChart(categories: categories, total: total)
                case .trend:
                    SpendingTrendChart(transactions: filteredTransactions)
                case .incomeExpense:
                    IncomeExpenseChart(transactions: filteredTransactions)
                }
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(SpendingPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private var emptyTransactionState: some View {
        if !appState.isDemoMode && !appState.serverConnected {
            ContentUnavailableView {
                Label("Server Offline", systemImage: "server.rack")
            } description: {
                Text("Start PlaidBarServer before spending activity can sync.")
            } actions: {
                Button {
                    Task { await appState.checkServerConnection() }
                } label: {
                    Label("Check Server", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else if appState.statusItemCount == 0 {
            ContentUnavailableView {
                Label("No Bank Linked", systemImage: "building.columns")
            } description: {
                Text("Connect a Plaid institution before spending and cashflow charts can populate.")
            } actions: {
                Button {
                    Task { await appState.addAccount() }
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else {
            ContentUnavailableView {
                Label("No Synced Activity", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Sync transactions to build the spending heatmap, trend, and cashflow views.")
            } actions: {
                Button {
                    Task { await appState.syncTransactions() }
                } label: {
                    Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        }
    }

    private var emptyPeriodState: some View {
        ContentUnavailableView {
            Label("No Activity in \(selectedPeriod.rawValue)", systemImage: "calendar.badge.clock")
        } description: {
            Text("No synced transactions fall inside this period. Choose a wider window or refresh the latest history.")
        } actions: {
            HStack {
                if selectedPeriod != .last90Days {
                    Button {
                        selectedPeriod = .last90Days
                    } label: {
                        Label("Show 90D", systemImage: "calendar")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    Task { await appState.syncTransactions() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func donutChart(categories: [(SpendingCategory, Double)], total: Double) -> some View {
        if categories.isEmpty || total <= 0 {
            ContentUnavailableView {
                Label("No Spending Categories", systemImage: "chart.pie")
            } description: {
                Text("This period has synced activity, but no categorized spending. Use Flow or Trend to inspect income, transfers, and zero-spend periods.")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        } else {
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

                        Text(Formatters.percent(amount / total * 100, decimals: 0))
                            .microText()
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xxs)
                }
            }

            // Donut chart
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
