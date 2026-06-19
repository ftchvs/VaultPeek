import PlaidBarCore
import SwiftUI

/// The Copilot-style category dashboard tree (AND-538): a two-level disclosure
/// of group rollup rows (AND-558) over their leaf rows (AND-557).
///
/// Each ``CategoryDashboardPresentation/GroupRollup`` is a parent row carrying
/// its own summed status bar; expanding it reveals the leaf
/// ``CategoryDashboardPresentation/Leaf`` rows, each with its independent status
/// bar. Group and leaf status are computed independently in the presentation —
/// a group can read *over* while every leaf reads *under* — and this view simply
/// renders whatever band each row was handed (spec §3/§4, §7).
///
/// The view is injected with a finished ``CategoryDashboardPresentation``; it
/// performs no aggregation, reads no `AppState`, and triggers no recompute. All
/// derived numbers come from ``CategoryStatusBarModel`` in PlaidBarCore.
struct CategoryTreeView: View {
    let presentation: CategoryDashboardPresentation
    /// When true, every currency figure is masked (Privacy Mask / App Lock).
    var privacyMaskEnabled: Bool = false

    /// Group IDs currently expanded. Budgeted-or-pressured groups start open so
    /// the rows that need attention are visible without a click.
    @State private var expandedGroupIDs: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(presentation: CategoryDashboardPresentation, privacyMaskEnabled: Bool = false) {
        self.presentation = presentation
        self.privacyMaskEnabled = privacyMaskEnabled
        // Open groups that are over/nearing so attention rows are visible up front.
        let openByDefault = presentation.groups
            .filter { $0.status != nil && $0.status != .under }
            .map(\.id)
        _expandedGroupIDs = State(initialValue: Set(openByDefault))
    }

    var body: some View {
        if presentation.isEmpty {
            emptyState
        } else {
            VStack(spacing: Spacing.xs) {
                ForEach(presentation.groups) { group in
                    groupSection(group)
                }
            }
        }
    }

    // MARK: - Group section

    @ViewBuilder
    private func groupSection(_ group: CategoryDashboardPresentation.GroupRollup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            groupHeader(group, isExpanded: isExpanded)

            if isExpanded {
                VStack(spacing: Spacing.xs) {
                    ForEach(group.leaves) { leaf in
                        leafRow(leaf)
                    }
                }
                .padding(.leading, Sizing.iconInline + Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.inset)
    }

    private func groupHeader(
        _ group: CategoryDashboardPresentation.GroupRollup,
        isExpanded: Bool
    ) -> some View {
        let model = CategoryStatusBarModel(group: group)
        return Button {
            withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                toggle(group.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(leafCountText(group.leaves.count))
                        .microText()
                        .foregroundStyle(.secondary)

                    Spacer(minLength: Spacing.sm)
                }

                CategoryStatusBar(
                    model: model,
                    spentText: currency(group.spent),
                    limitText: group.monthlyLimit.map(currency),
                    accent: SemanticColors.brand
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(groupAccessibilityLabel(group, model: model))
        .accessibilityHint(isExpanded ? "Collapse group" : "Expand group")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Leaf row

    private func leafRow(_ leaf: CategoryDashboardPresentation.Leaf) -> some View {
        let model = CategoryStatusBarModel(leaf: leaf)
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: leaf.category.iconName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CategoryAccentTokens.color(for: leaf.category))
                    .frame(width: Sizing.iconInline)

                Text(leaf.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)
            }

            CategoryStatusBar(
                model: model,
                spentText: currency(leaf.spent),
                limitText: leaf.monthlyLimit.map(currency),
                accent: CategoryAccentTokens.color(for: leaf.category)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(leaf.category.displayName). \(model.accessibilityDescription(spentText: currency(leaf.spent), limitText: leaf.monthlyLimit.map(currency)))")
    }

    private var emptyState: some View {
        Label("No category spending yet", systemImage: "chart.pie")
            .microText()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Spacing.md)
    }

    // MARK: - Helpers

    private func toggle(_ id: String) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(
            amount,
            format: .compact,
            isEnabled: privacyMaskEnabled,
            style: .compact
        )
    }

    private func leafCountText(_ count: Int) -> String {
        "\(count) categor\(count == 1 ? "y" : "ies")"
    }

    private func groupAccessibilityLabel(
        _ group: CategoryDashboardPresentation.GroupRollup,
        model: CategoryStatusBarModel
    ) -> String {
        let body = model.accessibilityDescription(
            spentText: currency(group.spent),
            limitText: group.monthlyLimit.map(currency)
        )
        return "\(group.title) group, \(leafCountText(group.leaves.count)). \(body)"
    }
}
