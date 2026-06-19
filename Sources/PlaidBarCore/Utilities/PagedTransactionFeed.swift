import Foundation

/// Pure, testable accumulator state for an infinite-scroll, page-on-demand
/// transaction list (AND-567).
///
/// The virtualized list view owns only rendering; this value type owns the
/// "what's loaded, what loads next, are we done" state machine so the
/// append-page / dedup-across-pages / stop-at-end logic is unit-tested rather than
/// tangled in a SwiftUI `onAppear`. It is deliberately free of SwiftData and
/// SwiftUI: the view (or an `@Observable` source) feeds it pages read from the
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
