import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// `/api/budgets` — CRUD for user-set category budgets (AND-402). Registered
/// under the same `APITokenMiddleware`-guarded group as the other API routes, so
/// every call requires the bearer token. Budgets are display-safe values only.
struct BudgetRoutes: Sendable {
    let budgetStore: BudgetStore

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("budgets")
            .get(use: listBudgets)
            .put(":category", use: saveBudget)
            .delete(":category", use: deleteBudget)
    }

    @Sendable
    func listBudgets(request: Request, context: some RequestContext) async throws -> Response {
        let budgets = try await budgetStore.allBudgets()
        return try Self.jsonResponse(CategoryBudgetsResponse(budgets: budgets))
    }

    @Sendable
    func saveBudget(request: Request, context: some RequestContext) async throws -> Response {
        let category = try Self.budgetableCategory(context.parameters.get("category"))
        let body = try await request.decode(as: SaveCategoryBudgetRequest.self, context: context)
        try Self.validateLimit(body.monthlyLimit)
        try await budgetStore.saveBudget(category: category, monthlyLimit: body.monthlyLimit)
        return try Self.jsonResponse(CategoryBudgetDTO(category: category, monthlyLimit: body.monthlyLimit))
    }

    @Sendable
    func deleteBudget(request: Request, context: some RequestContext) async throws -> HTTPResponse.Status {
        let category = try Self.budgetableCategory(context.parameters.get("category"))
        try await budgetStore.deleteBudget(category: category)
        return .noContent
    }

    // MARK: - Validation (pure, testable without a request context)

    /// Resolve the `{category}` path parameter to a budgetable `SpendingCategory`.
    /// Income and transfer categories are not spend, so they are rejected.
    static func budgetableCategory(_ raw: String?) throws -> SpendingCategory {
        guard let raw, !raw.isEmpty else {
            throw HTTPError(.badRequest, message: "Missing category path parameter")
        }
        guard let category = SpendingCategory(rawValue: raw) else {
            throw HTTPError(.badRequest, message: "Unknown spending category '\(raw)'")
        }
        guard !CategoryBudgetPlanner.excludedCategories.contains(category) else {
            throw HTTPError(.badRequest, message: "Income and transfer categories cannot be budgeted")
        }
        return category
    }

    static func validateLimit(_ limit: Double) throws {
        guard limit.isFinite, limit > 0 else {
            throw HTTPError(.badRequest, message: "monthlyLimit must be a positive amount")
        }
    }

    static func jsonResponse(_ value: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}
