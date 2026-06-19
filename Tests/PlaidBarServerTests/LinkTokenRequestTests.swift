import Foundation
@testable import PlaidBarServer
import Testing

/// Hosted Link request-shape and error-surfacing guarantees for the
/// `/api/link/create` flow.
///
/// Regression coverage for the sandbox/consumer link 500: `PlaidClient` used to
/// send BOTH a top-level `redirect_uri` AND `hosted_link.completion_redirect_uri`.
/// Plaid rejects that combination with `INVALID_FIELD` ("OAuth redirect URI must
/// be configured in the developer dashboard"), which `LinkRoutes` turned into an
/// opaque, empty-bodied HTTP 500. Hosted Link must omit the top-level
/// `redirect_uri` entirely.
///
/// All values here are synthetic; nothing contacts Plaid, the network, or the
/// Keychain.
@Suite("Hosted Link token request shape")
struct LinkTokenRequestTests {
    private func encodedRequest(_ request: PlaidLinkTokenRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("Create link-token body omits redirect_uri but keeps hosted_link")
    func createLinkTokenBodyOmitsRedirectURI() throws {
        let config = try PlaidLinkConfiguration.resolved(from: [:])
        let request = try config.createRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientUserId: "vaultpeek-install-test",
            completionRedirectURI: "http://localhost:8484/oauth/callback?state=abc"
        )

        let json = try encodedRequest(request)

        #expect(json["client_name"] as? String == "VaultPeek")
        #expect(json["products"] as? [String] == ["transactions"])
        // Liabilities is requested as an OPTIONAL product (AND-493) so it never
        // filters non-liability institutions out of Link.
        #expect(json["optional_products"] as? [String] == ["liabilities"])
        #expect(json["country_codes"] as? [String] == ["US"])
        #expect(json["language"] as? String == "en")
        #expect(json["webhook"] == nil)
        // The OAuth redirect_uri must be omitted from the JSON entirely.
        #expect(json["redirect_uri"] == nil)
        #expect(!json.keys.contains("redirect_uri"))

        // Hosted Link routing must remain present and carry the completion URI.
        let hostedLink = try #require(json["hosted_link"] as? [String: Any])
        #expect(
            hostedLink["completion_redirect_uri"] as? String
                == "http://localhost:8484/oauth/callback?state=abc"
        )
        #expect(hostedLink["url_lifetime_seconds"] as? Int == 1800)
        #expect(hostedLink["is_mobile_app"] == nil)
    }

    @Test("Update link-token body omits redirect_uri and includes access_token")
    func updateLinkTokenBodyOmitsRedirectURI() throws {
        let config = try PlaidLinkConfiguration.resolved(from: [:])
        let request = try config.updateRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientUserId: "vaultpeek-install-test",
            accessToken: "access-sandbox-token",
            completionRedirectURI: "http://localhost:8484/oauth/callback?state=def"
        )

        let json = try encodedRequest(request)

        #expect(json["redirect_uri"] == nil)
        #expect(!json.keys.contains("redirect_uri"))
        #expect(json["products"] == nil)
        #expect(json["access_token"] as? String == "access-sandbox-token")
        #expect(json["hosted_link"] != nil)
    }

    @Test("Managed/native config sets webhook redirect and mobile Hosted Link flags")
    func managedNativeConfigBuildsHostedLinkOptions() throws {
        let config = try PlaidLinkConfiguration.resolved(from: [
            "PLAID_LINK_PRODUCTS": "transactions, liabilities",
            "PLAID_LINK_COUNTRY_CODES": "US,CA",
            "PLAID_LINK_LANGUAGE": "fr",
            "PLAID_LINK_WEBHOOK_URL": "https://vaultpeek.example/webhooks/plaid-link",
            "PLAID_LINK_REDIRECT_URI": "https://vaultpeek.example/oauth/plaid",
            "PLAID_HOSTED_LINK_LIFETIME_SECONDS": "900",
            "PLAID_HOSTED_LINK_IS_MOBILE_APP": "true",
        ])
        let request = try config.createRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientUserId: "vaultpeek-install-test",
            completionRedirectURI: "vaultpeek://hosted-link-complete"
        )

        let json = try encodedRequest(request)
        #expect(json["products"] as? [String] == ["transactions", "liabilities"])
        #expect(json["country_codes"] as? [String] == ["US", "CA"])
        #expect(json["language"] as? String == "fr")
        #expect(json["webhook"] as? String == "https://vaultpeek.example/webhooks/plaid-link")
        #expect(json["redirect_uri"] as? String == "https://vaultpeek.example/oauth/plaid")

        let hostedLink = try #require(json["hosted_link"] as? [String: Any])
        #expect(hostedLink["completion_redirect_uri"] as? String == "vaultpeek://hosted-link-complete")
        #expect(hostedLink["url_lifetime_seconds"] as? Int == 900)
        #expect(hostedLink["is_mobile_app"] as? Bool == true)
    }

    @Test("Hosted-bridge config requires a Link webhook URL")
    func hostedBridgeRequiresWebhookURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-hosted-webhook-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingWebhookConfig = directory.appendingPathComponent("missing.conf")
        let configuredWebhookConfig = directory.appendingPathComponent("configured.conf")
        let missingDataDirectory = directory.appendingPathComponent("missing-data", isDirectory: true)
        let configuredDataDirectory = directory.appendingPathComponent("configured-data", isDirectory: true)

        try """
        PLAID_CLIENT_ID=client-id
        PLAID_SECRET=secret
        PLAID_ENV=sandbox
        PLAIDBAR_DEPLOYMENT=hosted-bridge
        PLAIDBAR_OAUTH_REDIRECT_URI=https://link.vaultpeek.example/oauth/callback
        PLAIDBAR_DATA_DIR=\(missingDataDirectory.path)
        """.write(to: missingWebhookConfig, atomically: true, encoding: .utf8)
        try """
        PLAID_CLIENT_ID=client-id
        PLAID_SECRET=secret
        PLAID_ENV=sandbox
        PLAIDBAR_DEPLOYMENT=hosted-bridge
        PLAID_LINK_WEBHOOK_URL=https://vaultpeek.example/webhooks/plaid/hosted-link
        PLAIDBAR_OAUTH_REDIRECT_URI=https://link.vaultpeek.example/oauth/callback
        PLAIDBAR_DATA_DIR=\(configuredDataDirectory.path)
        """.write(to: configuredWebhookConfig, atomically: true, encoding: .utf8)

        #expect(throws: ServerConfigError.self) {
            _ = try ServerConfig.load(from: missingWebhookConfig.path)
        }

        let configured = try ServerConfig.load(from: configuredWebhookConfig.path)
        #expect(configured.deployment == .hostedBridge)
        #expect(configured.link.webhookURL == "https://vaultpeek.example/webhooks/plaid/hosted-link")
    }

    @Test("A malformed server.conf line aborts the load with its 1-based line number")
    func malformedConfigLineThrowsWithLineNumber() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-malformed-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A line with no '=' is rejected, reporting its 1-based position (line 3).
        let noEquals = directory.appendingPathComponent("no-equals.conf")
        try """
        PLAID_CLIENT_ID=client-id
        PLAID_SECRET=secret
        GARBAGE_LINE_WITHOUT_EQUALS
        """.write(to: noEquals, atomically: true, encoding: .utf8)
        do {
            _ = try ServerConfig.load(from: noEquals.path)
            Issue.record("expected invalidConfigLine to be thrown")
        } catch let ServerConfigError.invalidConfigLine(_, line) {
            #expect(line == 3)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        // An empty key is likewise rejected, at its own line (line 2).
        let emptyKey = directory.appendingPathComponent("empty-key.conf")
        try """
        PLAID_CLIENT_ID=client-id
        =orphaned-value
        """.write(to: emptyKey, atomically: true, encoding: .utf8)
        do {
            _ = try ServerConfig.load(from: emptyKey.path)
            Issue.record("expected invalidConfigLine to be thrown")
        } catch let ServerConfigError.invalidConfigLine(_, line) {
            #expect(line == 2)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Link configuration rejects unsupported values before calling Plaid")
    func linkConfigurationValidation() {
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration(
                clientName: "This Name Is Far Too Long For Plaid Link",
                products: ["transactions"],
                optionalProducts: [],
                countryCodes: ["US"],
                language: "en",
                webhookURL: nil,
                redirectURI: nil,
                hostedLinkLifetimeSeconds: 1800,
                hostedLinkIsMobileApp: false
            ).createRequest(
                clientId: "test-client",
                secret: "test-secret",
                clientUserId: "vaultpeek-install-test",
                completionRedirectURI: "http://localhost:8484/oauth/callback"
            )
        }
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration.resolved(
                from: ["PLAID_LINK_PRODUCTS": "transactions,not_a_product"]
            )
        }
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration.resolved(from: ["PLAID_LINK_COUNTRY_CODES": "US,ZZ"])
        }
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration.resolved(from: ["PLAID_LINK_LANGUAGE": "xx"])
        }
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration.resolved(from: ["PLAID_HOSTED_LINK_LIFETIME_SECONDS": "0"])
        }
        // The refresh path always calls /transactions/sync, so a product list
        // that omits transactions must be rejected up front rather than linking
        // Items that error on every sync.
        #expect(throws: PlaidLinkConfigurationError.self) {
            _ = try PlaidLinkConfiguration.resolved(from: ["PLAID_LINK_PRODUCTS": "auth"])
        }
    }

    @Test("Stable install client_user_id is non-PII and does not embed secrets")
    func stableInstallClientUserIdIsSafe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-link-id-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("server.conf")
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        try """
        PLAID_CLIENT_ID=client-secret-shaped-value
        PLAID_SECRET=secret-shaped-value
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let first = try ServerConfig.load(from: configURL.path)
        let second = try ServerConfig.load(from: configURL.path)

        #expect(first.linkClientUserId == second.linkClientUserId)
        #expect(ServerConfig.isValidStoredLinkClientUserId(first.linkClientUserId))
        #expect(!first.linkClientUserId.contains("client-secret-shaped-value"))
        #expect(!first.linkClientUserId.contains("secret-shaped-value"))
        #expect(!first.linkClientUserId.contains("access-"))
        #expect(!first.linkClientUserId.contains("public-"))
        #expect(!first.linkClientUserId.contains("account"))
        #expect(!first.linkClientUserId.contains("@"))
        #expect(!first.linkClientUserId.contains("+1"))

        let storedURL = dataDirectory.appendingPathComponent(ServerConfig.linkClientUserIdFilename)
        #expect(try String(contentsOf: storedURL, encoding: .utf8) == first.linkClientUserId)
        #expect(try posixPermissions(at: storedURL) == 0o600)
    }

    @Test("Explicit redirectUri still encodes (non-Hosted-Link callers)")
    func explicitRedirectURIStillEncodes() throws {
        // The field is optional, not removed: a caller that does pass a value
        // must still serialize it, so we never silently drop a real redirect_uri.
        let request = PlaidLinkTokenRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientName: "VaultPeek",
            user: .init(clientUserId: "plaidbar-user-test"),
            products: ["transactions"],
            countryCodes: ["US"],
            language: "en",
            redirectUri: "http://localhost:8484/oauth/callback"
        )

        let json = try encodedRequest(request)
        #expect(json["redirect_uri"] as? String == "http://localhost:8484/oauth/callback")
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

@Suite("Hosted Link OAuth redirect readiness")
struct HostedLinkOAuthRedirectReadinessTests {
    @Test("Local sandbox BYO config allows localhost callback")
    func localSandboxAllowsLocalhostCallback() throws {
        let config = try loadConfig([
            "PLAID_CLIENT_ID=client",
            "PLAID_SECRET=secret",
            "PLAID_ENV=sandbox",
            "PLAIDBAR_DEPLOYMENT=local",
            "PLAIDBAR_OAUTH_REDIRECT_MODE=local",
            "PLAIDBAR_SERVER_PORT=9494",
        ])

        #expect(config.deployment == .local)
        #expect(config.oauthRedirect.mode == .local)
        #expect(config.redirectUri == "http://localhost:9494/oauth/callback")
    }

    @Test("Managed production rejects localhost callback")
    func managedProductionRejectsLocalhostCallback() throws {
        #expect(throws: ServerConfigError.self) {
            _ = try loadConfig([
                "PLAID_CLIENT_ID=client",
                "PLAID_SECRET=secret",
                "PLAID_ENV=production",
                "PLAIDBAR_DEPLOYMENT=hosted-bridge",
                "PLAIDBAR_OAUTH_REDIRECT_MODE=managed",
                "PLAIDBAR_OAUTH_REDIRECT_URI=http://localhost:8484/oauth/callback",
            ])
        }
    }

    @Test("Managed production accepts configured HTTPS callback")
    func managedProductionAcceptsHTTPSCallback() throws {
        let config = try loadConfig([
            "PLAID_CLIENT_ID=client",
            "PLAID_SECRET=secret",
            "PLAID_ENV=production",
            "PLAIDBAR_DEPLOYMENT=hosted-bridge",
            "PLAIDBAR_OAUTH_REDIRECT_MODE=managed",
            "PLAIDBAR_OAUTH_REDIRECT_URI=https://link.vaultpeek.example/oauth/callback",
            "PLAID_LINK_WEBHOOK_URL=https://vaultpeek.example/webhooks/plaid/hosted-link",
        ])

        #expect(config.deployment == .hostedBridge)
        #expect(config.oauthRedirect.mode == .managed)
        #expect(config.redirectUri == "https://link.vaultpeek.example/oauth/callback")
        #expect(config.oauthRedirect.isProductionReadyForHostedLink)
    }

    @Test("Link route readiness guard blocks only managed production without HTTPS")
    func linkRouteReadinessGuardBlocksOnlyManagedProductionWithoutHTTPS() {
        let localhostRedirect = OAuthRedirectConfiguration(
            mode: .managed,
            uri: "http://localhost:8484/oauth/callback"
        )
        let httpsRedirect = OAuthRedirectConfiguration(
            mode: .managed,
            uri: "https://link.vaultpeek.example/oauth/callback"
        )

        #expect(LinkRoutes.productionHostedLinkRedirectReadinessError(
            deployment: .local,
            plaidEnvironment: .sandbox,
            oauthRedirect: localhostRedirect
        ) == nil)
        #expect(LinkRoutes.productionHostedLinkRedirectReadinessError(
            deployment: .hostedBridge,
            plaidEnvironment: .production,
            oauthRedirect: localhostRedirect
        ) != nil)
        #expect(LinkRoutes.productionHostedLinkRedirectReadinessError(
            deployment: .hostedBridge,
            plaidEnvironment: .production,
            oauthRedirect: httpsRedirect
        ) == nil)
    }

    @Test("Future app callback mode requires HTTPS Universal Link shape")
    func appModeRequiresUniversalLinkShape() throws {
        #expect(throws: ServerConfigError.self) {
            _ = try loadConfig([
                "PLAID_CLIENT_ID=client",
                "PLAID_SECRET=secret",
                "PLAID_ENV=production",
                "PLAIDBAR_DEPLOYMENT=hosted-bridge",
                "PLAIDBAR_OAUTH_REDIRECT_MODE=app",
                "PLAIDBAR_OAUTH_REDIRECT_URI=vaultpeek://oauth/callback",
                "PLAID_LINK_WEBHOOK_URL=https://vaultpeek.example/webhooks/plaid/hosted-link",
            ])
        }

        let config = try loadConfig([
            "PLAID_CLIENT_ID=client",
            "PLAID_SECRET=secret",
            "PLAID_ENV=production",
            "PLAIDBAR_DEPLOYMENT=hosted-bridge",
            "PLAIDBAR_OAUTH_REDIRECT_MODE=app",
            "PLAIDBAR_OAUTH_REDIRECT_URI=https://vaultpeek.example/app/oauth/callback",
            "PLAID_LINK_WEBHOOK_URL=https://vaultpeek.example/webhooks/plaid/hosted-link",
        ])

        #expect(config.oauthRedirect.mode == .app)
        #expect(config.redirectUri == "https://vaultpeek.example/app/oauth/callback")
        #expect(config.oauthRedirect.isProductionReadyForHostedLink)
    }

    @Test("Managed production rejects http redirect even without hosted-bridge deployment")
    func managedProductionRejectsHTTPRedirectInLocalDeployment() throws {
        // Before the fix the HTTPS gate keyed on `.hostedBridge`, so managed mode
        // + local deployment + production accepted a plaintext redirect carrying
        // the one-time state. It must reject regardless of deployment mode.
        #expect(throws: ServerConfigError.self) {
            _ = try loadConfig([
                "PLAID_CLIENT_ID=client",
                "PLAID_SECRET=secret",
                "PLAID_ENV=production",
                "PLAIDBAR_DEPLOYMENT=local",
                "PLAIDBAR_OAUTH_REDIRECT_MODE=managed",
                "PLAIDBAR_OAUTH_REDIRECT_URI=http://broker.vaultpeek.example/oauth/callback",
            ])
        }
    }

    private func loadConfig(_ lines: [String]) throws -> ServerConfig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-redirect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("server.conf")
        let contents = (lines + ["PLAIDBAR_DATA_DIR=\(dataDirectory.path)"])
            .joined(separator: "\n")
        try contents.write(to: configURL, atomically: true, encoding: .utf8)
        do {
            let config = try ServerConfig.load(from: configURL.path)
            try? FileManager.default.removeItem(at: directory)
            return config
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

/// Plaid API errors from the Link flow must surface an actionable, secret-free
/// message instead of a bare HTTP 500 — and without echoing Plaid's raw,
/// provider-controlled `error_message` into the SwiftUI app (see `AGENTS.md`).
@Suite("Link error surfacing")
struct LinkErrorSurfacingTests {
    @Test("Known error code maps to a curated local description, not Plaid's prose")
    func knownCodeMapsToLocalDescription() {
        let message = LinkRoutes.linkErrorMessage(
            errorType: "INVALID_REQUEST",
            errorCode: "INVALID_FIELD"
        )

        // Carries the stable code identifier and locally-authored guidance.
        #expect(message.contains("INVALID_FIELD"))
        #expect(message.contains("redirect URI is registered in the Plaid dashboard"))
        #expect(message.hasPrefix("Plaid Link error (INVALID_FIELD):"))
    }

    @Test("Error code falls back to error_type, then a stable label")
    func errorCodeFallsBack() {
        // error_code nil → uses error_type, which is itself an allowlisted key.
        let rateLimited = LinkRoutes.linkErrorMessage(
            errorType: "RATE_LIMIT_EXCEEDED",
            errorCode: nil
        )
        #expect(rateLimited.hasPrefix("Plaid Link error (RATE_LIMIT_EXCEEDED):"))
        #expect(rateLimited.contains("rate-limiting"))

        // Both nil → stable PLAID_ERROR label, generic guidance, no provider text.
        let unknown = LinkRoutes.linkErrorMessage(errorType: nil, errorCode: nil)
        #expect(unknown.contains("PLAID_ERROR"))
        #expect(unknown.contains("try connecting again"))
    }

    @Test("An unknown code — even enum-shaped — collapses to PLAID_ERROR, never echoed")
    func unknownCodeCollapsesToPlaidError() {
        // Only allowlisted codes are surfaced. An enum-shaped but unmapped code
        // (which a sandbox/proxy could fabricate from an account/request token)
        // must NOT reach the app as a raw identifier.
        let message = LinkRoutes.linkErrorMessage(
            errorType: "SOME_NEW_TYPE",
            errorCode: "SOME_UNMAPPED_CODE"
        )
        #expect(message.contains("PLAID_ERROR"))
        #expect(!message.contains("SOME_UNMAPPED_CODE"))
        #expect(!message.contains("SOME_NEW_TYPE"))
        #expect(message.contains("try connecting again"))
    }

    @Test("Non-identifier-shaped codes are collapsed to PLAID_ERROR, never echoed")
    func nonIdentifierCodeIsSanitized() {
        // A misbehaving sandbox/proxy could return prose, request data, or an
        // over-long string in error_code/error_type. None of it may reach the app.
        let prose = LinkRoutes.linkErrorMessage(
            errorType: "the redirect uri http://evil/?token=abc was rejected",
            errorCode: "OAuth redirect URI must be configured; request_id=req_123"
        )
        #expect(prose.contains("PLAID_ERROR"))
        #expect(!prose.contains("request_id"))
        #expect(!prose.contains("http://"))

        // A numeric/uppercase token that happens to be enum-shaped is still not
        // allowlisted → collapsed, so no raw provider identifier leaks.
        let tokenLike = LinkRoutes.linkErrorMessage(errorType: nil, errorCode: "REQ_9F3A1B2C")
        #expect(tokenLike.contains("PLAID_ERROR"))
        #expect(!tokenLike.contains("REQ_9F3A1B2C"))
    }

    @Test("Raw Plaid error_message is never echoed into the surfaced text")
    func rawProviderMessageIsNeverEchoed() {
        // Even when Plaid would supply detailed prose for a known code, the
        // helper no longer accepts or forwards that field — the signature only
        // takes the stable code/type. Construct messages for several codes and
        // assert none contain hallmark provider-prose fragments or credential
        // hints that historically appeared in Plaid's free-form error_message.
        let leakedFragments = [
            "client_id",
            "secret",
            "Invalid client_id or secret provided",
            "request_id",
        ]
        for code in ["INVALID_API_KEYS", "INVALID_FIELD", "RATE_LIMIT_EXCEEDED"] {
            let message = LinkRoutes.linkErrorMessage(errorType: "INVALID_REQUEST", errorCode: code)
            for fragment in leakedFragments {
                #expect(!message.contains(fragment), "Leaked provider fragment '\(fragment)' for code \(code)")
            }
        }
    }
}
