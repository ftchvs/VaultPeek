import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

/// Round-trip tests that an AND-547 *edited* schema (custom categories/groups with
/// the new emoji/color/sortIndex fields) persists through ``BudgetingV2Store`` and
/// reloads byte-for-byte equal — the editor model's persistence path.
@Suite("Budgeting v2 editor store round-trip (AND-547)", .serialized)
struct BudgetingV2EditorStoreTests {

    @Test("an edited schema with a custom category + group survives save/load equal")
    func editedSchemaRoundTrips() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        let cacheKey = "sandbox|/x"

        var schema = try await store.seedV2(cacheKey: cacheKey)

        // Add a custom group + category, rename a system category, recolor it.
        schema = try BudgetCategoryEditor.addGroup(
            to: schema, id: BudgetCategoryEditor.customGroupID("g1"), name: "Side Projects"
        ).get()
        schema = try BudgetCategoryEditor.addCategory(
            to: schema,
            id: BudgetCategoryEditor.customCategoryID("c1"),
            name: "Gig Income",
            emoji: "💼",
            colorHex: "#22AA88",
            groupId: BudgetCategoryEditor.customGroupID("g1")
        ).get()
        schema = try BudgetCategoryEditor.editCategory(
            in: schema,
            categoryId: SpendingCategory.foodAndDrink.rawValue,
            name: "Groceries",
            colorHex: "#FF0000"
        ).get()

        try await store.save(cacheKey: cacheKey, schema: schema)
        let loaded = try #require(try await store.load(cacheKey: cacheKey))
        #expect(loaded == schema)

        // Spot-check the new fields survived persistence.
        let custom = try #require(loaded.category(id: BudgetCategoryEditor.customCategoryID("c1")))
        #expect(custom.emoji == "💼")
        #expect(custom.colorHex == "#22AA88")
        #expect(custom.isCustom)
        let renamed = try #require(loaded.category(id: SpendingCategory.foodAndDrink.rawValue))
        #expect(renamed.name == "Groceries")
        #expect(renamed.colorHex == "#FF0000")
        // System mapping intact after rename+recolor+persist.
        #expect(renamed.seededFromCategory == .foodAndDrink)
    }

    @Test("opting out after edits still recovers the carried-forward v1 budgets")
    func optOutAfterEditsRecoversV1() async throws {
        let store = try BudgetingV2Store(inMemory: true)
        let cacheKey = "sandbox|/x"
        let v1 = [CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500)]

        var schema = try await store.seedV2(cacheKey: cacheKey, carryingForward: v1, month: "2026-06")
        // Rename the system category the budget points at — the mapping must survive.
        schema = try BudgetCategoryEditor.editCategory(
            in: schema, categoryId: SpendingCategory.foodAndDrink.rawValue, name: "Groceries"
        ).get()
        try await store.save(cacheKey: cacheKey, schema: schema)

        let recovered = try await store.optOut(cacheKey: cacheKey, month: "2026-06")
        #expect(recovered.contains { $0.category == .foodAndDrink && $0.monthlyLimit == 500 })
        // Opt-out clears the snapshot — v1 is back in effect.
        #expect(try await store.isOptedIn(cacheKey: cacheKey) == false)
    }
}
