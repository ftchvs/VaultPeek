import PlaidBarCore
import SwiftUI

/// **Goals** destination (3-column — IA §3.1/§5.6, `[⌘5]`) — AND-606, net-new,
/// deferred from Epic 5 (ADR-001 window-first workspace).
///
/// Content column = the **goals list** (each row: name, progress bar + percent
/// text, on-track verdict) with an "Add goal" affordance; detail column = the
/// **selected goal's detail** (progress, remaining, pace, linked category) with
/// edit/delete controls. The detail column is **content-gated, not
/// existence-gated** (IA §3.1): with nothing selected it shows the "Select a goal"
/// prompt rather than collapsing.
///
/// **Local-first, app-local — no server, no Plaid:** goals are a net-new user
/// intention persisted as `goals.json` under the app data dir via ``GoalsStore``
/// (the same private-permissioned local-first pattern review metadata / merchant
/// rules use). The pure ``Goal`` value type and its progress math live in
/// `PlaidBarCore` and are unit-tested there; this file is presentation only.
///
/// Selection rides the per-window ``NavigationModel/goalSelection`` field (R-10 —
/// per-window scene state, **not** a selection singleton); the content and
/// inspector panes both read it through `appState.navigationModel`, so they share
/// one source of truth without a shared mutable singleton.
///
/// Progress and the on-track verdict are always carried by **text + SF Symbol**,
/// never color alone (ACCESSIBILITY.md). **Flag-OFF inert:** reached only when the
/// window-first `Window` opens (`WindowFirstFeatureFlag` ON); with the flag off
/// this file is never instantiated and the popover is byte-identical.
struct GoalsDestinationView: View {
    @Environment(AppState.self) private var appState
    @State private var editorState: GoalEditorState?

    private var store: GoalsStore { appState.goalsStore }
    private var navigationModel: NavigationModel { appState.navigationModel }
    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if !store.hasLoaded {
                loadingState
            } else if store.goals.isEmpty {
                emptyState
            } else {
                goalsList
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Goals")
                    .font(.title2.weight(.bold))
                Text("Set savings targets and track how close you are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Button {
                editorState = .creating
            } label: {
                Label("Add goal", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Create a new savings goal")
            .accessibilityHint("Opens the new-goal editor.")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - List

    private var goalsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(store.goals) { goal in
                    GoalRowView(
                        goal: goal,
                        isSelected: navigationModel.goalSelection == goal.id.uuidString,
                        isMasked: isMasked,
                        onSelect: { navigationModel.goalSelection = goal.id.uuidString }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Goals list, \(store.goals.count) goal\(store.goals.count == 1 ? "" : "s")")
    }

    // MARK: - Loading / empty states

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Goals. No goals yet. Create a savings goal to track progress.")
    }

    /// The detail-column (inspector) pane for Goals — the selected goal's detail,
    /// progress, pace, and edit/delete controls. Content-gated: shows the "Select a
    /// goal" prompt when nothing is selected (IA §3.1).
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
                    GoalDetailView(
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

// MARK: - Row

/// A single goal row: name, target, a labeled progress bar (percent text +
/// pace glyph), so meaning never rides color alone (ACCESSIBILITY.md).
private struct GoalRowView: View {
    let goal: Goal
    let isSelected: Bool
    let isMasked: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: goal.linkedCategory?.iconName ?? "flag.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Sizing.glyphSmall, height: Sizing.glyphSmall)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text("\(currency(goal.contributedAmount)) of \(currency(goal.targetAmount))")
                            .microText()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.xs)

                    Text("\(goal.percentComplete)%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                GoalProgressBar(goal: goal)

                paceLabel
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.rowVertical)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? SemanticColors.brand.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .nativeInsetSurface(stroke: isSelected ? SemanticColors.brand.opacity(0.28) : Color.primary.opacity(0.06))
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
                .microText()
                .foregroundStyle(.secondary)
        } else if pace != .noDeadline {
            Label(pace.label, systemImage: pace.systemImage)
                .microText()
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(goal.name), \(goal.percentComplete) percent funded"]
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
}

// MARK: - Progress bar

/// A determinate progress bar. The fraction is the *only* meaning carrier here;
/// the accompanying percent text in the row / detail makes it color-independent.
private struct GoalProgressBar: View {
    let goal: Goal

    var body: some View {
        ProgressView(value: goal.fractionComplete)
            .progressViewStyle(.linear)
            .tint(goal.isComplete ? SemanticColors.positive : SemanticColors.brand)
            .accessibilityHidden(true)
    }
}

// MARK: - Detail (inspector)

/// The selected goal's detail pane: progress, remaining, pace, linked category,
/// and edit/delete controls.
private struct GoalDetailView: View {
    let goal: Goal
    let isMasked: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                progressCard
                detailsCard
                actionsCard
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal detail. \(goal.name).")
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: goal.linkedCategory?.iconName ?? "flag.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline)
                    if let category = goal.linkedCategory {
                        Text(category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.sm)
            }
            .accessibilityElement(children: .combine)

            GoalProgressBar(goal: goal)

            HStack(alignment: .firstTextBaseline) {
                Text("\(goal.percentComplete)% funded")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                paceBadge
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    @ViewBuilder
    private var paceBadge: some View {
        let pace = goal.pace(asOf: Date())
        if goal.isComplete {
            Label("Funded", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SemanticColors.positive)
        } else if pace != .noDeadline {
            Label(pace.label, systemImage: pace.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(pace == .behind ? SemanticColors.warning : SemanticColors.positive)
                .accessibilityLabel("Pace: \(pace.label)")
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Details", systemImage: "list.bullet")
                .sectionTitle()
                .foregroundStyle(.secondary)

            detailRow("Saved", currency(goal.contributedAmount), systemImage: "banknote")
            detailRow("Target", currency(goal.targetAmount), systemImage: "target")
            detailRow("Remaining", currency(goal.remainingAmount), systemImage: "minus.circle")
            if let date = goal.targetDate {
                detailRow("Target date", Self.dateFormatter.string(from: date), systemImage: "calendar")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    private func detailRow(_ label: String, _ value: String, systemImage: String) -> some View {
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

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onEdit) {
                Label("Edit goal", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete goal", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    private func currency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: isMasked, style: .compact)
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
}

#Preview("Inspector") {
    GoalsDestinationView.Inspector()
        .environment(AppState())
}
