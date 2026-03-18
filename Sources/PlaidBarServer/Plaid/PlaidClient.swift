import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor PlaidClient {
    private let config: ServerConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(config: ServerConfig) {
        self.config = config
        self.session = URLSession.shared

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc
    }

    // MARK: - Link Token

    func createLinkToken(userId: String) async throws -> PlaidLinkTokenResponse {
        let body = PlaidLinkTokenRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            clientName: "PlaidBar",
            user: .init(clientUserId: userId),
            products: ["transactions"],
            countryCodes: ["US"],
            language: "en",
            redirectUri: config.redirectUri
        )
        return try await post("/link/token/create", body: body)
    }

    // MARK: - Token Exchange

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidTokenExchangeResponse {
        let body = PlaidTokenExchangeRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            publicToken: publicToken
        )
        return try await post("/item/public_token/exchange", body: body)
    }

    // MARK: - Accounts

    func getAccounts(accessToken: String) async throws -> PlaidAccountsResponse {
        let body = PlaidAuthenticatedRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            accessToken: accessToken
        )
        return try await post("/accounts/get", body: body)
    }

    func getBalances(accessToken: String) async throws -> PlaidAccountsResponse {
        let body = PlaidAuthenticatedRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            accessToken: accessToken
        )
        return try await post("/accounts/balance/get", body: body)
    }

    // MARK: - Transactions Sync

    func syncTransactions(
        accessToken: String,
        cursor: String?
    ) async throws -> PlaidTransactionsSyncResponse {
        let body = PlaidTransactionsSyncRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            accessToken: accessToken,
            cursor: cursor ?? "",
            count: 500
        )
        return try await post("/transactions/sync", body: body)
    }

    // MARK: - Remove Item

    func removeItem(accessToken: String) async throws {
        let body = PlaidAuthenticatedRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            accessToken: accessToken
        )
        let _: PlaidBaseResponse = try await post("/item/remove", body: body)
    }

    // MARK: - Private

    private func post<T: Encodable, R: Decodable>(
        _ path: String,
        body: T
    ) async throws -> R {
        guard let url = URL(string: "\(config.plaidBaseURL)\(path)") else {
            throw PlaidError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaidError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = try? decoder.decode(PlaidErrorResponse.self, from: data)
            throw PlaidError.apiError(
                statusCode: httpResponse.statusCode,
                errorType: errorBody?.errorType,
                errorCode: errorBody?.errorCode,
                errorMessage: errorBody?.errorMessage ?? "Unknown error"
            )
        }

        return try decoder.decode(R.self, from: data)
    }
}

// MARK: - Errors

enum PlaidError: Error, LocalizedError, Sendable {
    case invalidResponse
    case apiError(
        statusCode: Int,
        errorType: String?,
        errorCode: String?,
        errorMessage: String
    )

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Plaid API"
        case .apiError(let statusCode, _, _, let message):
            "Plaid API error (\(statusCode)): \(message)"
        }
    }
}
