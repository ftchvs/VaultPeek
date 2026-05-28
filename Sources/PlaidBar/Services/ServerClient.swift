import Foundation
import PlaidBarCore

actor ServerClient {
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 30

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
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
        self.session = URLSession(configuration: configuration)
        self.authTokenURL = authTokenURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func getStatus() async throws -> ServerStatus {
        guard let url = ServerEndpoint.url(baseURL: baseURL, path: "/api/status") else {
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

    private func post<T: Encodable & Sendable>(_ url: URL, body: T) async throws {
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await data(for: request)
        try Self.validateHTTPResponse(response, data: data)
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
        guard (200...299).contains(httpResponse.statusCode) else {
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
              let dictionary = object as? [String: Any] else {
            return nil
        }

        for key in ["message", "reason", "error", "detail", "title"] {
            if let value = dictionary[key] as? String,
               let message = value.trimmedNonEmpty {
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
        let token = try String(contentsOf: authTokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw ServerClientError.authTokenUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

enum ServerClientError: Error, LocalizedError, Sendable {
    case requestFailed
    case serverNotRunning
    case authTokenUnavailable
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Request to PlaidBar server failed"
        case .serverNotRunning: "PlaidBar server is not running"
        case .authTokenUnavailable: "PlaidBar server auth token is unavailable"
        case .httpError(let statusCode, let message):
            "PlaidBar server returned \(statusCode): \(message)"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
