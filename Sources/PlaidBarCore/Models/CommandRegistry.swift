import Foundation

/// The pure, `Sendable` model of every command the ⌘K palette can run
/// (AND-596).
///
/// The command palette is a
/// spotlight-style overlay with fuzzy search across three action classes —
/// **navigate**, **act**, **find**. This type is the registry of those commands
/// as *data*. It deliberately carries **no closures**: a command describes
/// *what* it does (a `Kind` + a stable `id` + display strings), and the app
/// layer maps the chosen command's `Kind` onto the existing action path
/// (navigate → `NavigationModel.destination`; act → the real refresh / Privacy
/// Mask / settings / summon paths). Keeping the registry closure-free is what
/// makes it `Sendable` and unit-testable without the SwiftUI app target
/// (CLAUDE.md: shared, testable logic lives in `PlaidBarCore`).
///
/// The palette filters/ranks this set with ``FuzzyMatcher``; selecting a result
/// hands the command's `Kind` back to the app to execute.
public struct CommandRegistry: Sendable, Equatable {
    /// The kind of thing a command does. Drives both how it is grouped in the
    /// palette and how the app executes it.
    public enum Kind: Sendable, Equatable, Hashable, Codable {
        /// Jump to a destination (the canonical route for it). Navigate class.
        case navigate(RouteDestination)
        /// A global verb that works from anywhere. Act class.
        case act(Action)
        /// Enter "find" mode — search transactions and jump to the match. Find
        /// class. The query itself is typed in the palette; this command
        /// is the entry point (it focuses the current destination's search, per
        /// the ⌘F keymap row).
        case find

        /// The bare destination a `navigate` command targets, else `nil`.
        public var navigationDestination: RouteDestination? {
            if case .navigate(let destination) = self { return destination }
            return nil
        }
    }

