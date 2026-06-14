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
        // Mirrors PlaidClient.createLinkToken: nil redirectUri, hosted_link set.
        let request = PlaidLinkTokenRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientName: "VaultPeek",
            user: .init(clientUserId: "plaidbar-user-test"),
            products: ["transactions"],
            countryCodes: ["US"],
            language: "en",
            hostedLink: .init(
                completionRedirectUri: "http://localhost:8484/oauth/callback?state=abc",
                urlLifetimeSeconds: 1800
            )
        )

        let json = try encodedRequest(request)

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
    }

    @Test("Update link-token body omits redirect_uri and includes access_token")
    func updateLinkTokenBodyOmitsRedirectURI() throws {
        // Mirrors PlaidClient.createUpdateLinkToken: nil redirectUri, access_token set.
        let request = PlaidLinkTokenRequest(
            clientId: "test-client",
            secret: "test-secret",
            clientName: "VaultPeek",
            user: .init(clientUserId: "plaidbar-user-test"),
            countryCodes: ["US"],
            language: "en",
            hostedLink: .init(
                completionRedirectUri: "http://localhost:8484/oauth/callback?state=def",
                urlLifetimeSeconds: 1800
            ),
            accessToken: "access-sandbox-token"
        )

        let json = try encodedRequest(request)

        #expect(json["redirect_uri"] == nil)
        #expect(!json.keys.contains("redirect_uri"))
        #expect(json["access_token"] as? String == "access-sandbox-token")
        #expect(json["hosted_link"] != nil)
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

    @Test("Unrecognized but enum-shaped code degrades to a generic message carrying only the code")
    func unrecognizedCodeIsGeneric() {
        let message = LinkRoutes.linkErrorMessage(
            errorType: "SOME_NEW_TYPE",
            errorCode: "SOME_UNMAPPED_CODE"
        )

        // The bounded code identifier is preserved; no provider prose is invented.
        #expect(message.contains("SOME_UNMAPPED_CODE"))
        #expect(message.contains("try connecting again"))
    }

    @Test("A non-identifier-shaped code is collapsed to PLAID_ERROR, never echoed")
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

        // Lowercase / mixed-case is not Plaid's enum shape → collapsed too.
        let mixed = LinkRoutes.linkErrorMessage(errorType: "SomethingWeird", errorCode: nil)
        #expect(mixed.contains("PLAID_ERROR"))

        // An absurdly long all-caps token is rejected by the length bound.
        let tooLong = LinkRoutes.linkErrorMessage(
            errorType: nil,
            errorCode: String(repeating: "A", count: 200)
        )
        #expect(tooLong.contains("PLAID_ERROR"))
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
