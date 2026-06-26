import PlaidBarCore
import SwiftUI

/// **Budgets** destination — window-first 3-column surface (AND-624, `[⌘3]`).
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
/// engines the popover uses; only the layout differs (re-host data, redesign
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
/// masked values stay dotted. **App Lock** is shell-gated (Epic 10), so
/// this canvas never double-gates. Data/charts stay solid (glass on chrome
/// only) via ``WindowSection``'s quiet card surface.
///
/// The content and inspector columns are separate split-view views that share
/// selection through the per-window ``NavigationModel``
/// (`appState.navigationModel.budgetCategorySelection`) — a per-window value, never
/// a singleton, so two windows hold independent Budgets selection (AND-621).
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
    /// User-selected flat-table ordering for the re-hosted "All categories" table.
    /// Stored as the small `Sendable` ``CategoryDashboardTableModel/Order`` enum (a
    /// `[KeyPathComparator]` is not `Sendable`, so it cannot live in `@State` under
    /// strict concurrency); mapped to the pure model when the rows are built.
    @State private var tableOrder: CategoryDashboardTableModel.Order = .spendDescending

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
                    tableSection
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
                // AND-731: the same `summary.remaining` figure also appears in the
                // status panel rendered at `.full` ("$247.79"). Render the hero at
                // the same precision here so one labeled value never reads as two
                // different numbers ("$248" vs "$247.79") on the same screen.
                value: reconciledHeroCurrency(abs(remaining), masked: masked),
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

    /// Hero currency for a figure that **also** appears elsewhere on this screen
    /// (the "Left this month" / "Over budget" remaining value, shown again in the
    /// status panel). Rendered at `.full` to match the panel's `currency(_:)` exactly
    /// (AND-731) so a single labeled value never reads as two different numbers
    /// ("$248" vs "$247.79"). Other hero tiles (Budgeted, Spent) are not duplicated,
    /// so they keep the compact `heroCurrency`.
    private func reconciledHeroCurrency(_ amount: Double, masked: Bool) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: masked, style: .compact)
    }

    /// Masked-aware currency for the flat table's money columns — matches the
    /// Inspector / legacy `CategoryDashboardWindow` formatting so every amount in
    /// the destination reads identically (Privacy Mask preserved).
    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(
            amount,
            format: .full,
            isEnabled: isMasked,
            style: .compact
        )
    }

    /// Redundant color cue for the table's status column — the glyph + label already
    /// carry the verdict (ACCESSIBILITY.md), so tint is never the only signal.
    /// Single-sourced via the shared `verdictTint` mapping (AND-664 #4).
    private func statusTint(_ status: CategoryBudgetStatus?) -> Color {
        status.verdictTint
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

    // MARK: - Flat "All categories" table

    /// The flat, sortable **SPENT / BUDGET / LEFT / Status / Plan** table — the
    /// analytic counterpart to the two-level tree, re-hosted from the legacy
    /// `CategoryDashboardWindow` so the "Open dashboard" route into Budgets keeps
    /// every leaf in one sortable list (AND-616 category-dashboard parity). The rows
    /// and footer totals come from the pure ``CategoryDashboardTableModel`` (no
    /// recompute); the Plan column drives the same `selectAndEdit` the tree uses, so
    /// editing here also selects the inspector. Amounts honor Privacy Mask; budget
    /// pressure rides on glyph + text, never color alone (ACCESSIBILITY.md).
    private var tableSection: some View {
        let rows = CategoryDashboardTableModel.rows(from: presentation, order: tableOrder)
        let totals = CategoryDashboardTableModel.totals(for: rows)

        return WindowSection("All categories", systemImage: "tablecells") {
            Picker("Sort", selection: $tableOrder) {
                Text("By spend").tag(CategoryDashboardTableModel.Order.spendDescending)
                Text("By group").tag(CategoryDashboardTableModel.Order.groupThenSpend)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Sort categories")
        } content: {
            VStack(alignment: .leading, spacing: WindowMetrics.sm) {
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
        }
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
    /// rows get a labeled button that selects the row for the inspector and opens
    /// `BudgetEditorSheet` (via the shared `selectAndEdit`); income / transfer rows
    /// show an em dash, since they can never carry a budget.
    @ViewBuilder
    private func budgetActionCell(_ row: CategoryDashboardTableRow) -> some View {
        let affordance = BudgetRowAffordance(category: row.category, isBudgeted: row.isBudgeted)
        if affordance.isAvailable {
            Button {
                selectAndEdit(row.category)
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
        HStack(spacing: WindowMetrics.lg) {
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
        .padding(.top, WindowMetrics.xs)
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
    /// -gated — shows the "Select a category" prompt when nothing is selected.
    /// Re-hosts the same Core engines as the content column.
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
                                .windowDataText()
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
                    .windowDataText()
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

#if canImport(PreviewsMacros)
#Preview("Content") {
    BudgetsDestinationView()
        .environment(AppState())
}
#endif

#if canImport(PreviewsMacros)
#Preview("Inspector") {
    BudgetsDestinationView.Inspector()
        .environment(AppState())
}
#endif
