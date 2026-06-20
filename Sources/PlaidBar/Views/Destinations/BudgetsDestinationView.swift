import PlaidBarCore
import SwiftUI

/// **Budgets** destination (3-column — IA §3.1/§5.4, `[⌘3]`).
///
/// Epic 5 / AND-583 (ADR-001 window-first workspace). The content column is the
/// override-aware **category tree** (donut + two-level status-bar tree); the
/// inspector column shows the **selected category's detail/editor** — re-hosting
/// `BudgetEditorSheet` — plus an overall month **status** rollup.
///
/// Everything is surfaced from existing engines — no new aggregation lives here:
/// - `AppState.categoryDashboardPresentation` (built by `CategoryDashboardBuilder`
///   over `CategoryBudgetPlanner.netSpendByCategory`, override-aware) drives the
///   donut + tree.
/// - `CategoryTreeView` / `SpendDonutChart` / `CategoryStatusBar` render it.
/// - `BudgetEditorSheet` is re-hosted for inline-editable category budgets.
/// - `BudgetsStatusSummary` (new pure Core, unit-tested) reduces the rollup into
///   the status pane.
///
/// Budget pressure (over/nearing) is always carried by **text + SF Symbol**, never
/// color alone (ACCESSIBILITY.md). The content and inspector columns are separate
/// split-view views, so they share selection through the per-window
/// ``NavigationModel`` (`appState.navigationModel.budgetCategorySelection`) — a
/// per-window value, never a singleton, so two windows hold independent Budgets
/// selection (AND-621, R-10).
///
/// Window-first surface only: reached solely when `AppShellView` mounts (behind
/// `WindowFirstFeatureFlag`, default OFF). With the flag off none of this is
/// instantiated and the popover is byte-identical.
struct BudgetsDestinationView: View {
    @Environment(AppState.self) private var appState
    /// The category whose budget the user is editing; drives the re-hosted
    /// `BudgetEditorSheet` (AND-541 pattern, mirroring `CategoryDashboardWindow`).
    @State private var budgetEditorCategory: BudgetEditorCategory?

