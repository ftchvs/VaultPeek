import Foundation

/// Pure, deterministic CRUD + validation for the budgeting-v2 categories &
/// groups editor (AND-547 — deferred epic AND-524).
///
/// All the *logic* of the editor lives here as a stateless `enum` so it stays
/// `Sendable`, has no hidden `Date()`/UUID/I/O (callers pass identity in), and is
/// fully unit-testable in `PlaidBarCore`. The Settings/Budgets editor UI is a thin
/// shell that calls these functions and persists the returned ``BudgetingV2Schema``
/// snapshot via `PlaidBarCache.BudgetingV2Store`.
///
/// ## What it edits
/// Every function takes the current ``BudgetingV2Schema`` and returns either a
/// **new** schema (value semantics — the input is never mutated) or a
/// ``BudgetCategoryEditError``. It covers the four AND-547 acceptance criteria:
/// 1. **Create a custom category** with name + emoji + color + group.
/// 2. **Rename / recolor / re-emoji** a category — including a *system* one —
///    **without breaking its `systemKey → Plaid` mapping** (``seededFromCategory``
///    is preserved verbatim; only presentation fields change).
/// 3. **Create / rename / reorder groups** and **move categories between groups**.
/// 4. **Delete a custom category**, **reassigning its budgets** to a fallback so no
///    spend is orphaned (a seeded *system* category is never deletable).
///
/// ## v1-safety contract
/// The editor only ever rewrites the **v2 snapshot** (an opt-in, disposable cache).
/// It never touches ``SpendingCategory`` `rawValue`s, the v1 ``CategoryBudgetDTO``
/// store, or `/api/budgets`. A user who has not opted into v2 never reaches this
/// code, so v1 budgeting is byte-for-byte unchanged.
public enum BudgetCategoryEditor {
    // MARK: - Identity prefixes

    /// Prefix for a user-created category id, e.g. `"cat_<uuid>"`. Keeps a custom id
    /// from ever colliding with — or being mistaken for — a Plaid `rawValue`
    /// (``SpendingCategory``), which is always uppercase letters/underscores.
    public static let customCategoryIDPrefix = "cat_"
    /// Prefix for a user-created group id, e.g. `"grp_<uuid>"`. Same rationale.
    public static let customGroupIDPrefix = "grp_"

    /// Build a stable custom-category id from a caller-supplied unique token (a UUID
    /// string at the call site — kept out of this pure layer so it stays testable).
    public static func customCategoryID(_ token: String) -> String {
        customCategoryIDPrefix + token
    }

    /// Build a stable custom-group id from a caller-supplied unique token.
    public static func customGroupID(_ token: String) -> String {
        customGroupIDPrefix + token
    }

    // MARK: - Errors

    /// Why an edit was rejected. Surfaced to the editor UI as a redundant
    /// text-carried message (never color-alone, ACCESSIBILITY.md).
    public enum BudgetCategoryEditError: Error, Sendable, Hashable {
        /// The name was empty (after trimming) or only whitespace.
        case emptyName
        /// The name is too long (> ``maxNameLength`` characters).
        case nameTooLong
        /// Another category in the same group already uses this name (case-insensitive).
        case duplicateCategoryName
        /// Another group already uses this name (case-insensitive).
        case duplicateGroupName
        /// The color string is not a valid `#RRGGBB` hex.
        case invalidColor
        /// The emoji is not a single emoji grapheme.
        case invalidEmoji
        /// The referenced category id does not exist in the snapshot.
        case categoryNotFound
        /// The referenced group id does not exist in the snapshot.
        case groupNotFound
        /// A system (seeded) category cannot be deleted — only renamed/recolored.
        case cannotDeleteSystemCategory
        /// A system (seeded) group cannot be deleted.
        case cannotDeleteSystemGroup
        /// The target fallback for a delete-reassignment is missing or invalid.
        case invalidReassignmentTarget
    }

    /// Longest allowed category / group name. Keeps the editor and dashboard rows
    /// from overflowing; long enough for any real label.
    public static let maxNameLength = 48

