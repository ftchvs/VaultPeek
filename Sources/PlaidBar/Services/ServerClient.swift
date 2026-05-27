import Foundation
import PlaidBarCore

actor ServerClient {
    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: String = PlaidBarConstants.serverBaseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
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
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServerClientError.requestFailed
        }
    }

    // MARK: - Private

    private func get<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServerClientError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServerClientError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }
}

enum ServerClientError: Error, LocalizedError, Sendable {
    case requestFailed
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Request to PlaidBar server failed"
        case .serverNotRunning: "PlaidBar server is not running"
        }
    }
}
