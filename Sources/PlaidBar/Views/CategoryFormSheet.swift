import PlaidBarCore
import SwiftUI

/// Create or edit a single budgeting-v2 category (AND-547).
///
/// A thin form over ``CategoryEditorModel``: it collects a name, optional emoji, and
/// a color, validates each field live via the pure ``BudgetCategoryEditor``
/// validators, and dispatches the create/edit. The model (and the Core editor it
/// delegates to) owns persistence and the authoritative duplicate/error rules; this
/// view only pre-flights the obvious field-level problems so Save stays enabled only
/// when the input is well-formed.
///
/// Accessibility: every field has an explicit label/value; the validation verdict is
/// carried by text (never color alone). A preset color is also labeled by name, so
/// the swatch grid is usable without color perception.
struct CategoryFormSheet: View {
    enum Mode {
        case create(groupId: String)
        case edit(BudgetCategoryV2)
    }

    let mode: Mode
    @Bindable var model: CategoryEditorModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var isSaving = false

    /// A small accessible palette of named presets (the v1 chart hues), so a user
    /// can pick a color without a system color well and each swatch reads by name.
    private static let presets: [(name: String, hex: String)] = [
        ("Coral", "#FF6B6B"), ("Teal", "#4ECDC4"), ("Sky", "#45B7D1"),
        ("Sage", "#96CEB4"), ("Butter", "#FFEAA7"), ("Lilac", "#DDA0DD"),
        ("Mint", "#98D8C8"), ("Gold", "#F7DC6F"), ("Violet", "#BB8FCE"),
        ("Tangerine", "#F8C471"), ("Spring", "#82E0AA"), ("Slate", "#AEB6BF"),
    ]

    init(mode: Mode, model: CategoryEditorModel) {
        self.mode = mode
        self.model = model
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _emoji = State(initialValue: "")
            _colorHex = State(initialValue: Self.presets[0].hex)
        case .edit(let category):
            _name = State(initialValue: category.name)
            _emoji = State(initialValue: category.emoji ?? "")
            _colorHex = State(initialValue: category.colorHex)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmoji: String { emoji.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether the current field values are well-formed enough to commit. The
    /// authoritative duplicate/exists checks still run in the model on save.
    private var isCommittable: Bool {
        guard BudgetCategoryEditor.validateName(trimmedName) == nil else { return false }
        guard BudgetCategoryEditor.isValidHexColor(colorHex) else { return false }
        if !trimmedEmoji.isEmpty, !BudgetCategoryEditor.isValidEmoji(trimmedEmoji) { return false }
        return true
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Category name", text: $name)
                    .accessibilityLabel("Category name")
            }

            Section {
                TextField("Emoji (optional)", text: $emoji)
                    .accessibilityLabel("Category emoji, optional")
                if !trimmedEmoji.isEmpty, !BudgetCategoryEditor.isValidEmoji(trimmedEmoji) {
                    Label("Use a single emoji, or leave it blank.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Emoji")
            } footer: {
                Text("Shown in place of the category icon.")
            }

            Section("Color") {
                colorPicker
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 320)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await commit() } }
                    .disabled(!isCommittable || isSaving)
            }
        }
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.sm) {
            ForEach(Self.presets, id: \.hex) { preset in
                Button {
                    colorHex = preset.hex
                } label: {
                    swatch(preset)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(colorHex.caseInsensitiveCompare(preset.hex) == .orderedSame ? [.isSelected] : [])
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func swatch(_ preset: (name: String, hex: String)) -> some View {
        let isSelected = colorHex.caseInsensitiveCompare(preset.hex) == .orderedSame
        return Circle()
            .fill(Color(budgetHex: preset.hex) ?? .secondary)
            .frame(width: 28, height: 28)
            .overlay {
                // Selection is shown by a redundant checkmark glyph, not color alone.
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
            }
            .overlay {
                Circle().strokeBorder(.primary.opacity(isSelected ? 0.6 : 0.15), lineWidth: isSelected ? 2 : 1)
            }
    }

    private var title: String {
        switch mode {
        case .create: "New Category"
        case .edit: "Edit Category"
        }
    }

    private func commit() async {
        guard !isSaving, isCommittable else { return }
        isSaving = true
        defer { isSaving = false }
        let emojiValue: String? = trimmedEmoji.isEmpty ? nil : trimmedEmoji

        switch mode {
        case .create(let groupId):
            await model.addCategory(
                name: trimmedName, emoji: emojiValue, colorHex: colorHex, groupId: groupId
            )
        case .edit(let category):
            await model.editCategory(
                categoryId: category.id,
                name: trimmedName,
                emoji: .some(emojiValue),
                colorHex: colorHex
            )
        }
        if model.lastError == nil { dismiss() }
    }
}

/// Create or rename a budgeting-v2 category group (AND-547).
struct GroupFormSheet: View {
    enum Mode {
        case create
        case rename(BudgetCategoryGroupV2)
    }

    let mode: Mode
    @Bindable var model: CategoryEditorModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSaving = false

    init(mode: Mode, model: CategoryEditorModel) {
        self.mode = mode
        self.model = model
        switch mode {
        case .create: _name = State(initialValue: "")
        case .rename(let group): _name = State(initialValue: group.name)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isCommittable: Bool { BudgetCategoryEditor.validateName(trimmedName) == nil }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Group name", text: $name)
                    .accessibilityLabel("Group name")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 340, minHeight: 160)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await commit() } }
                    .disabled(!isCommittable || isSaving)
            }
        }
    }

    private var title: String {
        switch mode {
        case .create: "New Group"
        case .rename: "Rename Group"
        }
    }

    private func commit() async {
        guard !isSaving, isCommittable else { return }
        isSaving = true
        defer { isSaving = false }
        switch mode {
        case .create:
            await model.addGroup(name: trimmedName)
        case .rename(let group):
            await model.renameGroup(groupId: group.id, name: trimmedName)
        }
        if model.lastError == nil { dismiss() }
    }
}