    // MARK: - Create a custom category (AC 1)

    /// Create a new **custom** category with a name, optional emoji, color, and
    /// parent group, appended at the end of that group's order.
    ///
    /// - Parameters:
    ///   - id: a fresh, unique id (build via ``customCategoryID(_:)`` at the call
    ///     site so this layer stays UUID-free and deterministic).
    ///   - name: display name; trimmed, must be non-empty, within ``maxNameLength``,
    ///     and unique within `groupId` (case-insensitive).
    ///   - emoji: optional single-emoji glyph; validated when present.
    ///   - colorHex: `#RRGGBB` color; validated.
    ///   - groupId: the parent group; must exist.
    ///   - iconName: SF Symbol fallback shown when no emoji is set. Defaults to the
    ///     neutral "tag" glyph.
    /// - Returns: a new snapshot with the category added, or an error.
    public static func addCategory(
        to schema: BudgetingV2Schema,
        id: String,
        name: String,
        emoji: String? = nil,
        colorHex: String,
        groupId: String,
        iconName: String = "tag"
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateName(trimmedName) { return .failure(error) }
        guard schema.group(id: groupId) != nil else { return .failure(.groupNotFound) }
        if let error = validateColor(colorHex) { return .failure(error) }
        if let emoji, let error = validateEmoji(emoji) { return .failure(error) }
        if hasDuplicateCategoryName(in: schema, groupId: groupId, name: trimmedName, excluding: nil) {
            return .failure(.duplicateCategoryName)
        }

        let nextIndex = nextCategorySortIndex(in: schema, groupId: groupId)
        let category = BudgetCategoryV2(
            id: id,
            name: trimmedName,
            iconName: iconName,
            emoji: normalizedEmoji(emoji),
            colorHex: normalizedColor(colorHex),
            groupId: groupId,
            sortIndex: nextIndex,
            seededFromCategory: nil
        )
        var categories = schema.categories
        categories.append(category)
        return .success(schema.replacingCategories(categories))
    }

    // MARK: - Edit a category (rename / recolor / re-emoji) (AC 2)

    /// Rename, recolor, and/or re-emoji a category — system **or** custom — without
    /// touching its ``BudgetCategoryV2/seededFromCategory`` link, so a renamed
    /// *system* category keeps its exact `systemKey → Plaid` mapping (every
    /// already-categorized transaction still buckets to the same Plaid key; only the
    /// label/color/glyph the user sees changes).
    ///
    /// `nil` fields leave the current value untouched; pass `emoji: .some(nil)` to
    /// *clear* an emoji. Only the presentation fields are editable here — the id,
    /// group membership, and seed link are immutable through this entrypoint (use
    /// ``moveCategory(in:categoryId:toGroupId:)`` to change the group).
    public static func editCategory(
        in schema: BudgetingV2Schema,
        categoryId: String,
        name: String? = nil,
        emoji: String?? = nil,
        colorHex: String? = nil
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        guard let existing = schema.category(id: categoryId) else {
            return .failure(.categoryNotFound)
        }

        var newName = existing.name
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let error = validateName(trimmed) { return .failure(error) }
            if hasDuplicateCategoryName(
                in: schema, groupId: existing.groupId, name: trimmed, excluding: categoryId
            ) {
                return .failure(.duplicateCategoryName)
            }
            newName = trimmed
        }

        var newColor = existing.colorHex
        if let colorHex {
            if let error = validateColor(colorHex) { return .failure(error) }
            newColor = normalizedColor(colorHex)
        }

        var newEmoji = existing.emoji
        if let emoji {
            if let emoji, let error = validateEmoji(emoji) { return .failure(error) }
            newEmoji = normalizedEmoji(emoji)
        }

