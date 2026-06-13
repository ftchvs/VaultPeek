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
        guard let stateParam = request.uri.queryParameters.get("state") else {
            return Response(
                status: .badRequest,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(
                    string: Self.errorPage("Missing or expired link session state")
                ))
            )
        }
        let state = String(stateParam)
        guard let pendingSession = await pendingLinkSessions.beginCompletion(state: state) else {
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
                _ = await pendingLinkSessions.consume(state: state)
                return Response(
                    status: .ok,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
                )
            }

            guard !publicTokenResults.isEmpty else {
                await pendingLinkSessions.releaseCompletion(state: state)
                return Response(
                    status: .badRequest,
                    headers: [.contentType: "text/html"],
                    body: .init(byteBuffer: ByteBuffer(
                        string: Self.errorPage("Plaid Link completed without a public token")
                    ))
                )
            }

            let completedResultCount = min(
                pendingSession.completedPublicTokenResultCount,
                publicTokenResults.count
            )
            for publicTokenResult in publicTokenResults.dropFirst(completedResultCount) {
                try await exchangeAndStore(publicTokenResult: publicTokenResult)
                await pendingLinkSessions.markPublicTokenResultStored(state: state)
            }
            _ = await pendingLinkSessions.consume(state: state)

            return Response(
                status: .ok,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
            )
        } catch {
            await pendingLinkSessions.releaseCompletion(state: state)
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
