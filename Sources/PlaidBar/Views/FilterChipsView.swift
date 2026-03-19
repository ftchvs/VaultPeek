import SwiftUI
import PlaidBarCore

struct FilterChipsView: View {
    @Binding var selectedCategory: SpendingCategory?
    @Binding var selectedAccountId: String?
    @Binding var selectedDateRange: DateRangeFilter
    let accounts: [AccountDTO]
    let availableCategories: [SpendingCategory]

    var activeFilterCount: Int {
        var count = 0
        if selectedCategory != nil { count += 1 }
        if selectedAccountId != nil { count += 1 }
        if selectedDateRange != .all { count += 1 }
        return count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // Category filter
                Menu {
                    Button("All Categories") {
                        selectedCategory = nil
                    }
                    Divider()
                    ForEach(availableCategories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(category.displayName, systemImage: category.iconName)
                        }
                    }
                } label: {
                    chipLabel(
                        text: selectedCategory?.displayName ?? "Category",
                        isActive: selectedCategory != nil
                    )
                }
                .menuStyle(.borderlessButton)

                // Account filter
                Menu {
                    Button("All Accounts") {
                        selectedAccountId = nil
                    }
                    Divider()
                    ForEach(accounts) { account in
                        Button(account.name) {
                            selectedAccountId = account.id
                        }
                    }
                } label: {
                    chipLabel(
                        text: accounts.first(where: { $0.id == selectedAccountId })?.name ?? "Account",
                        isActive: selectedAccountId != nil
                    )
                }
                .menuStyle(.borderlessButton)

                // Date range filter
                Menu {
                    ForEach(DateRangeFilter.allCases, id: \.self) { range in
                        Button(range.displayName) {
                            selectedDateRange = range
                        }
                    }
                } label: {
                    chipLabel(
                        text: selectedDateRange.displayName,
                        isActive: selectedDateRange != .all
                    )
                }
                .menuStyle(.borderlessButton)

                // Clear all
                if activeFilterCount > 0 {
                    Button {
                        selectedCategory = nil
                        selectedAccountId = nil
                        selectedDateRange = .all
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear all filters")
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activeFilterCount > 0 ? "\(activeFilterCount) filters active" : "Transaction filters")
    }

    @ViewBuilder
    private func chipLabel(text: String, isActive: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(text)
                .font(.caption)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            isActive ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: Capsule()
        )
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
    }
}

enum DateRangeFilter: String, CaseIterable, Sendable {
    case week = "This Week"
    case month = "This Month"
    case thirtyDays = "30 Days"
    case all = "All"

    var displayName: String { rawValue }

    func startDate() -> String? {
        let calendar = Calendar.current
        let now = Date()
        let start: Date?
        switch self {
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: now)
        case .all:
            return nil
        }
        guard let start else { return nil }
        return Formatters.transactionDateString(start)
    }
}
