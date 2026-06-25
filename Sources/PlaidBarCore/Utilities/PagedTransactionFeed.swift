import Foundation

/// Pure, testable accumulator state for an infinite-scroll, page-on-demand
/// transaction list (AND-567).
///
/// The virtualized list view owns only rendering; this value type owns the
/// "what's loaded, what loads next, are we done" state machine so the
/// append-page / dedup-across-pages / stop-at-end logic is unit-tested rather than
/// tangled in a SwiftUI `onAppear`. It is deliberately free of the storage layer
/// and SwiftUI: the view (or an `@Observable` source) feeds it pages read from the
/// ``TransactionCacheStore`` and asks it for the next ``TransactionPageWindow``.
///
/// Rows are newest-first and de-duplicated by id across pages, so a transaction
/// that shifts between pages because a concurrent re-sync changed `total` can
/// never render twice.
public struct PagedTransactionFeed: Sendable, Equatable {
    /// The page size each fetch requests.
    public let pageSize: Int
    /// The authoritative total row count the windows are computed against. Updated
    /// when the live history grows/shrinks so paging tracks the current size.
    public private(set) var total: Int
    /// Loaded rows in render order (newest-first), de-duplicated by id.
    public private(set) var loaded: [TransactionDTO]
    /// Highest page index already appended, or `nil` before the first page loads.
    public private(set) var lastLoadedPageIndex: Int?

    private var loadedIds: Set<String>

    public init(pageSize: Int, total: Int = 0) {
        self.pageSize = max(0, pageSize)
        self.total = max(0, total)
        self.loaded = []
        self.lastLoadedPageIndex = nil
        self.loadedIds = []
    }

    /// The window to fetch next, or `nil` when the loaded rows already cover the
    /// history (or paging is disabled by a non-positive page size). The first call
    /// returns page 0; subsequent calls return the page after the last appended.
    public var nextWindow: TransactionPageWindow? {
        guard pageSize > 0, total > 0 else { return nil }
        let nextIndex = (lastLoadedPageIndex.map { $0 + 1 }) ?? 0
        let window = TransactionPageWindow.make(pageIndex: nextIndex, pageSize: pageSize, total: total)
        return window.limit > 0 ? window : nil
    }

    /// True while there is at least one more page to request.
    public var hasMore: Bool { nextWindow != nil }

    /// Appends a freshly fetched page's rows (already newest-first for its window),
    /// recording that `window.pageIndex` is now loaded. Rows whose id is already
    /// loaded are skipped (dedup), so an overlapping re-fetch is idempotent.
    public mutating func appendPage(_ rows: [TransactionDTO], window: TransactionPageWindow) {
        for row in rows where !loadedIds.contains(row.id) {
            loaded.append(row)
            loadedIds.insert(row.id)
        }
        lastLoadedPageIndex = max(lastLoadedPageIndex ?? window.pageIndex, window.pageIndex)
    }

    /// Updates the known total (e.g. after a refresh changed the history size).
    /// Does not drop already-loaded rows; it only changes whether more pages
    /// remain to be fetched.
    public mutating func updateTotal(_ newTotal: Int) {
        total = max(0, newTotal)
    }

