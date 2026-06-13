import Foundation

/// One segment in the dashboard nav/filter bar, fully resolved for rendering.
///
/// The UI layer should render these items verbatim — counts, badges, keyboard
/// shortcut ordinals, and accessibility strings are all decided here so the
/// filter bar stays testable without SwiftUI.
public struct DashboardNavBarItem: Identifiable, Equatable, Sendable {
    /// The filter this segment activates.
    public let kind: DashboardAccountFilterKind
    /// The visible segment label (for example "Cash").
    public let title: String
    /// Number of accounts matching this filter.
    public let count: Int
    /// Number of unique degraded Plaid Items represented by the matching
    /// accounts. Nonzero only for `.status`. This is item-scoped, not
    /// account-scoped: one degraded institution exposing several accounts
    /// counts once, so recovery messaging never overstates how many
    /// institutions are broken.
    public let attentionItemCount: Int
    /// True only for `.status` when at least one account needs attention.
    /// Pair the badge with an icon or text — never color alone.
    public let showsAttentionBadge: Bool
    /// 1-based position in display order, for ⌘1–⌘6 keyboard shortcuts.
    public let shortcutOrdinal: Int
    /// VoiceOver label (for example "Cash account filter").
    public let accessibilityLabel: String
    /// VoiceOver value (for example "3 matching accounts").
    public let accessibilityValue: String

    public var id: DashboardAccountFilterKind {
        kind
    }

    public init(
        kind: DashboardAccountFilterKind,
        title: String,
        count: Int,
        attentionItemCount: Int = 0,
        showsAttentionBadge: Bool,
        shortcutOrdinal: Int,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.kind = kind
        self.title = title
        self.count = count
        self.attentionItemCount = attentionItemCount
        self.showsAttentionBadge = showsAttentionBadge
        self.shortcutOrdinal = shortcutOrdinal
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

public extension DashboardNavBarItem {
    /// Tooltip for the filter segment, including its command shortcut,
    /// for example "Show Cash accounts (⌘2)".
    var helpText: String {
        "Show \(title) accounts (⌘\(shortcutOrdinal))"
    }

    /// SF Symbol that pairs the status segment's attention state with a
    /// non-color signal: a warning triangle when degraded items exist, a
    /// quiet checkmark when there are none. `nil` for every other segment.
    var statusIconName: String? {
        guard kind == .status else { return nil }
        return showsAttentionBadge ? "exclamationmark.triangle.fill" : "checkmark.circle"
    }

    /// VoiceOver label for the adjacent status indicator the filter bar shows
    /// when the Status segment needs attention. `nil` for non-status segments
    /// and for a healthy Status segment (no separate indicator is shown then).
    var statusIndicatorAccessibilityLabel: String? {
        guard kind == .status, showsAttentionBadge else { return nil }
        // Item-scoped, not row-scoped: a bank that exposes checking, savings,
        // and credit under one Plaid Item must announce one item, not three.
        // Fall back to `count` when a direct caller badged the segment without
        // supplying an item-scoped count, preserving the prior wording for
        // previews/tests/downstream code that omit `attentionItemCount`.
        let attention = attentionItemCount > 0 ? attentionItemCount : count
        return "\(attention) \(attention == 1 ? "item needs" : "items need") attention"
    }
}

/// Pure presenter for the dashboard nav/filter bar.
///
/// Maps the current account list (plus degraded-item state) into one
/// `DashboardNavBarItem` per `DashboardAccountFilterKind`, in display order.
public enum DashboardNavBarModel {
    /// Builds one nav bar item per filter kind, in `allCases` display order.
    public static func items(
        accounts: [AccountDTO],
        degradedItemIds: Set<String> = []
    ) -> [DashboardNavBarItem] {
        DashboardAccountFilterKind.allCases.enumerated().map { index, kind in
            let count = accounts.count { kind.includes($0, degradedItemIds: degradedItemIds) }
            let showsAttentionBadge = kind == .status && count > 0
            // Collapse the matching account rows to the unique Plaid Items they
            // belong to, so recovery messaging counts institutions, not rows.
            let attentionItemCount = kind == .status
                ? Set(accounts.lazy.filter { degradedItemIds.contains($0.itemId) }.map(\.itemId)).count
                : 0
            var accessibilityValue = "\(count) matching \(accountWord(for: count))"
            if showsAttentionBadge {
                // VoiceOver cannot see the warning icon; say it.
                accessibilityValue += ", needs attention"
            }
            return DashboardNavBarItem(
                kind: kind,
                title: kind.rawValue,
                count: count,
                attentionItemCount: attentionItemCount,
                showsAttentionBadge: showsAttentionBadge,
                shortcutOrdinal: index + 1,
                accessibilityLabel: "\(kind.rawValue) account filter",
                accessibilityValue: accessibilityValue
            )
        }
    }

    /// VoiceOver label for the whole filter bar container.
    ///
    /// macOS VoiceOver announces a group's *label* when entering it but does
    /// not reliably read a group's accessibility *value* before jumping to
    /// the children, so the selected-filter rollup is folded into the label
    /// itself — for example "Account filters. Cash: 3 of 8 accounts;
    /// select a row for details". The drill-in clause carries over from the
    /// removed overview caption so VoiceOver users keep the row-selection
    /// state.
    public static func containerAccessibilityLabel(
        selected: DashboardAccountFilterKind,
        items: [DashboardNavBarItem],
        hasSelectedAccount: Bool
    ) -> String {
        let detailClause = hasSelectedAccount
            ? "selected row shows details"
            : "select a row for details"
        return "Account filters. \(summary(selected: selected, items: items)); \(detailClause)"
    }

    /// One-line VoiceOver/caption summary for the selected filter.
    ///
    /// Examples: `.all` → "All: 8 accounts"; `.cash` → "Cash: 3 of 8 accounts".
    public static func summary(
        selected: DashboardAccountFilterKind,
        items: [DashboardNavBarItem]
    ) -> String {
        let selectedCount = items.first { $0.kind == selected }?.count ?? 0
        let totalCount = items.first { $0.kind == .all }?.count ?? selectedCount

        if selected == .all {
            return "All: \(totalCount) \(accountWord(for: totalCount))"
        }

        return "\(selected.rawValue): \(selectedCount) of \(totalCount) \(accountWord(for: totalCount))"
    }

    private static func accountWord(for count: Int) -> String {
        count == 1 ? "account" : "accounts"
    }
}
