import Foundation
import Testing
@testable import PlaidBarCore

/// Backward-compatibility tests for the AND-547 additive schema fields
/// (`emoji` / `colorHex` / `sortIndex` on ``BudgetCategoryV2``, `isCustom` derivation).
///
/// A v2 snapshot written **before** AND-547 has none of the new category keys. The
/// custom decoder must default them rather than throw, so the opt-in v2 store stays
/// self-healing and the upgrade is additive (a v2 user who opted in pre-AND-547
/// keeps their snapshot and just gains the new presentation fields).
@Suite("BudgetingV2Schema back-compat")
struct BudgetingV2SchemaBackCompatTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("a pre-AND-547 category JSON (no emoji/colorHex/sortIndex) still decodes")
    func decodesLegacyCategory() throws {
        // Exactly the shape AND-546 wrote: id/name/iconName/groupId/seededFromCategory.
        let legacyJSON = """
        {
          "id": "FOOD_AND_DRINK",
          "name": "Food & Drink",
          "iconName": "fork.knife",
          "groupId": "FOOD_AND_DINING",
          "seededFromCategory": "FOOD_AND_DRINK"
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try decoder.decode(BudgetCategoryV2.self, from: data)

        #expect(decoded.id == "FOOD_AND_DRINK")
        #expect(decoded.emoji == nil) // defaulted
        #expect(decoded.sortIndex == 0) // defaulted
        // Missing color falls back to the seeded category's v1 chart color.
        #expect(decoded.colorHex == SpendingCategory.foodAndDrink.colorHex)
        #expect(decoded.seededFromCategory == .foodAndDrink)
        #expect(!decoded.isCustom)
    }

    @Test("a legacy custom-ish row with no seed and no color falls back to neutral")
    func decodesLegacyCustomNeutralColor() throws {
        let legacyJSON = """
        {
          "id": "cat_legacy",
          "name": "Legacy",
          "iconName": "tag",
          "groupId": "OTHER"
        }
        """
        let decoded = try decoder.decode(BudgetCategoryV2.self, from: Data(legacyJSON.utf8))
        #expect(decoded.colorHex == BudgetCategoryV2.neutralColorHex)
        #expect(decoded.seededFromCategory == nil)
        #expect(decoded.isCustom)
    }

    @Test("a full AND-547 snapshot round-trips through encode/decode unchanged")
    func roundTripsNewSchema() throws {
        var schema = BudgetingV2Migration.seed()
        schema = try BudgetCategoryEditor.addCategory(
            to: schema,
            id: BudgetCategoryEditor.customCategoryID("c1"),
            name: "Hobbies",
            emoji: "🎨",
            colorHex: "#FF8800",
            groupId: CategoryGroup.shopping.rawValue
        ).get()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(schema)
        let decoded = try decoder.decode(BudgetingV2Schema.self, from: data)
        #expect(decoded == schema)
    }

    @Test("isCustom is purely derived — a seeded row is never custom, a fresh one always is")
    func isCustomDerivation() {
        let seeded = BudgetCategoryV2(seedingFrom: .shopping)
        #expect(!seeded.isCustom)
        let custom = BudgetCategoryV2(
            id: "cat_x", name: "X", iconName: "tag", colorHex: "#FF8800",
            groupId: "OTHER", seededFromCategory: nil
        )
        #expect(custom.isCustom)

        let seededGroup = BudgetCategoryGroupV2(seedingFrom: .housing)
        #expect(!seededGroup.isCustom)
        let customGroup = BudgetCategoryGroupV2(id: "grp_x", name: "X", sortIndex: 99, seededFromGroup: nil)
        #expect(customGroup.isCustom)
    }
}
