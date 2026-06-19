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
}
