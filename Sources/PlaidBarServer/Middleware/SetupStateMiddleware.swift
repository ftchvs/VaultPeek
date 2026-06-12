import Foundation
import Hummingbird
import NIOCore

/// Maps the credential-less setup state to a clear 503 on Plaid-backed
/// routes, so clients can tell "server is up but awaiting credentials" apart
/// from a real failure (a bare 500). `/health` and `/api/status` keep
/// working in setup state; only requests that would have to call Plaid land
/// here.
///
/// The body is a flat `{"error": ...}` object because that is the shape the
/// app's `ServerClient` extracts a user-facing message from.
struct SetupStateMiddleware<Context: RequestContext>: RouterMiddleware {
    static var setupStateMessage: String {
        "Plaid credentials are not configured on PlaidBarServer. "
            + "Add PLAID_CLIENT_ID and PLAID_SECRET to server.conf; "
            + "the menu bar app restarts its bundled server automatically."
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch PlaidError.credentialsNotConfigured {
            let body = try JSONEncoder().encode(["error": Self.setupStateMessage])
            return Response(
                status: .serviceUnavailable,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: body))
            )
        }
    }
}
