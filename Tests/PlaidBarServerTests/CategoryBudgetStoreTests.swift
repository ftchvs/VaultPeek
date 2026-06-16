import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdTesting
import Logging
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

@Suite("Category budget persistence (AND-402)")
struct CategoryBudgetStoreTests {
    private let apiToken = "local-budget-token"

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

    /// Runs `body` against the real `/api/budgets` route registered behind the
    /// same bearer-token middleware shape as the server. The temporary SQLite
    /// database is migrated first so these tests fail if the budget table is not
    /// available to the wired route/store contract.
    private func withBudgetAPI(_ body: @Sendable (any TestClientProtocol) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-budget-api-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("budgets.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.budget-api")
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateCategoryBudgets())

        var bodyError: Error?
        do {
            try await fluent.migrate()

            let router = Router()
            let api = router.group("api")
            api.add(middleware: APITokenMiddleware(authToken: apiToken))
            BudgetRoutes(budgetStore: BudgetStore(fluent: fluent))
                .register(with: api)

            let app = Application(router: router, logger: logger)
            try await app.test(.router) { client in
                try await body(client)
            }
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError { throw bodyError }
    }

    private var authorizedJSONHeaders: HTTPFields {
        var headers = HTTPFields()
        headers[.authorization] = "Bearer \(apiToken)"
        headers[.contentType] = "application/json"
        return headers
    }

    private func encodeBudgetRequest(monthlyLimit: Double) throws -> ByteBuffer {
        ByteBuffer(data: try JSONEncoder().encode(SaveCategoryBudgetRequest(monthlyLimit: monthlyLimit)))
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from response: TestResponse) throws -> T {
        var body = response.body
        let data = body.readData(length: body.readableBytes) ?? Data()
        return try JSONDecoder().decode(T.self, from: data)
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

    // MARK: - API contract round-trip

    @Test("GET /api/budgets starts empty after the category budget migration")
    func apiListBudgetsStartsEmptyAfterMigration() async throws {
        try await withBudgetAPI { client in
            let response = try await client.execute(
                uri: "/api/budgets",
                method: .get,
                headers: authorizedJSONHeaders
            )

            #expect(response.status == .ok)
            let payload = try decodeResponse(CategoryBudgetsResponse.self, from: response)
            #expect(payload.budgets.isEmpty)
        }
    }

    @Test("PUT/GET/DELETE /api/budgets/{category} round-trips the client payload shape")
    func apiBudgetRoundTripContract() async throws {
        try await withBudgetAPI { client in
            let create = try await client.execute(
                uri: "/api/budgets/FOOD_AND_DRINK",
                method: .put,
                headers: authorizedJSONHeaders,
                body: try encodeBudgetRequest(monthlyLimit: 125.50)
            )
            #expect(create.status == .ok)
            let created = try decodeResponse(CategoryBudgetDTO.self, from: create)
            #expect(created.category == .foodAndDrink)
            #expect(created.monthlyLimit == 125.50)

            let update = try await client.execute(
                uri: "/api/budgets/FOOD_AND_DRINK",
                method: .put,
                headers: authorizedJSONHeaders,
                body: try encodeBudgetRequest(monthlyLimit: 150.75)
            )
            #expect(update.status == .ok)
            let updated = try decodeResponse(CategoryBudgetDTO.self, from: update)
            #expect(updated.category == .foodAndDrink)
            #expect(updated.monthlyLimit == 150.75)

            let listAfterUpdate = try await client.execute(
                uri: "/api/budgets",
                method: .get,
                headers: authorizedJSONHeaders
            )
            #expect(listAfterUpdate.status == .ok)
            let persisted = try decodeResponse(CategoryBudgetsResponse.self, from: listAfterUpdate)
            #expect(persisted.budgets == [
                CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 150.75),
            ])

            let delete = try await client.execute(
                uri: "/api/budgets/FOOD_AND_DRINK",
                method: .delete,
                headers: authorizedJSONHeaders
            )
            #expect(delete.status == .noContent)

            let listAfterDelete = try await client.execute(
                uri: "/api/budgets",
                method: .get,
                headers: authorizedJSONHeaders
            )
            #expect(listAfterDelete.status == .ok)
            let deleted = try decodeResponse(CategoryBudgetsResponse.self, from: listAfterDelete)
            #expect(deleted.budgets.isEmpty)
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

    @Test("Budget route payloads use the documented JSON contract")
    func payloadJSONContract() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        let saveData = try encoder.encode(SaveCategoryBudgetRequest(monthlyLimit: 123.45))
        #expect(String(data: saveData, encoding: .utf8) == "{\"monthlyLimit\":123.45}")
        let decodedSave = try decoder.decode(SaveCategoryBudgetRequest.self, from: saveData)
        #expect(decodedSave.monthlyLimit == 123.45)

        let response = CategoryBudgetsResponse(budgets: [
            CategoryBudgetDTO(category: .foodAndDrink, monthlyLimit: 500),
        ])
        let responseData = try encoder.encode(response)
        #expect(String(data: responseData, encoding: .utf8) == "{\"budgets\":[{\"category\":\"FOOD_AND_DRINK\",\"monthlyLimit\":500}]}")
        let decodedResponse = try decoder.decode(CategoryBudgetsResponse.self, from: responseData)
        #expect(decodedResponse.budgets == response.budgets)
    }
}
