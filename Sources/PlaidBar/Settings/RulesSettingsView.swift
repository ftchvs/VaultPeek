import PlaidBarCore
import SwiftUI

/// Settings surface that lets the user manage categorization rules — list, edit,
/// and delete the `TransactionRule`s that were previously create-only inline
/// (AND-551, DEFERRED v2 / AND-524).
///
/// Thin renderer over `TransactionRuleManager`: that pure type owns the display
/// order, the match/effect copy, and the conflict (shadowing) detection, so the
/// view never re-derives "which rule wins". Mutations route through
/// `AppState.updateTransactionRule` / `deleteTransactionRule`, which reuse the
/// existing rule store and persistence path. Deleting a rule does **not**
/// retroactively un-review past transactions (AC #2) — `AppState` leaves review
/// metadata untouched.
///
/// Privacy: rule text (matchers, categories, renames) carries no balances or
/// amounts, but the surface is still suppressed under Privacy Mask / App Lock as
/// defense in depth, matching every other financial surface.
struct RulesSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var editing: EditingRule?
    @State private var pendingDeletion: TransactionRule?

    private var rows: [TransactionRuleManager.RuleRow] {
        TransactionRuleManager.rows(for: appState.transactionRules)
    }

    var body: some View {
        Group {
            if appState.shouldMaskFinancialValues {
                maskedState
            } else if rows.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { editingRule in
            RuleEditorSheet(
                draft: editingRule.rule,
                isNew: editingRule.isNew,
                onSave: { appState.updateTransactionRule($0) }
            )
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { rule in
            Button("Delete Rule", role: .destructive) {
                appState.deleteTransactionRule(id: rule.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text(
                "Removes the “\(TransactionRuleManager.shortLabel(for: rule))” rule. Transactions you have already reviewed stay reviewed — deleting a rule never re-opens past transactions. New transactions will no longer match this rule."
            )
        }
    }

    // MARK: - List

    private var ruleList: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    RuleRowView(row: row) {
                        editing = EditingRule(rule: row.rule, isNew: false)
                    } onDelete: {
                        pendingDeletion = row.rule
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules automatically recategorize, rename, mark as transfer, or exclude matching transactions. When two rules match the same transaction, the most recently created one wins for any field they both set; an overridden rule is flagged below.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button {
                    editing = EditingRule(rule: TransactionRule(), isNew: true)
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Empty / masked states

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rules Yet", systemImage: "wand.and.stars")
        } description: {
            Text("Rules recategorize, rename, or exclude transactions automatically. Create one here, or from the Review inbox when you correct a transaction.")
        } actions: {
            Button {
                editing = EditingRule(rule: TransactionRule(), isNew: true)
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var maskedState: some View {
        ContentUnavailableView {
            Label(
                appState.isContentLocked ? "Locked" : "Hidden by Privacy Mask",
                systemImage: appState.isContentLocked ? "lock" : "eye.slash"
            )
        } description: {
            Text(
                appState.isContentLocked
                    ? "Unlock VaultPeek to manage your categorization rules."
                    : "Turn off Privacy Mask to manage your categorization rules."
            )
        }
    }
}

/// Identifies the rule being edited, distinguishing a brand-new draft (which
/// `AppState` appends) from an edit of an existing rule (whose `id`/`createdAt` are
/// preserved). `id` is the rule's id so the `.sheet(item:)` re-presents correctly.
private struct EditingRule: Identifiable {
    let rule: TransactionRule
    let isNew: Bool
    var id: UUID { rule.id }
}

// MARK: - Row

private struct RuleRowView: View {
    let row: TransactionRuleManager.RuleRow
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.matchDescription)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                Button("Edit", action: onEdit)
                    .controlSize(.small)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .accessibilityLabel("Delete rule")
            }

            if row.effects.isEmpty {
                Text("No effect")
                    .detailText()
            } else {
                effectChips
            }

            if row.isShadowed {
                shadowWarning
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap Edit to change, or Delete to remove this rule.")
    }

    private var effectChips: some View {
        // Wrapping rows of text+icon chips. Meaning is in the text; the icon and
        // any tint are decoration only (ACCESSIBILITY.md). Reuses the shared
        // wrapping layout from the Insights surface.
        InsightsFlowLayout(spacing: Spacing.xs) {
            ForEach(Array(row.effects.enumerated()), id: \.offset) { _, effect in
                Label(effect.label, systemImage: effect.systemImage)
                    .font(.caption.weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.chipVertical)
                    .background(.quinary, in: Capsule())
            }
        }
    }

    private var shadowWarning: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(row.shadowedFields) { conflict in
                Label {
                    Text("\(conflict.field.displayName) is overridden by the “\(conflict.winningRuleLabel)” rule.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SemanticColors.warning)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [row.matchDescription]
        if row.effects.isEmpty {
            parts.append("No effect")
        } else {
            parts.append(contentsOf: row.effects.map(\.label))
        }
        for conflict in row.shadowedFields {
            parts.append("\(conflict.field.displayName) overridden by the \(conflict.winningRuleLabel) rule")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Editor

private struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var matchMerchant: String
    @State private var matchOriginalName: String
    @State private var hasCategory: Bool
    @State private var category: SpendingCategory
    @State private var renameEnabled: Bool
    @State private var renameTo: String
    @State private var transferChoice: TriState
    @State private var excludeChoice: TriState

    private let originalRule: TransactionRule
    let isNew: Bool
    let onSave: (TransactionRule) -> Void

    /// Three-state toggle for the optional `Bool?` rule fields: leave unset, set
    /// true, or set false. Modeling them as `Bool?` (rather than a plain `Toggle`)
    /// keeps the additive contract — a rule that never set transfer/exclusion is
    /// stored exactly the same after a round-trip through the editor.
    private enum TriState: String, CaseIterable, Identifiable {
        case unset
        case on
        case off
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unset: "No change"
            case .on: "Yes"
            case .off: "No"
            }
        }
        var boolValue: Bool? {
            switch self {
            case .unset: nil
            case .on: true
            case .off: false
            }
        }
        init(_ value: Bool?) {
            switch value {
            case .none: self = .unset
            case .some(true): self = .on
            case .some(false): self = .off
            }
        }
    }

    init(draft: TransactionRule, isNew: Bool, onSave: @escaping (TransactionRule) -> Void) {
        self.originalRule = draft
        self.isNew = isNew
        self.onSave = onSave
        _matchMerchant = State(initialValue: draft.matchMerchantContains ?? "")
        _matchOriginalName = State(initialValue: draft.matchOriginalNameContains ?? "")
        _hasCategory = State(initialValue: draft.category != nil)
        _category = State(initialValue: draft.category ?? .foodAndDrink)
        _renameEnabled = State(initialValue: (draft.merchantName?.isEmpty == false))
        _renameTo = State(initialValue: draft.merchantName ?? "")
        _transferChoice = State(initialValue: TriState(draft.isTransfer))
        _excludeChoice = State(initialValue: TriState(draft.excludedFromBudgets))
    }

    private var composedRule: TransactionRule {
        TransactionRule(
            id: originalRule.id,
            matchMerchantContains: matchMerchant,
            matchOriginalNameContains: matchOriginalName,
            category: hasCategory ? category : nil,
            merchantName: renameEnabled ? renameTo : nil,
            isTransfer: transferChoice.boolValue,
            excludedFromBudgets: excludeChoice.boolValue,
            createdAt: originalRule.createdAt
        )
    }

    private var validationProblems: [TransactionRuleManager.ValidationProblem] {
        TransactionRuleManager.validate(TransactionRuleManager.normalized(composedRule))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Merchant contains", text: $matchMerchant, prompt: Text("e.g. Starbucks"))
                    TextField("Description contains", text: $matchOriginalName, prompt: Text("e.g. SQ *"))
                } header: {
                    Text("Match when")
                } footer: {
                    Text("A transaction matches if either field is contained in its merchant or description (case-insensitive). Fill at least one.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Then") {
                    Toggle("Set category", isOn: $hasCategory)
                    if hasCategory {
                        Picker("Category", selection: $category) {
                            ForEach(SpendingCategory.allCases, id: \.self) { option in
                                Label(option.displayName, systemImage: option.iconName).tag(option)
                            }
                        }
                    }

                    Toggle("Rename merchant", isOn: $renameEnabled)
                    if renameEnabled {
                        TextField("Display name", text: $renameTo, prompt: Text("e.g. Coffee"))
                    }

                    Picker("Mark as transfer", selection: $transferChoice) {
                        ForEach(TriState.allCases) { Text($0.title).tag($0) }
                    }

                    Picker("Exclude from budgets", selection: $excludeChoice) {
                        ForEach(TriState.allCases) { Text($0.title).tag($0) }
                    }
                }

                if !validationProblems.isEmpty {
                    Section {
                        ForEach(validationProblems, id: \.self) { problem in
                            Label {
                                Text(problem.message)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(SemanticColors.warning)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") {
                    onSave(composedRule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!validationProblems.isEmpty)
            }
            .padding(Spacing.md)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 480)
    }
}
