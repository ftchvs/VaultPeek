import PlaidBarCore
import SwiftUI

/// The popover center-column **Category Dashboard card** (AND-539) — the surface
/// that finally *shows* the Copilot-style category dashboard inline: the spend
/// donut, the top spending group rollups, and an "Open dashboard" affordance that
/// launches the full detached window.
///
/// It is a thin assembler over already-built pieces (spec §3/§4, Option A):
/// `SpendDonutChart` (AND-537) and per-group `CategoryStatusBar` rows (AND-538),
/// all driven by the override-aware ``CategoryDashboardPresentation`` `AppState`
/// already caches — the card never recomputes spend. Every derived number and the
/// top-N group selection come from the pure ``CategoryDashboardCardModel`` in
/// PlaidBarCore, so the view owns only layout, glass, and the open-window intent.
///
/// Accessibility (ACCESSIBILITY.md): budget pressure and the headline summary are
/// carried as glyph + text, never color alone; amounts honor Privacy Mask.
struct CategoryDashboardCard: View {
    @Environment(AppState.self) private var appState
    /// Opens the detached full dashboard window. Injected by the app scene; a
    /// no-op in previews / headless renders.
    @Environment(\.openCategoryDashboard) private var openCategoryDashboard

    /// Mounts the shared card on the **window** workspace rather than the popover.
    /// In the window the card backs onto the solid window surface
    /// (`windowCardSurface()` — HIG Materials / ADR-001 "glass on chrome, not
    /// data"); in the popover (default) it keeps the raised glass surface.
    var inWindow: Bool = false

    private var presentation: CategoryDashboardPresentation {
        appState.categoryDashboardPresentation
    }

    private var model: CategoryDashboardCardModel {
        CategoryDashboardCardModel(presentation: presentation)
    }

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        let model = model

        surfaced {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header(model)

                if model.isEmpty {
                    emptyState
                } else {
                    SpendDonutChart(model: model.donut, isPrivacyMasked: isMasked)

                    if !model.topGroups.isEmpty {
                        topGroups(model)
                    }
                }

                openDashboardButton(model)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(model))
    }

    /// Wraps the card content in the surface appropriate to where it is mounted:
    /// the solid window card surface in the window (data stays solid — ADR-001
    /// "glass on chrome, not data"), the raised glass surface in the popover.
    /// `windowCardSurface()` does not self-pad, so window padding is applied here.
    @ViewBuilder
    private func surfaced(@ViewBuilder _ content: () -> some View) -> some View {
        if inWindow {
            content()
                .padding(WindowMetrics.md)
                .windowCardSurface()
        } else {
            content()
                .padding(Spacing.sm)
                .glassSurface(.raised)
        }
    }

    // MARK: - Header

    private func header(_ model: CategoryDashboardCardModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label("Spending by Category", systemImage: "chart.pie")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            if let summary = model.attentionSummary(isBudgeted: isAnyBudgeted) {
                Label(summary, systemImage: attentionIcon(model))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(attentionTint(model))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(attentionTint(model).opacity(0.11), in: Capsule())
                    .accessibilityLabel("Budget status: \(summary)")
            }
        }
    }

    // MARK: - Top group rollups

    private func topGroups(_ model: CategoryDashboardCardModel) -> some View {
        VStack(spacing: Spacing.xs) {
            ForEach(model.topGroups) { group in
                groupRow(group)
            }
        }
    }

    private func groupRow(_ group: CategoryDashboardPresentation.GroupRollup) -> some View {
        let statusModel = CategoryStatusBarModel(group: group)
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: groupIcon(group.group))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(groupAccent(group.group))
                    .frame(width: Sizing.iconInline)
                    .accessibilityHidden(true)

                Text(group.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)
            }

            CategoryStatusBar(
                model: statusModel,
                spentText: currency(group.spent),
                limitText: group.monthlyLimit.map(currency),
                accent: groupAccent(group.group)
            )
        }
        .padding(Spacing.sm)
        .nativeInsetSurface()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label("No category spending yet", systemImage: "chart.pie")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Spending shows here once this month's transactions arrive.")
                .microText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .nativeInsetSurface()
    }

    // MARK: - Open dashboard

    private func openDashboardButton(_ model: CategoryDashboardCardModel) -> some View {
        Button {
            openCategoryDashboard()
        } label: {
            HStack(spacing: Spacing.xs) {
                Label("Open dashboard", systemImage: "rectangle.expand.vertical")
                    .font(.caption.weight(.semibold))
                if let overflow = model.overflowText {
                    Text(overflow)
                        .microText()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "arrow.up.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full category dashboard in a window")
    }

    // MARK: - Helpers

    /// At least one leaf in the rollup tracks a budget — drives whether the header
    /// summary line shows at all (an unbudgeted month never claims "On track").
    private var isAnyBudgeted: Bool {
        presentation.leaves.contains { $0.monthlyLimit != nil }
    }

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(
            amount,
            format: .compact,
            isEnabled: isMasked,
            style: .compact
        )
    }

    private func groupAccent(_ group: CategoryGroup) -> Color {
        guard let representative = group.categories.first else { return SemanticColors.brand }
        return CategoryAccentTokens.color(for: representative)
    }

    private func groupIcon(_ group: CategoryGroup) -> String {
        group.categories.first?.iconName ?? "circle.fill"
    }

    /// Attention glyph for the header pill — over outranks nearing; an on-track or
    /// unbudgeted month uses a neutral check. Never the only signal (text label too).
    private func attentionIcon(_ model: CategoryDashboardCardModel) -> String {
        if model.overBudgetCount > 0 { return "exclamationmark.triangle.fill" }
        if model.nearingCount > 0 { return "exclamationmark.circle" }
        return "checkmark.circle"
    }

    /// Redundant color cue layered over the glyph + text (never alone).
    private func attentionTint(_ model: CategoryDashboardCardModel) -> Color {
        if model.overBudgetCount > 0 { return SemanticColors.negative }
        if model.nearingCount > 0 { return SemanticColors.warning }
        return SemanticColors.positive
    }

    private func accessibilitySummary(_ model: CategoryDashboardCardModel) -> String {
        guard !model.isEmpty else {
            return "Spending by category. No category spending yet this month."
        }
        let total = isMasked ? PrivacyMaskPresentation.compactValue : model.totalSpentText
        var sentence = "Spending by category. \(total) spent this month."
        if let summary = model.attentionSummary(isBudgeted: isAnyBudgeted) {
            sentence += " \(summary)."
        }
        return sentence
    }
}
