import Foundation
import Hummingbird

struct APITokenMiddleware<Context: RequestContext>: RouterMiddleware {
    private let expectedAuthorizationHeader: String

    init(authToken: String) {
        self.expectedAuthorizationHeader = "Bearer \(authToken)"
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard APITokenAuthorization.constantTimeEquals(
            request.headers[.authorization] ?? "",
            expectedAuthorizationHeader
        ) else {
            throw HTTPError(.unauthorized, message: "Missing or invalid authorization token")
        }

        return try await next(request, context)
    }
}

enum APITokenAuthorization {
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        let maxCount = max(lhsBytes.count, rhsBytes.count)
        var difference = lhsBytes.count ^ rhsBytes.count

        for index in 0..<maxCount {
            let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
            let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(lhsByte ^ rhsByte)
        }

        return difference == 0
    }
}
