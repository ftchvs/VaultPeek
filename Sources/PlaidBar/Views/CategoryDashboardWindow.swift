import PlaidBarCore
import SwiftUI

/// The full **Category Dashboard** surface hosted in the detached desktop window
/// (AND-539) — Copilot's "full category tab." It assembles the same override-aware
/// pieces the popover card previews, at full size (spec §3/§4, Option A):
///
/// - the spend donut (`SpendDonutChart`, AND-537) with its center total,
/// - the two-level status-bar tree (`CategoryTreeView`, AND-538), and
/// - a flat, sortable **SPENT / BUDGET / LEFT** `Table` of every leaf category.
///
/// It reads the finished ``CategoryDashboardPresentation`` from `AppState` and does
/// no aggregation: the donut/tree drive off the presentation directly, and the
/// table rows + footer totals come from the pure ``CategoryDashboardTableModel`` in
/// PlaidBarCore. Amounts honor Privacy Mask; budget pressure rides on glyph + text,
/// never color alone (ACCESSIBILITY.md).
///
/// The monthly-history `BarMark` + dashed budget `RuleMark` (spec §3) is deferred
/// to a follow-up: there is no current override-aware multi-month spend rollup in
/// PlaidBarCore to drive it, and building one is beyond assembling existing
/// components. The card + window ship complete without it.
struct CategoryDashboardWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openCategoryDashboard) private var openCategoryDashboard

    /// User-selected flat-table ordering. Stored as a small `Sendable` enum (a
    /// `[KeyPathComparator]` is not `Sendable`, so it cannot live in `@State` under
    /// strict concurrency); mapped to the pure ``CategoryDashboardTableModel/Order``
    /// when the rows are built.
    @State private var tableOrder: CategoryDashboardTableModel.Order = .spendDescending
    /// The category whose budget the user is editing (AND-541); drives the sheet.
    @State private var budgetEditorCategory: BudgetEditorCategory?

    private var presentation: CategoryDashboardPresentation {
        appState.categoryDashboardPresentation
    }

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if presentation.isEmpty {
                    emptyState
                } else {
                    donutSection
                    treeSection
                    tableSection
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 520, minHeight: 480)
        .accessibilityElement(children: .contain)
        .sheet(item: $budgetEditorCategory) { item in
            BudgetEditorSheet(category: item.category)
                .environment(appState)
        }
    }

    /// Open the budget editor for `category` (AND-541).
    private func editBudget(_ category: SpendingCategory) {
        budgetEditorCategory = BudgetEditorCategory(category)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Spending by Category")
                .font(.title2.weight(.bold))
            Text("Where this month's money went, by category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Donut

    private var donutSection: some View {
        let donut = SpendDonutModel(presentation: presentation)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SpendDonutChart(model: donut, isPrivacyMasked: isMasked)
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    // MARK: - Tree

    private var treeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("By group", systemImage: "list.bullet.indent")
                .sectionTitle()
                .foregroundStyle(.secondary)
            CategoryTreeView(
                presentation: presentation,
                privacyMaskEnabled: isMasked,
                onEditBudget: editBudget
            )
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    // MARK: - Flat table

    private var tableSection: some View {
        let rows = CategoryDashboardTableModel.rows(from: presentation, order: tableOrder)
        let totals = CategoryDashboardTableModel.totals(for: rows)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Label("All categories", systemImage: "tablecells")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer(minLength: Spacing.sm)

                Picker("Sort", selection: $tableOrder) {
                    Text("By spend").tag(CategoryDashboardTableModel.Order.spendDescending)
                    Text("By group").tag(CategoryDashboardTableModel.Order.groupThenSpend)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Sort categories")
            }

            Table(rows) {
                TableColumn("Category") { row in
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.categoryName)
                                .lineLimit(1)
                            Text(row.groupTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: row.iconName)
                            .foregroundStyle(CategoryAccentTokens.color(for: row.category))
                    }
                    .accessibilityLabel("\(row.categoryName), \(row.groupTitle)")
                }
                .width(min: 160, ideal: 200)

                TableColumn("Spent") { row in
                    Text(currency(row.spent))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 96)

                TableColumn("Budget") { row in
                    Text(row.budget.map(currency) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(row.isBudgeted ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 96)

                TableColumn("Left") { row in
                    leftCell(row)
                }
                .width(min: 80, ideal: 96)

                TableColumn("Status") { row in
                    Label(row.statusText, systemImage: row.statusIconName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusTint(row.status))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityLabel(row.statusText)
                }
                .width(min: 120, ideal: 140)

                TableColumn("Plan") { row in
                    budgetActionCell(row)
                }
                .width(min: 104, ideal: 120)
            }
            .frame(minHeight: 220)

            tableFooter(totals)
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    private func leftCell(_ row: CategoryDashboardTableRow) -> some View {
        guard let remaining = row.remaining else {
            return AnyView(
                Text("—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            )
        }
        // Over-budget rows read negative; the band glyph + text already carry the
        // verdict, so the tint here is a redundant cue, never the only signal.
        return AnyView(
            Text(currency(remaining))
                .monospacedDigit()
                .foregroundStyle(remaining < 0 ? SemanticColors.negative : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(remaining < 0
                    ? "\(currency(abs(remaining))) over"
                    : "\(currency(remaining)) left")
        )
    }

    /// The flat-table "Set a budget" / "Edit" action cell (AND-541). Budgetable
    /// rows get a labeled button that opens `BudgetEditorSheet`; income / transfer
    /// rows show an em dash, since they can never carry a budget.
    @ViewBuilder
    private func budgetActionCell(_ row: CategoryDashboardTableRow) -> some View {
        let affordance = BudgetRowAffordance(category: row.category, isBudgeted: row.isBudgeted)
        if affordance.isAvailable {
            Button {
                editBudget(row.category)
            } label: {
                Label(affordance.title, systemImage: affordance.systemImage)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel(affordance.accessibilityLabel)
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func tableFooter(_ totals: CategoryDashboardTableModel.Totals) -> some View {
        HStack(spacing: Spacing.md) {
            footerStat("Total spent", currency(totals.spent))
            if totals.hasBudget {
                footerStat("Budgeted", currency(totals.budget))
                footerStat(
                    totals.remaining < 0 ? "Over" : "Left",
                    currency(abs(totals.remaining)),
                    tint: totals.remaining < 0 ? SemanticColors.negative : .primary
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.xs)
    }

    private func footerStat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("No category spending yet", systemImage: "chart.pie")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Spending appears here once this month's transactions arrive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(Spacing.lg)
        .glassSurface(.raised)
    }

    // MARK: - Helpers

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(
            amount,
            format: .full,
            isEnabled: isMasked,
            style: .compact
        )
    }

    /// Redundant color cue for the status column — the glyph + label already carry
    /// the verdict (ACCESSIBILITY.md).
    private func statusTint(_ status: CategoryBudgetStatus?) -> Color {
        switch status {
        case .over: SemanticColors.negative
        case .nearing: SemanticColors.warning
        case .under: .secondary
        case nil: .secondary
        }
    }
}
