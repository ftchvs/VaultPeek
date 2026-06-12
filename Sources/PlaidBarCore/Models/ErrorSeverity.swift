import Foundation

/// Severity tier for user-facing failure states, shared by the presentation
/// mappings (`DashboardStatusReadiness`, `AttentionQueue`,
/// `ServerConnectionPresentation`, `MenuBarStatusPresentation`).
///
/// This is deliberately a property derived from the existing state mappings,
/// not a parallel error taxonomy: each surface keeps its own copy/action
/// model and exposes the severity of the state it already computed.
///
/// - `advisory`: degraded but recoverable in place (a transient action or
///   cache hiccup while the server stays reachable). Advisory failures are
///   rendered inline next to the affected module (status banner, attention
///   queue) and expire on the next successful refresh, which clears the
///   underlying error. They must never paint app-wide chrome.
/// - `blocking`: the connection or credential path is down (server offline,
///   local auth missing/rejected, credentials missing, item errors). The
///   menu-bar and status-strip alert treatments are reserved for this tier.
public enum ErrorSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case advisory
    case blocking

    public static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .advisory: 0
        case .blocking: 1
        }
    }
}
