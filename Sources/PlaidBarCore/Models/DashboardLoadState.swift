import Foundation

/// Load phase for a single data surface. Distinguishes "first data is still
/// arriving" from the genuine offline/empty/error states so boot renders as
/// loading instead of a broken or offline app.
public enum DashboardLoadPhase: String, CaseIterable, Sendable {
    /// Connected with no content and no fetch in flight — the surface's
    /// regular empty-state evaluator owns the messaging.
    case idle
    /// A fetch is in flight and the surface has no content to show yet.
    case loading
    /// Content is available. A background refresh may still be running, but
    /// the surface keeps rendering last-known data while it does.
    case loaded
    /// The connectivity check completed and the server is unreachable.
    case offline
    /// The last load failed with a user-facing error and left no content.
    case error
}

/// Data surfaces that render a distinct loading treatment.
public enum DashboardLoadSurface: String, CaseIterable, Sendable {
    case menuBarSummary
    case summaryCards
    case accounts
    case transactions
    case spending
    case credit
    case recurring
    case activityHeatmap

    public var loadingTitle: String {
        switch self {
        case .menuBarSummary: "Loading summary"
        case .summaryCards: "Loading balances"
        case .accounts: "Loading accounts"
        case .transactions: "Loading transactions"
        case .spending: "Loading spending activity"
        case .credit: "Loading credit accounts"
        case .recurring: "Loading recurring charges"
        case .activityHeatmap: "Loading activity"
        }
    }

    public var loadingDetail: String {
        switch self {
        case .menuBarSummary:
            "Fetching the menu bar summary from the local VaultPeek server."
        case .summaryCards:
            "Fetching the latest balances from the local VaultPeek server."
        case .accounts:
            "Fetching linked account balances from the local VaultPeek server."
        case .transactions:
            "Syncing recent transaction history from the local VaultPeek server."
        case .spending:
            "Syncing transactions to build spending and cashflow views."
        case .credit:
            "Fetching credit accounts and utilization from the local VaultPeek server."
        case .recurring:
            "Syncing transaction history to detect recurring charges."
        case .activityHeatmap:
            "Syncing transaction history to build the activity heatmap."
        }
    }
}

/// Pure presenter for the boot/refresh load-phase state machine. Views ask
/// for the phase per surface and render skeletons/redacted placeholders only
/// while the *first* data is in flight; cached or live content always wins.
public struct DashboardLoadState: Equatable, Sendable {
    public let surface: DashboardLoadSurface
    public let phase: DashboardLoadPhase

    public init(surface: DashboardLoadSurface, phase: DashboardLoadPhase) {
        self.surface = surface
        self.phase = phase
    }

    /// True while the first fetch is in flight with nothing to show —
    /// surfaces render skeleton/redacted placeholders instead of offline or
    /// empty copy.
    public var isInitialLoad: Bool {
        phase == .loading
    }

    /// Alias that reads better at skeleton call sites.
    public var showsSkeleton: Bool {
        isInitialLoad
    }

    /// VoiceOver copy for the loading placeholder. Nil outside the loading
    /// phase so callers never announce loading over real content.
    public var loadingAccessibilityLabel: String? {
        guard isInitialLoad else { return nil }
        return "\(surface.loadingTitle). \(surface.loadingDetail)"
    }

    public static func evaluate(
        surface: DashboardLoadSurface,
        isDemoMode: Bool,
        isBooting: Bool,
        isLoading: Bool,
        serverConnected: Bool,
        hasContent: Bool,
        errorMessage: String?
    ) -> DashboardLoadState {
        // Demo fixtures load synchronously; demo never skeletons.
        if isDemoMode {
            return DashboardLoadState(surface: surface, phase: hasContent ? .loaded : .idle)
        }

        // Last-known data always wins over in-flight refreshes (T093):
        // a surface with content never regresses to a skeleton.
        if hasContent {
            return DashboardLoadState(surface: surface, phase: .loaded)
        }

        if isBooting || isLoading {
            return DashboardLoadState(surface: surface, phase: .loading)
        }

        let trimmedError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedError, !trimmedError.isEmpty {
            return DashboardLoadState(surface: surface, phase: .error)
        }

        if !serverConnected {
            return DashboardLoadState(surface: surface, phase: .offline)
        }

        return DashboardLoadState(surface: surface, phase: .idle)
    }
}
