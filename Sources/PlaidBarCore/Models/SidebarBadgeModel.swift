import Foundation

/// Pure, `Sendable` model assembling the window-first sidebar's per-destination
/// count badges (AND-595).
///
/// The product mandates **textual count badges, never color-only dots**
/// (`ACCESSIBILITY.md`: no meaning by color alone) — so each badge is a number
/// plus a spoken accessibility phrase, and a badge **hides when its count is
/// zero**. Keeping the derivation here (rather than in the SwiftUI sidebar) makes
/// the "which destinations badge, what counts, when do they hide" policy
/// unit-testable without the app target (CLAUDE.md: shared logic lives in
/// `PlaidBarCore`); the view stays a thin renderer over `badges`. When Privacy
/// Mask / App Lock is active, badges are withheld entirely so the window-first
/// sidebar does not reveal review, budget, alert, or reconnect counts while the
/// rest of the app is private.
///
/// Four destinations badge, each from a live `AppState` signal:
///
/// | Destination | Count source | Hidden when |
/// |-------------|--------------|-------------|
/// | Dashboard | unacknowledged-alert count (non-healthy `AttentionQueue` rows minus acknowledged — the canonical "do I need to act?" signal). Carried by Dashboard since the Alerts fold (Gate-0, AND-979): Dashboard's attention card is the alerts surface now, so the badge follows it | none unacked |
/// | Review   | unreviewed inbox count (`TransactionReviewInboxSnapshot.totalCount`) | queue clear |
/// | Budgets  | over-budget category count (`CategoryBudgetPresentation.overBudgetCount`) | nothing over |
/// | Accounts | reconnect-needed count (`ConnectionHealthStrip` reconnect bucket) | all healthy |
///
/// All other destinations carry no badge.
public struct SidebarBadgeModel: Sendable, Equatable {
    /// One destination's badge. Only constructed for a positive count, so a
    /// `Badge` is always visible — a zero count yields no `Badge` at all, which
    /// is the "hide when zero" contract expressed in the type.
    public struct Badge: Sendable, Equatable, Identifiable {
        public let destination: RouteDestination
        /// The number shown (always `> 0`).
        public let count: Int
        /// The trailing text shown next to the row (the count as a string).
        public let text: String
        /// The phrase folded into the row's VoiceOver label, e.g.
        /// `"4 items to review"` — so the badge is announced, not just seen.
        public let accessibilityText: String

        public var id: RouteDestination { destination }

        public init(
            destination: RouteDestination,
            count: Int,
            accessibilityText: String
        ) {
            self.destination = destination
            self.count = count
            self.text = String(count)
            self.accessibilityText = accessibilityText
        }
    }

    /// The visible badges, in `RouteDestination.allCases` (sidebar) order. Only
    /// destinations with a positive count appear.
    public let badges: [Badge]

    public init(badges: [Badge]) {
        self.badges = badges
    }

    /// The badge for a destination, or `nil` when it has none (no source, or a
    /// zero count). The sidebar row calls this to decide whether to draw a badge.
    public func badge(for destination: RouteDestination) -> Badge? {
        badges.first { $0.destination == destination }
    }

    /// An empty model — every destination badge hidden.
    public static let empty = SidebarBadgeModel(badges: [])

    // MARK: - Derivation

    /// Builds the badge model from the four live counts `AppState` already
    /// computes. Each negative input is clamped to zero, and a zero count
    /// produces no badge (the hide-when-zero rule). The resulting badges are
    /// ordered by `RouteDestination.allCases` so the model's order matches the
    /// sidebar's. When `isMasked` is true, all badges are withheld because exact
    /// counts are behavioral finance metadata.
    ///
    /// - Parameters:
    ///   - unreviewedCount: items awaiting review
    ///     (`AppState.transactionReviewCount`).
    ///   - overBudgetCount: categories over their limit
    ///     (`AppState.categoryBudgetPresentation.overBudgetCount`).
    ///   - unacknowledgedAlertCount: alerts needing acknowledgement — the count
    ///     of non-healthy `AttentionQueue` rows not yet acknowledged, the same
    ///     "do I need to act?" rollup the menu-bar glance and Dashboard's
    ///     attention card use. Badged on `.dashboard` since the Alerts fold.
    ///   - reconnectNeededCount: items needing reconnect
    ///     (`ConnectionHealthStrip` reconnect-needed bucket).
    ///   - isMasked: Privacy Mask / App Lock state. When true, every badge is
    ///     hidden regardless of count.
    public static func make(
        unreviewedCount: Int,
        overBudgetCount: Int,
        unacknowledgedAlertCount: Int,
        reconnectNeededCount: Int,
        isMasked: Bool = false
    ) -> SidebarBadgeModel {
        guard !isMasked else { return .empty }

        var badges: [Badge] = []

        func appendBadge(
            _ destination: RouteDestination,
            count: Int,
            accessibility: (Int) -> String
        ) {
            let clamped = max(0, count)
            guard clamped > 0 else { return }
            badges.append(
                Badge(
                    destination: destination,
                    count: clamped,
                    accessibilityText: accessibility(clamped)
                )
            )
        }

        // Emit in sidebar order so `badges` reads top-to-bottom like the list.
        // The alert badge lives on Dashboard since the Alerts fold (AND-979):
        // the sidebar no longer renders an `.alerts` row, and Dashboard's
        // attention card is where the badge's count is acted on.
        appendBadge(.dashboard, count: unacknowledgedAlertCount) { count in
            "\(count) unacknowledged \(count == 1 ? "alert" : "alerts")"
        }
        appendBadge(.review, count: unreviewedCount) { count in
            "\(count) \(count == 1 ? "item" : "items") to review"
        }
        appendBadge(.budgets, count: overBudgetCount) { count in
            "\(count) \(count == 1 ? "category" : "categories") over budget"
        }
        appendBadge(.accounts, count: reconnectNeededCount) { count in
            "\(count) \(count == 1 ? "account needs" : "accounts need") reconnecting"
        }

        return SidebarBadgeModel(badges: badges)
    }
}
