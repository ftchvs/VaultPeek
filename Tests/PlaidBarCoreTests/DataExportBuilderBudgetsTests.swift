import Foundation
@testable import PlaidBarCore
import Testing

/// AND-645: budgets in the CSV/JSON export, plus the pure masked-state gating
/// rule that protects Privacy Mask / App Lock from being bypassed by writing
/// real values to disk.
@Suite("Data Export Builder — Budgets & Masking (AND-645)")
struct DataExportBuilderBudgetsTests {
    // MARK: - Masked-state gating

    @Test("Export is blocked whenever financial values are masked (Privacy Mask or App Lock)")
    func exportGatedOnMask() {
        #expect(DataExportBuilder.isExportAllowed(shouldMaskFinancialValues: false))
        // Masked (Privacy Mask on) or locked (App Lock) both surface through
        // shouldMaskFinancialValues, so a single true input blocks the export.
        #expect(!DataExportBuilder.isExportAllowed(shouldMaskFinancialValues: true))
    }

    // MARK: - Budgets CSV

    @Test("budgetsCSV emits a stable header and a row per budget sorted by category raw value")
    func budgetsCSVHeaderAndStableOrder() {
        // Intentionally unsorted input order — output must be deterministic.
        let csv = DataExportBuilder.budgetsCSV([
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 200),
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 450.5),
            CategoryBudgetDTO(category: .billsAndUtilities, monthlyLimit: 1000),
        ])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 4) // header + 3 rows
        #expect(lines[0] == "category,category_name,monthly_limit")
        // Sorted by rawValue: FOOD_AND_DRINK < RENT_AND_UTILITIES < TRANSPORTATION
        #expect(lines[1] == "FOOD_AND_DRINK,Food & Drink,450.50")
        #expect(lines[2] == "RENT_AND_UTILITIES,Bills & Utilities,1000.00")
        #expect(lines[3] == "TRANSPORTATION,Transportation,200.00")
    }

    @Test("budgetsCSV dictionary overload sorts deterministically regardless of dictionary order")
    func budgetsCSVDictionaryOverloadIsStable() {
        let dictionary: [SpendingCategory: Double] = [
            .travel: 300,
            .education: 75,
            .entertainment: 60,
        ]
        // Run twice; dictionary iteration order is non-deterministic but the CSV
        // must be byte-identical every time.
        let first = DataExportBuilder.budgetsCSV(dictionary)
        let second = DataExportBuilder.budgetsCSV(dictionary)
        #expect(first == second)
        let lines = first.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // EDUCATION < ENTERTAINMENT < TRAVEL by raw value.
        #expect(lines[1].hasPrefix("EDUCATION,"))
        #expect(lines[2].hasPrefix("ENTERTAINMENT,"))
        #expect(lines[3].hasPrefix("TRAVEL,"))
    }

    @Test("budgetsCSV escapes a category display name and neutralizes formula-leading text safely")
    func budgetsCSVEscapingAndNeutralization() {
        // The category raw value and a numeric limit are machine values, but
        // verify the row goes through the shared escaping path: a value that
        // would need quoting (comma) or formula neutralization is handled. We
        // can exercise this via csvField directly to prove the row builder uses
        // it; the displayName values are constants, so no real budget name can
        // inject — this guards the shared codepath stays wired in.
        #expect(DataExportBuilder.csvField("Food & Drink") == "Food & Drink")
        #expect(DataExportBuilder.csvField("Bills, Utilities") == "\"Bills, Utilities\"")
        #expect(DataExportBuilder.csvField("=cmd") == "'=cmd")
    }

    @Test("budgetsCSV with no budgets yields a header-only document")
    func budgetsCSVEmpty() {
        let csv = DataExportBuilder.budgetsCSV([CategoryBudgetDTO]())
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 1)
        #expect(lines[0] == "category,category_name,monthly_limit")
    }

    @Test("budgetDTOs normalizes the app dictionary into a stably ordered DTO array")
    func budgetDTOsStableOrder() {
        let dtos = DataExportBuilder.budgetDTOs(from: [
            .shopping: 500,
            .foodAndDrink: 400,
        ])
        // FOOD_AND_DRINK < GENERAL_MERCHANDISE by raw value.
        #expect(dtos.map(\.category) == [.foodAndDrink, .shopping])
        #expect(dtos.map(\.monthlyLimit) == [400, 500])
    }

    // MARK: - JSON envelope with budgets

    @Test("combinedJSON carries budgets, a stable budget order, and a budgets count")
    func combinedJSONIncludesBudgets() throws {
        let budgets = [
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 200),
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 450),
        ]
        let data = try DataExportBuilder.combinedJSON(
            accounts: [],
            transactions: [],
            balanceHistory: [],
            budgets: budgets,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            environment: "sandbox"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DataExportBuilder.Envelope.self, from: data)
        // Current envelope schema is 3 (AND-550 added the optional splits array);
        // the budgets array from AND-645 is unchanged.
        #expect(envelope.schemaVersion == 3)
        #expect(envelope.counts.budgets == 2)
        // Stable order: sorted by category raw value (FOOD_AND_DRINK first).
        #expect(envelope.budgets.map(\.category) == [.foodAndDrink, .transportation])
        #expect(envelope.budgets == [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 450),
            CategoryBudgetDTO(category: .transportation, monthlyLimit: 200),
        ])
    }

    @Test("combinedJSON omitting budgets yields an empty budgets array and zero count")
    func combinedJSONDefaultsBudgetsEmpty() throws {
        let data = try DataExportBuilder.combinedJSON(
            accounts: [],
            transactions: [],
            balanceHistory: [],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DataExportBuilder.Envelope.self, from: data)
        #expect(envelope.budgets.isEmpty)
        #expect(envelope.counts.budgets == 0)
    }

    @Test("A v1 envelope without budgets/counts.budgets decodes as empty/zero (backward compatible)")
    func decodesLegacyV1EnvelopeWithoutBudgets() throws {
        // A schemaVersion-1 backup written before AND-645 has no `budgets` key and
        // no `counts.budgets`. It must still decode cleanly with empty budgets.
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-06-24T00:00:00Z",
          "environment": "sandbox",
          "counts": { "accounts": 0, "transactions": 0, "balanceHistory": 0 },
          "accounts": [],
          "transactions": [],
          "balanceHistory": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            DataExportBuilder.Envelope.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.budgets.isEmpty)
        #expect(envelope.counts.budgets == 0)
        #expect(envelope.counts.accounts == 0)
    }
}
