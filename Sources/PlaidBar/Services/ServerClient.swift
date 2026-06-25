import Foundation
import PlaidBarCore

actor ServerClient {
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 30

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let authTokenURL: URL

    init(
        baseURL: String = PlaidBarConstants.serverBaseURL,
        authTokenURL: URL = LocalDataStore.authTokenURL()
    ) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        self.authTokenURL = authTokenURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func getStatusIncludingItems() async throws -> ServerStatus {
        guard let url = ServerEndpoint.statusURL(baseURL: baseURL, includeItems: true) else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    func getItems() async throws -> [ItemStatus] {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/items") else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    // Reserved for the gated billing track (AND-392/393) — deferred scaffolding, no live callers yet.
    func getBillingSubscription() async throws -> BillingSubscription? {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/billing/subscription") else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    func saveBillingSubscription(_ request: SaveBillingSubscriptionRequest) async throws -> BillingSubscription {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/billing/subscription") else {
            throw ServerClientError.requestFailed
        }
        return try await put(url, body: request)
    }

    func getAccounts() async throws -> [AccountDTO] {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/accounts") else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    func getBalances() async throws -> [AccountDTO] {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/accounts/balances") else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    func getLiabilities() async throws -> [LiabilityDTO] {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/accounts/liabilities") else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    /// Plaid Investments holdings + securities for every linked item that has the
    /// `investments` product. The server joins per-item responses; items without
    /// the scope contribute nothing (never an error).
    func getInvestmentHoldings() async throws -> InvestmentsResponse {
        guard let url = ServerEndpoint.investmentHoldingsURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    /// Raw image bytes for a merchant logo, fetched + on-disk-cached by the local
    /// server's authenticated proxy. The app never reaches a logo CDN directly.
    func merchantLogoData(for logoURL: String) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)/api/merchant-logo")
        components?.queryItems = [URLQueryItem(name: "u", value: logoURL)]
        guard let url = components?.url else {
            throw ServerClientError.requestFailed
        }
        let request = try authorizedRequest(url: url)
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return data
    }

    func listCategoryBudgets() async throws -> [CategoryBudgetDTO] {
        guard let url = ServerEndpoint.categoryBudgetsURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        let response: CategoryBudgetsResponse = try await get(url)
        return response.budgets
    }

    func saveCategoryBudget(categoryId: String, amount: Double) async throws -> CategoryBudgetDTO {
        guard let url = ServerEndpoint.saveCategoryBudgetURL(baseURL: baseURL, categoryId: categoryId) else {
            throw ServerClientError.requestFailed
        }
        return try await put(url, body: SaveCategoryBudgetRequest(monthlyLimit: amount))
    }

    func deleteCategoryBudget(categoryId: String) async throws {
        guard let url = ServerEndpoint.deleteCategoryBudgetURL(baseURL: baseURL, categoryId: categoryId) else {
            throw ServerClientError.requestFailed
        }
        try await delete(url)
    }

    // MARK: - Opt-in server-synced review state (AND-552)

    /// Pull the server's stored review-state snapshot. Only called when the user
    /// has enabled `ServerSyncedReviewFeatureFlag` (default OFF); a not-opted-in
    /// app never reaches this.
    func getReviewState() async throws -> ReviewStateSnapshotDTO {
        guard let url = ServerEndpoint.reviewStateURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    /// Upload the device's review-state snapshot and return the server's merged
    /// union (per-record last-writer-wins). Opt-in only.
    func putReviewState(_ snapshot: ReviewStateSnapshotDTO) async throws -> ReviewStateSnapshotDTO {
        guard let url = ServerEndpoint.reviewStateURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        return try await put(url, body: snapshot)
    }

    /// Clear all synced review state on the server (opt-out / reset). Opt-in only.
    func clearReviewState() async throws {
        guard let url = ServerEndpoint.reviewStateURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        try await delete(url)
    }

    func syncTransactions(itemId: String? = nil) async throws -> SyncResponse {
        guard let url = ServerEndpoint.transactionSyncURL(baseURL: baseURL, itemId: itemId) else {
            throw ServerClientError.requestFailed
        }
        return try await get(url)
    }

    func commitSyncCursors(_ cursors: [String: String]) async throws {
        guard !cursors.isEmpty else { return }
        guard let url = ServerEndpoint.transactionCursorCommitURL(baseURL: baseURL) else {
            throw ServerClientError.requestFailed
        }
        try await post(url, body: SyncCursorCommitRequest(cursors: cursors))
    }

    func createLinkToken() async throws -> LinkResponse {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/link/create") else {
            throw ServerClientError.requestFailed
        }
        return try await post(url)
    }

    func createUpdateLinkToken(itemId: String) async throws -> LinkResponse {
        guard let url = ServerEndpoint.updateLinkTokenURL(baseURL: baseURL, itemId: itemId) else {
            throw ServerClientError.requestFailed
        }
        return try await post(url)
    }

    func removeItem(itemId: String) async throws {
        guard let url = ServerEndpoint.removeItemURL(baseURL: baseURL, itemId: itemId) else {
            throw ServerClientError.requestFailed
        }
        var request = try authorizedRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
    }

    // MARK: - Private

    private func get<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        let request = try authorizedRequest(url: url)
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func put<T: Decodable & Sendable>(
        _ url: URL,
        body: some Encodable & Sendable
    ) async throws -> T {
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ url: URL, body: some Encodable & Sendable) async throws {
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
    }

    private func delete(_ url: URL) async throws {
        var request = try authorizedRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
    }

    /// Unauthenticated probe of `/health`. Distinguishes "no server is
    /// listening" from "a server is up but this client cannot authenticate",
    /// so the bundled-server auto-launch never races an externally managed
    /// server just because the local auth token is missing or stale.
    func isLocalServerResponding() async -> Bool {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200 ... 299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where Self.isLocalServerTransportFailure(error) {
            throw ServerClientError.serverNotRunning
        } catch {
            throw error
        }
    }

    private static func isLocalServerTransportFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut:
            true
        default:
            false
        }
    }

    private static func validateHTTPResponse(
        _ response: URLResponse,
        data: Data
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerClientError.requestFailed
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServerClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let jsonMessage = jsonErrorMessage(from: data) {
            return jsonMessage
        }

        if let body = String(data: data, encoding: .utf8)?.trimmedNonEmpty {
            return truncate(body)
        }

        return HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    private static func jsonErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        for key in ["message", "reason", "error", "detail", "title"] {
            if let value = dictionary[key] as? String,
               let message = value.trimmedNonEmpty
            {
                return truncate(message)
            }
        }
        return nil
    }

    private static func truncate(_ message: String) -> String {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 500 else { return normalized }
        return String(normalized.prefix(500)) + "..."
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        // A missing token file means the server has not been started yet --
        // surface the clean typed error, never Cocoa's raw file message.
        guard let token = (try? String(contentsOf: authTokenURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw ServerClientError.authTokenUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

enum ServerClientError: Error, LocalizedError {
    case requestFailed
    case serverNotRunning
    case authTokenUnavailable
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Request to the VaultPeek companion server failed"
        case .serverNotRunning: "The VaultPeek companion server is not running"
        // Keep the "auth token is unavailable" substring intact: the recovery
        // matchers in DashboardStatusReadiness, AttentionQueue, and
        // ServerConnectionPresentation key off it.
        case .authTokenUnavailable: "VaultPeek companion server auth token is unavailable. Start the server, then check again."
        case let .httpError(statusCode, message):
            "VaultPeek companion server returned \(statusCode): \(message)"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
