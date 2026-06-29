import Foundation
import PlaidBarCore

/// App-local, local-first store for user savings ``Goal``s (AND-606).
///
/// Goals are net-new and live **entirely on the user's machine** — no server
/// schema, no Plaid call. They persist as `goals.json` under the app data dir
/// (`LocalDataStore.goalsURL`), the same private-permissioned local-first pattern
/// the review metadata / merchant rules use. The pure ``Goal`` value type (and its
/// progress math) lives in `PlaidBarCore`; this is the thin `@Observable`
/// `@MainActor` shell SwiftUI binds to plus the persistence round-trip.
///
/// Window-first surface only: nothing constructs this with the
/// `WindowFirstFeatureFlag` OFF (the Goals destination is reached solely through
/// the window-first shell), so the popover boot path never touches goals storage
/// and flag-OFF behavior is byte-identical. Loading is lazy — `loadIfNeeded()`
/// runs on the destination's first appearance, not at app launch.
@Observable
@MainActor
final class GoalsStore {
    /// The user's goals, newest-created first for display.
    private(set) var goals: [Goal] = []

    /// True once the on-disk goals have been loaded (or confirmed absent), so the
    /// view can distinguish "still loading" from a genuine empty / first-run state.
    private(set) var hasLoaded = false

    /// Non-nil when the last load or save failed; surfaced as a non-blocking
    /// banner rather than throwing into the view.
    private(set) var errorMessage: String?

    private let cache: LocalDataCacheService
    private let directoryProvider: @MainActor () -> URL
    private var preDemoSnapshot: GoalsSnapshot?
    private var isShowingDemoGoals = false

    private struct GoalsSnapshot {
        let goals: [Goal]
        let hasLoaded: Bool
        let errorMessage: String?
    }

    /// - Parameters:
    ///   - cache: the local JSON cache actor. Default constructs its own so the
    ///     store is self-contained and independent of `AppState`'s lifecycle.
    ///   - directoryProvider: resolves the app data dir. Defaults to the shared
    ///     `~/.vaultpeek` location; tests inject a temp directory for isolation.
    init(
        cache: LocalDataCacheService = LocalDataCacheService(),
        directoryProvider: @escaping @MainActor () -> URL = { LocalDataStore.storageDirectoryURL() }
    ) {
        self.cache = cache
        self.directoryProvider = directoryProvider
    }

    // MARK: - Loading

    /// Loads goals from disk once. Idempotent: a second call (e.g. the inspector
    /// and content pane both appearing) is a no-op after the first load.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    /// Forces a reload from disk (used by `loadIfNeeded` and recoverable errors).
    func reload() async {
        let directory = directoryProvider()
        do {
            let loaded = try await cache.loadGoals(from: directory)
            goals = Self.sortedForDisplay(loaded)
            errorMessage = nil
        } catch {
            errorMessage = "Goals failed to load: \(error.localizedDescription)"
        }
        hasLoaded = true
    }

    /// Replaces the in-memory list with synthetic demo fixtures without touching
    /// the user's persisted `goals.json`. Demo mode should be useful on a clean
    /// machine, but it must never overwrite local-first user data.
    func loadDemoGoals(_ demoGoals: [Goal]) {
        if preDemoSnapshot == nil {
            preDemoSnapshot = GoalsSnapshot(
                goals: goals,
                hasLoaded: hasLoaded,
                errorMessage: errorMessage
            )
        }
        isShowingDemoGoals = true
        goals = Self.sortedForDisplay(demoGoals)
        errorMessage = nil
        hasLoaded = true
    }

    /// Restores the real local-first goals after leaving demo mode. If goals had
    /// already loaded before demo entry, restore that in-memory snapshot; otherwise
    /// reload from disk so the demo fixture list cannot keep `loadIfNeeded()` from
    /// reaching the user's saved `goals.json`.
    func restoreAfterDemo() async {
        let snapshot = preDemoSnapshot
        preDemoSnapshot = nil
        isShowingDemoGoals = false
        guard let snapshot else {
            hasLoaded = false
            await reload()
            return
        }

        if snapshot.hasLoaded {
            goals = snapshot.goals
            hasLoaded = true
            errorMessage = snapshot.errorMessage
        } else {
            goals = []
            errorMessage = nil
            hasLoaded = false
            await reload()
        }
    }

    // MARK: - CRUD (each mutation persists)

    /// Adds a new goal and persists. Returns the stored goal (with its id).
    @discardableResult
    func add(_ goal: Goal) async -> Goal {
        goals = Self.sortedForDisplay(goals + [goal])
        await persist()
        return goal
    }

    /// Replaces an existing goal (matched by id) and persists. No-op if the id is
    /// unknown.
    func update(_ goal: Goal) async {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
        goals = Self.sortedForDisplay(goals)
        await persist()
    }

    /// Deletes the goal with the given id and persists. No-op if absent.
    func delete(id: Goal.ID) async {
        let filtered = goals.filter { $0.id != id }
        guard filtered.count != goals.count else { return }
        goals = filtered
        await persist()
    }

    /// The goal for an id, or `nil`.
    func goal(id: Goal.ID) -> Goal? {
        goals.first { $0.id == id }
    }

    // MARK: - Persistence

    private func persist() async {
        guard !isShowingDemoGoals else {
            errorMessage = nil
            return
        }

        let snapshot = goals
        let directory = directoryProvider()
        do {
            try await cache.saveGoals(snapshot, to: directory)
            errorMessage = nil
        } catch {
            errorMessage = "Goals failed to save: \(error.localizedDescription)"
        }
    }

    /// Newest-created first; ties broken by name then id for a stable order.
    private static func sortedForDisplay(_ goals: [Goal]) -> [Goal] {
        goals.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
