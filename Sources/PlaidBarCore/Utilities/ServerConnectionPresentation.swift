import Foundation

public enum ServerConnectionIssue: Sendable, Equatable {
    case demo
    case syncing
    case connected
    case offline
    case localAuthMissing
    case localAuthRejected
    case serverModeMismatch
    case error

    /// Severity tier of this connection state; `nil` when nothing failed.
    /// Offline and local-auth failures block every Plaid-backed action, so
    /// they own the chrome-level alert treatments. A generic `.error` means
    /// the server is still reachable and a recent action failed — advisory,
    /// rendered inline and cleared by the next successful refresh.
    public var errorSeverity: ErrorSeverity? {
        switch self {
        case .demo, .syncing, .connected: nil
        case .offline, .localAuthMissing, .localAuthRejected, .serverModeMismatch: .blocking
        case .error: .advisory
        }
    }
}

public struct ServerConnectionPresentation: Sendable, Equatable {
    public let issue: ServerConnectionIssue
    public let statusText: String
    public let diagnosticsSummary: String
    public let attentionText: String?

    /// Severity tier derived from the issue this mapping already computed.
    public var errorSeverity: ErrorSeverity? {
        issue.errorSeverity
    }

    public init(
        issue: ServerConnectionIssue,
        statusText: String,
        diagnosticsSummary: String,
        attentionText: String? = nil
    ) {
        self.issue = issue
        self.statusText = statusText
        self.diagnosticsSummary = diagnosticsSummary
        self.attentionText = attentionText
    }

    public static func evaluate(
        isDemoMode: Bool,
        isInitialLoad: Bool = false,
        isLoading: Bool,
        serverConnected: Bool,
        errorMessage: String?
    ) -> ServerConnectionPresentation {
        if isDemoMode {
            return ServerConnectionPresentation(
                issue: .demo,
                statusText: "Local demo",
                diagnosticsSummary: "Demo data loaded"
            )
        }

        if let blockingIssue = blockingIssue(from: errorMessage) {
            return blockingIssue
        }

        // Boot handshake: the first connectivity check has not completed,
        // so neither "Offline" nor an attention badge is a real verdict yet.
        if isInitialLoad {
            return ServerConnectionPresentation(
                issue: .syncing,
                statusText: "Connecting",
                diagnosticsSummary: "Connecting to the local server"
            )
        }

        if isLoading {
            return ServerConnectionPresentation(
                issue: .syncing,
                statusText: "Syncing",
                diagnosticsSummary: "Plaid sync in progress"
            )
        }

        // Offline is evaluated before a generic error message: when the
        // server is unreachable, that blocking state is the real condition
        // and must win over whatever advisory error the last action left
        // behind.
        guard serverConnected else {
            return ServerConnectionPresentation(
                issue: .offline,
                statusText: "Offline",
                diagnosticsSummary: "Server offline",
                attentionText: "Offline"
            )
        }

        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ServerConnectionPresentation(
                issue: .error,
                statusText: "Error",
                diagnosticsSummary: "Recent action failed",
                attentionText: "Error"
            )
        }

        return ServerConnectionPresentation(
            issue: .connected,
            statusText: "Connected",
            diagnosticsSummary: "Server connected"
        )
    }

    private static func blockingIssue(from message: String?) -> ServerConnectionPresentation? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()

        if normalized.contains("server is running in") &&
            (normalized.contains("not sandbox") || normalized.contains("not production")) {
            return ServerConnectionPresentation(
                issue: .serverModeMismatch,
                statusText: "Mode mismatch",
                diagnosticsSummary: "Server mode mismatch",
                attentionText: "Mode"
            )
        }

        if normalized.contains("auth token is unavailable") {
            return ServerConnectionPresentation(
                issue: .localAuthMissing,
                statusText: "Auth missing",
                diagnosticsSummary: "Local server auth missing",
                attentionText: "Auth"
            )
        }

        if normalized.contains("plaidbar server returned 401") ||
            normalized.contains("plaidbar server returned 403") ||
            normalized.contains("vaultpeek companion server returned 401") ||
            normalized.contains("vaultpeek companion server returned 403") {
            return ServerConnectionPresentation(
                issue: .localAuthRejected,
                statusText: "Auth rejected",
                diagnosticsSummary: "Local server auth rejected",
                attentionText: "Auth"
            )
        }

        return nil
    }
}
