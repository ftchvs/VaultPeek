import SwiftUI
import Charts
import PlaidBarCore

struct SpendingView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPeriod: SpendingPeriod = .thisMonth

    enum SpendingPeriod: String, CaseIterable, Sendable {
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30Days = "Last 30 Days"
    }

    private var filteredSpending: [(SpendingCategory, Double)] {
        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        switch selectedPeriod {
        case .thisWeek:
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .thisMonth:
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }

        let startString = Self.formatDate(startDate)
        let filtered = appState.transactions.filter {
            !$0.isIncome && $0.date >= startString &&
            $0.category != .transfer && $0.category != .transferOut
        }

        let grouped = Dictionary(grouping: filtered) { $0.category ?? .other }
        return grouped.map { (category, txns) in
            (category, txns.reduce(0) { $0 + $1.displayAmount })
        }.sorted { $0.1 > $1.1 }
    }

    private var totalFiltered: Double {
        filteredSpending.reduce(0) { $0 + $1.1 }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Period picker
            Picker("Period", selection: $selectedPeriod) {
                ForEach(SpendingPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Total
            Text("Total: \(Formatters.currency(totalFiltered, format: .full))")
                .font(.title3)
                .fontWeight(.semibold)

            // Donut chart
            if !filteredSpending.isEmpty {
                Chart(filteredSpending, id: \.0) { category, amount in
                    SectorMark(
                        angle: .value("Amount", amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                    .annotation(position: .overlay) {
                        if amount / totalFiltered > 0.1 {
                            Text(Formatters.percent(amount / totalFiltered * 100, decimals: 0))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 150)
                .padding(.horizontal)
            }

            // Category breakdown
            ForEach(filteredSpending, id: \.0) { category, amount in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: category.colorHex) ?? .gray)
                        .frame(width: 10, height: 10)

                    Text(category.displayName)
                        .font(.body)

                    Spacer()

                    Text(Formatters.currency(amount, format: .full))
                        .monospacedDigit()

                    Text(Formatters.percent(amount / totalFiltered * 100, decimals: 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 8)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
