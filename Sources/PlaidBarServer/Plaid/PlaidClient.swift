import Foundation
import PlaidBarCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

protocol PlaidClientProtocol: Sendable {
    func createLinkToken(
        clientUserId: String,
        completionRedirectUri: String
    ) async throws -> PlaidLinkTokenResponse

    func createUpdateLinkToken(
        clientUserId: String,
        accessToken: String,
        completionRedirectUri: String
    ) async throws -> PlaidLinkTokenResponse

    func getLinkToken(_ linkToken: String) async throws -> PlaidLinkTokenGetResponse

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidTokenExchangeResponse

    func getAccounts(accessToken: String) async throws -> PlaidAccountsResponse

    func getBalances(accessToken: String) async throws -> PlaidAccountsResponse

    func syncTransactions(
        accessToken: String,
        cursor: String?
    ) async throws -> PlaidTransactionsSyncResponse

    func removeItem(accessToken: String) async throws
}

actor PlaidClient: PlaidClientProtocol {
    private let config: ServerConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maxAttempts: Int
    private let retryBaseDelayNanoseconds: UInt64

    init(
        config: ServerConfig,
        session: URLSession = PlaidClient.makeDefaultSession(),
        maxAttempts: Int = 3,
        retryBaseDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.config = config
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
        self.retryBaseDelayNanoseconds = retryBaseDelayNanoseconds

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        encoder = enc
    }

    // MARK: - Link Token

    func createLinkToken(
        clientUserId: String,
        completionRedirectUri: String
    ) async throws -> PlaidLinkTokenResponse {
        let body = try config.link.createRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            clientUserId: clientUserId,
            completionRedirectURI: completionRedirectUri
        )
        return try await post("/link/token/create", body: body)
    }

    func createUpdateLinkToken(
        clientUserId: String,
        accessToken: String,
        completionRedirectUri: String
    ) async throws -> PlaidLinkTokenResponse {
        let body = try config.link.updateRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            clientUserId: clientUserId,
            accessToken: accessToken,
            completionRedirectURI: completionRedirectUri
        )
        return try await post("/link/token/create", body: body)
    }

    func getLinkToken(_ linkToken: String) async throws -> PlaidLinkTokenGetResponse {
        let body = PlaidLinkTokenGetRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            linkToken: linkToken
        )
        return try await post("/link/token/get", body: body)
    }

    // MARK: - Token Exchange

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidTokenExchangeResponse {
        let body = PlaidTokenExchangeRequest(
            clientId: config.plaidClientId,
            secret: config.plaidSecret,
            publicToken: publicToken
        )
        return try await post("/item/public_token/exchange", body: body, retryPolicy: .singleAttempt)
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
        let _: PlaidBaseResponse = try await post("/item/remove", body: body, retryPolicy: .singleAttempt)
    }

    // MARK: - Private

    private func post<R: Decodable>(
        _ path: String,
        body: some Encodable,
        retryPolicy: PlaidRetryPolicy = .transient
    ) async throws -> R {
        // Setup state: the server booted without credentials, so no request
        // can ever succeed. Fail before contacting Plaid with an error the
        // routes surface as 503 instead of leaking a Plaid auth failure.
        guard config.credentialsConfigured else {
            throw PlaidError.credentialsNotConfigured
        }
        guard let url = URL(string: "\(config.plaidBaseURL)\(path)") else {
            throw PlaidError.invalidResponse
        }

        let requestBody = try encoder.encode(body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody

        let allowedAttempts = Self.allowedAttempts(maxAttempts: maxAttempts, retryPolicy: retryPolicy)
        for attempt in 1 ... allowedAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PlaidError.invalidResponse
                }

                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    if Self.isRetryableHTTPStatus(httpResponse.statusCode), attempt < allowedAttempts {
                        try await sleepBeforeRetry(attempt: attempt)
                        continue
                    }

                    let errorBody = try? decoder.decode(PlaidErrorResponse.self, from: data)
                    throw PlaidError.apiError(
                        statusCode: httpResponse.statusCode,
                        errorType: errorBody?.errorType,
                        errorCode: errorBody?.errorCode,
                        errorMessage: errorBody?.errorMessage ?? "Unknown error"
                    )
                }

                return try decoder.decode(R.self, from: data)
            } catch let error as CancellationError {
                throw error
            } catch {
                guard attempt < allowedAttempts, Self.isRetryableTransportError(error) else {
                    throw error
                }
                try await sleepBeforeRetry(attempt: attempt)
            }
        }

        throw PlaidError.invalidResponse
    }

    private func sleepBeforeRetry(attempt: Int) async throws {
        let delay = Self.retryDelayNanoseconds(
            baseDelayNanoseconds: retryBaseDelayNanoseconds,
            attempt: attempt
        )
        try await Task.sleep(nanoseconds: delay)
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500 ... 599).contains(statusCode)
    }

    static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    static func retryDelayNanoseconds(baseDelayNanoseconds: UInt64, attempt: Int) -> UInt64 {
        let exponent = UInt64(max(0, attempt - 1))
        let multiplier = UInt64(1) << min(exponent, 4)
        return min(baseDelayNanoseconds * multiplier, 8_000_000_000)
    }

    static func allowedAttempts(maxAttempts: Int, retryPolicy: PlaidRetryPolicy) -> Int {
        switch retryPolicy {
        case .transient:
            max(1, maxAttempts)
        case .singleAttempt:
            1
        }
    }
}

enum PlaidRetryPolicy: Sendable {
    case transient
    case singleAttempt
}

// MARK: - Errors

enum PlaidError: Error, LocalizedError, Equatable, Sendable {
    case credentialsNotConfigured
    case invalidResponse
    case apiError(
        statusCode: Int,
        errorType: String?,
        errorCode: String?,
        errorMessage: String
    )

    var errorDescription: String? {
        switch self {
        case .credentialsNotConfigured:
            "Plaid credentials are not configured. Add PLAID_CLIENT_ID and PLAID_SECRET "
                + "to server.conf, then restart the VaultPeek companion server."
        case .invalidResponse:
            "Invalid response from Plaid API"
        case let .apiError(statusCode, _, _, message):
            "Plaid API error (\(statusCode)): \(message)"
        }
    }
}
