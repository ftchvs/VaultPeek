import PlaidBarCore
import SwiftUI

/// The window-first **Dashboard** savings-goals glance card (AND-730).
///
/// Goals were previously invisible until you navigated to the Goals workspace.
/// This card surfaces the top few goals — name, a labeled progress bar, the
/// saved-of-target figure, and the percent — directly on the dashboard's
/// "Money & insights" column, with an **Open Goals** affordance that deep-links to
/// ``RouteDestination/goals``.
///
/// Surface only — every figure is the pure, Core-tested ``Goal`` /
/// ``DashboardGoalsPreview`` math (`fractionComplete`, `percentComplete`,
/// `pace(asOf:)`, the top-N ordering); persistence is the same local-first
/// ``GoalsStore`` the Goals workspace reads, so the two can never disagree. The
/// card lazily triggers `loadIfNeeded()` on appear (the dashboard does not
/// otherwise touch goals storage).
///
/// When there are **no goals**, it shows a quiet "set a savings goal" empty
/// affordance with an Open Goals action rather than self-hiding, so the dashboard
/// grid keeps a uniform card rather than a hole and offers a next step.
///
/// Progress is always carried by **text + the bar**, never color alone
/// (ACCESSIBILITY.md); amounts honor Privacy Mask (`PrivacyMaskPresentation`).
/// **Flag-OFF inert:** reached only inside the window-first dashboard; the
/// popover never instantiates it.
struct DashboardGoalsCard: View {
    @Environment(AppState.self) private var appState
    /// Deep-links to the Goals workspace.
    let onOpen: () -> Void

    private var store: GoalsStore { appState.goalsStore }
    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        WindowSection("Goals", systemImage: "target") {
            openButton
        } content: {
            if !store.hasLoaded {
                loadingState
            } else if store.goals.isEmpty {
                emptyState
            } else {
                let preview = DashboardGoalsPreview.make(from: store.goals)
                VStack(alignment: .leading, spacing: WindowMetrics.md) {
                    ForEach(preview.goals) { goal in
                        DashboardGoalRow(goal: goal, isMasked: isMasked)
                    }
                    if let overflow = preview.overflowLabel {
                        Button(action: onOpen) {
                            Text("+ \(overflow)")
                                .windowSupportingText()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the Goals workspace to see all goals.")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .task { await store.loadIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    /// The header "Open Goals" affordance — routes to the Goals workspace.
    private var openButton: some View {
        Button(action: onOpen) {
            Label("Open Goals", systemImage: "arrow.up.right")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Open the Goals workspace")
        .accessibilityHint("Opens the Goals workspace.")
    }

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 60)
            .accessibilityLabel("Loading goals")
    }

    /// A quiet empty affordance — a prompt + an Open Goals action — rather than a
    /// broken/blank card or a self-hide that would leave a hole in the grid.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            Label("Set a savings goal", systemImage: "flag.checkered")
                .windowDataText()
            Text("Track a target like an emergency fund and watch your progress here.")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpen) {
                Label("Open Goals", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goals. Set a savings goal to track your progress. Opens the Goals workspace.")
    }
}

// MARK: - Compact goal row

/// A compact dashboard goal row: the goal name + percent on one line, a labeled
/// progress bar, and the saved-of-target figure with the pace verdict. Meaning is
/// carried by text + the bar, never color alone (ACCESSIBILITY.md); amounts honor
/// Privacy Mask.
private struct DashboardGoalRow: View {
    let goal: Goal
    let isMasked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                Image(systemName: goal.linkedCategory?.iconName ?? "flag.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(goal.name)
                    .windowCardTitle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: WindowMetrics.sm)
                Text(percent(goal.percentComplete))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            progressBar

            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                Text("\(currency(goal.contributedAmount)) of \(currency(goal.targetAmount))")
                    .windowSupportingText()
                    .lineLimit(1)
                Spacer(minLength: WindowMetrics.sm)
                paceLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var progressBar: some View {
        if isMasked {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.secondary)
                .accessibilityHidden(true)
        } else {
            ProgressView(value: goal.fractionComplete)
                .progressViewStyle(.linear)
                .tint(goal.isComplete ? SemanticColors.positive : SemanticColors.brand)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var paceLabel: some View {
        let pace = goal.pace(asOf: Date())
        if goal.isComplete {
            Label("Funded", systemImage: "checkmark.seal.fill")
                .windowSupportingText()
        } else if pace != .noDeadline {
            Label(pace.label, systemImage: pace.systemImage)
                .windowSupportingText()
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(goal.name), \(percent(goal.percentComplete)) funded"]
        parts.append("\(currency(goal.contributedAmount)) of \(currency(goal.targetAmount))")
        if goal.isComplete {
            parts.append("Funded")
        } else {
            let pace = goal.pace(asOf: Date())
            if pace != .noDeadline { parts.append(pace.label) }
        }
        return parts.joined(separator: ". ")
    }

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: isMasked, style: .compact)
    }

    private func percent(_ value: Int) -> String {
        PrivacyMaskPresentation.percent(Double(value), decimals: 0, isEnabled: isMasked)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    DashboardGoalsCard(onOpen: {})
        .environment(AppState())
        .padding()
        .frame(width: 360)
}
#endif
