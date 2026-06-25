import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Paged transaction feed accumulator (AND-567)")
struct PagedTransactionFeedTests {

    private func tx(_ i: Int) -> TransactionDTO {
        TransactionDTO(id: "tx_\(i)", accountId: "chk", amount: Double(i), date: "2026-01-01", name: "M\(i)")
    }

    /// Simulates the store: returns `window.limit` rows starting at `window.offset`
    /// from a synthetic newest-first id space.
    private func fetch(_ window: TransactionPageWindow) -> [TransactionDTO] {
        (window.offset..<(window.offset + window.limit)).map { tx($0) }
    }

    @Test("drives page-on-demand to walk the whole history once")
    func walksWholeHistory() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 25)
        var guardCount = 0
        while let window = feed.nextWindow, guardCount < 100 {
            feed.appendPage(fetch(window), window: window)
            guardCount += 1
        }
        #expect(feed.loaded.count == 25, "all rows loaded across pages")
        #expect(feed.loaded.map(\.id) == (0..<25).map { "tx_\($0)" }, "newest-first order preserved")
        #expect(!feed.hasMore, "no more pages once the history is covered")
    }

    @Test("first nextWindow is page 0")
    func firstWindowIsPageZero() {
        let feed = PagedTransactionFeed(pageSize: 10, total: 25)
        #expect(feed.nextWindow?.pageIndex == 0)
        #expect(feed.nextWindow?.offset == 0)
        #expect(feed.hasMore)
    }

    @Test("empty history has no pages to load")
    func emptyHistory() {
        let feed = PagedTransactionFeed(pageSize: 10, total: 0)
        #expect(feed.nextWindow == nil)
        #expect(!feed.hasMore)
        #expect(feed.loaded.isEmpty)
    }

    @Test("non-positive page size disables paging (no infinite loop)")
    func pagingDisabled() {
        let feed = PagedTransactionFeed(pageSize: 0, total: 100)
        #expect(feed.nextWindow == nil)
        #expect(!feed.hasMore)
    }

    @Test("dedups a row already loaded across overlapping pages")
    func dedupOverlap() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 30)
        let page0 = TransactionPageWindow.make(pageIndex: 0, pageSize: 10, total: 30)
        feed.appendPage(fetch(page0), window: page0)
        // Re-append an overlapping window (rows 5..15); 5..9 already loaded.
        let overlap = TransactionPageWindow(pageIndex: 0, offset: 5, limit: 10, hasMore: true)
        feed.appendPage(fetch(overlap), window: overlap)
        #expect(feed.loaded.count == 15, "only the 5 new rows were added, no duplicates")
        #expect(Set(feed.loaded.map(\.id)).count == feed.loaded.count)
    }

    @Test("updateTotal extends paging when the history grows")
    func growHistory() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 10)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0)
        #expect(!feed.hasMore, "10 rows of a 10-row history → done")

        feed.updateTotal(25)
        #expect(feed.hasMore, "history grew, more pages now available")
        #expect(feed.nextWindow?.pageIndex == 1)
    }

    @Test("reset clears loaded rows for a fresh total")
    func resetClears() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 30)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0)
        #expect(feed.loaded.count == 10)

        feed.reset(total: 5)
        #expect(feed.loaded.isEmpty)
        #expect(feed.lastLoadedPageIndex == nil)
        #expect(feed.nextWindow?.pageIndex == 0)
        #expect(feed.nextWindow?.limit == 5)
    }

    // MARK: - No-regression: fallback path renders today's rows unchanged

    @Test("fallback mode renders the in-memory array byte-for-byte (no regression)")
    func fallbackRendersInMemoryUnchanged() {
        let inMemory = (0..<37).map { tx($0) }
        // Paging disabled / cache unavailable → fallback mode. The rendered rows
        // must equal exactly today's in-memory list, regardless of any loaded pages.
        let rendered = PagedTransactionRendering.rows(
            mode: .fallback,
            fallback: inMemory,
            loaded: [tx(999)] // even if a stray page existed, fallback ignores it
        )
        #expect(rendered == inMemory, "fallback path must be identical to today's rendering")
    }

    @Test("empty in-memory fallback renders empty (no regression)")
    func fallbackEmpty() {
        let rendered = PagedTransactionRendering.rows(mode: .fallback, fallback: [], loaded: [])
        #expect(rendered.isEmpty)
    }

    @Test("paged mode renders the loaded pages, not the fallback")
    func pagedRendersLoaded() {
        let inMemory = [tx(1), tx(2)]
        let loaded = [tx(10), tx(11), tx(12)]
        let rendered = PagedTransactionRendering.rows(mode: .paged, fallback: inMemory, loaded: loaded)
        #expect(rendered == loaded)
    }

    @Test("a feed with no pages appended exposes nothing loaded, so the source stays on fallback rows")
    func unloadedFeedHasNoRows() {
        // Mirrors PagedTransactionSource before loadFirstPageIfNeeded engages: the
        // feed is empty, so a paged render would be empty — which is why the source
        // only flips to .paged after a non-empty page loads, keeping the list on the
        // in-memory fallback until real cached rows exist.
        let feed = PagedTransactionFeed(pageSize: 50, total: 0)
        #expect(feed.loaded.isEmpty)
        let rendered = PagedTransactionRendering.rows(mode: .fallback, fallback: [tx(1)], loaded: feed.loaded)
        #expect(rendered == [tx(1)])
    }

    // MARK: - Regression: stale captured total must not drop a transaction (Finding B)

    /// Reproduces the `PagedTransactionSource.loadNextPageIfNeeded` regression: the
    /// feed's `total` is captured when the first page loads, so a concurrent
    /// re-sync that grows the history would make the window math believe paging is
    /// done — silently dropping the newly added newest rows — unless the next-page
    /// path re-reads `count()` and calls `updateTotal` first.
    @Test("re-reading total before the next window recovers rows a concurrent re-sync added")
    func staleTotalDoesNotDropRows() {
        // Initial paging session over a 10-row history at 10/page: one full page.
        var feed = PagedTransactionFeed(pageSize: 10, total: 10)
        let firstWindow = feed.nextWindow!
        feed.appendPage(fetch(firstWindow), window: firstWindow)
        #expect(feed.loaded.count == 10)
        #expect(!feed.hasMore, "with the captured total, the feed thinks it is done")

        // A concurrent re-sync grew the cache to 15 rows. The OLD behavior (no
        // re-read) would stop here and never surface rows 10..14.
        let liveTotalAfterResync = 15

        // NEW behavior: loadNextPageIfNeeded re-reads count() and updates the feed
        // before asking for the next window.
        feed.updateTotal(liveTotalAfterResync)
        #expect(feed.hasMore, "after re-reading the grown total, a new page is available")

        guard let recoveredWindow = feed.nextWindow else {
            Issue.record("expected a next window after the total grew")
            return
        }
        feed.appendPage(fetch(recoveredWindow), window: recoveredWindow)

        #expect(feed.loaded.count == 15, "the 5 newly synced rows are no longer dropped")
        #expect(feed.loaded.map(\.id) == (0..<15).map { "tx_\($0)" }, "newest-first order preserved")
        #expect(!feed.hasMore, "paging completes once the live total is fully covered")
    }

    @Test("re-reading an unchanged total is a stable no-op (next page still loads)")
    func reReadingUnchangedTotalIsStable() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 25)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0)

        // Simulate loadNextPageIfNeeded re-reading the same total each call.
        feed.updateTotal(25)
        let page1 = feed.nextWindow
        #expect(page1?.pageIndex == 1, "an unchanged total still advances to the next page")
        feed.appendPage(fetch(page1!), window: page1!)
        feed.updateTotal(25)
        #expect(feed.nextWindow?.pageIndex == 2)
        #expect(feed.loaded.count == 20)
    }

    @Test("last partial page loads the remaining rows then stops")
    func lastPartialPage() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 23)
        // page 0, page 1 (full), page 2 (3 rows)
        var iterations = 0
        while let window = feed.nextWindow, iterations < 10 {
            feed.appendPage(fetch(window), window: window)
            iterations += 1
        }
        #expect(iterations == 3, "three pages cover 23 rows at 10/page")
        #expect(feed.loaded.count == 23)
        #expect(!feed.hasMore)
    }

    // MARK: - Regression: mid-session sync surfaces new head rows in paged mode (AND-632)

    /// A newest-first id where lower index == newer. `tx(0)` is the very newest, so a
    /// sync that prepends `tx(-1)`/`tx(-2)` puts the freshest rows at the front,
    /// mirroring how `appState.transactions` grows at the head.
    private func head(_ i: Int) -> TransactionDTO {
        TransactionDTO(id: "tx_\(i)", accountId: "chk", amount: Double(i), date: "2026-01-01", name: "M\(i)")
    }

    @Test("mergeHead prepends a mid-session sync's new head rows into the loaded pages (AND-632)")
    func mergeHeadSurfacesNewHeadRows() {
        // A paged session has loaded one page (rows tx_0..tx_9) from the cache.
        var feed = PagedTransactionFeed(pageSize: 10, total: 10)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0)
        #expect(feed.loaded.map(\.id) == (0..<10).map { "tx_\($0)" })

        // Mid-session sync: two brand-new transactions arrive at the head of the live
        // in-memory array (newest-first), ahead of every previously-loaded row.
        let live = [head(-2), head(-1)] + (0..<10).map { head($0) }

        let prepended = feed.mergeHead(from: live)

        #expect(prepended == 2, "exactly the two new head rows were merged")
        #expect(
            feed.loaded.map(\.id) == ["tx_-2", "tx_-1"] + (0..<10).map { "tx_\($0)" },
            "the new rows lead the loaded list, newest-first, ahead of the paged window"
        )
        #expect(feed.total == 12, "total grew by the merged rows so window math still tracks the live size")
        #expect(Set(feed.loaded.map(\.id)).count == feed.loaded.count, "no duplicates")
    }

    @Test("mergeHead is a no-op when the live head adds nothing new (idempotent)")
    func mergeHeadNoNewRowsIsNoOp() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 10)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0)
        let before = feed.loaded

        // Same head as already loaded → nothing newer to prepend.
        let prepended = feed.mergeHead(from: (0..<10).map { head($0) })

        #expect(prepended == 0)
        #expect(feed.loaded == before, "loaded rows are untouched")
        #expect(feed.total == 10, "total unchanged when nothing merged")
    }

    @Test("mergeHead stops at the boundary: only rows ahead of the loaded head merge")
    func mergeHeadStopsAtBoundary() {
        // Loaded rows are tx_2..tx_6 (a middle slice).
        var feed = PagedTransactionFeed(pageSize: 5, total: 5)
        let window = TransactionPageWindow(pageIndex: 0, offset: 2, limit: 5, hasMore: false)
        feed.appendPage((2..<7).map { head($0) }, window: window)
        #expect(feed.loaded.map(\.id) == ["tx_2", "tx_3", "tx_4", "tx_5", "tx_6"])

        // Live array: one brand-new head row (tx_1), then the loaded head (tx_2)
        // appears — the walk must STOP there, never reaching the older tx_7/tx_8 that
        // belong to a not-yet-loaded later page.
        let live = [head(1), head(2), head(3), head(7), head(8)]
        let prepended = feed.mergeHead(from: live)

        #expect(prepended == 1, "only tx_1 is ahead of the loaded head; the walk stops at tx_2")
        #expect(feed.loaded.first?.id == "tx_1")
        #expect(!feed.loaded.contains { $0.id == "tx_7" }, "later-page rows are never pulled in by a head merge")
    }

    @Test("mergeHead is a no-op before any page loads (still on the fallback path)")
    func mergeHeadBeforePagingEngages() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 0)
        let prepended = feed.mergeHead(from: [head(-1), head(0)])
        #expect(prepended == 0, "nothing is loaded to prepend onto; the source still renders the fallback")
        #expect(feed.loaded.isEmpty)
    }

    @Test("mergeHead refuses a wholesale replace: unrelated live array does not stack onto stale rows")
    func mergeHeadRefusesWholesaleReplace() {
        var feed = PagedTransactionFeed(pageSize: 10, total: 10)
        let page0 = feed.nextWindow!
        feed.appendPage(fetch(page0), window: page0) // tx_0..tx_9
        let before = feed.loaded

        // An environment switch / full reset yields an array sharing NO ids with the
        // loaded rows. Blindly prepending it would stack a whole foreign history on
        // top of stale rows; the lineage guard must reject it (reset(total:) is the
        // correct path for a wholesale replace, not mergeHead).
        let unrelated = (100..<110).map { head($0) }
        let prepended = feed.mergeHead(from: unrelated)

        #expect(prepended == 0, "no shared lineage → no merge")
        #expect(feed.loaded == before, "loaded rows are left exactly as they were")
    }

    /// End-to-end repro of the AND-632 bug at the layer the view composes: a
    /// mid-session sync's new head row must be *visible under an active filter*.
    /// Reproduces the original failure (head rows hidden behind the paged window)
    /// and pins the fix: after `mergeHead`, the freshly-synced row survives the
    /// pure `TransactionWorkspace` filter that the view runs over the paged rows —
    /// without re-reading the cache or re-draining later pages.
    @Test("mid-session sync surfaces a new head row under an active search filter (AND-632)")
    func newHeadRowVisibleUnderActiveFilter() {
        // Paged session: one loaded page of "Coffee" rows the user is filtering for.
        func coffee(_ i: Int) -> TransactionDTO {
            TransactionDTO(id: "tx_\(i)", accountId: "chk", amount: 5, date: "2026-01-0\(i % 9 + 1)", name: "Coffee \(i)")
        }
        var feed = PagedTransactionFeed(pageSize: 5, total: 5)
        let page0 = feed.nextWindow!
        feed.appendPage((0..<5).map { coffee($0) }, window: page0)

        // An active search filter the view already applies to the paged rows.
        let filter = TransactionWorkspace.Filter(searchText: "coffee")
        #expect(filter.isActive)

        // BEFORE the sync: the matching rows are exactly the loaded page.
        let now = Date()
        let beforeRows = TransactionWorkspace.rows(transactions: feed.loaded, metadata: [], rules: [])
        let beforeFiltered = TransactionWorkspace.filtered(beforeRows, by: filter, now: now)
        #expect(beforeFiltered.count == 5)
        #expect(!beforeFiltered.contains { $0.id == "tx_-1" }, "the not-yet-synced head row is absent, as expected")

        // Mid-session sync prepends a new matching "Coffee" transaction at the head.
        let synced = TransactionDTO(id: "tx_-1", accountId: "chk", amount: 5, date: "2026-01-09", name: "Coffee NEW")
        let live = [synced] + (0..<5).map { coffee($0) }
        feed.mergeHead(from: live)

        // AFTER the merge: the view's pipeline over the (still paged) rows now
        // includes the new head row under the SAME active filter — no cache re-read,
        // no page re-drain. This is the assertion the bug failed.
        let afterRows = TransactionWorkspace.rows(transactions: feed.loaded, metadata: [], rules: [])
        let afterFiltered = TransactionWorkspace.filtered(afterRows, by: filter, now: now)
        #expect(afterFiltered.contains { $0.id == "tx_-1" }, "the mid-session sync's new head row is now visible under the active filter")
        #expect(afterFiltered.count == 6, "no other row dropped — later-page matches are untouched")
    }
}
