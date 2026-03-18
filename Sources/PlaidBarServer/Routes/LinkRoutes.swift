import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct LinkRoutes: Sendable {
    let plaidClient: PlaidClient
    let tokenStore: TokenStore
    let config: ServerConfig

    func register(with group: RouterGroup<some RequestContext>) {
        group.group("link")
            .post("create", use: createLinkToken)
    }

    @Sendable
    func createLinkToken(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let userId = "plaidbar-user-\(UUID().uuidString.prefix(8))"
        let plaidResponse = try await plaidClient.createLinkToken(userId: userId)

        let linkUrl = plaidResponse.hostedLinkUrl(redirectUri: config.redirectUri)
        let dto = LinkResponse(linkToken: plaidResponse.linkToken, linkUrl: linkUrl)

        let data = try JSONEncoder().encode(dto)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

// MARK: - OAuth Callback (top-level route, not under /api)

struct OAuthCallbackRoute: Sendable {
    let plaidClient: PlaidClient
    let tokenStore: TokenStore

    func register(with router: Router<some RequestContext>) {
        router.get("oauth/callback", use: handleCallback)
    }

    @Sendable
    func handleCallback(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        // Extract public_token from query params
        guard let publicToken = request.uri.queryParameters.get("public_token") else {
            return Response(
                status: .badRequest,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(
                    string: Self.errorPage("Missing public_token parameter")
                ))
            )
        }

        // Exchange public token for access token
        let exchangeResponse = try await plaidClient.exchangePublicToken(
            String(publicToken)
        )

        // Get account info to determine institution
        let accountsResponse = try await plaidClient.getAccounts(
            accessToken: exchangeResponse.accessToken
        )
        let institutionId = accountsResponse.item?.institutionId

        // Store the item
        try await tokenStore.saveItem(
            id: exchangeResponse.itemId,
            accessToken: exchangeResponse.accessToken,
            institutionId: institutionId,
            institutionName: nil
        )

        return Response(
            status: .ok,
            headers: [.contentType: "text/html"],
            body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
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

    private static func errorPage(_ message: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>PlaidBar -- Error</title></head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 60px;">
            <h1>Connection Error</h1>
            <p>\(message)</p>
            <p>Please try again from PlaidBar.</p>
        </body>
        </html>
        """
    }
}
