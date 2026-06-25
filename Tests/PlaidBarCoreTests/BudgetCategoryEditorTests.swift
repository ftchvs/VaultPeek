import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the budgeting-v2 categories & groups editor (AND-547).
///
/// Verifies the four acceptance criteria as pure, view-free logic:
/// 1. create a custom category with name + emoji + color + group;
/// 2. rename/recolor a SYSTEM category without breaking its `systemKey → Plaid`
///    mapping;
/// 3. create/rename/reorder groups + move categories between groups;
/// 4. deleting a custom category reassigns its budgets (no orphaned spend).
@Suite("BudgetCategoryEditor")
struct BudgetCategoryEditorTests {
    /// A freshly seeded snapshot (no carried-forward budgets) — the editor's input.
    private func seededSchema() -> BudgetingV2Schema {
        BudgetingV2Migration.seed()
    }

    // MARK: - AC 1: create a custom category

    @Test("addCategory creates a custom category with name + emoji + color + group")
    func addCustomCategory() throws {
        let schema = seededSchema()
        let groupId = CategoryGroup.shopping.rawValue
        let id = BudgetCategoryEditor.customCategoryID("hobbies-1")

        let result = BudgetCategoryEditor.addCategory(
            to: schema,
            id: id,
            name: "Hobbies",
            emoji: "🎨",
            colorHex: "#ff8800",
            groupId: groupId
        )
        let updated = try result.get()

        let created = try #require(updated.category(id: id))
        #expect(created.name == "Hobbies")
        #expect(created.emoji == "🎨")
        #expect(created.colorHex == "#FF8800") // normalized to uppercase
        #expect(created.groupId == groupId)
        #expect(created.isCustom)
        #expect(created.seededFromCategory == nil)
        // Appended after the group's seeded members.
        let inGroup = updated.categories.filter { $0.groupId == groupId }
        #expect(created.sortIndex == (inGroup.map(\.sortIndex).max() ?? -1))
        // Additive: every seeded category survives.
        #expect(updated.categories.count == schema.categories.count + 1)
    }

