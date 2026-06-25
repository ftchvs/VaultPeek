import Foundation
import Testing
@testable import PlaidBarCore

/// Schema-foundation tests for budgeting v2 (AND-546 — deferred epic AND-524).
///
/// Covers: the forward seed preserves today's categorization one-to-one; the
/// migration is reversible (v1 budgets round-trip losslessly); the seed is
/// additive (it never touches the v1 enum / DTO); and the schema-version check
/// drives self-healing.
@Suite("Budgeting v2 schema + migration foundation (AND-546)")
struct BudgetingV2MigrationTests {

    // MARK: - Forward seed preserves the v1 taxonomy

    @Test("Seed produces exactly one v2 category per SpendingCategory, keyed by rawValue")
    func seedCategoriesAreOneToOneWithV1() {
        let schema = BudgetingV2Migration.seed()

        #expect(schema.categories.count == SpendingCategory.allCases.count)

        // Every v1 case has a v2 row keyed by its rawValue, carrying the v1 name,
        // icon, and parent group — i.e. categorization is preserved, not reclassified.
        for category in SpendingCategory.allCases {
            let row = schema.category(id: category.rawValue)
            #expect(row != nil)
            #expect(row?.id == category.rawValue)
            #expect(row?.name == category.displayName)
            #expect(row?.iconName == category.iconName)
            #expect(row?.groupId == category.group.rawValue)
            #expect(row?.seededFromCategory == category)
        }
    }

    @Test("Seed produces exactly one v2 group per CategoryGroup, in display order")
    func seedGroupsAreOneToOneWithV1() {
        let schema = BudgetingV2Migration.seed()

        #expect(schema.groups.count == CategoryGroup.allCases.count)
        #expect(schema.groups.map(\.id) == CategoryGroup.displayOrder.map(\.rawValue))

        for group in CategoryGroup.allCases {
            let row = schema.group(id: group.rawValue)
            #expect(row?.name == group.title)
            #expect(row?.sortIndex == group.sortIndex)
            #expect(row?.seededFromGroup == group)
        }
    }

    @Test("Every seeded category's groupId references a seeded group (referential integrity)")
    func seededCategoriesReferenceSeededGroups() {
        let schema = BudgetingV2Migration.seed()
        let groupIds = Set(schema.groups.map(\.id))
        for category in schema.categories {
            #expect(groupIds.contains(category.groupId))
        }
    }

    @Test("Bare seed has no budgets — the foundation seeds the taxonomy, not budgets")
    func bareSeedHasNoBudgets() {
        let schema = BudgetingV2Migration.seed()
        #expect(schema.budgets.isEmpty)
    }

    @Test("Seed is deterministic — same inputs produce an equal snapshot")
    func seedIsDeterministic() {
        #expect(BudgetingV2Migration.seed() == BudgetingV2Migration.seed())
    }

    // MARK: - Carrying v1 budgets forward

    @Test("v1 budgets carried forward land on the chosen month with rollover off")
    func carryV1BudgetsForward() {
        let v1 = [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500),
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 120),
        ]
        let schema = BudgetingV2Migration.seed(carryingForward: v1, month: "2026-06")

        #expect(schema.budgets.count == 2)
        let food = schema.budgets.first { $0.categoryId == SpendingCategory.foodAndDrink.rawValue }
        #expect(food?.month == "2026-06")
        #expect(food?.monthlyLimit == 500)
        #expect(food?.rollover == false)
        #expect(food?.id == "2026-06|FOOD_AND_DRINK")
    }

    @Test("Carrying budgets forward without a month is a no-op (taxonomy only)")
    func carryWithoutMonthIsNoOp() {
        let v1 = [CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500)]
        let schema = BudgetingV2Migration.seed(carryingForward: v1, month: nil)
        #expect(schema.budgets.isEmpty)
    }

    // MARK: - Reversibility (opt-out restores v1)

    @Test("Reverse migration recovers the exact v1 budgets for a month (lossless round-trip)")
    func reverseRoundTripsV1Budgets() {
        let v1 = [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500),
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 120),
            CategoryBudgetDTO(category: .shopping, monthlyLimit: 300),
        ]
        let schema = BudgetingV2Migration.seed(carryingForward: v1, month: "2026-06")

        let recovered = BudgetingV2Migration.reverseToV1Budgets(schema, month: "2026-06")

        // Sorted both sides by rawValue for an order-independent equality.
        let expected = v1.sorted { $0.category.rawValue < $1.category.rawValue }
        #expect(recovered == expected)
    }

    @Test("Reverse migration only recovers budgets for the requested month")
    func reverseFiltersByMonth() {
        // Manually compose a snapshot with two months of budgets.
        let seed = BudgetingV2Migration.seed()
        let schema = BudgetingV2Schema(
            groups: seed.groups,
            categories: seed.categories,
            budgets: [
                MonthlyBudgetV2(month: "2026-06", categoryId: "FOOD_AND_DRINK", monthlyLimit: 500),
                MonthlyBudgetV2(month: "2026-07", categoryId: "FOOD_AND_DRINK", monthlyLimit: 450),
            ]
        )

        let june = BudgetingV2Migration.reverseToV1Budgets(schema, month: "2026-06")
        #expect(june.count == 1)
        #expect(june.first?.monthlyLimit == 500)

        let july = BudgetingV2Migration.reverseToV1Budgets(schema, month: "2026-07")
        #expect(july.first?.monthlyLimit == 450)
    }

    @Test("Seeding never mutates the v1 SpendingCategory enum or DTO (additive)")
    func seedIsAdditive() {
        // The v1 surfaces are value types / static enums; "additive" means the seed
        // is derived FROM them and leaves them intact. Assert the v1 contract still
        // holds after a seed: same case count, same rawValues, same DTO id rule.
        let before = SpendingCategory.allCases.map(\.rawValue)
        _ = BudgetingV2Migration.seed(
            carryingForward: [CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500)],
            month: "2026-06"
        )
        let after = SpendingCategory.allCases.map(\.rawValue)
        #expect(before == after)
        // v1 DTO identity is unchanged.
        #expect(CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 1).id == "FOOD_AND_DRINK")
    }

    // MARK: - Schema version / self-healing

    @Test("needsMigration is true for nil and for an older schema version")
    func needsMigrationDetectsStale() {
        #expect(BudgetingV2Migration.needsMigration(nil))

        let current = BudgetingV2Migration.seed()
        #expect(!BudgetingV2Migration.needsMigration(current))

        let stale = BudgetingV2Schema(
            schemaVersion: BudgetingV2Schema.currentSchemaVersion - 1,
            groups: current.groups,
            categories: current.categories,
            budgets: current.budgets
        )
        #expect(BudgetingV2Migration.needsMigration(stale))
        #expect(!stale.isCurrentSchema)
    }

    @Test("Schema snapshot round-trips through Codable")
    func schemaCodableRoundTrip() throws {
        let schema = BudgetingV2Migration.seed(
            carryingForward: [CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500)],
            month: "2026-06"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(schema)
        let decoded = try JSONDecoder().decode(BudgetingV2Schema.self, from: data)
        #expect(decoded == schema)
    }
}
