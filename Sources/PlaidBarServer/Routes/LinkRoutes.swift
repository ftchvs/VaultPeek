import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct LinkRoutes: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    let pendingLinkSessions: PendingLinkSessionStore
    let config: ServerConfig

    func register(with group: RouterGroup<some RequestContext>) {
        let link = group.group("link")
        link.post("create", use: createLinkToken)
        link.group("update")
            .post("{itemId}", use: createUpdateLinkToken)
    }

    @Sendable
    func createLinkToken(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let userId = "plaidbar-user-\(UUID().uuidString.prefix(8))"
        let state = await pendingLinkSessions.issueState()
        let plaidResponse = try await Self.mappingPlaidError {
            try await plaidClient.createLinkToken(
                userId: userId,
                completionRedirectUri: callbackURL(state: state)
            )
        }

        guard let linkUrl = plaidResponse.hostedLinkUrl else {
            throw HTTPError(.internalServerError, message: "Plaid did not return a hosted Link URL")
        }
        await pendingLinkSessions.save(state: state, linkToken: plaidResponse.linkToken)
        let dto = LinkResponse(linkToken: plaidResponse.linkToken, linkUrl: linkUrl)

        let data = try JSONEncoder().encode(dto)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    @Sendable
    func createUpdateLinkToken(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        guard let itemId = context.parameters.get("itemId") else {
            throw HTTPError(.badRequest, message: "Missing itemId parameter")
        }
        guard let item = try await tokenStore.getItem(id: itemId) else {
            throw HTTPError(.notFound, message: "Plaid item not found")
        }
        let accessToken = try tokenStore.accessToken(for: item)

        let userId = "plaidbar-user-\(UUID().uuidString.prefix(8))"
        let state = await pendingLinkSessions.issueState()
        let plaidResponse = try await Self.mappingPlaidError {
            try await plaidClient.createUpdateLinkToken(
                userId: userId,
                accessToken: accessToken,
                completionRedirectUri: callbackURL(state: state)
            )
        }

        guard let linkUrl = plaidResponse.hostedLinkUrl else {
            throw HTTPError(.internalServerError, message: "Plaid did not return a hosted Link URL")
        }
        await pendingLinkSessions.save(
            state: state,
            linkToken: plaidResponse.linkToken,
            updateItemId: itemId
        )
        let dto = LinkResponse(linkToken: plaidResponse.linkToken, linkUrl: linkUrl)

        let data = try JSONEncoder().encode(dto)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    /// Runs a Plaid Link call and translates `PlaidError.apiError` into an
    /// actionable `HTTPError` so the client sees the Plaid error code/message
    /// instead of an opaque, empty-bodied 500. `credentialsNotConfigured` is
    /// rethrown unchanged so the setup-state middleware can map it to a 503
    /// with credential guidance.
    private static func mappingPlaidError<T: Sendable>(
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch let error as PlaidError {
            switch error {
            case .credentialsNotConfigured:
                throw error
            case let .apiError(_, errorType, errorCode, _):
                throw HTTPError(.badGateway, message: linkErrorMessage(
                    errorType: errorType,
                    errorCode: errorCode
                ))
            case .invalidResponse:
                throw HTTPError(.badGateway, message: "Plaid returned an invalid response")
            }
        }
    }

    /// Builds an actionable, app-safe Link error string from Plaid's *stable*
    /// `error_code`/`error_type` enum identifiers only.
    ///
    /// Plaid's free-form `error_message` is deliberately NOT echoed: `AGENTS.md`
    /// treats moving raw provider payloads into the SwiftUI app as high priority,
    /// and that field is provider-controlled text that can carry request/provider
    /// detail beyond the local diagnosis (this string reaches `AppState.error`
    /// via `ServerClient`). Instead, known codes map to a curated local
    /// description, and anything unrecognized degrades to a generic message that
    /// still carries only the bounded code identifier — never provider prose.
    static func linkErrorMessage(
        errorType: String?,
        errorCode: String?
    ) -> String {
        let code = errorCode ?? errorType ?? "PLAID_ERROR"
        if let description = knownLinkErrorDescriptions[code] {
            return "Plaid Link error (\(code)): \(description)"
        }
        return "Plaid Link error (\(code)). Please try connecting again, or check the "
            + "VaultPeek companion server logs for details."
    }

    /// Allowlist of Plaid Link `error_code`/`error_type` identifiers mapped to
    /// locally-authored, secret-free guidance. Keys are Plaid's documented enum
    /// values; values never contain provider-supplied free text.
    private static let knownLinkErrorDescriptions: [String: String] = [
        "INVALID_FIELD":
            "A Link request field was rejected by Plaid. If this is an OAuth flow, "
            + "confirm the redirect URI is registered in the Plaid dashboard.",
        "INVALID_API_KEYS":
            "Plaid rejected the configured credentials. Verify PLAID_CLIENT_ID and "
            + "PLAID_SECRET in the VaultPeek companion server config.",
        "INVALID_REQUEST":
            "Plaid rejected the Link request. Please try connecting again.",
        "RATE_LIMIT_EXCEEDED":
            "Plaid is rate-limiting requests. Please wait a moment and try again.",
        "INSTITUTION_DOWN":
            "The selected institution is temporarily unavailable. Please try again later.",
        "INSTITUTION_NOT_RESPONDING":
            "The selected institution is not responding. Please try again later.",
        "INTERNAL_SERVER_ERROR":
            "Plaid reported a temporary internal error. Please try again shortly.",
        "PLANNED_MAINTENANCE":
            "Plaid is undergoing planned maintenance. Please try again later.",
    ]

    private func callbackURL(state: String) -> String {
        guard var components = URLComponents(string: config.redirectUri) else {
            return config.redirectUri
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "state", value: state))
        components.queryItems = queryItems
        return components.string ?? config.redirectUri
    }
}

