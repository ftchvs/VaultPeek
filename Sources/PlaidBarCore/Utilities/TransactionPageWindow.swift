import Foundation

/// Pure, testable page-window math for large-history transaction paging
/// (AND-567).
///
/// Owns the offset/limit/`hasMore` arithmetic for an infinite-scroll list backed
/// by a paged store (the SwiftData `CachedTransaction` cache, or any ordered
/// collection). Keeping this free of SwiftData and SwiftUI means the page-on-demand
/// boundary conditions — last partial page, empty history, a `total` that shrinks
/// under the loaded window after a re-sync — are unit-tested in isolation rather
/// than discovered in a scrolling view.
///
/// Indexing convention: `pageIndex` is zero-based, results are newest-first, and a
/// window maps to a `FetchDescriptor` as `fetchOffset = offset`, `fetchLimit = limit`.
public struct TransactionPageWindow: Sendable, Equatable {
    /// Zero-based page index this window describes.
    public let pageIndex: Int
    /// Number of rows to skip — the `FetchDescriptor.fetchOffset`.
    public let offset: Int
    /// Maximum rows to read — the `FetchDescriptor.fetchLimit`.
    public let limit: Int
    /// True when at least one more row exists beyond this window, so the list
    /// should request the next page when the user scrolls to the end.
    public let hasMore: Bool

    public init(pageIndex: Int, offset: Int, limit: Int, hasMore: Bool) {
        self.pageIndex = pageIndex
        self.offset = offset
        self.limit = limit
        self.hasMore = hasMore
    }

    /// Builds the window for `pageIndex` given the `total` row count and a
    /// `pageSize`. Clamps defensively so a caller can never produce a negative
    /// offset/limit or claim there is more to load when the requested page already
    /// sits at or past the end.
    ///
    /// - A non-positive `pageSize` yields an empty window (`limit == 0`,
    ///   `hasMore == false`) so a misconfiguration degrades to "nothing to page"
    ///   rather than an infinite-loop fetch.
    /// - When the requested page starts at or beyond `total`, the window is empty
    ///   and `hasMore` is false (there is nothing past the end to load).
    /// - `limit` is the page size except on the final partial page, where it is
    ///   trimmed to exactly the rows that remain — so a fetch never over-reads.
    public static func make(pageIndex: Int, pageSize: Int, total: Int) -> TransactionPageWindow {
        let safeTotal = max(0, total)
        guard pageSize > 0, pageIndex >= 0 else {
            return TransactionPageWindow(pageIndex: max(0, pageIndex), offset: 0, limit: 0, hasMore: false)
        }

        let offset = pageIndex * pageSize
        guard offset < safeTotal else {
            // Requested page is entirely past the end: empty, nothing more to load.
            return TransactionPageWindow(pageIndex: pageIndex, offset: offset, limit: 0, hasMore: false)
        }

        let remaining = safeTotal - offset
        let limit = min(pageSize, remaining)
        let hasMore = (offset + limit) < safeTotal
        return TransactionPageWindow(pageIndex: pageIndex, offset: offset, limit: limit, hasMore: hasMore)
    }

    /// Total number of pages needed to cover `total` rows at `pageSize`. Zero when
    /// there is nothing to page or the page size is invalid.
    public static func pageCount(pageSize: Int, total: Int) -> Int {
        let safeTotal = max(0, total)
        guard pageSize > 0, safeTotal > 0 else { return 0 }
        return (safeTotal + pageSize - 1) / pageSize
    }

    /// The window for the page that should load *after* the currently loaded
    /// window, or `nil` when the current window already reached the end. Drives the
    /// infinite-scroll "load next page when the last row appears" trigger without
    /// the view re-deriving offsets.
    public func next(pageSize: Int, total: Int) -> TransactionPageWindow? {
        guard hasMore else { return nil }
        let candidate = TransactionPageWindow.make(pageIndex: pageIndex + 1, pageSize: pageSize, total: total)
        return candidate.limit > 0 ? candidate : nil
    }
}
