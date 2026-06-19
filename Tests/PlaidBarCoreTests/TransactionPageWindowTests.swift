import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Transaction page-window math (AND-567)")
struct TransactionPageWindowTests {

    @Test("first page of a multi-page history")
    func firstPage() {
        let w = TransactionPageWindow.make(pageIndex: 0, pageSize: 50, total: 320)
        #expect(w.offset == 0)
        #expect(w.limit == 50)
        #expect(w.hasMore, "320 rows beyond page 0 means more to load")
    }

    @Test("middle page offsets by pageIndex * pageSize")
    func middlePage() {
        let w = TransactionPageWindow.make(pageIndex: 3, pageSize: 50, total: 320)
        #expect(w.offset == 150)
        #expect(w.limit == 50)
        #expect(w.hasMore)
    }

    @Test("final partial page trims the limit to the remaining rows")
    func finalPartialPage() {
        // 320 rows, 50/page → pages 0..6; page 6 starts at 300, 20 rows remain.
        let w = TransactionPageWindow.make(pageIndex: 6, pageSize: 50, total: 320)
        #expect(w.offset == 300)
        #expect(w.limit == 20, "only 20 rows remain on the last page")
        #expect(!w.hasMore, "the last page is the end of the history")
    }

    @Test("exact final page when total is a multiple of pageSize")
    func exactFinalPage() {
        // 100 rows, 50/page → page 1 is the last full page; nothing follows.
        let w = TransactionPageWindow.make(pageIndex: 1, pageSize: 50, total: 100)
        #expect(w.offset == 50)
        #expect(w.limit == 50)
        #expect(!w.hasMore, "offset+limit == total → no more pages")
    }

    @Test("page past the end is empty with no more to load")
    func pastEnd() {
        let w = TransactionPageWindow.make(pageIndex: 9, pageSize: 50, total: 100)
        #expect(w.limit == 0)
        #expect(!w.hasMore)
    }

    @Test("empty history yields an empty first page")
    func emptyHistory() {
        let w = TransactionPageWindow.make(pageIndex: 0, pageSize: 50, total: 0)
        #expect(w.offset == 0)
        #expect(w.limit == 0)
        #expect(!w.hasMore)
    }

    @Test("non-positive page size degrades to an empty window, never an infinite fetch")
    func invalidPageSize() {
        let zero = TransactionPageWindow.make(pageIndex: 0, pageSize: 0, total: 100)
        #expect(zero.limit == 0)
        #expect(!zero.hasMore)

        let negative = TransactionPageWindow.make(pageIndex: 2, pageSize: -10, total: 100)
        #expect(negative.limit == 0)
        #expect(!negative.hasMore)
    }

    @Test("negative page index clamps to an empty page-0 window")
    func negativePageIndex() {
        let w = TransactionPageWindow.make(pageIndex: -1, pageSize: 50, total: 100)
        #expect(w.pageIndex == 0)
        #expect(w.limit == 0)
        #expect(!w.hasMore)
    }

    @Test("a single short page never claims more to load")
    func singleShortPage() {
        let w = TransactionPageWindow.make(pageIndex: 0, pageSize: 50, total: 12)
        #expect(w.offset == 0)
        #expect(w.limit == 12)
        #expect(!w.hasMore)
    }

    @Test("pageCount rounds up partial pages")
    func pageCount() {
        #expect(TransactionPageWindow.pageCount(pageSize: 50, total: 320) == 7)
        #expect(TransactionPageWindow.pageCount(pageSize: 50, total: 100) == 2)
        #expect(TransactionPageWindow.pageCount(pageSize: 50, total: 0) == 0)
        #expect(TransactionPageWindow.pageCount(pageSize: 0, total: 100) == 0)
    }

    @Test("next walks forward then stops at the end")
    func nextWalk() {
        let pageSize = 50
        let total = 120 // pages 0,1,2 (sizes 50,50,20)
        let first = TransactionPageWindow.make(pageIndex: 0, pageSize: pageSize, total: total)
        let second = first.next(pageSize: pageSize, total: total)
        #expect(second?.pageIndex == 1)
        #expect(second?.offset == 50)

        let third = second?.next(pageSize: pageSize, total: total)
        #expect(third?.pageIndex == 2)
        #expect(third?.limit == 20)
        #expect(third?.hasMore == false)

        #expect(third?.next(pageSize: pageSize, total: total) == nil, "no page follows the last one")
    }

    @Test("next returns nil when the total shrank below the loaded window (re-sync removed rows)")
    func nextNilWhenTotalShrank() {
        // Loaded as if total were large, but the live total is now smaller than
        // where the next page would start.
        let stale = TransactionPageWindow(pageIndex: 5, offset: 250, limit: 50, hasMore: true)
        #expect(stale.next(pageSize: 50, total: 100) == nil)
    }
}