// MARK: - OAuth Callback (top-level route, not under /api)

struct OAuthCallbackRoute: Sendable {
    let plaidClient: any PlaidClientProtocol
    let tokenStore: TokenStore
    let pendingLinkSessions: PendingLinkSessionStore

    func register(with router: Router<some RequestContext>) {
        router.get("oauth/callback", use: handleCallback)
    }

    @Sendable
    func handleCallback(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        guard let stateParam = request.uri.queryParameters.get("state"),
              let pendingSession = await pendingLinkSessions.consume(state: String(stateParam))
        else {
            return Response(
                status: .badRequest,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(
                    string: Self.errorPage("Missing or expired link session state")
                ))
            )
        }

        do {
            let publicTokenResults = try await publicTokenResults(from: request, pendingSession: pendingSession)
            if publicTokenResults.isEmpty, let updateItemId = pendingSession.updateItemId {
                try await tokenStore.updateItemStatus(id: updateItemId, status: ItemConnectionStatus.connected.rawValue)
                return Response(
                    status: .ok,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
                )
            }

            guard !publicTokenResults.isEmpty else {
                return Response(
                    status: .badRequest,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(
                        string: Self.errorPage("Plaid Link completed without a public token")
                    ))
                )
            }

            for publicTokenResult in publicTokenResults {
                try await exchangeAndStore(publicTokenResult: publicTokenResult)
            }

            return Response(
                status: .ok,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
            )
        } catch {
            return Response(
                status: .internalServerError,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(
                    string: Self.errorPage(error.localizedDescription)
                ))
            )
        }
    }

    private func publicTokenResults(
        from request: Request,
        pendingSession: PendingLinkSession
    ) async throws -> [PlaidPublicTokenResult] {
        if let publicToken = request.uri.queryParameters.get("public_token") {
            return [PlaidPublicTokenResult(publicToken: String(publicToken), institution: nil)]
        }

        let linkSession = try await plaidClient.getLinkToken(pendingSession.linkToken)
        return linkSession.publicTokenResults
    }

    private func exchangeAndStore(publicTokenResult: PlaidPublicTokenResult) async throws {
        let exchangeResponse = try await plaidClient.exchangePublicToken(publicTokenResult.publicToken)
        let accountsResponse = try await plaidClient.getAccounts(
            accessToken: exchangeResponse.accessToken
        )
        let institutionId = publicTokenResult.institution?.institutionId ?? accountsResponse.item?.institutionId

        try await tokenStore.saveItem(
            id: exchangeResponse.itemId,
            accessToken: exchangeResponse.accessToken,
            institutionId: institutionId,
            institutionName: publicTokenResult.institution?.normalizedName
        )
    }

    // MARK: - HTML Pages

    private static func successPage() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>VaultPeek -- Connected!</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
            <h1>Account Connected</h1>
            <p>Your bank account has been linked to VaultPeek.</p>
            <p>You can close this tab and return to the app.</p>
            <script>setTimeout(() => window.close(), 3000);</script>
        </body>
        </html>
        """
    }

    static func errorPage(_ message: String) -> String {
        let escapedMessage = message.htmlEscaped
        return """
        <!DOCTYPE html>
        <html>
        <head><title>VaultPeek -- Error</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
            <h1>Connection Error</h1>
            <p>\(escapedMessage)</p>
            <p>Please try again from VaultPeek.</p>
        </body>
        </html>
        """
    }
}

private extension PlaidLinkInstitution {
    var normalizedName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
