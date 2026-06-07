import Foundation

public enum ServerConnectionIssue: Sendable, Equatable {
    case demo
    case syncing
    case connected
    case offline
    case localAuthMissing
    case localAuthRejected
    case error
}

public struct ServerConnectionPresentation: Sendable, Equatable {
    public let issue: ServerConnectionIssue
    public let statusText: String
    public let diagnosticsSummary: String
    public let attentionText: String?

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

        if let authIssue = localAuthIssue(from: errorMessage) {
            return authIssue
        }

        if isLoading {
            return ServerConnectionPresentation(
                issue: .syncing,
                statusText: "Syncing",
                diagnosticsSummary: "Plaid sync in progress"
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

        guard serverConnected else {
            return ServerConnectionPresentation(
                issue: .offline,
                statusText: "Offline",
                diagnosticsSummary: "Server offline",
                attentionText: "Offline"
            )
        }

        return ServerConnectionPresentation(
            issue: .connected,
            statusText: "Connected",
            diagnosticsSummary: "Server connected"
        )
    }

    private static func localAuthIssue(from message: String?) -> ServerConnectionPresentation? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()

        if normalized.contains("auth token is unavailable") {
            return ServerConnectionPresentation(
                issue: .localAuthMissing,
                statusText: "Auth missing",
                diagnosticsSummary: "Local server auth missing",
                attentionText: "Auth"
            )
        }

        if normalized.contains("plaidbar server returned 401") ||
            normalized.contains("plaidbar server returned 403") {
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
