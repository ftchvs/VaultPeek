import Foundation
import PlaidBarCore
import Testing

@Suite("CommandRegistry default set")
struct CommandRegistryDefaultTests {
    private let registry = CommandRegistry.makeDefault()

    /// The destinations a navigate command exists for — every `RouteDestination`
    /// except deprecated-in-place ones (``RouteDestination/canonicalRedirect``,
    /// e.g. `.planning`, folded into Insights 2026-07-02, Gate-0 AND-979). A
    /// "Go to Planning" result would just duplicate "Go to Insights", so the
    /// deprecated case has no navigate command of its own — it's still
    /// findable by its old keywords, folded into Insights' keyword list.
    private var liveDestinations: [RouteDestination] {
        RouteDestination.allCases.filter { $0.canonicalRedirect == nil }
    }

    @Test("Has a navigate command for every live destination, the 4 act verbs, and find")
    func completeness() {
        let commands = registry.commands

        // Navigate: one per live (non-deprecated) RouteDestination.
        let navigateDestinations = commands.compactMap { $0.kind.navigationDestination }
        #expect(Set(navigateDestinations) == Set(liveDestinations))
        #expect(navigateDestinations.count == liveDestinations.count)

        // Act: exactly the four global verbs.
        let actions = commands.compactMap { command -> CommandRegistry.Action? in
            if case .act(let action) = command.kind { return action }
            return nil
        }
        #expect(Set(actions) == Set(CommandRegistry.Action.allCases))
        #expect(actions.count == 4)

        // Find: exactly one.
        let findCount = commands.filter { $0.kind == .find }.count
        #expect(findCount == 1)

        // Total = 9 live destinations + 4 acts + 1 find = 14.
        #expect(commands.count == liveDestinations.count + 4 + 1)
    }

    @Test("All command ids are unique and stable")
    func uniqueStableIDs() {
        let ids = registry.commands.map(\.id)
        #expect(Set(ids).count == ids.count, "ids must be unique")

        // Stable derivation matches the documented scheme.
        #expect(registry.command(id: "navigate.dashboard")?.kind == .navigate(.dashboard))
        #expect(registry.command(id: "act.refresh")?.kind == .act(.refresh))
        #expect(registry.command(id: "find")?.kind == .find)
        #expect(CommandRegistry.navigateID(.budgets) == "navigate.budgets")
        #expect(CommandRegistry.actID(.togglePrivacyMask) == "act.togglePrivacyMask")
        #expect(CommandRegistry.findID == "find")
    }

    @Test("Every command has a non-empty title and SF Symbol")
    func displayStrings() {
        for command in registry.commands {
            #expect(!command.title.isEmpty)
            #expect(!command.systemImage.isEmpty)
        }
    }

    @Test("Display order is navigate (sidebar order) → act → find")
    func displayOrder() {
        let kinds = registry.commands.map(\.kind)
        let navigateCount = liveDestinations.count

        // First N are navigate, in sidebar (allCases, minus deprecated-in-place
        // destinations) order.
        let navigatePrefix = kinds.prefix(navigateCount).compactMap(\.navigationDestination)
        #expect(navigatePrefix == liveDestinations)

        // Then the four acts, then find last.
        #expect(kinds[navigateCount] == .act(.refresh))
        #expect(kinds.last == .find)
    }

    @Test("Numbered destinations show their ⌘N shortcut as the subtitle")
    func navigateSubtitleShortcut() {
        // Dashboard = ⌘1, Accounts = ⌘8.
        #expect(registry.command(id: "navigate.dashboard")?.subtitle == "⌘1")
        #expect(registry.command(id: "navigate.accounts")?.subtitle == "⌘8")
        // Transactions has no number → no ⌘N subtitle.
        #expect(registry.command(id: "navigate.transactions")?.subtitle == nil)
    }

    @Test("Kind.navigationDestination extracts the destination only for navigate")
    func navigationDestinationAccessor() {
        #expect(CommandRegistry.Kind.navigate(.goals).navigationDestination == .goals)
        #expect(CommandRegistry.Kind.act(.refresh).navigationDestination == nil)
        #expect(CommandRegistry.Kind.find.navigationDestination == nil)
    }
}

@Suite("CommandRegistry search")
struct CommandRegistrySearchTests {
    private let registry = CommandRegistry.makeDefault()

    @Test("Empty query returns the full command set in registry order")
    func emptyQuery() {
        let results = registry.search("")
        #expect(results.count == registry.commands.count)
        #expect(results.map(\.id) == registry.commands.map(\.id))
    }

    @Test("Typing a destination name surfaces its navigate command first")
    func navigateByName() {
        #expect(registry.search("budgets").first?.kind == .navigate(.budgets))
        #expect(registry.search("review").first?.kind == .navigate(.review))
        #expect(registry.search("accounts").first?.kind == .navigate(.accounts))
    }

    @Test("Act verbs are reachable by title and by keyword synonyms")
    func actByTitleAndKeyword() {
        // By title.
        #expect(registry.search("refresh").first?.kind == .act(.refresh))
        #expect(registry.search("privacy").first?.kind == .act(.togglePrivacyMask))
        // By keyword synonym: "sync" → Refresh, "hide" → Privacy Mask.
        #expect(registry.search("sync").first?.kind == .act(.refresh))
        #expect(registry.search("hide").first?.kind == .act(.togglePrivacyMask))
    }

    @Test("Find is reachable by 'search' / 'find' keywords")
    func findReachable() {
        #expect(registry.search("find").first?.kind == .find)
    }

    @Test("A no-match query returns an empty result set")
    func noMatch() {
        #expect(registry.search("zzqqxx").isEmpty)
    }

    @Test("Keyword-driven navigation: unique synonyms surface their destination")
    func keywordNavigation() {
        // "subscriptions" was unique to Planning; folded into Insights' keyword
        // list when Planning was deprecated-in-place (2026-07-02, Gate-0
        // AND-979), so it now surfaces "Go to Insights". "limits" is unique to
        // Budgets.
        #expect(registry.search("subscriptions").first?.kind == .navigate(.insights))
        #expect(registry.search("limits").first?.kind == .navigate(.budgets))
        // "banks" is unique to Accounts.
        #expect(registry.search("banks").first?.kind == .navigate(.accounts))
    }
}

@Suite("CommandRegistry Codable kinds")
struct CommandRegistryCodableTests {
    @Test("Kind round-trips through Codable for every case shape")
    func kindCodable() throws {
        let kinds: [CommandRegistry.Kind] = [
            .navigate(.dashboard),
            .navigate(.settings),
            .act(.refresh),
            .act(.summon),
            .find,
        ]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(CommandRegistry.Kind.self, from: data)
            #expect(decoded == kind)
        }
    }
}
