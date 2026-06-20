import PlaidBarCore
import SwiftUI

/// **Budgets** destination — window-first 3-column surface (AND-624; ADR-001
/// window-first workspace, IA §3.1/§5.4, `[⌘3]`).
///
/// Re-hosted to the **desk-distance design language** the Dashboard reference set
/// (``WindowMetrics`` / ``WindowTypography`` / ``WindowSection`` /
/// ``WindowHeroMetricTile``): a calm content canvas — a **hero metric row**
/// (total budget / spent / left) above two generous ``WindowSection`` cards (the
/// **spend donut** as the prominent hero visual, then the override-aware
/// **category tree**) — paired with a window-scale **inspector** (overall month
/// status rollup + the selected category's detail/editor).
///
/// **Data is re-hosted, not recomputed** — every figure comes from the same Core
/// engines the popover uses; only the layout differs (R: re-host data, redesign
/// layout):
/// - `AppState.categoryDashboardPresentation` (built by `CategoryDashboardBuilder`
///   over `CategoryBudgetPlanner.netSpendByCategory`, override-aware) drives the
///   donut + tree.
/// - `CategoryTreeView` / `SpendDonutChart` / `CategoryStatusBar` render it unchanged.
/// - `BudgetEditorSheet` is re-hosted for inline-editable category budgets.
/// - `BudgetsStatusSummary` reduces the rollup into the hero row + status pane.
///
/// **Never color alone (ACCESSIBILITY.md):** budget pressure (over / nearing) is
/// always carried by **text + SF Symbol**; tint is layered redundantly on top.
/// **Privacy Mask:** every figure runs through `PrivacyMaskPresentation`, so
/// masked values stay dotted. **App Lock** is shell-gated (ADR-001 Epic 10), so
/// this canvas never double-gates. Data/charts stay solid (R-08, glass on chrome
/// only) via ``WindowSection``'s quiet card surface.
///
/// The content and inspector columns are separate split-view views that share
/// selection through the per-window ``NavigationModel``
/// (`appState.navigationModel.budgetCategorySelection`) — a per-window value, never
/// a singleton, so two windows hold independent Budgets selection (AND-621, R-10).
///
/// **Flag-OFF inert:** reached solely when `AppShellView` mounts (behind
/// `WindowFirstFeatureFlag`, default OFF). With the flag off none of this is
/// instantiated and the popover stays byte-identical.
struct BudgetsDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                if presentation.isEmpty {
                    emptyState
                } else {
                    heroMetricsRow
                    donutSection
                    treeSection
                }
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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

    // MARK: - Hero metrics row

    /// The headline month figures across the top of the canvas — budgeted total,
    /// spent, and what's left (or over) — as large tabular ``WindowHeroMetricTile``
    /// figures. Reflows to wrap on a narrow window so each figure keeps its tabular
    /// legibility (`heroTileMinWidth`). Reduces a finished `BudgetsStatusSummary`,
    /// no new aggregation. None rely on color for meaning (the label names the
    /// figure; the "Left/Over" tile carries its sense in the label + glyph).
    private var heroMetricsRow: some View {
        let metrics = heroMetrics
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: WindowMetrics.heroTileMinWidth), spacing: WindowMetrics.lg)],
            alignment: .leading,
            spacing: WindowMetrics.lg
        ) {
            ForEach(metrics) { metric in
                WindowHeroMetricTile(
                    label: metric.label,
                    value: metric.value,
                    systemImage: metric.systemImage,
                    detail: metric.detail,
                    accent: metric.accent,
                    reduceMotion: reduceMotion
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Budget headline figures")
    }

    /// One headline figure for the hero row. Pure presentation data derived from
    /// the same `BudgetsStatusSummary` the inspector status pane uses.
    private struct HeroMetric: Identifiable {
        let id: String
        let label: String
        let value: String
        let systemImage: String
        let detail: String?
        let accent: Color
    }

    private var heroMetrics: [HeroMetric] {
        let summary = BudgetsStatusSummary.summarize(presentation)
        let masked = isMasked

        let budgeted = HeroMetric(
            id: "budgeted",
            label: "Budgeted this month",
            value: heroCurrency(summary.totalLimit, masked: masked),
            systemImage: "slider.horizontal.3",
            detail: summary.budgetedDetail,
            accent: SemanticColors.brand
        )

        let spent = HeroMetric(
            id: "spent",
            label: "Spent",
            value: heroCurrency(summary.totalSpent, masked: masked),
            systemImage: "creditcard",
            detail: summary.spentDetail,
            accent: .secondary
        )

        // The third tile flips its identity (and glyph) with the verdict — never
        // color alone: the label says "Left this month" vs "Over budget".
        let remainingTile: HeroMetric
        if let remaining = summary.remaining {
            remainingTile = HeroMetric(
                id: "remaining",
                label: summary.isAggregateOver ? "Over budget" : "Left this month",
                value: heroCurrency(abs(remaining), masked: masked),
                systemImage: summary.isAggregateOver ? "exclamationmark.triangle.fill" : "checkmark.circle",
                detail: summary.remainingDetail,
                accent: summary.isAggregateOver ? SemanticColors.negative : SemanticColors.positive
            )
        } else {
            remainingTile = HeroMetric(
                id: "remaining",
                label: "No budgets set",
                value: "—",
                systemImage: "slider.horizontal.3",
                detail: "Add a limit to a category to start tracking",
                accent: .secondary
            )
        }

        return [budgeted, spent, remainingTile]
    }

    /// Hero figures use the compact masked-aware currency the Dashboard hero row
    /// uses, so the two destinations' headline numbers read identically.
    private func heroCurrency(_ amount: Double, masked: Bool) -> String {
        PrivacyMaskPresentation.currency(amount, format: .compact, isEnabled: masked)
    }

    // MARK: - Donut (hero visual)

    /// The spend donut — the destination's prominent hero visual, given its own
    /// titled ``WindowSection`` card so it reads as the signature instrument rather
    /// than a small chart stuck to the tree.
    private var donutSection: some View {
        let donut = SpendDonutModel(presentation: presentation)
        return WindowSection("Spending by category", systemImage: "chart.pie") {
            CategoryCountAccessory(count: presentation.leaves.count)
        } content: {
            SpendDonutChart(model: donut, isPrivacyMasked: isMasked)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tree

    /// The override-aware two-level category tree. Tapping a leaf's budget
    /// affordance selects it for the inspector and opens the editor; the inspector
    /// reflects the selection independently.
    private var treeSection: some View {
        WindowSection("By group", systemImage: "list.bullet.indent") {
            CategoryTreeView(
                presentation: presentation,
                privacyMaskEnabled: isMasked,
                onEditBudget: selectAndEdit
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        WindowSection("Spending by category", systemImage: "chart.pie") {
            ContentUnavailableView {
                Label("No category spending yet", systemImage: "chart.pie")
            } description: {
                Text("Budgets and spending appear here once this month's transactions arrive.")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    /// A small trailing header count for a ``WindowSection``, naming the figure in
    /// text (never count-by-position alone).
    private struct CategoryCountAccessory: View {
        let count: Int
        var body: some View {
            Text(count == 1 ? "1 category" : "\(count) categories")
                .windowSupportingText()
                .monospacedDigit()
                .accessibilityLabel("\(count) categories tracked")
        }
    }

    /// The detail-column (inspector) pane for Budgets at window scale: the overall
    /// month **status** rollup, then the selected category's detail/editor. Content
    /// -gated — shows the "Select a category" prompt when nothing is selected
    /// (IA §3.1). Re-hosts the same Core engines as the content column.
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
                VStack(alignment: .leading, spacing: WindowMetrics.lg) {
                    statusSection

                    if let category = navigationModel.budgetCategorySelection {
                        categoryDetail(category)
                    } else {
                        selectionPrompt
                    }
                }
                .padding(WindowMetrics.canvasMargin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
            return WindowSection("Status", systemImage: "gauge.with.dots.needle.33percent") {
                VStack(alignment: .leading, spacing: WindowMetrics.sm) {
                    // Headline verdict: glyph + label, tint redundant (ACCESSIBILITY.md).
                    Label(summary.health.label, systemImage: summary.health.iconName)
                        .windowCardTitle()
                        .foregroundStyle(healthTint(summary.health))
                        .accessibilityLabel("Budget status: \(summary.health.label)")

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

                    if let remaining = summary.remaining {
                        Divider().opacity(0.4)
                        HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                            Label(
                                summary.isAggregateOver ? "Over by" : "Left this month",
                                systemImage: summary.isAggregateOver ? "minus.circle" : "plus.circle"
                            )
                            .windowSupportingText()
                            Spacer(minLength: WindowMetrics.sm)
                            Text(currency(abs(remaining)))
                                .windowBodyText()
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(summary.isAggregateOver ? SemanticColors.negative : .primary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }

        private func statusStat(_ label: String, _ value: String, systemImage: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                Label(label, systemImage: systemImage)
                    .windowSupportingText()
                Spacer(minLength: WindowMetrics.sm)
                Text(value)
                    .windowBodyText()
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }

        // MARK: - Selected category detail/editor

        private func categoryDetail(_ category: SpendingCategory) -> some View {
            let leaf = presentation.leaf(category)
            return WindowSection(category.displayName, systemImage: category.iconName) {
                Text(category.group.title)
                    .windowSupportingText()
            } content: {
                VStack(alignment: .leading, spacing: WindowMetrics.md) {
                    if let leaf {
                        CategoryStatusBar(
                            model: CategoryStatusBarModel(leaf: leaf),
                            spentText: currency(leaf.spent),
                            limitText: leaf.monthlyLimit.map(currency),
                            accent: CategoryAccentTokens.color(for: category)
                        )
                    } else {
                        Label("No spending or budget yet this month", systemImage: "tray")
                            .windowBodyText()
                            .foregroundStyle(.secondary)
                    }

                    editBudgetButton(for: category)
                }
            }
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
                .controlSize(.large)
                .accessibilityLabel(affordance.accessibilityLabel)
            } else {
                Label(
                    "Income and transfer categories can't have a budget.",
                    systemImage: "info.circle"
                )
                .windowSupportingText()
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