        let updated = BudgetCategoryV2(
            id: existing.id,
            name: newName,
            iconName: existing.iconName,
            emoji: newEmoji,
            colorHex: newColor,
            groupId: existing.groupId,
            sortIndex: existing.sortIndex,
            // Preserved verbatim — the rename/recolor never breaks the Plaid mapping.
            seededFromCategory: existing.seededFromCategory
        )
        return .success(schema.replacingCategory(updated))
    }

    /// Reorder categories *within a single group* by supplying the desired
    /// top-to-bottom id order. Ids not in `orderedCategoryIds` keep their relative
    /// order after the listed ones; ids that don't belong to `groupId` are ignored.
    public static func reorderCategories(
        in schema: BudgetingV2Schema,
        groupId: String,
        orderedCategoryIds: [String]
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        guard schema.group(id: groupId) != nil else { return .failure(.groupNotFound) }

        let inGroup = schema.categories.filter { $0.groupId == groupId }
        let rank = Dictionary(
            orderedCategoryIds.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        // Stable order: listed ids by their given rank, then the rest by current
        // sortIndex/name — so an incomplete list never drops a category.
        let reordered = inGroup.sorted { lhs, rhs in
            let lr = rank[lhs.id] ?? Int.max
            let rr = rank[rhs.id] ?? Int.max
            if lr != rr { return lr < rr }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.name < rhs.name
        }

        var byId = Dictionary(schema.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, category) in reordered.enumerated() {
            byId[category.id] = category.withSortIndex(index)
        }
        let categories = schema.categories.map { byId[$0.id] ?? $0 }
        return .success(schema.replacingCategories(categories))
    }

    /// Move a category to a different group, appending it at the end of the target
    /// group's order. The category's id, name, color, emoji, and seed link are all
    /// preserved — only the group membership and within-group order change.
    public static func moveCategory(
        in schema: BudgetingV2Schema,
        categoryId: String,
        toGroupId: String
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        guard let existing = schema.category(id: categoryId) else {
            return .failure(.categoryNotFound)
        }
        guard schema.group(id: toGroupId) != nil else { return .failure(.groupNotFound) }
        guard existing.groupId != toGroupId else { return .success(schema) }

        // A move can collide with a same-named category already in the target group.
        if hasDuplicateCategoryName(
            in: schema, groupId: toGroupId, name: existing.name, excluding: categoryId
        ) {
            return .failure(.duplicateCategoryName)
        }

        let moved = BudgetCategoryV2(
            id: existing.id,
            name: existing.name,
            iconName: existing.iconName,
            emoji: existing.emoji,
            colorHex: existing.colorHex,
            groupId: toGroupId,
            sortIndex: nextCategorySortIndex(in: schema, groupId: toGroupId),
            seededFromCategory: existing.seededFromCategory
        )
        return .success(schema.replacingCategory(moved))
    }

    // MARK: - Delete a custom category (AC 4 — reassign, never orphan)

    /// The result of a delete: the new schema plus the id every budget that pointed
    /// at the deleted category was reassigned to, so a caller can re-point any
    /// transaction-level overrides the same way (no orphaned spend).
    public struct DeletionResult: Sendable, Hashable {
        /// The post-delete snapshot.
        public let schema: BudgetingV2Schema
        /// The deleted category's id.
        public let deletedCategoryId: String
        /// The category id that the deleted category's budgets (and the caller's
        /// transaction overrides) were reassigned to.
        public let reassignedToCategoryId: String

        public init(schema: BudgetingV2Schema, deletedCategoryId: String, reassignedToCategoryId: String) {
            self.schema = schema
            self.deletedCategoryId = deletedCategoryId
            self.reassignedToCategoryId = reassignedToCategoryId
        }
    }

    /// Delete a **custom** category, **reassigning** any budgets that pointed at it
    /// to `reassignToCategoryId` so no monthly budget — and, via the returned
    /// mapping, no transaction's spend — is left orphaned. A *system* (seeded)
    /// category cannot be deleted (it anchors the Plaid mapping); rename/recolor it
    /// instead.
    ///
    /// When a month already has a budget for *both* the deleted and the target
    /// category, the two limits are **summed** into the target so no budgeted dollar
    /// silently disappears. If `reassignToCategoryId` is `nil`, spend is reassigned
    /// to the closest system fallback — the `.other` seeded category — guaranteeing
    /// a always-present, never-deletable home.
    public static func deleteCustomCategory(
        in schema: BudgetingV2Schema,
        categoryId: String,
        reassignToCategoryId: String? = nil
    ) -> Result<DeletionResult, BudgetCategoryEditError> {
        guard let existing = schema.category(id: categoryId) else {
            return .failure(.categoryNotFound)
        }
        guard existing.isCustom else { return .failure(.cannotDeleteSystemCategory) }

        // Resolve the reassignment target. Default to the seeded `.other` category,
        // which always exists and is never deletable.
        let targetId = reassignToCategoryId ?? SpendingCategory.other.rawValue
        guard targetId != categoryId else { return .failure(.invalidReassignmentTarget) }
        guard schema.category(id: targetId) != nil else {
            return .failure(.invalidReassignmentTarget)
        }

        // Reassign budgets: each (month, deletedCategory) budget is folded onto the
        // (month, target) budget — summing limits when both exist so no budgeted
        // amount is dropped.
        var budgetsByKey = Dictionary(
            schema.budgets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for budget in schema.budgets where budget.categoryId == categoryId {
            budgetsByKey.removeValue(forKey: budget.id)
            let targetBudget = MonthlyBudgetV2(
                month: budget.month,
                categoryId: targetId,
                monthlyLimit: budget.monthlyLimit,
                rollover: budget.rollover
            )
            if let existingTarget = budgetsByKey[targetBudget.id] {
                budgetsByKey[targetBudget.id] = MonthlyBudgetV2(
                    month: existingTarget.month,
                    categoryId: existingTarget.categoryId,
                    monthlyLimit: existingTarget.monthlyLimit + budget.monthlyLimit,
                    // Keep rollover on if either side wanted it.
                    rollover: existingTarget.rollover || budget.rollover
                )
            } else {
                budgetsByKey[targetBudget.id] = targetBudget
            }
        }

        let categories = schema.categories.filter { $0.id != categoryId }
        let budgets = budgetsByKey.values.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
        let newSchema = BudgetingV2Schema(
            schemaVersion: schema.schemaVersion,
            groups: schema.groups,
            categories: categories,
            budgets: budgets
        )
        return .success(
            DeletionResult(
                schema: newSchema,
                deletedCategoryId: categoryId,
                reassignedToCategoryId: targetId
            )
        )
    }

    // MARK: - Groups (AC 3)

    /// Create a new **custom** group, appended at the end of the group order.
    public static func addGroup(
        to schema: BudgetingV2Schema,
        id: String,
        name: String
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateName(trimmed) { return .failure(error) }
        if hasDuplicateGroupName(in: schema, name: trimmed, excluding: nil) {
            return .failure(.duplicateGroupName)
        }
        let nextIndex = (schema.groups.map(\.sortIndex).max() ?? -1) + 1
        let group = BudgetCategoryGroupV2(
            id: id,
            name: trimmed,
            sortIndex: nextIndex,
            seededFromGroup: nil
        )
        var groups = schema.groups
        groups.append(group)
        return .success(schema.replacingGroups(groups))
    }

    /// Rename a group (system or custom). The id and seed link are preserved, so a
    /// renamed *system* group still maps back to its ``CategoryGroup`` on opt-out.
    public static func renameGroup(
        in schema: BudgetingV2Schema,
        groupId: String,
        name: String
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        guard let existing = schema.group(id: groupId) else { return .failure(.groupNotFound) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateName(trimmed) { return .failure(error) }
        if hasDuplicateGroupName(in: schema, name: trimmed, excluding: groupId) {
            return .failure(.duplicateGroupName)
        }
        let updated = BudgetCategoryGroupV2(
            id: existing.id,
            name: trimmed,
            sortIndex: existing.sortIndex,
            seededFromGroup: existing.seededFromGroup
        )
        return .success(schema.replacingGroup(updated))
    }

    /// Reorder groups top-to-bottom by supplying the desired id order. Ids not in
    /// `orderedGroupIds` keep their relative order after the listed ones.
    public static func reorderGroups(
        in schema: BudgetingV2Schema,
        orderedGroupIds: [String]
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        let rank = Dictionary(
            orderedGroupIds.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let reordered = schema.groups.sorted { lhs, rhs in
            let lr = rank[lhs.id] ?? Int.max
            let rr = rank[rhs.id] ?? Int.max
            if lr != rr { return lr < rr }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.name < rhs.name
        }
        let groups = reordered.enumerated().map { index, group in
            BudgetCategoryGroupV2(
                id: group.id,
                name: group.name,
                sortIndex: index,
                seededFromGroup: group.seededFromGroup
            )
        }
        return .success(schema.replacingGroups(groups))
    }

    /// Delete a **custom** group, moving every category in it to `reassignToGroupId`
    /// (or the seeded `.other` group by default) so no category — and therefore no
    /// spend — is orphaned. A *system* (seeded) group cannot be deleted.
    public static func deleteCustomGroup(
        in schema: BudgetingV2Schema,
        groupId: String,
        reassignToGroupId: String? = nil
    ) -> Result<BudgetingV2Schema, BudgetCategoryEditError> {
        guard let existing = schema.group(id: groupId) else { return .failure(.groupNotFound) }
        guard existing.isCustom else { return .failure(.cannotDeleteSystemGroup) }

        let targetId = reassignToGroupId ?? CategoryGroup.other.rawValue
        guard targetId != groupId else { return .failure(.invalidReassignmentTarget) }
        guard schema.group(id: targetId) != nil else { return .failure(.invalidReassignmentTarget) }

        // Move the group's categories to the target, appended after the target's
        // current members so order stays deterministic.
        var nextIndex = nextCategorySortIndex(in: schema, groupId: targetId)
        let categories = schema.categories.map { category -> BudgetCategoryV2 in
            guard category.groupId == groupId else { return category }
            let moved = BudgetCategoryV2(
                id: category.id,
                name: category.name,
                iconName: category.iconName,
                emoji: category.emoji,
                colorHex: category.colorHex,
                groupId: targetId,
                sortIndex: nextIndex,
                seededFromCategory: category.seededFromCategory
            )
            nextIndex += 1
            return moved
        }
        let groups = schema.groups.filter { $0.id != groupId }
        return .success(
            BudgetingV2Schema(
                schemaVersion: schema.schemaVersion,
                groups: groups,
                categories: categories,
                budgets: schema.budgets
            )
        )
    }

    // MARK: - Validation (public so the UI can pre-flight a field live)

    /// `nil` when `trimmedName` is a legal label, else the reason it isn't. Expects
    /// an already-trimmed string (the editor trims before calling so the live field
    /// validates against the committed value).
    public static func validateName(_ trimmedName: String) -> BudgetCategoryEditError? {
        if trimmedName.isEmpty { return .emptyName }
        if trimmedName.count > maxNameLength { return .nameTooLong }
        return nil
    }

    /// `nil` when `colorHex` is a valid `#RRGGBB` (case-insensitive, leading `#`
    /// required), else ``BudgetCategoryEditError/invalidColor``.
    public static func validateColor(_ colorHex: String) -> BudgetCategoryEditError? {
        isValidHexColor(colorHex) ? nil : .invalidColor
    }

    /// `nil` when `emoji` is exactly one emoji grapheme, else
    /// ``BudgetCategoryEditError/invalidEmoji``.
    public static func validateEmoji(_ emoji: String) -> BudgetCategoryEditError? {
        isValidEmoji(emoji) ? nil : .invalidEmoji
    }

    /// Whether a string is a well-formed `#RRGGBB` hex color (6 hex digits after a
    /// required `#`). Both cases accepted; normalized to uppercase on store.
    public static func isValidHexColor(_ value: String) -> Bool {
        guard value.hasPrefix("#") else { return false }
        let hex = value.dropFirst()
        guard hex.count == 6 else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    /// Whether a string is exactly one emoji grapheme (a single `Character` whose
    /// scalars include an emoji). Rejects empty, multi-character, and plain-text
    /// (non-emoji) input so the glyph stays a clean single symbol.
    public static func isValidEmoji(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let scalar = trimmed.unicodeScalars.first else { return false }
        // A grapheme is an emoji when its first scalar is an emoji *and* it is
        // presented as emoji (covers ZWJ sequences and modifier-bearing emoji,
        // which keep `isEmoji` on the first scalar).
        return scalar.properties.isEmoji && (scalar.value >= 0x203C || scalar.properties.isEmojiPresentation)
    }

    // MARK: - Normalization

    /// Uppercase a valid `#RRGGBB` so stored colors compare equal regardless of the
    /// case the user typed. Assumes ``isValidHexColor(_:)`` already passed.
    static func normalizedColor(_ colorHex: String) -> String {
        "#" + colorHex.dropFirst().uppercased()
    }

    /// Trim an emoji to its single grapheme; `nil` clears it.
    static func normalizedEmoji(_ emoji: String?) -> String? {
        guard let emoji else { return nil }
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Internals

    /// Whether `name` collides with another category in `groupId` (case-insensitive),
    /// ignoring `excluding` (the row being edited).
    static func hasDuplicateCategoryName(
        in schema: BudgetingV2Schema,
        groupId: String,
        name: String,
        excluding: String?
    ) -> Bool {
        let needle = name.lowercased()
        return schema.categories.contains { category in
            category.groupId == groupId
                && category.id != excluding
                && category.name.lowercased() == needle
        }
    }

    /// Whether `name` collides with another group (case-insensitive), ignoring
    /// `excluding`.
    static func hasDuplicateGroupName(
        in schema: BudgetingV2Schema,
        name: String,
        excluding: String?
    ) -> Bool {
        let needle = name.lowercased()
        return schema.groups.contains { group in
            group.id != excluding && group.name.lowercased() == needle
        }
    }

    /// The next within-group `sortIndex` for `groupId` (max + 1, or 0 when empty).
    static func nextCategorySortIndex(in schema: BudgetingV2Schema, groupId: String) -> Int {
        (schema.categories.filter { $0.groupId == groupId }.map(\.sortIndex).max() ?? -1) + 1
    }
}

// MARK: - Schema value-replacement helpers

extension BudgetCategoryV2 {
    /// A copy with a new within-group order, all other fields preserved.
    func withSortIndex(_ index: Int) -> BudgetCategoryV2 {
        BudgetCategoryV2(
            id: id,
            name: name,
            iconName: iconName,
            emoji: emoji,
            colorHex: colorHex,
            groupId: groupId,
            sortIndex: index,
            seededFromCategory: seededFromCategory
        )
    }
}

extension BudgetingV2Schema {
    /// A copy with `categories` replaced (groups/budgets/version unchanged).
    func replacingCategories(_ categories: [BudgetCategoryV2]) -> BudgetingV2Schema {
        BudgetingV2Schema(
            schemaVersion: schemaVersion,
            groups: groups,
            categories: categories,
            budgets: budgets
        )
    }

    /// A copy with the category sharing `updated.id` replaced in place.
    func replacingCategory(_ updated: BudgetCategoryV2) -> BudgetingV2Schema {
        replacingCategories(categories.map { $0.id == updated.id ? updated : $0 })
    }

    /// A copy with `groups` replaced (categories/budgets/version unchanged).
    func replacingGroups(_ groups: [BudgetCategoryGroupV2]) -> BudgetingV2Schema {
        BudgetingV2Schema(
            schemaVersion: schemaVersion,
            groups: groups,
            categories: categories,
            budgets: budgets
        )
    }

    /// A copy with the group sharing `updated.id` replaced in place.
    func replacingGroup(_ updated: BudgetCategoryGroupV2) -> BudgetingV2Schema {
        replacingGroups(groups.map { $0.id == updated.id ? updated : $0 })
    }
}
