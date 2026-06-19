import Foundation
import Observation
import OSLog
import PlaidBarCache
import PlaidBarCore
import SwiftUI

/// `@Observable` data source for the virtualized, page-on-demand transaction list
/// (AND-567).
///
/// It drives the disposable per-transaction SwiftData cache
/// (``TransactionCacheStore``) through the pure ``PagedTransactionFeed``
/// accumulator: page 0 loads on appear, the next page loads when the list scrolls
/// near the end. Only one page (``PlaidBarConstants/transactionPageSize`` rows) is
/// materialized per fetch, so a multi-thousand-row history never loads at once.
///
/// ## Fallback-safe (no regression)
/// The list this source feeds always has the in-memory `fallbackTransactions`
/// available. When the cache is unavailable — `readModelCacheEnabled == false`,
/// the store fails to open, or no environment context is known yet — the source
/// stays in ``Mode/fallback`` and ``rows`` is exactly the in-memory array the list
/// renders today. The SwiftData path is a pure optimization layered on top; if any
/// part of it fails, rendering is byte-for-byte today's behavior.
@MainActor
@Observable
final class PagedTransactionSource {
    /// Which path is feeding the list. `fallback` is the default and the
    /// regression-safe path; `paged` engages only once the cache loaded a page.
    enum Mode: Equatable {
        case fallback
        case paged
    }

    private static let logger = Logger(subsystem: "com.ftchvs.PlaidBar", category: "PagedTransactionSource")

    /// Today's in-memory transactions — the source of truth and the default
    /// rendering. Never discarded; the paged path only *replaces what is shown*
    /// once it has loaded equivalent rows from the cache.
    private(set) var fallbackTransactions: [TransactionDTO]

    /// The cache store + scoping key, or `nil` when paging is unavailable (then the
    /// source stays on the fallback path forever, which is exactly today's behavior).
    private let store: TransactionCacheStore?
    private let cacheKey: String?
    private let pageSize: Int

    private var feed: PagedTransactionFeed
    private(set) var mode: Mode = .fallback
    /// True while a page fetch is in flight, so the view does not double-trigger.
    private(set) var isLoadingPage = false

    init(
        fallbackTransactions: [TransactionDTO],
        store: TransactionCacheStore?,
        cacheKey: String?,
        pageSize: Int = PlaidBarConstants.transactionPageSize
    ) {
        self.fallbackTransactions = fallbackTransactions
        self.store = store
        self.cacheKey = cacheKey
        self.pageSize = pageSize
        self.feed = PagedTransactionFeed(pageSize: pageSize, total: 0)
    }

    /// An in-memory-only source: no SwiftData store, so it stays on the fallback
    /// path (today's rows) but renders them through the virtualized `LazyVStack`.
    /// Used for per-account surfaces where the global cache's scope does not apply
    /// but the list should still virtualize a large per-account history.
    static func inMemory(_ transactions: [TransactionDTO]) -> PagedTransactionSource {
        PagedTransactionSource(fallbackTransactions: transactions, store: nil, cacheKey: nil)
    }

    /// The rows the list should render: the loaded cache pages once the paged path
    /// engaged, otherwise the in-memory fallback (today's behavior). Delegates to
    /// the pure ``PagedTransactionRendering`` so the fallback guarantee is the one
    /// the Core regression test pins.
    var rows: [TransactionDTO] {
        PagedTransactionRendering.rows(
            mode: mode == .paged ? .paged : .fallback,
            fallback: fallbackTransactions,
            loaded: feed.loaded
        )
    }

    /// True while another page can be loaded (paged mode only). The list uses this
    /// to decide whether to show a "loading more" affordance and whether the
    /// last-row appearance should trigger a fetch.
    var hasMore: Bool {
        mode == .paged && feed.hasMore
    }

    /// Loads the first page from the cache. Best-effort: any failure (or no store)
    /// leaves the source on the fallback path, so the list renders today's rows. On
    /// success it switches to the paged path only if the cache actually has rows;
    /// an empty cache stays on the fallback so a not-yet-seeded history still shows
    /// the in-memory transactions.
    func loadFirstPageIfNeeded() async {
        guard mode == .fallback, let store, let cacheKey else { return }
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let total = (try? await store.count(cacheKey: cacheKey)) ?? 0
        guard total > 0 else {
            // Cache empty / not seeded yet: stay on the in-memory fallback.
            return
        }
        feed = PagedTransactionFeed(pageSize: pageSize, total: total)
        guard let window = feed.nextWindow else { return }
        guard let page = try? await store.page(cacheKey: cacheKey, window: window), !page.isEmpty else {
            Self.logger.error("Paged transaction first page read empty/failed; staying on in-memory fallback")
            return
        }
        feed.appendPage(page, window: window)
        mode = .paged
    }

    /// Loads the next page when the list scrolls near the end. No-op outside the
    /// paged path, when a fetch is already running, or when there is nothing more.
    ///
    /// Before computing the next window it re-reads the cache `count()` and feeds
    /// it back via `updateTotal`. The feed's `total` is captured when the first
    /// page loads, so without this a concurrent re-sync that *grows* the history
    /// would leave the window math believing there is nothing more to load and
    /// silently drop the newly added newest transactions. Re-reading keeps the
    /// window bound to the current size; the feed's per-id dedup keeps a row that
    /// shifted between pages from rendering twice.
    func loadNextPageIfNeeded() async {
        guard mode == .paged, let store, let cacheKey, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        if let currentTotal = try? await store.count(cacheKey: cacheKey) {
            feed.updateTotal(currentTotal)
        }
        guard let window = feed.nextWindow else { return }
        guard let page = try? await store.page(cacheKey: cacheKey, window: window), !page.isEmpty else {
            // A failed page read just stops paging; already-loaded rows remain.
            return
        }
        feed.appendPage(page, window: window)
    }

    /// Updates the in-memory fallback when the live array changes. Keeps the
    /// fallback path current so a refresh that arrives before/without a cache page
    /// still shows fresh data.
    func updateFallback(_ transactions: [TransactionDTO]) {
        fallbackTransactions = transactions
    }
}