    private var navigationModel: NavigationModel { appState.navigationModel }

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
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(RouteDestination.budgets.title)
        .loadingRedaction(appState.loadState(for: .summaryCards))
        .sheet(item: $budgetEditorCategory) { item in
            BudgetEditorSheet(category: item.category)
                .environment(appState)
        }
        .accessibilityElement(children: .contain)
    }

    /// Select a category (drives the inspector) and open its budget editor.
    private func selectAndEdit(_ category: SpendingCategory) {
        navigationModel.budgetCategorySelection = category
        budgetEditorCategory = BudgetEditorCategory(category)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Budgets")
                .font(.title2.weight(.bold))
            Text("Set monthly limits and track this month's spending by category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
            // Tapping a leaf's budget affordance selects it for the inspector and
            // opens the editor; the inspector reflects the selection independently.
            CategoryTreeView(
                presentation: presentation,
                privacyMaskEnabled: isMasked,
                onEditBudget: selectAndEdit
            )
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("No category spending yet", systemImage: "chart.pie")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Budgets and spending appear here once this month's transactions arrive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(Spacing.lg)
        .glassSurface(.raised)
    }

    /// The detail-column (inspector) pane for Budgets: the selected category's
    /// detail/editor plus the overall month status rollup. Content-gated — shows
    /// the "Select a category" prompt when nothing is selected (IA §3.1).
    struct Inspector: View {
        @Environment(AppState.self) private var appState
        @State private var budgetEditorCategory: BudgetEditorCategory?

        private var navigationModel: NavigationModel { appState.navigationModel }

        private var presentation: CategoryDashboardPresentation {
            appState.categoryDashboardPresentation
        }

        private var isMasked: Bool { appState.shouldMaskFinancialValues }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    statusSection

                    if let category = navigationModel.budgetCategorySelection {
                        categoryDetail(category)
                    } else {
                        selectionPrompt
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .sheet(item: $budgetEditorCategory) { item in
                BudgetEditorSheet(category: item.category)
                    .environment(appState)
            }
            .accessibilityElement(children: .contain)
        }

        // MARK: - Status rollup

        private var statusSection: some View {
            let summary = BudgetsStatusSummary.summarize(presentation)
            return VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Status", systemImage: "gauge.with.dots.needle.33percent")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                // Headline verdict: glyph + label, tint redundant (ACCESSIBILITY.md).
                Label(summary.health.label, systemImage: summary.health.iconName)
                    .font(.headline)
                    .foregroundStyle(healthTint(summary.health))
                    .accessibilityLabel("Budget status: \(summary.health.label)")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    statusStat(
                        "Over budget",
                        "\(summary.overBudgetCount)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    statusStat(
                        "Nearing a limit",
                        "\(summary.nearingCount)",
                        systemImage: "exclamationmark.circle"
                    )
                    statusStat(
                        "Budgeted categories",
                        "\(summary.budgetedCount) of \(summary.trackedCount)",
                        systemImage: "slider.horizontal.3"
                    )
                }

                if let remaining = summary.remaining {
                    Divider().opacity(0.4)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Label(
                            summary.isAggregateOver ? "Over by" : "Left this month",
                            systemImage: summary.isAggregateOver ? "minus.circle" : "plus.circle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        Spacer(minLength: Spacing.sm)
                        Text(currency(abs(remaining)))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(summary.isAggregateOver ? SemanticColors.negative : .primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Spacing.md)
            .glassSurface(.raised)
        }

        private func statusStat(_ label: String, _ value: String, systemImage: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Label(label, systemImage: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.sm)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }

        // MARK: - Selected category detail/editor

        private func categoryDetail(_ category: SpendingCategory) -> some View {
            let leaf = presentation.leaf(category)
            return VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: category.iconName)
                        .font(.title3)
                        .foregroundStyle(CategoryAccentTokens.color(for: category))
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName)
                            .font(.headline)
                        Text(category.group.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Spacing.sm)
                }
                .accessibilityElement(children: .combine)

                if let leaf {
                    CategoryStatusBar(
                        model: CategoryStatusBarModel(leaf: leaf),
                        spentText: currency(leaf.spent),
                        limitText: leaf.monthlyLimit.map(currency),
                        accent: CategoryAccentTokens.color(for: category)
                    )
                } else {
                    Label("No spending or budget yet this month", systemImage: "tray")
                        .microText()
                        .foregroundStyle(.secondary)
                }

                editBudgetButton(for: category)
            }
            .padding(Spacing.md)
            .glassSurface(.raised)
        }

        @ViewBuilder
        private func editBudgetButton(for category: SpendingCategory) -> some View {
            let isBudgeted = presentation.leaf(category)?.isBudgeted ?? false
            let affordance = BudgetRowAffordance(category: category, isBudgeted: isBudgeted)
            if affordance.isAvailable {
                Button {
                    budgetEditorCategory = BudgetEditorCategory(category)
                } label: {
                    Label(affordance.title, systemImage: affordance.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityLabel(affordance.accessibilityLabel)
            } else {
                Label(
                    "Income and transfer categories can't have a budget.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        private var selectionPrompt: some View {
            ContentUnavailableView {
                Label(
                    RouteDestination.budgets.detailColumnEmptyPrompt ?? "Select a category",
                    systemImage: RouteDestination.budgets.systemImage
                )
            } description: {
                Text("Choose a category from the list to edit its budget and see its detail here.")
            }
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

        /// Redundant color cue — the glyph + label already carry the verdict.
        private func healthTint(_ health: BudgetsStatusSummary.Health) -> Color {
            switch health {
            case .over: SemanticColors.negative
            case .nearing: SemanticColors.warning
            case .onTrack: SemanticColors.positive
            case .noBudgets: .secondary
            }
        }
    }
}

#Preview("Content") {
    BudgetsDestinationView()
        .environment(AppState())
}

#Preview("Inspector") {
    BudgetsDestinationView.Inspector()
        .environment(AppState())
}
