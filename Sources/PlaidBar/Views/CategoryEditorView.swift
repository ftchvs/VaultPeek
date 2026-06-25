import PlaidBarCore
import SwiftUI

/// Settings/Budgets editor for budgeting-v2 categories & groups (AND-547).
///
/// Lets the user create/rename/recolor/re-emoji/reorder categories, define and
/// reorder groups, move categories between groups, and delete custom categories
/// (with their budgets reassigned, never orphaned). It is **opt-in**: until the user
/// taps "Enable custom categories" no v2 snapshot exists and v1 budgeting is
/// unchanged.
///
/// All logic lives in the pure `BudgetCategoryEditor` (Core, unit-tested) via
/// ``CategoryEditorModel``; this view only renders the schema and dispatches edits.
///
/// Accessibility: a category's identity is always carried by its **name text** and
/// SF Symbol/emoji glyph, never by its color swatch alone (ACCESSIBILITY.md). Edit
/// errors are shown as text. Dynamic Type is respected (system fonts, no fixed
/// frames on text).
struct CategoryEditorView: View {
    @Bindable var model: CategoryEditorModel

    /// The currently saved v1 budgets, carried forward when the user opts in so an
    /// existing budgeter keeps their numbers.
    let v1Budgets: [CategoryBudgetDTO]
    /// The current month as `YYYY-MM`, used to carry v1 budgets forward / recover on
    /// opt-out. Passed in (no hidden `Date()`).
    let currentMonth: String

    @State private var presentedSheet: EditorSheet?

    private enum EditorSheet: Identifiable {
        case newCategory(groupId: String)
        case editCategory(BudgetCategoryV2)
        case newGroup
        case renameGroup(BudgetCategoryGroupV2)

        var id: String {
            switch self {
            case .newCategory(let groupId): "new-cat-\(groupId)"
            case .editCategory(let category): "edit-cat-\(category.id)"
            case .newGroup: "new-group"
            case .renameGroup(let group): "rename-group-\(group.id)"
            }
        }
    }

    var body: some View {
        Group {
            if model.isOptedIn {
                editorList
            } else {
                optInPrompt
            }
        }
        .navigationTitle("Categories")
        .task { await model.load() }
        .sheet(item: $presentedSheet) { sheet in
            sheetContent(sheet)
        }
    }

    // MARK: - Opt-in prompt

