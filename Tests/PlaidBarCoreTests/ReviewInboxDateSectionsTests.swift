import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Inbox Date Sections (AND-529)")
struct ReviewInboxDateSectionsTests {
    // Pinned reference "now": Wednesday 2026-06-17. Calendar pinned to Gregorian /
    // en_US_POSIX with firstWeekday = Sunday so week boundaries are deterministic
    // regardless of the host's locale.
    private let asOf = makeDate("2026-06-17")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }

    @Test("Empty input yields no sections")
    func emptyInput() {
        let sections = ReviewInboxDateSections.sections(items: [], asOf: asOf, calendar: calendar)
        #expect(sections.isEmpty)
    }

    @Test("Buckets each row into the right recency section")
    func bucketsByRecency() {
        let items = [
            item(id: "today", date: "2026-06-17"),
            item(id: "yesterday", date: "2026-06-16"),
            // 2026-06-15 (Mon) is earlier in the same Sun-started week as 06-17.
            item(id: "thisWeek", date: "2026-06-15"),
            // 2026-06-13 (Sat) is in the prior week → Earlier.
            item(id: "earlier", date: "2026-06-13"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(sections.map(\.kind) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(section(sections, .today)?.itemIDs == ["today"])
        #expect(section(sections, .yesterday)?.itemIDs == ["yesterday"])
        #expect(section(sections, .thisWeek)?.itemIDs == ["thisWeek"])
        #expect(section(sections, .earlier)?.itemIDs == ["earlier"])
    }

    @Test("Sections are always in fixed recency order regardless of input order")
    func fixedRecencyOrder() {
        // Deliberately shuffle input order: earlier first, today last.
        let items = [
            item(id: "earlier", date: "2026-06-01"),
            item(id: "thisWeek", date: "2026-06-15"),
            item(id: "yesterday", date: "2026-06-16"),
            item(id: "today", date: "2026-06-17"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(sections.map(\.kind) == [.today, .yesterday, .thisWeek, .earlier])
    }

    @Test("Section labels are correct and leak no figures")
    func labelsCorrect() {
        let items = [
            item(id: "today", date: "2026-06-17"),
            item(id: "yesterday", date: "2026-06-16"),
            item(id: "thisWeek", date: "2026-06-15"),
            item(id: "earlier", date: "2026-06-01"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(sections.map(\.label) == ["Today", "Yesterday", "This Week", "Earlier"])
    }

    @Test("Empty buckets are omitted, not rendered as empty headers")
    func emptyBucketsOmitted() {
        // Only today + earlier rows: yesterday and this-week sections must not appear.
        let items = [
            item(id: "today", date: "2026-06-17"),
            item(id: "earlier", date: "2026-05-30"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(sections.map(\.kind) == [.today, .earlier])
    }

    @Test("Input order is preserved within a section")
    func orderPreservedWithinSection() {
        // Three Today rows in a specific input order: the section must keep it.
        let items = [
            item(id: "first", date: "2026-06-17"),
            item(id: "second", date: "2026-06-17"),
            item(id: "third", date: "2026-06-17"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(sections.count == 1)
        #expect(section(sections, .today)?.itemIDs == ["first", "second", "third"])
    }

    @Test("Per-section item-id grouping maps the right ids to each bucket")
    func itemIDGrouping() {
        let items = [
            item(id: "t1", date: "2026-06-17"),
            item(id: "t2", date: "2026-06-17"),
            item(id: "y1", date: "2026-06-16"),
            item(id: "w1", date: "2026-06-14"), // Sunday start of this week
            item(id: "e1", date: "2026-06-10"),
            item(id: "e2", date: "2026-06-09"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(section(sections, .today)?.itemIDs == ["t1", "t2"])
        #expect(section(sections, .yesterday)?.itemIDs == ["y1"])
        #expect(section(sections, .thisWeek)?.itemIDs == ["w1"])
        #expect(section(sections, .earlier)?.itemIDs == ["e1", "e2"])
        // Counts mirror the grouping.
        #expect(section(sections, .today)?.count == 2)
        #expect(section(sections, .earlier)?.count == 2)
    }

    @Test("Sunday week start: a Sunday row is This Week, the prior Saturday is Earlier")
    func weekBoundaryAcrossSunday() {
        // asOf 2026-06-17 (Wed) → week of Sun 2026-06-14.
        let items = [
            item(id: "sunday", date: "2026-06-14"), // first day of this week
            item(id: "saturday", date: "2026-06-13"), // last day of prior week
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(section(sections, .thisWeek)?.itemIDs == ["sunday"])
        #expect(section(sections, .earlier)?.itemIDs == ["saturday"])
        #expect(section(sections, .yesterday) == nil)
    }

    @Test("Month boundary: yesterday crossing into the prior month still reads as Yesterday")
    func monthBoundaryYesterday() {
        // asOf first of a month → yesterday is the last day of the prior month.
        let asOfFirst = makeDate("2026-07-01")
        let items = [
            item(id: "today", date: "2026-07-01"),
            item(id: "yesterday", date: "2026-06-30"),
            item(id: "earlier", date: "2026-06-20"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOfFirst, calendar: calendar)

        #expect(section(sections, .today)?.itemIDs == ["today"])
        #expect(section(sections, .yesterday)?.itemIDs == ["yesterday"])
        // 2026-06-30 (Tue) sits in the week of Sun 2026-06-28; the week of asOf
        // 2026-07-01 starts Sun 2026-06-28 too, so 06-20 is clearly Earlier.
        #expect(section(sections, .earlier)?.itemIDs == ["earlier"])
    }

    @Test("Year boundary: Jan 1 today, Dec 31 yesterday")
    func yearBoundaryYesterday() {
        let asOfNewYear = makeDate("2027-01-01")
        let items = [
            item(id: "today", date: "2027-01-01"),
            item(id: "yesterday", date: "2026-12-31"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOfNewYear, calendar: calendar)

        #expect(section(sections, .today)?.itemIDs == ["today"])
        #expect(section(sections, .yesterday)?.itemIDs == ["yesterday"])
    }

    @Test("An unparseable date defers to Earlier rather than dropping the row")
    func unparseableDateFallsToEarlier() {
        let items = [
            item(id: "today", date: "2026-06-17"),
            item(id: "garbage", date: "not-a-date"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        #expect(section(sections, .today)?.itemIDs == ["today"])
        #expect(section(sections, .earlier)?.itemIDs == ["garbage"])
    }

    @Test("A future-dated row reads as Today, never lost")
    func futureDatedReadsAsToday() {
        let items = [
            item(id: "future", date: "2026-06-20"),
            item(id: "today", date: "2026-06-17"),
        ]

        let sections = ReviewInboxDateSections.sections(items: items, asOf: asOf, calendar: calendar)

        // Both land in Today (future defensively folds forward); no row is dropped.
        #expect(section(sections, .today)?.itemIDs == ["future", "today"])
        #expect(sections.count == 1)
    }

    // MARK: - Helpers

    private func section(
        _ sections: [ReviewInboxDateSections.Section],
        _ kind: ReviewInboxDateSections.Kind
    ) -> ReviewInboxDateSections.Section? {
        sections.first { $0.kind == kind }
    }

    private func item(id: String, date: String) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: TransactionDTO(
                id: id,
                accountId: "test-account",
                amount: 12,
                date: date,
                name: "MERCHANT \(id)",
                merchantName: "Merchant \(id)",
                category: nil,
                pending: false
            ),
            status: .needsReview,
            reasonCodes: [.uncategorized],
            effectiveCategory: nil,
            effectiveMerchantName: "Merchant \(id)",
            isTransfer: false,
            excludedFromBudgets: false,
            matchedRuleIds: []
        )
    }

}

/// Builds a deterministic reference `Date` from a `yyyy-MM-dd` key, anchored at
/// midday in the test's pinned timezone so timezone offsets never tip the date
/// across a day boundary.
private func makeDate(_ key: String) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: key)!.addingTimeInterval(12 * 3600)
}
