import PlaidBarCore
import SwiftUI

/// What the Goals editor sheet is doing: creating a fresh goal, or editing one.
/// `Identifiable` so it drives `.sheet(item:)`.
enum GoalEditorState: Identifiable {
    case creating
    case editing(Goal)

    var id: String {
        switch self {
        case .creating: "new"
        case let .editing(goal): goal.id.uuidString
        }
    }

    var existingGoal: Goal? {
        if case let .editing(goal) = self { return goal }
        return nil
    }
}

/// Create or edit a single ``Goal`` (AND-606).
///
/// The sheet owns only its local text/field state; validation is the pure
/// ``GoalEditorInput`` (unit-tested in Core), and persistence is the local-first
/// ``GoalsStore`` (writes `goals.json` under the app data dir — no server, no
/// Plaid). On save it folds the validated draft onto the existing goal (preserving
/// its id and `createdAt`) or constructs a new one.
///
/// Accessibility: the validation verdict is carried by text + an SF Symbol, never
/// color alone (ACCESSIBILITY.md). Window-first surface only — never mounted with
/// `WindowFirstFeatureFlag` OFF.
struct GoalEditorSheet: View {
    let state: GoalEditorState

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var nameText: String
    @State private var targetText: String
    @State private var contributedText: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var linkedCategory: SpendingCategory?
    @State private var isSaving = false

    private var store: GoalsStore { appState.goalsStore }

    init(state: GoalEditorState) {
        self.state = state
        let goal = state.existingGoal
        _nameText = State(initialValue: goal?.name ?? "")
        _targetText = State(initialValue: goal.map { Self.amountString($0.targetAmount) } ?? "")
        _contributedText = State(initialValue: goal.map { Self.amountString($0.contributedAmount) } ?? "")
        _hasTargetDate = State(initialValue: goal?.targetDate != nil)
        _targetDate = State(initialValue: goal?.targetDate ?? Self.defaultTargetDate)
        _linkedCategory = State(initialValue: goal?.linkedCategory)
    }

    private var outcome: GoalEditorInput.Outcome {
        GoalEditorInput.validate(
            nameText: nameText,
            targetText: targetText,
            contributedText: contributedText,
            targetDate: hasTargetDate ? targetDate : nil,
            linkedCategory: linkedCategory
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $nameText, prompt: Text("e.g. Emergency fund"))
                    .accessibilityLabel("Goal name")
            } header: {
                Text("Goal")
            }

            Section {
                LabeledContent("Target") {
                    TextField("0", text: $targetText, prompt: Text("0"))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .accessibilityLabel("Target amount")
                }
                LabeledContent("Saved so far") {
                    TextField("0", text: $contributedText, prompt: Text("0"))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .accessibilityLabel("Saved amount")
                }
            } header: {
                Text("Amount")
            } footer: {
                validationFooter
            }

            Section {
                Toggle("Set a target date", isOn: $hasTargetDate)
                if hasTargetDate {
                    DatePicker(
                        "Target date",
                        selection: $targetDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }
            }

            Section {
                Picker("Linked category", selection: $linkedCategory) {
                    Text("None").tag(SpendingCategory?.none)
                    ForEach(Self.linkableCategories, id: \.self) { category in
                        Label(category.displayName, systemImage: category.iconName)
                            .tag(SpendingCategory?.some(category))
                    }
                }
            } header: {
                Text("Category (optional)")
            } footer: {
                Text("Annotate which spending category this goal relates to. Display only — it doesn't change any spending math.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
        .navigationTitle(state.existingGoal == nil ? "New Goal" : "Edit Goal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await commit() } }
                    .disabled(!outcome.isCommittable || isSaving)
            }
        }
    }

    @ViewBuilder
    private var validationFooter: some View {
        if let message = outcome.message {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(SemanticColors.warning)
                .accessibilityLabel("Validation: \(message)")
        } else {
            Label("Looks good.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func commit() async {
        guard let draft = outcome.draft, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        if let existing = state.existingGoal {
            var updated = existing
            updated.name = draft.name
            updated.targetAmount = draft.targetAmount
            updated.contributedAmount = draft.contributedAmount
            updated.targetDate = draft.targetDate
            updated.linkedCategory = draft.linkedCategory
            await store.update(updated)
        } else {
            let goal = Goal(
                name: draft.name,
                targetAmount: draft.targetAmount,
                targetDate: draft.targetDate,
                linkedCategory: draft.linkedCategory,
                contributedAmount: draft.contributedAmount
            )
            await store.add(goal)
            appState.navigationModel.goalSelection = goal.id.uuidString
        }
        dismiss()
    }

    // MARK: - Helpers

    /// Categories that make sense to link a savings goal to (spend categories,
    /// excluding income/transfer flows).
    private static let linkableCategories: [SpendingCategory] = SpendingCategory.allCases.filter {
        switch $0 {
        case .income, .transfer, .transferOut: false
        default: true
        }
    }

    private static var defaultTargetDate: Date {
        Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    }

    /// Plain numeric seed for the amount fields (no currency symbol, so it round-
    /// trips cleanly through `GoalEditorInput.parseAmount`).
    private static func amountString(_ amount: Double) -> String {
        if amount == amount.rounded() {
            return String(Int(amount))
        }
        return String(format: "%.2f", amount)
    }
}

#if canImport(PreviewsMacros)
#Preview("New") {
    GoalEditorSheet(state: .creating)
        .environment(AppState())
}
#endif