    private var optInPrompt: some View {
        ContentUnavailableView {
            Label("Custom categories", systemImage: "folder.badge.gearshape")
        } description: {
            Text("""
            Rename, recolor, and reorganize your budget categories, or create your \
            own. Your current budgets carry over, and you can switch back anytime.
            """)
        } actions: {
            Button("Enable custom categories") {
                Task { await model.optIn(carryingForward: v1Budgets, month: currentMonth) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
    }

    // MARK: - Editor list

    private var editorList: some View {
        List {
            if let error = model.lastError {
                Section {
                    Label(message(for: error), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Edit error: \(message(for: error))")
                }
            }

            ForEach(model.orderedGroups) { group in
                groupSection(group)
            }

            Section {
                Button {
                    presentedSheet = .newGroup
                } label: {
                    Label("Add group", systemImage: "folder.badge.plus")
                }
                .disabled(model.isBusy)

                Button(role: .destructive) {
                    Task { await model.optOut(month: currentMonth) }
                } label: {
                    Label("Switch back to standard categories", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.isBusy)
            } footer: {
                Text("Switching back restores the standard categories and your saved budgets.")
            }
        }
        .listStyle(.inset)
    }

    private func groupSection(_ group: BudgetCategoryGroupV2) -> some View {
        Section {
            ForEach(model.categories(in: group)) { category in
                categoryRow(category)
            }
            .onMove { indices, newOffset in
                moveCategories(in: group, from: indices, to: newOffset)
            }

            Button {
                presentedSheet = .newCategory(groupId: group.id)
            } label: {
                Label("Add category", systemImage: "plus.circle")
                    .font(.callout)
            }
            .disabled(model.isBusy)
        } header: {
            HStack {
                Text(group.name)
                if group.isCustom {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Custom group")
                }
                Spacer()
                Menu {
                    Button("Rename group") { presentedSheet = .renameGroup(group) }
                    if group.isCustom {
                        Button("Delete group", role: .destructive) {
                            Task { await model.deleteCustomGroup(groupId: group.id) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Group options for \(group.name)")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func categoryRow(_ category: BudgetCategoryV2) -> some View {
        HStack(spacing: Spacing.sm) {
            glyph(for: category)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.body)
                Text(category.isCustom ? "Custom" : "Standard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit") { presentedSheet = .editCategory(category) }
                moveMenu(for: category)
                if category.isCustom {
                    Button("Delete", role: .destructive) {
                        Task { await model.deleteCustomCategory(categoryId: category.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Options for \(category.name)")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(category.name), \(category.isCustom ? "custom" : "standard") category"
        )
    }

    /// The category's leading glyph: its emoji when set, else its SF Symbol tinted by
    /// the category color. The color is a *redundant* accent — the name text and
    /// glyph always carry identity, so meaning is never color-alone.
    @ViewBuilder
    private func glyph(for category: BudgetCategoryV2) -> some View {
        if let emoji = category.emoji {
            Text(emoji)
                .font(.title3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: category.iconName)
                .font(.title3)
                .foregroundStyle(Color(budgetHex: category.colorHex) ?? .secondary)
                .accessibilityHidden(true)
        }
    }

    private func moveMenu(for category: BudgetCategoryV2) -> some View {
        Menu("Move to group") {
            ForEach(model.orderedGroups.filter { $0.id != category.groupId }) { group in
                Button(group.name) {
                    Task { await model.moveCategory(categoryId: category.id, toGroupId: group.id) }
                }
            }
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .newCategory(let groupId):
            CategoryFormSheet(mode: .create(groupId: groupId), model: model)
        case .editCategory(let category):
            CategoryFormSheet(mode: .edit(category), model: model)
        case .newGroup:
            GroupFormSheet(mode: .create, model: model)
        case .renameGroup(let group):
            GroupFormSheet(mode: .rename(group), model: model)
        }
    }

    // MARK: - Reorder

    private func moveCategories(in group: BudgetCategoryGroupV2, from indices: IndexSet, to newOffset: Int) {
        var ids = model.categories(in: group).map(\.id)
        ids.move(fromOffsets: indices, toOffset: newOffset)
        Task { await model.reorderCategories(groupId: group.id, orderedCategoryIds: ids) }
    }

    // MARK: - Error copy

    private func message(for error: BudgetCategoryEditor.BudgetCategoryEditError) -> String {
        switch error {
        case .emptyName: "Enter a name."
        case .nameTooLong: "That name is too long."
        case .duplicateCategoryName: "Another category in this group already uses that name."
        case .duplicateGroupName: "Another group already uses that name."
        case .invalidColor: "Choose a valid color."
        case .invalidEmoji: "Pick a single emoji."
        case .categoryNotFound: "That category no longer exists."
        case .groupNotFound: "That group no longer exists."
        case .cannotDeleteSystemCategory: "Standard categories can't be deleted — rename or recolor instead."
        case .cannotDeleteSystemGroup: "Standard groups can't be deleted."
        case .invalidReassignmentTarget: "Pick where to move this category's budget first."
        }
    }
}

// MARK: - Color(hex:) for v2 category swatches

extension Color {
    /// Build a SwiftUI `Color` from a `#RRGGBB` hex (the v2 category `colorHex`).
    /// Returns `nil` for a malformed string so the caller can fall back to a neutral
    /// tint — the color is always a redundant accent, never the sole carrier of
    /// meaning (ACCESSIBILITY.md).
    init?(budgetHex hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
