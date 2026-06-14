import CryptoKit
import Foundation
import Hummingbird
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

            var unrecoverableItemCount = 0
            for publicTokenResult in publicTokenResults {
                let identity = Self.resultIdentity(for: publicTokenResult)
                // Skip results already finalized on a prior attempt — keyed by a
                // stable identity, so reordered multi-item retries skip the right
                // ones (not by ordinal position). "Finalized" means either stored
                // OR irrecoverably spent (see below); both must never be replayed.
                if pendingSession.completedResultIdentities.contains(identity) {
                    continue
                }

                let outcome = await storeResult(publicTokenResult: publicTokenResult)
                switch outcome {
                case .stored:
                    // Fully persisted — mark finalized so a retry skips it.
                    await pendingLinkSessions.markResultCompleted(state: state, identity: identity)
                case .notExchanged:
                    // The public token was NOT consumed (exchange itself failed),
                    // so it is still replayable. Release the session and surface
                    // an error; the user (or an auto-retry) can try again.
                    await pendingLinkSessions.releaseCompletion(state: state)
                    return Self.errorResponse("Connecting your account failed. Please try again.")
                case .spentButNotStored:
                    // Exchange SUCCEEDED but the item could not be stored: the
                    // single-use token is spent and the access token is lost.
                    // Mark finalized so the dead token is never replayed (no
                    // endless 500s), but count it so we do NOT report success —
                    // the user must re-link this institution.
                    await pendingLinkSessions.markResultCompleted(state: state, identity: identity)
                    unrecoverableItemCount += 1
                }
            }
            _ = await pendingLinkSessions.consume(state: state)

            if unrecoverableItemCount > 0 {
                // Honest outcome: do not show "Connected" when an item was lost.
                return Self.errorResponse(
                    "Some accounts could not be finished connecting. Please re-link "
                        + "them from VaultPeek."
                )
            }
            return Response(
                status: .ok,
                headers: [.contentType: "text/html"],
                body: .init(byteBuffer: ByteBuffer(string: Self.successPage()))
            )
        } catch {
            // A failure outside the per-result loop (e.g. /link/token/get) leaves
            // nothing consumed, so the session stays retryable.
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

    /// The outcome of attempting to exchange + store a single Link result, which
    /// determines both whether the result may be retried and what the user sees.
    private enum StoreResultOutcome {
        /// Exchanged and persisted locally; safe to mark finalized.
        case stored
        /// The public-token exchange itself failed; the token is unspent and the
        /// result is still replayable.
        case notExchanged
        /// Exchange succeeded but the item could not be persisted; the token is
        /// spent and lost. Never replay, but report failure to the user.
        case spentButNotStored
    }

    private static func errorResponse(_ message: String) -> Response {
        Response(
            status: .internalServerError,
            headers: [.contentType: "text/html"],
            body: .init(byteBuffer: ByteBuffer(string: errorPage(message)))
        )
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

    /// Exchanges the result's public token and persists the item, returning an
    /// outcome that captures exactly how far it got. Crucially it distinguishes a
    /// pre-exchange failure (token unspent → retryable) from a post-exchange
    /// failure (token spent → not retryable, must report failure), so the caller
    /// never both consumes a token AND tells the user the account connected.
    private func storeResult(publicTokenResult: PlaidPublicTokenResult) async -> StoreResultOutcome {
        let exchangeResponse: PlaidTokenExchangeResponse
        do {
            exchangeResponse = try await plaidClient.exchangePublicToken(publicTokenResult.publicToken)
        } catch {
            // The single-use public token was not consumed — still replayable.
            return .notExchanged
        }

        // From here the token is SPENT. Any failure means the item is
        // unrecoverable, so we always return `.spentButNotStored` rather than
        // throwing back into a path that could replay the token.

        // getAccounts only enriches institution metadata; a failure here must NOT
        // lose the item, since we already hold the access token. Fall back to the
        // result's own institution id (best-effort) and still persist.
        let accountsItemInstitutionId = try? await plaidClient.getAccounts(
            accessToken: exchangeResponse.accessToken
        ).item?.institutionId
        let institutionId = publicTokenResult.institution?.institutionId ?? accountsItemInstitutionId

        do {
            try await tokenStore.saveItem(
                id: exchangeResponse.itemId,
                accessToken: exchangeResponse.accessToken,
                institutionId: institutionId,
                institutionName: publicTokenResult.institution?.normalizedName
            )
        } catch {
            return .spentButNotStored
        }
        return .stored
    }

    /// A stable, token-free identity for a Link result, used to skip results
    /// already consumed on a prior callback attempt. The public token is
    /// single-use and unique per result, so its SHA-256 is a perfect fingerprint
    /// — and hashing keeps the raw token out of the pending-session store, which
    /// holds no Plaid tokens. Falls back to the institution id when no public
    /// token is present (update-mode results carry none).
    static func resultIdentity(for result: PlaidPublicTokenResult) -> String {
        let seed = result.publicToken.isEmpty
            ? "institution:\(result.institution?.institutionId ?? "unknown")"
            : "public-token:\(result.publicToken)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
