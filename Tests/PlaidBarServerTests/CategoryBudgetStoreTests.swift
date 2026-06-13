import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import Logging
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

@Suite("Category budget persistence (AND-402)")
struct CategoryBudgetStoreTests {
    /// Runs `body` against a BudgetStore backed by a temporary SQLite file, then
    /// always shuts Fluent down so the test does not hold database files.
    private func withBudgetStore(_ body: (BudgetStore) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("budgets.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.budgets")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateCategoryBudgets())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(BudgetStore(fluent: fluent))
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError { throw bodyError }
    }

    // MARK: - Storage round-trip

    @Test("Saved budgets round-trip and list sorted by category name")
    func roundTripSorted() async throws {
        try await withBudgetStore { store in
            try await store.saveBudget(category: .transportation, monthlyLimit: 200)
            try await store.saveBudget(category: .foodAndDrink, monthlyLimit: 500)

            let budgets = try await store.allBudgets()
            // "Food & Drink" sorts before "Transportation".
            #expect(budgets.map(\.category) == [.foodAndDrink, .transportation])
            #expect(budgets.map(\.monthlyLimit) == [500, 200])
        }
    }

    @Test("Saving the same category twice updates rather than duplicates")
    func upsertReplaces() async throws {
        try await withBudgetStore { store in
            try await store.saveBudget(category: .shopping, monthlyLimit: 150)
            try await store.saveBudget(category: .shopping, monthlyLimit: 250)

            let budgets = try await store.allBudgets()
            #expect(budgets.count == 1)
            #expect(budgets.first?.monthlyLimit == 250)
        }
    }

    @Test("Deleting a budget removes it; deleting a missing one is a no-op")
    func deleteRemovesAndTolerates() async throws {
        try await withBudgetStore { store in
            try await store.saveBudget(category: .entertainment, monthlyLimit: 100)
            try await store.deleteBudget(category: .entertainment)
            let afterDelete = try await store.allBudgets()
            #expect(afterDelete.isEmpty)

            // No throw when nothing is stored.
            try await store.deleteBudget(category: .entertainment)
        }
    }

    @Test("An empty store returns no budgets")
    func emptyStore() async throws {
        try await withBudgetStore { store in
            let budgets = try await store.allBudgets()
            #expect(budgets.isEmpty)
        }
    }

    // MARK: - Route validation

    @Test("Path category parameter parses, with bad/missing/excluded values rejected")
    func categoryValidation() throws {
        #expect(try BudgetRoutes.budgetableCategory("FOOD_AND_DRINK") == .foodAndDrink)
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory(nil) }
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory("") }
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory("NOT_A_CATEGORY") }
        // Income and transfers are not budgetable spend.
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory("INCOME") }
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory("TRANSFER_IN") }
        #expect(throws: (any Error).self) { try BudgetRoutes.budgetableCategory("TRANSFER_OUT") }
    }

    @Test("Monthly limit must be positive and finite")
    func limitValidation() throws {
        #expect(throws: Never.self) { try BudgetRoutes.validateLimit(100) }
        #expect(throws: (any Error).self) { try BudgetRoutes.validateLimit(0) }
        #expect(throws: (any Error).self) { try BudgetRoutes.validateLimit(-50) }
        #expect(throws: (any Error).self) { try BudgetRoutes.validateLimit(.nan) }
        #expect(throws: (any Error).self) { try BudgetRoutes.validateLimit(.infinity) }
    }

    @Test("CategoryBudgetsResponse.byCategory maps for the planner")
    func responseMapsToPlannerInput() {
        let response = CategoryBudgetsResponse(budgets: [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500),
            CategoryBudgetDTO(category: .shopping, monthlyLimit: 200),
        ])
        #expect(response.byCategory == [.foodAndDrink: 500, .shopping: 200])
    }
}
