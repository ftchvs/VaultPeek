import PlaidBarCore
import SwiftUI

/// Set, edit, or clear a single category's current-month budget (AND-540).
///
/// This is the live half of category-budget editing — the first caller of the
/// previously-dead `AppState.setCategoryBudget` / `removeCategoryBudget`. Scope is
/// deliberately Option-A: one monthly limit per category, no per-month series and
/// no rollover (those are the deferred v2 epic, AND-524).
///
/// The sheet owns only its local text/validation state; persistence (server CRUD +
/// local cache + dashboard invalidation) lives in `AppState`. Validation is the
/// pure `BudgetEditorInput`, so the same rules are unit-tested without a view.
///
/// Accessibility: the validation verdict is always carried by text + an SF Symbol,
/// never color alone (ACCESSIBILITY.md); the field has an explicit value label.
struct BudgetEditorSheet: View {
    let category: SpendingCategory

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Raw text the user is editing. Seeded from the existing saved limit.
    @State private var amountText: String
    /// True while a save/clear network round-trip is in flight.
    @State private var isSaving = false

    init(category: SpendingCategory) {
        self.category = category
        // The field is seeded from the live saved limit in `onAppear`, once the
        // AppState environment is available; it starts empty.
        _amountText = State(initialValue: "")
    }

    /// Outcome of parsing the current field text, recomputed every render.
    private var outcome: BudgetEditorInput.Outcome {
        BudgetEditorInput.parse(amountText, category: category)
    }

    var body: some View {
        Form {
            Section {
                categoryHeader
            }

            if BudgetEditorInput.isBudgetable(category) {
                Section {
                    amountField
                } header: {
                    Text("Monthly limit")
                } footer: {
                    validationFooter
                }

                if let suggestedItem {
                    Section {
                        suggestedRow(suggestedItem)
                    } header: {
                        Text("Suggested")
                    }
                }
            } else {
                Section {
                    Label(
                        "Income and transfer categories can't have a budget.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 240)
        .navigationTitle("Edit Budget")
        .onAppear(perform: seedFromCurrentLimit)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveButtonTitle) { Task { await commit() } }
                    .disabled(!outcome.isCommittable || isSaving)
            }
        }
    }

    // MARK: - Sections

    private var categoryHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: category.iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.headline)
                if let currentLimit, currentLimit > 0 {
                    Text("Current limit \(Formatters.currency(currentLimit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No budget set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var amountField: some View {
        HStack(spacing: Spacing.xs) {
            Text("$")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("0", text: $amountText)
                .textFieldStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Monthly budget limit for \(category.displayName)")
                .accessibilityValue(amountText.isEmpty ? "No amount entered" : amountText)
        }
    }

    /// "Ghost guardrail" row: shows the history-derived suggested limit (and its
    /// current-month spend, carried by text) with a one-tap accept that promotes it
    /// to a saved budget. Tapping also seeds the field so the value is visible.
    private func suggestedRow(_ item: CategoryBudgetPresentation.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Based on recent spending")
                    .font(.callout)
                Text(
                    "\(Formatters.currency(item.spent)) spent so far this month"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.sm)
            SuggestedBudgetAcceptButton(
                item: item,
                existingBudgets: appState.categoryBudgets
            )
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var validationFooter: some View {
        switch outcome {
        case .invalid:
            Label("Enter a positive dollar amount.", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .clear:
            Label("Saving 0 removes this budget.", systemImage: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .save(let amount):
            Label(
                "Sets the monthly limit to \(Formatters.currency(amount)).",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .empty, .categoryNotBudgetable:
            // Offer the remove affordance when a budget already exists.
            if (currentLimit ?? 0) > 0 {
                Button(role: .destructive) {
                    Task { await remove() }
                } label: {
                    Label("Remove budget", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isSaving)
            } else {
                Text("Enter a monthly limit, or leave blank to keep none.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Derived state

    /// The category's currently-saved (explicit, non-suggested) limit, if any.
    private var currentLimit: Double? {
        appState.categoryBudgets[category]
    }

    /// The history-derived suggested guardrail for this category, if the dashboard
    /// is offering one and the user has not already saved a limit. Read from the
    /// live merged budget presentation (suggestions are flagged `isSuggested`); the
    /// pure `SuggestedBudgetAcceptance` decides whether a one-tap accept is legal.
    private var suggestedItem: CategoryBudgetPresentation.Item? {
        guard (currentLimit ?? 0) <= 0 else { return nil }
        return appState.categoryBudgetPresentation.items.first { item in
            item.category == category
                && SuggestedBudgetAcceptance.evaluate(
                    item: item,
                    existingBudgets: appState.categoryBudgets
                ).isAcceptable
        }
    }

    private var saveButtonTitle: String {
        outcome == .clear ? "Clear" : "Save"
    }

    // MARK: - Actions

    private func seedFromCurrentLimit() {
        guard amountText.isEmpty, let currentLimit, currentLimit > 0 else { return }
        // Whole-dollar limits read cleaner without trailing ".0".
        if currentLimit == currentLimit.rounded() {
            amountText = String(Int(currentLimit))
        } else {
            amountText = String(format: "%.2f", currentLimit)
        }
    }

    private func commit() async {
        guard !isSaving else { return }
        switch outcome {
        case .save(let amount):
            isSaving = true
            await appState.setCategoryBudget(category, amount: amount)
            isSaving = false
            if appState.error == nil { dismiss() }
        case .clear:
            await remove()
        case .empty, .invalid, .categoryNotBudgetable:
            break
        }
    }

    private func remove() async {
        guard !isSaving else { return }
        isSaving = true
        await appState.removeCategoryBudget(category)
        isSaving = false
        if appState.error == nil { dismiss() }
    }
}