    /// Merges the *new head* of a freshly-synced, newest-first in-memory history
    /// into the loaded rows — without re-reading the cache or resetting the feed
    /// (AND-632).
    ///
    /// ## The bug this fixes
    /// In paged mode the list renders ``loaded`` (the cache pages), not the live
    /// in-memory array. So an in-session sync that prepends newer transactions to
    /// `appState.transactions` left them invisible until the view was recreated:
    /// the source only refreshed the render-dead fallback, never the paged rows.
    ///
    /// ## Why this is the safe shape (vs. re-reading page 0)
    /// The earlier fix re-seeded from the cache, which (a) could read the *old*
    /// cache before the detached persist committed — resurrecting stale rows — and
    /// (b) dropped later loaded pages, so active-filter matches on those pages
    /// vanished. This instead **only prepends** rows already in hand from the live
    /// array, touching nothing already loaded:
    /// - No cache read → no not-yet-committed-cache race.
    /// - Later pages are untouched → an active filter draining later pages keeps
    ///   its matches; nothing needs re-keying or re-draining.
    /// - Deduped by id → a row can never render twice.
    ///
    /// ## What counts as the "new head"
    /// Walks `liveNewestFirst` from the front, collecting rows whose id is **not**
    /// already loaded, and **stops at the first id that is** — that boundary is
    /// where the live head meets the already-loaded window, so everything before it
    /// is provably newer than every loaded row. The collected prefix is prepended
    /// (newest-first order preserved) and `total` grows by the number added so the
    /// window math still tracks the live size.
    ///
    /// ## Guard against wholesale replacement
    /// Prepending is only sound when the live array and the loaded rows share
    /// lineage (a head-append, not an environment switch / full replace). The
    /// signal: the current head of ``loaded`` still appears somewhere in
    /// `liveNewestFirst`. If it does not — the histories are unrelated, or the
    /// loaded head row was *removed* by the sync — this is a no-op; a wholesale
    /// replace is the caller's `reset(total:)` path, never a blind prepend that
    /// would stack the entire live array on top of stale rows.
    ///
    /// Returns the number of rows prepended (0 when nothing merged), so the caller
    /// can decide whether a downstream invalidation is worth doing.
    @discardableResult
    public mutating func mergeHead(from liveNewestFirst: [TransactionDTO]) -> Int {
        // Nothing loaded yet → the page path has not engaged; there is nothing to
        // prepend *onto* (the source is still rendering the in-memory fallback).
        guard let loadedHeadId = loaded.first?.id else { return 0 }

        // Lineage check: the loaded head must still be present in the live array,
        // proving this is an append at the head and not a wholesale replacement.
        // (Linear scan, but it short-circuits at the boundary below in the common
        // case where the new head is a small prefix.)
        guard liveNewestFirst.contains(where: { $0.id == loadedHeadId }) else { return 0 }

        var newHead: [TransactionDTO] = []
        for row in liveNewestFirst {
            // Stop at the first row already loaded: that is the boundary between the
            // freshly-synced head and the already-paged window. Everything collected
            // before it is strictly newer than every loaded row.
            if loadedIds.contains(row.id) { break }
            newHead.append(row)
        }
        guard !newHead.isEmpty else { return 0 }

        loaded.insert(contentsOf: newHead, at: 0)
        for row in newHead { loadedIds.insert(row.id) }
        // The history grew by exactly the rows we prepended; keep `total` in step so
        // `nextWindow` / `hasMore` continue to track the live size.
        total += newHead.count
        return newHead.count
    }

    /// Resets to the empty, unloaded state for a fresh `total` — used when the
    /// underlying data is replaced wholesale (environment switch, full refresh) so
    /// stale rows never persist in the feed.
    public mutating func reset(total newTotal: Int) {
        total = max(0, newTotal)
        loaded = []
        loadedIds = []
        lastLoadedPageIndex = nil
    }

    public static func == (lhs: PagedTransactionFeed, rhs: PagedTransactionFeed) -> Bool {
        lhs.pageSize == rhs.pageSize
            && lhs.total == rhs.total
            && lhs.lastLoadedPageIndex == rhs.lastLoadedPageIndex
            && lhs.loaded == rhs.loaded
    }
}

/// The two paths a paged transaction list can render from (AND-567). `fallback`
/// is the default, regression-safe path — today's in-memory array; `paged`
/// engages only once the disposable cache has loaded equivalent rows.
public enum PagedTransactionRenderMode: Sendable, Equatable {
    case fallback
    case paged
}

/// Pure rendering decision for the paged transaction list (AND-567).
///
/// Centralizes "which rows does the list show" so both the app-target
/// `PagedTransactionSource` and a unit test share one definition. The key
/// regression guarantee lives here: in ``PagedTransactionRenderMode/fallback``
/// — the path taken whenever paging is disabled, the cache is unavailable, or no
/// page has loaded yet — the rendered rows are **exactly** the supplied in-memory
/// array, unchanged from today's behavior.
public enum PagedTransactionRendering {
    /// The rows to render for `mode`, given the in-memory `fallback` array and the
    /// `loaded` cache pages.
    public static func rows(
        mode: PagedTransactionRenderMode,
        fallback: [TransactionDTO],
        loaded: [TransactionDTO]
    ) -> [TransactionDTO] {
        switch mode {
        case .fallback: return fallback
        case .paged: return loaded
        }
    }
}