    @Test("addCategory rejects an empty name, bad color, bad emoji, and unknown group")
    func addCategoryValidation() {
        let schema = seededSchema()
        let groupId = CategoryGroup.shopping.rawValue

        #expect(throwsEditError(.emptyName) {
            try BudgetCategoryEditor.addCategory(
                to: schema, id: "cat_x", name: "   ", colorHex: "#FF8800", groupId: groupId
            ).get()
        })
        #expect(throwsEditError(.invalidColor) {
            try BudgetCategoryEditor.addCategory(
                to: schema, id: "cat_x", name: "Hobbies", colorHex: "FF8800", groupId: groupId
            ).get()
        })
        #expect(throwsEditError(.invalidEmoji) {
            try BudgetCategoryEditor.addCategory(
                to: schema, id: "cat_x", name: "Hobbies", emoji: "ab",
                colorHex: "#FF8800", groupId: groupId
            ).get()
        })
        #expect(throwsEditError(.groupNotFound) {
            try BudgetCategoryEditor.addCategory(
                to: schema, id: "cat_x", name: "Hobbies", colorHex: "#FF8800", groupId: "nope"
            ).get()
        })
    }

    @Test("addCategory rejects a duplicate name within the same group, case-insensitively")
    func addCategoryDuplicateName() throws {
        var schema = seededSchema()
        let groupId = CategoryGroup.shopping.rawValue
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: "cat_1", name: "Hobbies", colorHex: "#FF8800", groupId: groupId
        ).get()

        #expect(throwsEditError(.duplicateCategoryName) {
            try BudgetCategoryEditor.addCategory(
                to: schema, id: "cat_2", name: "hobbies", colorHex: "#00FF00", groupId: groupId
            ).get()
        })
        // Same name in a *different* group is allowed.
        let otherGroup = CategoryGroup.entertainment.rawValue
        #expect((try? BudgetCategoryEditor.addCategory(
            to: schema, id: "cat_3", name: "Hobbies", colorHex: "#00FF00", groupId: otherGroup
        ).get()) != nil)
    }

    // MARK: - AC 2: rename/recolor a SYSTEM category preserves the Plaid mapping

    @Test("editCategory renames/recolors a system category WITHOUT breaking the Plaid mapping")
    func editSystemCategoryPreservesMapping() throws {
        let schema = seededSchema()
        let systemId = SpendingCategory.foodAndDrink.rawValue // "FOOD_AND_DRINK"

        let updated = try BudgetCategoryEditor.editCategory(
            in: schema,
            categoryId: systemId,
            name: "Groceries & Eats",
            emoji: .some("🍜"),
            colorHex: "#123abc"
        ).get()

        let edited = try #require(updated.category(id: systemId))
        #expect(edited.name == "Groceries & Eats")
        #expect(edited.emoji == "🍜")
        #expect(edited.colorHex == "#123ABC")
        // The id is unchanged AND the seed link is preserved verbatim — the
        // systemKey → Plaid mapping is intact.
        #expect(edited.id == systemId)
        #expect(edited.seededFromCategory == .foodAndDrink)
        #expect(!edited.isCustom)
        // Reverse migration still recovers the v1 key for this renamed category.
        let v1 = BudgetingV2Migration.reverseToV1Budgets(
            updated.replacingCategory(edited).withBudget(
                MonthlyBudgetV2(month: "2026-06", categoryId: systemId, monthlyLimit: 100)
            ),
            month: "2026-06"
        )
        #expect(v1.contains { $0.category == .foodAndDrink && $0.monthlyLimit == 100 })
    }

    @Test("editCategory with nil fields is a no-op for those fields; clearing an emoji works")
    func editCategoryPartial() throws {
        var schema = seededSchema()
        let id = BudgetCategoryEditor.customCategoryID("c1")
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: id, name: "Hobbies", emoji: "🎨",
            colorHex: "#FF8800", groupId: CategoryGroup.shopping.rawValue
        ).get()

        // Rename only: color + emoji untouched.
        var updated = try BudgetCategoryEditor.editCategory(in: schema, categoryId: id, name: "Crafts").get()
        var row = try #require(updated.category(id: id))
        #expect(row.name == "Crafts")
        #expect(row.emoji == "🎨")
        #expect(row.colorHex == "#FF8800")

        // Clear the emoji explicitly via .some(nil).
        updated = try BudgetCategoryEditor.editCategory(in: updated, categoryId: id, emoji: .some(nil)).get()
        row = try #require(updated.category(id: id))
        #expect(row.emoji == nil)
        #expect(row.name == "Crafts") // unchanged
    }

    @Test("editCategory rejects an unknown id and a duplicate name within the group")
    func editCategoryValidation() throws {
        var schema = seededSchema()
        let groupId = CategoryGroup.shopping.rawValue
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: "cat_a", name: "Alpha", colorHex: "#FF8800", groupId: groupId
        ).get()
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: "cat_b", name: "Beta", colorHex: "#00FF00", groupId: groupId
        ).get()

        #expect(throwsEditError(.categoryNotFound) {
            try BudgetCategoryEditor.editCategory(in: schema, categoryId: "nope", name: "X").get()
        })
        #expect(throwsEditError(.duplicateCategoryName) {
            try BudgetCategoryEditor.editCategory(in: schema, categoryId: "cat_b", name: "alpha").get()
        })
    }

    @Test("reorderCategories reindexes within a group and never drops an unlisted id")
    func reorderCategories() throws {
        let schema = seededSchema()
        let groupId = CategoryGroup.entertainment.rawValue
        let original = schema.categories.filter { $0.groupId == groupId }.map(\.id)
        #expect(original.count >= 2)

        // Reverse just the first two; the rest must remain, in order, after them.
        let reordered = Array(original.prefix(2).reversed())
        let updated = try BudgetCategoryEditor.reorderCategories(
            in: schema, groupId: groupId, orderedCategoryIds: reordered
        ).get()

        let resultIds = updated.categories
            .filter { $0.groupId == groupId }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        #expect(resultIds.prefix(2) == ArraySlice(reordered))
        #expect(Set(resultIds) == Set(original)) // nothing dropped
        // Indices are contiguous from 0.
        let indices = updated.categories.filter { $0.groupId == groupId }.map(\.sortIndex).sorted()
        #expect(indices == Array(0..<indices.count))
    }

    // MARK: - AC 3: groups CRUD + move categories between groups

    @Test("addGroup / renameGroup / reorderGroups manage custom and system groups")
    func groupCrud() throws {
        var schema = seededSchema()
        let originalGroupCount = schema.groups.count
        let groupId = BudgetCategoryEditor.customGroupID("g1")

        // Create.
        schema = try BudgetCategoryEditor.addGroup(to: schema, id: groupId, name: "Side Projects").get()
        let created = try #require(schema.group(id: groupId))
        #expect(created.name == "Side Projects")
        #expect(created.isCustom)
        #expect(schema.groups.count == originalGroupCount + 1)

        // Duplicate name rejected (system group "Housing").
        #expect(throwsEditError(.duplicateGroupName) {
            try BudgetCategoryEditor.addGroup(to: schema, id: "grp_x", name: "housing").get()
        })

        // Rename.
        schema = try BudgetCategoryEditor.renameGroup(in: schema, groupId: groupId, name: "Hobbies").get()
        #expect(schema.group(id: groupId)?.name == "Hobbies")

        // Reorder: move the new group to the front.
        let order = [groupId] + schema.groups.map(\.id).filter { $0 != groupId }
        schema = try BudgetCategoryEditor.reorderGroups(in: schema, orderedGroupIds: order).get()
        let sorted = schema.groups.sorted { $0.sortIndex < $1.sortIndex }
        #expect(sorted.first?.id == groupId)
        #expect(sorted.map(\.sortIndex) == Array(0..<sorted.count))
    }

    @Test("renameGroup preserves a system group's seed link for opt-out")
    func renameSystemGroupPreservesSeed() throws {
        let schema = seededSchema()
        let groupId = CategoryGroup.housing.rawValue
        let updated = try BudgetCategoryEditor.renameGroup(in: schema, groupId: groupId, name: "Home Base").get()
        let group = try #require(updated.group(id: groupId))
        #expect(group.name == "Home Base")
        #expect(group.seededFromGroup == .housing)
        #expect(!group.isCustom)
    }

    @Test("moveCategory relocates a category and appends it in the target group")
    func moveCategory() throws {
        let schema = seededSchema()
        let categoryId = SpendingCategory.travel.rawValue // seeds into .entertainment
        let originalGroup = try #require(schema.category(id: categoryId)).groupId
        let target = CategoryGroup.shopping.rawValue
        #expect(originalGroup != target)

        let updated = try BudgetCategoryEditor.moveCategory(
            in: schema, categoryId: categoryId, toGroupId: target
        ).get()
        let moved = try #require(updated.category(id: categoryId))
        #expect(moved.groupId == target)
        // Seed link preserved across a move — the Plaid mapping is intact.
        #expect(moved.seededFromCategory == .travel)
        // Appended at the end of the target group.
        let targetIndices = updated.categories.filter { $0.groupId == target }.map(\.sortIndex)
        #expect(moved.sortIndex == (targetIndices.max() ?? -1))
    }

    @Test("deleteCustomGroup moves its categories to the fallback group, never orphaning them")
    func deleteCustomGroupReassigns() throws {
        var schema = seededSchema()
        let groupId = BudgetCategoryEditor.customGroupID("g1")
        schema = try BudgetCategoryEditor.addGroup(to: schema, id: groupId, name: "Side").get()
        let catId = BudgetCategoryEditor.customCategoryID("c1")
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: catId, name: "Gig", colorHex: "#FF8800", groupId: groupId
        ).get()

        let updated = try BudgetCategoryEditor.deleteCustomGroup(in: schema, groupId: groupId).get()
        #expect(updated.group(id: groupId) == nil)
        // The category survived and moved to the default fallback (.other).
        let moved = try #require(updated.category(id: catId))
        #expect(moved.groupId == CategoryGroup.other.rawValue)
    }

    @Test("a system group cannot be deleted")
    func systemGroupNotDeletable() {
        let schema = seededSchema()
        #expect(throwsEditError(.cannotDeleteSystemGroup) {
            try BudgetCategoryEditor.deleteCustomGroup(in: schema, groupId: CategoryGroup.housing.rawValue).get()
        })
    }

    // MARK: - AC 4: delete a custom category reassigns its spend (no orphans)

    @Test("deleteCustomCategory reassigns its budgets to the fallback, summing collisions")
    func deleteCustomCategoryReassignsBudgets() throws {
        var schema = seededSchema()
        let groupId = CategoryGroup.shopping.rawValue
        let customId = BudgetCategoryEditor.customCategoryID("c1")
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: customId, name: "Hobbies", colorHex: "#FF8800", groupId: groupId
        ).get()

        let fallback = SpendingCategory.shopping.rawValue
        // The custom category has a budget; the fallback already has one in the same
        // month — they must SUM so no budgeted dollar disappears.
        schema = schema.withBudget(MonthlyBudgetV2(month: "2026-06", categoryId: customId, monthlyLimit: 80))
        schema = schema.withBudget(MonthlyBudgetV2(month: "2026-06", categoryId: fallback, monthlyLimit: 120))
        schema = schema.withBudget(MonthlyBudgetV2(month: "2026-07", categoryId: customId, monthlyLimit: 50))

        let result = try BudgetCategoryEditor.deleteCustomCategory(
            in: schema, categoryId: customId, reassignToCategoryId: fallback
        ).get()

        #expect(result.deletedCategoryId == customId)
        #expect(result.reassignedToCategoryId == fallback)
        #expect(result.schema.category(id: customId) == nil)
        // No budget references the deleted category anymore.
        #expect(!result.schema.budgets.contains { $0.categoryId == customId })
        // June: 120 + 80 summed onto the fallback. July: 50 carried over.
        let june = result.schema.budgets.first { $0.month == "2026-06" && $0.categoryId == fallback }
        #expect(june?.monthlyLimit == 200)
        let july = result.schema.budgets.first { $0.month == "2026-07" && $0.categoryId == fallback }
        #expect(july?.monthlyLimit == 50)
        // Total budgeted dollars are conserved across the delete.
        let before = schema.budgets.map(\.monthlyLimit).reduce(0, +)
        let after = result.schema.budgets.map(\.monthlyLimit).reduce(0, +)
        #expect(before == after)
    }

    @Test("deleteCustomCategory defaults the reassignment target to the .other system category")
    func deleteCustomCategoryDefaultFallback() throws {
        var schema = seededSchema()
        let customId = BudgetCategoryEditor.customCategoryID("c1")
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: customId, name: "Hobbies", colorHex: "#FF8800",
            groupId: CategoryGroup.shopping.rawValue
        ).get()
        schema = schema.withBudget(MonthlyBudgetV2(month: "2026-06", categoryId: customId, monthlyLimit: 40))

        let result = try BudgetCategoryEditor.deleteCustomCategory(in: schema, categoryId: customId).get()
        #expect(result.reassignedToCategoryId == SpendingCategory.other.rawValue)
        let moved = result.schema.budgets.first {
            $0.month == "2026-06" && $0.categoryId == SpendingCategory.other.rawValue
        }
        #expect(moved?.monthlyLimit == 40)
    }

    @Test("a SYSTEM category cannot be deleted")
    func systemCategoryNotDeletable() {
        let schema = seededSchema()
        #expect(throwsEditError(.cannotDeleteSystemCategory) {
            try BudgetCategoryEditor.deleteCustomCategory(
                in: schema, categoryId: SpendingCategory.foodAndDrink.rawValue
            ).get()
        })
    }

    @Test("deleteCustomCategory rejects reassigning to itself or a missing target")
    func deleteCustomCategoryInvalidTarget() throws {
        var schema = seededSchema()
        let customId = BudgetCategoryEditor.customCategoryID("c1")
        schema = try BudgetCategoryEditor.addCategory(
            to: schema, id: customId, name: "Hobbies", colorHex: "#FF8800",
            groupId: CategoryGroup.shopping.rawValue
        ).get()

        #expect(throwsEditError(.invalidReassignmentTarget) {
            try BudgetCategoryEditor.deleteCustomCategory(
                in: schema, categoryId: customId, reassignToCategoryId: customId
            ).get()
        })
        #expect(throwsEditError(.invalidReassignmentTarget) {
            try BudgetCategoryEditor.deleteCustomCategory(
                in: schema, categoryId: customId, reassignToCategoryId: "ghost"
            ).get()
        })
    }

    // MARK: - Validation primitives

    @Test("hex color validation accepts #RRGGBB only")
    func hexColorValidation() {
        #expect(BudgetCategoryEditor.isValidHexColor("#FF8800"))
        #expect(BudgetCategoryEditor.isValidHexColor("#ff8800"))
        #expect(!BudgetCategoryEditor.isValidHexColor("FF8800"))   // no #
        #expect(!BudgetCategoryEditor.isValidHexColor("#FFF"))     // too short
        #expect(!BudgetCategoryEditor.isValidHexColor("#GG8800"))  // non-hex
        #expect(!BudgetCategoryEditor.isValidHexColor("#FF88000")) // too long
    }

    @Test("emoji validation accepts exactly one emoji grapheme")
    func emojiValidation() {
        #expect(BudgetCategoryEditor.isValidEmoji("🎨"))
        #expect(BudgetCategoryEditor.isValidEmoji("👩‍🚀")) // ZWJ sequence is one grapheme
        #expect(!BudgetCategoryEditor.isValidEmoji("ab"))   // plain text
        #expect(!BudgetCategoryEditor.isValidEmoji("a"))    // single non-emoji
        #expect(!BudgetCategoryEditor.isValidEmoji(""))     // empty
        #expect(!BudgetCategoryEditor.isValidEmoji("🎨🎨")) // two
    }

    @Test("name length is bounded")
    func nameLength() {
        let long = String(repeating: "x", count: BudgetCategoryEditor.maxNameLength + 1)
        #expect(BudgetCategoryEditor.validateName(long) == .nameTooLong)
        let ok = String(repeating: "x", count: BudgetCategoryEditor.maxNameLength)
        #expect(BudgetCategoryEditor.validateName(ok) == nil)
    }

    // MARK: - Additive / v1-safety guarantees

    @Test("a freshly seeded snapshot carries v1 colors and contiguous within-group order")
    func seedCarriesColorsAndOrder() {
        let schema = seededSchema()
        // Every seeded category keeps its v1 chart color.
        for category in schema.categories {
            #expect(category.colorHex == category.seededFromCategory?.colorHex)
            #expect(!category.isCustom)
        }
        // Within each group the sortIndex is contiguous from 0.
        for group in schema.groups {
            let indices = schema.categories
                .filter { $0.groupId == group.id }
                .map(\.sortIndex)
                .sorted()
            #expect(indices == Array(0..<indices.count))
        }
    }

    // MARK: - Helpers

    /// Assert a throwing editor expression fails with exactly `expected`.
    private func throwsEditError(
        _ expected: BudgetCategoryEditor.BudgetCategoryEditError,
        _ body: () throws -> Any
    ) -> Bool {
        do {
            _ = try body()
            return false
        } catch let error as BudgetCategoryEditor.BudgetCategoryEditError {
            return error == expected
        } catch {
            return false
        }
    }
}

// MARK: - Test-only schema convenience

private extension BudgetingV2Schema {
    /// A copy with one budget appended (replacing any existing budget for the same
    /// (month, category) key).
    func withBudget(_ budget: MonthlyBudgetV2) -> BudgetingV2Schema {
        var byKey = Dictionary(budgets.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        byKey[budget.id] = budget
        return BudgetingV2Schema(
            schemaVersion: schemaVersion,
            groups: groups,
            categories: categories,
            budgets: byKey.values.sorted { $0.id < $1.id }
        )
    }
}
