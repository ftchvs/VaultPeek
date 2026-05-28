import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct LinkRoutes: Sendable {
    let plaidClient: PlaidClient
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
        let plaidResponse = try await plaidClient.createLinkToken(
            userId: userId,
            completionRedirectUri: callbackURL(state: state)
        )

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
        let plaidResponse = try await plaidClient.createUpdateLinkToken(
            userId: userId,
            accessToken: accessToken,
            completionRedirectUri: callbackURL(state: state)
        )

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
    let plaidClient: PlaidClient
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
            let publicTokens = try await publicTokens(from: request, pendingSession: pendingSession)
            if publicTokens.isEmpty, let updateItemId = pendingSession.updateItemId {
                try await tokenStore.updateItemStatus(id: updateItemId, status: ItemConnectionStatus.connected.rawValue)
                return Response(
                    status: .ok,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
                )
            }

            guard !publicTokens.isEmpty else {
                return Response(
                    status: .badRequest,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(
                        string: Self.errorPage("Plaid Link completed without a public token")
                    ))
                )
            }

            for publicToken in publicTokens {
                try await exchangeAndStore(publicToken: publicToken)
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

    private func publicTokens(
        from request: Request,
        pendingSession: PendingLinkSession
    ) async throws -> [String] {
        if let publicToken = request.uri.queryParameters.get("public_token") {
            return [String(publicToken)]
        }

        let linkSession = try await plaidClient.getLinkToken(pendingSession.linkToken)
        return linkSession.publicTokens
    }

    private func exchangeAndStore(publicToken: String) async throws {
        let exchangeResponse = try await plaidClient.exchangePublicToken(publicToken)
        let accountsResponse = try await plaidClient.getAccounts(
            accessToken: exchangeResponse.accessToken
        )
        let institutionId = accountsResponse.item?.institutionId

        try await tokenStore.saveItem(
            id: exchangeResponse.itemId,
            accessToken: exchangeResponse.accessToken,
            institutionId: institutionId,
            institutionName: nil
        )
    }

    // MARK: - HTML Pages

    private static func successPage() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>PlaidBar -- Connected!</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
            <h1>Account Connected</h1>
            <p>Your bank account has been linked to PlaidBar.</p>
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
        <head><title>PlaidBar -- Error</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
            <h1>Connection Error</h1>
            <p>\(escapedMessage)</p>
            <p>Please try again from PlaidBar.</p>
        </body>
        </html>
        """
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
