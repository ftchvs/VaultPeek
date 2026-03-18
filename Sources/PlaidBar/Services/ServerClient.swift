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
        try await get("/api/status")
    }

    func getAccounts() async throws -> [AccountDTO] {
        try await get("/api/accounts")
    }

    func getBalances() async throws -> [AccountDTO] {
        try await get("/api/accounts/balances")
    }

    func syncTransactions(itemId: String? = nil) async throws -> SyncResponse {
        var path = "/api/transactions/sync"
        if let itemId {
            path += "?item_id=\(itemId)"
        }
        return try await get(path)
    }

    func createLinkToken() async throws -> LinkResponse {
        try await post("/api/link/create")
    }

    func removeItem(itemId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/accounts/\(itemId)") else {
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

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ServerClientError.requestFailed
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServerClientError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ServerClientError.requestFailed
        }
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
