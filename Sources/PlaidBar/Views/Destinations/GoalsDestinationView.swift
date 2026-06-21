import PlaidBarCore
import SwiftUI

/// **Goals** destination (3-column — IA §3.1/§5.6, `[⌘5]`) — AND-606 / AND-624
/// window-first redesign.
///
/// Re-hosts the goals data in the desk-distance **window-scale** language the
/// Dashboard reference sets (``WindowMetrics`` / ``WindowTypography``), not the
/// compact popover scale: the content column leads with a **goals summary hero
/// row** (total saved / total target / overall progress, as large tabular
/// figures via ``WindowHeroMetricTile``) above a **goals list** of generous rows
/// with large labeled progress bars; the detail column re-hosts the selected
/// goal's detail as ``WindowSection`` cards with the editor sheet.
///
/// **No model logic lives here.** Every figure is the pure, Core-tested ``Goal``
/// /``GoalsSummary`` math (`fractionComplete`, `percentComplete`, `pace(asOf:)`,
/// `GoalsSummary.make`); persistence is the local-first ``GoalsStore`` and edits
/// route through the unchanged ``GoalEditorSheet``. The hero row and Planning's
/// goals overview read the *same* `GoalsSummary`, so they can never disagree.
///
/// The detail column is **content-gated, not existence-gated** (IA §3.1): with
/// nothing selected it shows the "Select a goal" prompt rather than collapsing.
/// Selection rides the per-window ``NavigationModel/goalSelection`` field (R-10),
/// shared by the content and inspector panes without a selection singleton.
///
/// Progress and the on-track verdict are always carried by **text + SF Symbol**,
/// never color alone (ACCESSIBILITY.md); data surfaces stay solid (Liquid Glass
/// on chrome only, ADR-001 / R-08); figures honor Privacy Mask, and App Lock is
/// shell-gated so this canvas never double-gates. **Flag-OFF inert:** reached
/// only when the window-first `Window` opens (`WindowFirstFeatureFlag` ON); with
/// the flag off this file is never instantiated and the popover is byte-identical.
struct GoalsDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editorState: GoalEditorState?

    private var store: GoalsStore { appState.goalsStore }
    private var navigationModel: NavigationModel { appState.navigationModel }
    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                if !store.hasLoaded {
                    loadingState
                } else if store.goals.isEmpty {
                    emptyState
                } else {
                    summaryHeroRow
                    goalsListSection
                }
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(RouteDestination.goals.title)
        .task { await store.loadIfNeeded() }
        // Self-heal: a deleted goal must not linger selected.
        .onChange(of: store.goals.map(\.id)) { _, _ in
            navigationModel.reconcileGoalSelection(visibleGoalIDs: store.goals.map(\.id.uuidString))
        }
        .sheet(item: $editorState) { state in
            GoalEditorSheet(state: state)
                .environment(appState)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Summary hero row

    /// The headline figures across the top of the content column — total saved,
    /// total target, and overall progress — as large tabular figures (the same
    /// `GoalsSummary` Planning previews, so the two surfaces never disagree).
    /// Reflows to wrap on a narrow window so each figure keeps its tabular
    /// legibility; every value honors Privacy Mask and none rely on color for
    /// meaning (the label names the figure).
    private var summaryHeroRow: some View {
        let summary = GoalsSummary.make(from: store.goals)
        return VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: WindowMetrics.heroTileMinWidth), spacing: WindowMetrics.lg)],
                alignment: .leading,
                spacing: WindowMetrics.lg
            ) {
                WindowHeroMetricTile(
                    label: "Total saved",
                    value: currency(summary.totalSaved),
                    systemImage: "banknote",
                    detail: savedDetail(summary),
                    accent: SemanticColors.brand,
                    reduceMotion: reduceMotion
                )
                WindowHeroMetricTile(
                    label: "Total target",
                    value: currency(summary.totalTarget),
                    systemImage: "target",
                    detail: targetDetail(summary),
                    accent: .secondary,
                    reduceMotion: reduceMotion
                )
                WindowHeroMetricTile(
                    label: "Overall progress",
                    value: percent(summary.overallPercent),
                    systemImage: "chart.bar.fill",
                    detail: remainingDetail(summary),
                    accent: SemanticColors.positive,
                    reduceMotion: reduceMotion
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(summaryAccessibilityLabel(summary))

            GoalsOverallProgressBar(
                fraction: summary.overallFraction,
                isComplete: false,
                isMasked: isMasked
            )
        }
    }

    private func savedDetail(_ summary: GoalsSummary) -> String {
        let goals = summary.goalCount == 1 ? "1 goal" : "\(summary.goalCount) goals"
        if summary.fundedCount > 0 {
            return "\(goals) · \(summary.fundedCount) funded"
        }
        return "Across \(goals)"
    }

    private func targetDetail(_ summary: GoalsSummary) -> String {
        if summary.behindCount > 0 {
            return summary.behindCount == 1 ? "1 goal behind pace" : "\(summary.behindCount) goals behind pace"
        }
        return "Everything on pace"
    }

    private func remainingDetail(_ summary: GoalsSummary) -> String {
        // Per-goal-clamped remaining — an over-funded goal can't mask another
        // goal's shortfall (matches each row's `Goal.remainingAmount`).
        let remaining = summary.totalRemaining
        return "\(currency(remaining)) remaining"
    }

    private func summaryAccessibilityLabel(_ summary: GoalsSummary) -> String {
        var parts = ["Goals summary", "\(percent(summary.overallPercent)) overall"]
        parts.append("\(currency(summary.totalSaved)) saved of \(currency(summary.totalTarget)) target")
        if summary.fundedCount > 0 { parts.append("\(summary.fundedCount) funded") }
        if summary.behindCount > 0 { parts.append("\(summary.behindCount) behind pace") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Goals list

    /// The list of goals in one titled ``WindowSection`` card — each row a
    /// generous, full-width entry with a large labeled progress bar. The
    /// "Add goal" affordance lives in the section header accessory.
    private var goalsListSection: some View {
        WindowSection("Your goals", systemImage: "flag.checkered") {
            Button {
                editorState = .creating
            } label: {
                Label("Add goal", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Create a new savings goal")
            .accessibilityHint("Opens the new-goal editor.")
        } content: {
            VStack(spacing: WindowMetrics.sm) {
                ForEach(store.goals) { goal in
                    GoalListRow(
                        goal: goal,
                        isSelected: navigationModel.goalSelection == goal.id.uuidString,
                        isMasked: isMasked,
                        onSelect: { navigationModel.goalSelection = goal.id.uuidString }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Goals list, \(store.goals.count) goal\(store.goals.count == 1 ? "" : "s")")
        }
    }

    // MARK: - Loading / empty states

    private var loadingState: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 240)
            .accessibilityLabel("Loading goals")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No goals yet", systemImage: "flag.checkered")
        } description: {
            Text("Create a savings goal to set a target and track your progress toward it.")
        } actions: {
            Button {
                editorState = .creating
            } label: {
                Label("Add goal", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityLabel("Goals. No goals yet. Create a savings goal to track progress.")
    }

    // MARK: - Helpers

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(amount, format: .compact, isEnabled: isMasked)
    }

    private func percent(_ value: Int) -> String {
        PrivacyMaskPresentation.percent(Double(value), decimals: 0, isEnabled: isMasked)
    }

    /// The detail-column (inspector) pane for Goals — the selected goal's detail,
    /// progress, pace, and edit/delete controls, at window scale. Content-gated:
    /// shows the "Select a goal" prompt when nothing is selected (IA §3.1).
    struct Inspector: View {
        @Environment(AppState.self) private var appState
        @State private var editorState: GoalEditorState?

        private var store: GoalsStore { appState.goalsStore }
        private var navigationModel: NavigationModel { appState.navigationModel }
        private var isMasked: Bool { appState.shouldMaskFinancialValues }

        private var selectedGoal: Goal? {
            guard let id = UUID(uuidString: navigationModel.goalSelection) else { return nil }
            return store.goal(id: id)
        }

        var body: some View {
            Group {
                if let goal = selectedGoal {
                    GoalDetailPane(
                        goal: goal,
                        isMasked: isMasked,
                        onEdit: { editorState = .editing(goal) },
                        onDelete: { delete(goal) }
                    )
                } else {
                    emptyPrompt
                }
            }
            .task { await store.loadIfNeeded() }
            .sheet(item: $editorState) { state in
                GoalEditorSheet(state: state)
                    .environment(appState)
            }
        }

        private func delete(_ goal: Goal) {
            navigationModel.deselectGoal()
            Task { await store.delete(id: goal.id) }
        }

        private var emptyPrompt: some View {
            ContentUnavailableView {
                Label(
                    RouteDestination.goals.detailColumnEmptyPrompt ?? "Select a goal",
                    systemImage: RouteDestination.goals.systemImage
                )
            } description: {
                Text("Choose a goal from the list to see its progress and edit it here.")
            }
            .accessibilityLabel("Select a goal to see its detail.")
        }
    }
}

// MARK: - List row

/// A single goal row at window scale: a leading category glyph, the goal name +
/// saved-of-target line, the percent figure, a large labeled progress bar, and
/// the pace verdict — so meaning never rides color alone (ACCESSIBILITY.md).
private struct GoalListRow: View {
    let goal: Goal
    let isSelected: Bool
    let isMasked: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                    Image(systemName: goal.linkedCategory?.iconName ?? "flag.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .windowCardTitle()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("\(currency(goal.contributedAmount)) of \(currency(goal.targetAmount))")
                            .windowSupportingText()
                            .lineLimit(1)
                    }

                    Spacer(minLength: WindowMetrics.sm)

                    Text(percent(goal.percentComplete))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                GoalProgressBar(goal: goal, isMasked: isMasked)

                paceLabel
            }
            .padding(WindowMetrics.md)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? SemanticColors.brand.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius)
                .stroke(
                    isSelected ? SemanticColors.brand.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the goal detail.")
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

// MARK: - Progress bars

/// A determinate per-goal progress bar. The fraction is the *only* meaning
/// carrier here; the accompanying percent text in the row / detail makes it
/// color-independent (ACCESSIBILITY.md).
private struct GoalProgressBar: View {
    let goal: Goal
    let isMasked: Bool

    @ViewBuilder
    var body: some View {
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
}

/// The aggregate progress bar under the summary hero row. Color-independent —
/// the overall percent in the hero tile carries the meaning in text.
private struct GoalsOverallProgressBar: View {
    let fraction: Double
    let isComplete: Bool
    let isMasked: Bool

    @ViewBuilder
    var body: some View {
        if isMasked {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.secondary)
                .accessibilityHidden(true)
        } else {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(isComplete ? SemanticColors.positive : SemanticColors.brand)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Detail (inspector) pane

/// The selected goal's detail at window scale: a prominent progress card, a
/// details card, and an actions card — all ``WindowSection``-style solid
/// surfaces, with the on-track verdict carried by text + SF Symbol.
private struct GoalDetailPane: View {
    let goal: Goal
    let isMasked: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowMetrics.lg) {
                progressCard
                detailsCard
                actionsCard
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal detail. \(goal.name).")
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                Image(systemName: goal.linkedCategory?.iconName ?? "flag.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .windowCardTitle()
                    if let category = goal.linkedCategory {
                        Text(category.displayName)
                            .windowSupportingText()
                    }
                }
                Spacer(minLength: WindowMetrics.sm)
            }
            .accessibilityElement(children: .combine)

            Text(currency(goal.contributedAmount))
                .windowHeroMetric()
                .rollingTabularNumber(currency(goal.contributedAmount), reduceMotion: reduceMotion)
                .foregroundStyle(AppearanceTextColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Saved \(currency(goal.contributedAmount))")

            GoalProgressBar(goal: goal, isMasked: isMasked)

            HStack(alignment: .firstTextBaseline) {
                Text("\(percent(goal.percentComplete)) funded")
                    .windowDataText()
                Spacer()
                paceBadge
            }
            .accessibilityElement(children: .combine)
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCardSurface()
    }

    @ViewBuilder
    private var paceBadge: some View {
        let pace = goal.pace(asOf: Date())
        if goal.isComplete {
            Label("Funded", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SemanticColors.positive)
        } else if pace != .noDeadline {
            Label(pace.label, systemImage: pace.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pace == .behind ? SemanticColors.warning : SemanticColors.positive)
                .accessibilityLabel("Pace: \(pace.label)")
        }
    }

    private var detailsCard: some View {
        WindowSection("Details", systemImage: "list.bullet") {
            detailRow("Saved", currency(goal.contributedAmount), systemImage: "banknote")
            detailRow("Target", currency(goal.targetAmount), systemImage: "target")
            detailRow("Remaining", currency(goal.remainingAmount), systemImage: "minus.circle")
            if let date = goal.targetDate {
                detailRow("Target date", Self.dateFormatter.string(from: date), systemImage: "calendar")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, systemImage: String) -> some View {
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

    private var actionsCard: some View {
        WindowSection("Manage", systemImage: "slider.horizontal.3") {
            HStack(spacing: WindowMetrics.sm) {
                Button(action: onEdit) {
                    Label("Edit goal", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .confirmationDialog(
                    "Delete \"\(goal.name)\"?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete goal", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the goal and its tracked progress. This can't be undone.")
                }
            }
        }
    }

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: isMasked, style: .compact)
    }

    private func percent(_ value: Int) -> String {
        PrivacyMaskPresentation.percent(Double(value), decimals: 0, isEnabled: isMasked)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

#Preview("Content") {
    GoalsDestinationView()
        .environment(AppState())
        .frame(width: 720, height: 600)
}

#Preview("Inspector") {
    GoalsDestinationView.Inspector()
        .environment(AppState())
        .frame(width: 360, height: 600)
}
