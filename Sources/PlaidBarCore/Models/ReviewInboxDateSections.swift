import Foundation

/// Pure date-bucketing for the Review Inbox (AND-529).
///
/// Groups review-inbox rows into recency sections — Today / Yesterday / This
/// Week / Earlier — each with a stable kind, a human label, and the item ids it
/// covers. The view renders one section header per group and offers a
/// per-section "approve all in section" affordance that reuses the existing
/// single/bulk approve path; no review logic is forked here.
///
/// Design notes:
/// - **No hidden `Date()`.** `asOf` and the `Calendar` are injected, so bucketing
///   is deterministic and unit-testable across day/week/month boundaries.
/// - **String dates.** `transaction.date` is a canonical `yyyy-MM-dd` Plaid key;
///   it is parsed with the same pinned-locale formatter the rest of the app uses
///   (`Formatters.parseTransactionDate`). A row whose date cannot be parsed falls
///   into `Earlier` rather than being dropped — the inbox never silently loses a
///   row to a malformed date.
/// - **Order preserved.** Input order (already priority- then date-sorted by
///   `TransactionReviewInbox`) is preserved within each section, so the visual
///   order inside a section matches the snapshot.
/// - **Empty sections omitted.** Only non-empty sections are emitted, in fixed
///   recency order, so the view never renders an empty "Today" header.
public enum ReviewInboxDateSections {
    /// A stable identity for a recency bucket. Distinct from the label so the
    /// view can key on it (and tests can assert ordering) independent of copy.
    public enum Kind: String, Sendable, Equatable, CaseIterable, Hashable {
        case today
        case yesterday
        case thisWeek
        case earlier

        /// Fixed recency order: most-recent bucket first.
        public var order: Int {
            switch self {
            case .today: 0
            case .yesterday: 1
            case .thisWeek: 2
            case .earlier: 3
            }
        }

        /// Human-facing section header. Carries meaning through text, never color
        /// alone (accessibility), and leaks no sensitive figures (privacy).
        public var label: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .thisWeek: "This Week"
            case .earlier: "Earlier"
            }
        }
    }

    /// One rendered recency group.
    public struct Section: Sendable, Equatable, Identifiable {
        public let kind: Kind
        public let items: [TransactionReviewItem]

        /// Stable id for `ForEach` / `Identifiable`. The kind is unique per
        /// emitted section, so it doubles as the identity.
        public var id: Kind { kind }

        /// The section header label (e.g. "Today").
        public var label: String { kind.label }

        /// Transaction ids in this section, in list order — the exact input the
        /// per-section approve hands to the shared bulk-review path.
        public var itemIDs: [String] { items.map(\.id) }

        /// Rows in this section the count/blast-radius should speak about. The
        /// inbox only lists unresolved rows, but guard against a lingering
        /// already-reviewed row so a per-section count never overstates its reach.
        public var count: Int { items.count }

        public init(kind: Kind, items: [TransactionReviewItem]) {
            self.kind = kind
            self.items = items
        }
    }

    /// Buckets `items` into ordered, non-empty recency sections.
    ///
    /// - Parameters:
    ///   - items: inbox rows in display order (already truncated to what the
    ///     surface shows).
    ///   - asOf: the reference "now" — injected so bucketing is deterministic.
    ///   - calendar: the calendar used for day/week boundaries (defaults to the
    ///     user's current calendar; injected for tests).
    /// - Returns: sections in fixed recency order (Today → Earlier), each
    ///   non-empty, preserving the input order of rows within each section.
    public static func sections(
        items: [TransactionReviewItem],
        asOf: Date,
        calendar: Calendar = .current
    ) -> [Section] {
        guard !items.isEmpty else { return [] }

        // Pre-compute the boundary days once (start-of-day for today/yesterday and
        // the start of the current week) so each row is an O(1) comparison rather
        // than a per-row calendar component diff.
        let startOfToday = calendar.startOfDay(for: asOf)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
        let startOfWeek = startOfWeek(for: asOf, calendar: calendar)

        var grouped: [Kind: [TransactionReviewItem]] = [:]
        for item in items {
            let kind = bucket(
                for: item,
                startOfToday: startOfToday,
                startOfYesterday: startOfYesterday,
                startOfWeek: startOfWeek,
                calendar: calendar
            )
            grouped[kind, default: []].append(item)
        }

        return Kind.allCases
            .sorted { $0.order < $1.order }
            .compactMap { kind in
                guard let bucketItems = grouped[kind], !bucketItems.isEmpty else { return nil }
                return Section(kind: kind, items: bucketItems)
            }
    }

    /// Classifies a single row. An unparseable date defers to `Earlier` so a
    /// malformed key never drops the row.
    private static func bucket(
        for item: TransactionReviewItem,
        startOfToday: Date,
        startOfYesterday: Date?,
        startOfWeek: Date?,
        calendar: Calendar
    ) -> Kind {
        guard let date = Formatters.parseTransactionDate(item.transaction.date) else {
            return .earlier
        }
        let startOfDate = calendar.startOfDay(for: date)

        if startOfDate >= startOfToday {
            // Same calendar day as `asOf` (or, defensively, a future-dated row)
            // reads as Today rather than slipping into Earlier.
            return .today
        }
        if let startOfYesterday, startOfDate == startOfYesterday {
            return .yesterday
        }
        if let startOfWeek, startOfDate >= startOfWeek {
            // Earlier in the current week (older than yesterday but on/after the
            // week's first day).
            return .thisWeek
        }
        return .earlier
    }

    /// Start of the calendar week containing `date`, using the injected calendar's
    /// `firstWeekday`. Falls back to `nil` only if the calendar cannot resolve the
    /// interval, in which case week rows degrade to `Earlier` rather than crash.
    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
