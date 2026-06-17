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

        // Defense-in-depth: the native app never sends Origin/Referer, but a
        // browser always attaches Origin on a cross-origin fetch. Reject any
        // /api request that carries a non-localhost browser origin so a token
        // leaked to a web page cannot be replayed from the browser.
        guard APITokenAuthorization.isAllowedBrowserOrigin(
            origin: request.headers[.origin],
            referer: request.headers[.referer]
        ) else {
            throw HTTPError(.forbidden, message: "Cross-origin requests are not allowed")
        }

        return try await next(request, context)
    }
}

enum APITokenAuthorization {
    /// Loopback hosts a browser may legitimately use to reach the local server.
    private static let allowedLoopbackHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]"]

    /// Returns `true` when the request carries no browser origin (native app),
    /// or when both Origin and Referer (when present) resolve to a loopback
    /// host. Any foreign origin is rejected.
    static func isAllowedBrowserOrigin(origin: String?, referer: String?) -> Bool {
        // The native app sends neither header; that is the common, allowed case.
        if let origin, !isLoopbackOrigin(origin) {
            return false
        }
        if let referer, !isLoopbackOrigin(referer) {
            return false
        }
        return true
    }

    /// `true` when the header value's host component is a loopback host.
    /// Parses the host without relying on full URL validation so a malformed
    /// value fails closed (rejected) rather than slipping through.
    private static func isLoopbackOrigin(_ value: String) -> Bool {
        guard let host = host(fromOriginValue: value) else { return false }
        return allowedLoopbackHosts.contains(host.lowercased())
    }

    private static func host(fromOriginValue value: String) -> String? {
        // Strip the scheme (e.g. "http://").
        guard let schemeRange = value.range(of: "://") else { return nil }
        let afterScheme = value[schemeRange.upperBound...]
        // Authority ends at the first path/query/fragment delimiter.
        let authority = afterScheme.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty else { return nil }
        // Drop any userinfo ("user@host").
        let hostPort = authority.split(separator: "@", maxSplits: 1).last.map(String.init) ?? String(authority)
        // IPv6 literal: "[::1]" or "[::1]:8484".
        if hostPort.hasPrefix("[") {
            guard let closing = hostPort.firstIndex(of: "]") else { return nil }
            return String(hostPort[...closing])
        }
        // Strip the port from "host:port".
        return hostPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostPort
    }

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
