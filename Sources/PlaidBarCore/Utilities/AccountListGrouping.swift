import Foundation

/// Pure, testable grouping of accounts by ``AccountType`` for the window-first
/// **Accounts** destination's content column (AND-623).
///
/// The menu-bar popover lists accounts in a single flat section. The Accounts
/// destination re-hosts the same rows but groups them by type the way the
/// dashboard's account filter buckets them (Cash / Credit / Savings / Debt /
/// Investments), so a long account list scans as labeled sections. The bucketing
/// math lives here (not in the view) so it is `Sendable`, reusable, and unit
/// tested at the Core layer (CLAUDE.md).
///
/// Grouping preserves the **input order** of accounts within each group, so the
/// destination shows accounts in the same relative order the caller already
/// sorted them — only adding section breaks, never reordering within a section.
public enum AccountListGrouping {
    /// One labeled section of the grouped account list.
    public struct Section: Identifiable, Sendable, Equatable {
        /// The account type this section collects — also the stable section id.
        public let type: AccountType
        /// A human-readable, pluralization-agnostic section title (e.g. "Credit").
        public let title: String
        /// The accounts in this section, in the caller's original order.
        public let accounts: [AccountDTO]

        public var id: AccountType { type }

        public init(type: AccountType, title: String, accounts: [AccountDTO]) {
            self.type = type
            self.title = title
            self.accounts = accounts
        }
    }

    /// The order sections appear in: most-used asset types first, then liabilities,
    /// matching the dashboard's reading order (cash → credit → loans → investments).
    /// `other` is last so unclassified accounts never lead the list.
    private static let sectionOrder: [AccountType] = [
        .depository, .credit, .loan, .investment, .other,
    ]

    /// The display title for a section header. Stable, singular nouns — the section
    /// count badge carries the cardinality, so the title need not pluralize.
    public static func title(for type: AccountType) -> String {
        switch type {
        case .depository: "Cash & Savings"
        case .credit: "Credit"
        case .loan: "Loans"
        case .investment: "Investments"
        case .other: "Other"
        }
    }

    /// Group `accounts` into ordered, non-empty sections by ``AccountType``.
    ///
    /// - Empty input ⇒ no sections (the caller shows its own empty state).
    /// - A type with no accounts produces no section (never an empty header).
    /// - Within a section, accounts keep their input order (stable grouping).
    public static func sections(for accounts: [AccountDTO]) -> [Section] {
        guard !accounts.isEmpty else { return [] }

        var buckets: [AccountType: [AccountDTO]] = [:]
        for account in accounts {
            buckets[account.type, default: []].append(account)
        }

        return sectionOrder.compactMap { type in
            guard let bucket = buckets[type], !bucket.isEmpty else { return nil }
            return Section(type: type, title: title(for: type), accounts: bucket)
        }
    }
}
