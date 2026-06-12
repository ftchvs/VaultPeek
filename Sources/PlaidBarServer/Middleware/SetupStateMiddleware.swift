import Foundation
import Hummingbird
import NIOCore
import PlaidBarCore

/// Maps the credential-less setup state to a clear 503 on Plaid-backed
/// routes, so clients can tell "server is up but awaiting credentials" apart
/// from a real failure (a bare 500) or a successful empty refresh. `/health`,
/// `/api/status`, and `/api/items` keep working in setup state.
///
/// Plaid-backed paths are rejected before the handler runs: with no linked
/// items the per-item routes would otherwise skip `PlaidClient` entirely and
/// return `200` with an empty payload, hiding the missing credentials. The
/// catch stays as a safety net for any Plaid call reached through a path the
/// prefix list does not name.
///
/// The 503 body names exactly which credential variable is missing and is
/// scoped to the server's Plaid environment, so a partially configured
/// `server.conf` (one variable set, the other forgotten) gets an actionable
/// message instead of a generic "credentials are not configured".
///
/// The body is a flat `{"error": ...}` object because that is the shape the
/// app's `ServerClient` extracts a user-facing message from.
struct SetupStateMiddleware<Context: RequestContext>: RouterMiddleware {
    let credentialDiagnosis: CredentialSetupDiagnosis
    let plaidEnvironment: PlaidEnvironment

    var credentialsConfigured: Bool {
        credentialDiagnosis.isConfigured
    }

    static func setupStateMessage(
        diagnosis: CredentialSetupDiagnosis,
        environment: PlaidEnvironment
    ) -> String {
        diagnosis.setupGuidance(environment: environment)
            ?? "Plaid credentials are not configured on the VaultPeek companion server. "
            + "Add PLAID_CLIENT_ID and PLAID_SECRET to server.conf; "
            + "the menu bar app restarts its bundled server automatically."
    }

    /// Route groups that cannot do anything meaningful without Plaid
    /// credentials. Status and item readiness endpoints are deliberately
    /// absent: they serve local metadata that setup guidance relies on.
    static var plaidBackedPathPrefixes: [String] {
        ["/api/link", "/api/accounts", "/api/transactions"]
    }

    static func isPlaidBackedPath(_ path: String) -> Bool {
        plaidBackedPathPrefixes.contains { prefix in
            guard path.hasPrefix(prefix) else { return false }
            let remainder = path.dropFirst(prefix.count)
            return remainder.isEmpty || remainder.hasPrefix("/")
        }
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if !credentialsConfigured, Self.isPlaidBackedPath(request.uri.path) {
            return try setupStateResponse()
        }
        do {
            return try await next(request, context)
        } catch PlaidError.credentialsNotConfigured {
            return try setupStateResponse()
        }
    }

    private func setupStateResponse() throws -> Response {
        let message = Self.setupStateMessage(
            diagnosis: credentialDiagnosis,
            environment: plaidEnvironment
        )
        let body = try JSONEncoder().encode(["error": message])
        return Response(
            status: .serviceUnavailable,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: body))
        )
    }
}