    /// The global verbs the palette exposes (the act class + the keymap).
    /// Each maps to an existing app action — the palette never invents behavior,
    /// it surfaces the paths the menu-bar / shortcuts already drive.
    public enum Action: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        /// Refresh / sync now (`⌘R`) — `AppState.refreshDashboard()`.
        case refresh
        /// Toggle Privacy Mask (`⌘⇧P`) — `AppState.togglePrivacyMask()`.
        case togglePrivacyMask
        /// Open the native Settings scene (`⌘,`) — `openSettings()`.
        case openSettings
        /// Summon VaultPeek to the front (`⇧⌘V`) — the summon-hotkey path.
        case summon
    }

    /// One palette command. Pure data: id + kind + the strings the palette shows
    /// and searches.
    public struct Command: Sendable, Equatable, Identifiable, Hashable {
        /// Stable identifier, also the de-dupe / selection key. Derived from the
        /// kind so it is deterministic (`navigate.dashboard`, `act.refresh`,
        /// `find`).
        public let id: String
        public let kind: Kind
        /// The primary label, fuzzy-searched with the highest weight.
        public let title: String
        /// Optional secondary line (e.g. the shortcut hint or a hint of scope).
        public let subtitle: String?
        /// Extra search terms (synonyms / verbs) so "sync" finds "Refresh" and
        /// "hide balances" finds "Toggle Privacy Mask". Fuzzy-searched below the
        /// title.
        public let keywords: [String]
        /// SF Symbol for the row (chrome only — the title always carries meaning).
        public let systemImage: String

        public init(
            id: String,
            kind: Kind,
            title: String,
            subtitle: String? = nil,
            keywords: [String] = [],
            systemImage: String
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.keywords = keywords
            self.systemImage = systemImage
        }
    }

    /// Every command, in a stable display order: navigate (sidebar order) →
    /// act → find. The palette shows this order when the query is empty.
    public let commands: [Command]

    public init(commands: [Command]) {
        self.commands = commands
    }

    /// Looks a command up by its stable id (the palette hands this back on
    /// selection so the app can dispatch the `Kind`).
    public func command(id: String) -> Command? {
        commands.first { $0.id == id }
    }

    /// Fuzzy-searches the registry, best match first, using ``FuzzyMatcher``
    /// over each command's title + keywords. An empty query returns every
    /// command in registry order (so the palette lists everything before the
    /// user types).
    public func search(_ query: String) -> [Command] {
        FuzzyMatcher.search(
            query: query,
            candidates: commands,
            title: { $0.title },
            keywords: { $0.keywords }
        ).map(\.element)
    }

    // MARK: - Construction

    /// Builds the **default** registry: a navigate command for every
    /// `RouteDestination`, the four global act verbs, and the find entry point.
    /// This is the complete command set AND-596 ships; contextual per-destination
    /// commands layer on in later epics.
    ///
    /// Order: navigate (sidebar / `allCases` order) → act (refresh, Privacy Mask,
    /// settings, summon) → find.
    public static func makeDefault() -> CommandRegistry {
        var commands: [Command] = []

        // 1. Navigate — one per destination, in sidebar order (navigate class).
        for destination in RouteDestination.allCases {
            commands.append(
                Command(
                    id: navigateID(destination),
                    kind: .navigate(destination),
                    title: "Go to \(destination.title)",
                    subtitle: navigateSubtitle(destination),
                    keywords: navigateKeywords(destination),
                    systemImage: destination.systemImage
                )
            )
        }

        // 2. Act — the global verbs, each mapping to an existing action path.
        commands.append(
            Command(
                id: actID(.refresh),
                kind: .act(.refresh),
                title: "Refresh",
                subtitle: "Sync now",
                keywords: ["sync", "reload", "update", "fetch"],
                systemImage: "arrow.clockwise"
            )
        )
        commands.append(
            Command(
                id: actID(.togglePrivacyMask),
                kind: .act(.togglePrivacyMask),
                title: "Toggle Privacy Mask",
                subtitle: "Hide or show balances",
                keywords: ["privacy", "hide", "mask", "balances", "amounts", "blur", "redact"],
                systemImage: "eye.slash"
            )
        )
        commands.append(
            Command(
                id: actID(.openSettings),
                kind: .act(.openSettings),
                title: "Open Settings",
                subtitle: "Preferences",
                keywords: ["settings", "preferences", "configuration", "options"],
                systemImage: "gearshape"
            )
        )
        commands.append(
            Command(
                id: actID(.summon),
                kind: .act(.summon),
                title: "Summon VaultPeek",
                subtitle: "Bring to front",
                keywords: ["summon", "front", "activate", "show", "bring", "focus"],
                systemImage: "macwindow.on.rectangle"
            )
        )

        // 3. Find — the search entry point (find class).
        commands.append(
            Command(
                id: findID,
                kind: .find,
                title: "Find Transaction",
                subtitle: "Search by merchant, amount, or category",
                keywords: ["find", "search", "transaction", "merchant", "amount", "category", "filter"],
                systemImage: "magnifyingglass"
            )
        )

        return CommandRegistry(commands: commands)
    }

    // MARK: - Stable id derivation

    public static func navigateID(_ destination: RouteDestination) -> String {
        "navigate.\(destination.rawValue)"
    }

    public static func actID(_ action: Action) -> String {
        "act.\(action.rawValue)"
    }

    public static let findID = "find"

    // MARK: - Per-destination palette copy

    private static func navigateSubtitle(_ destination: RouteDestination) -> String? {
        guard let number = destination.commandShortcutNumber else { return nil }
        return "⌘\(number)"
    }

    /// Search synonyms so a destination is reachable by its job, not just its
    /// label (e.g. "spending" → Budgets, "subscriptions" → Planning).
    private static func navigateKeywords(_ destination: RouteDestination) -> [String] {
        switch destination {
        case .dashboard: ["home", "overview", "net worth", "summary"]
        case .review: ["inbox", "triage", "approve", "categorize", "unreviewed"]
        case .transactions: ["ledger", "history", "spending", "payments"]
        case .budgets: ["spending", "categories", "limits", "over budget"]
        case .planning: ["forecast", "recurring", "subscriptions", "runway", "cashflow"]
        case .goals: ["savings", "payoff", "targets", "progress"]
        case .insights: ["receipts", "weekly review", "trends", "ai"]
        case .alerts: ["notifications", "warnings", "watchlist"]
        case .accounts: ["banks", "institutions", "balances", "connections"]
        case .settings: ["preferences", "configuration", "options"]
        }
    }
}
