import Foundation
import PlaidBarCore
import Testing

// MARK: - SidebarBadgeModel (window-first sidebar count badges, AND-595)

@Suite("Sidebar badge model")
struct SidebarBadgeModelTests {
    @Test("Each positive count yields a visible badge on the right destination")
    func badgesForEachSource() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 4,
            overBudgetCount: 2,
            unacknowledgedAlertCount: 3,
            reconnectNeededCount: 1
        )

        #expect(model.badge(for: .review)?.count == 4)
        #expect(model.badge(for: .budgets)?.count == 2)
        #expect(model.badge(for: .alerts)?.count == 3)
        #expect(model.badge(for: .accounts)?.count == 1)
        #expect(model.badges.count == 4)
    }

    @Test("Badge text is the count as a string")
    func badgeTextIsCount() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 12,
            overBudgetCount: 0,
            unacknowledgedAlertCount: 0,
            reconnectNeededCount: 0
        )
        #expect(model.badge(for: .review)?.text == "12")
    }

    @Test("A zero count hides the badge (hide-when-zero contract)")
    func hidesWhenZero() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 0,
            overBudgetCount: 5,
            unacknowledgedAlertCount: 0,
            reconnectNeededCount: 0
        )
        #expect(model.badge(for: .review) == nil)
        #expect(model.badge(for: .alerts) == nil)
        #expect(model.badge(for: .accounts) == nil)
        #expect(model.badge(for: .budgets)?.count == 5)
        #expect(model.badges.count == 1)
    }

    @Test("All-zero counts produce an empty model")
    func allZeroIsEmpty() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 0,
            overBudgetCount: 0,
            unacknowledgedAlertCount: 0,
            reconnectNeededCount: 0
        )
        #expect(model.badges.isEmpty)
        #expect(model == .empty)
    }

    @Test("Privacy Mask withholds all exact sidebar counts")
    func privacyMaskWithholdsCounts() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 7,
            overBudgetCount: 3,
            unacknowledgedAlertCount: 2,
            reconnectNeededCount: 1,
            isMasked: true
        )

        #expect(model == .empty)
        #expect(model.badge(for: .review) == nil)
        #expect(model.badge(for: .budgets) == nil)
        #expect(model.badge(for: .alerts) == nil)
        #expect(model.badge(for: .accounts) == nil)
    }

    @Test("Negative inputs clamp to zero (no negative or phantom badges)")
    func negativeClampsToZero() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: -3,
            overBudgetCount: -1,
            unacknowledgedAlertCount: -7,
            reconnectNeededCount: -2
        )
        #expect(model.badges.isEmpty)
    }

    @Test("Only the four IA-specified destinations ever badge")
    func onlyFourDestinationsBadge() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 1,
            overBudgetCount: 1,
            unacknowledgedAlertCount: 1,
            reconnectNeededCount: 1
        )
        let badged = Set(model.badges.map(\.destination))
        #expect(badged == [.review, .budgets, .alerts, .accounts])
        // Destinations the IA gives no badge never appear.
        for d in [RouteDestination.dashboard, .transactions, .planning, .goals, .insights, .settings] {
            #expect(model.badge(for: d) == nil)
        }
    }

    @Test("Badges are emitted in sidebar (allCases) order")
    func badgeOrderMatchesSidebar() {
        let model = SidebarBadgeModel.make(
            unreviewedCount: 1,
            overBudgetCount: 1,
            unacknowledgedAlertCount: 1,
            reconnectNeededCount: 1
        )
        // Review (band Workflows) → Budgets (Workflows) → Alerts (Insights) →
        // Accounts (Money): the order they appear in RouteDestination.allCases.
        #expect(model.badges.map(\.destination) == [.review, .budgets, .alerts, .accounts])
    }

    // MARK: Accessibility phrasing (singular vs plural; folded into the row label)

    @Test("Review accessibility text pluralizes correctly")
    func reviewAccessibilityPluralization() {
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 1, overBudgetCount: 0, unacknowledgedAlertCount: 0, reconnectNeededCount: 0)
                .badge(for: .review)?.accessibilityText == "1 item to review"
        )
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 5, overBudgetCount: 0, unacknowledgedAlertCount: 0, reconnectNeededCount: 0)
                .badge(for: .review)?.accessibilityText == "5 items to review"
        )
    }

    @Test("Budgets accessibility text pluralizes category/categories")
    func budgetsAccessibilityPluralization() {
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 1, unacknowledgedAlertCount: 0, reconnectNeededCount: 0)
                .badge(for: .budgets)?.accessibilityText == "1 category over budget"
        )
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 3, unacknowledgedAlertCount: 0, reconnectNeededCount: 0)
                .badge(for: .budgets)?.accessibilityText == "3 categories over budget"
        )
    }

    @Test("Alerts accessibility text pluralizes alert/alerts")
    func alertsAccessibilityPluralization() {
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 0, unacknowledgedAlertCount: 1, reconnectNeededCount: 0)
                .badge(for: .alerts)?.accessibilityText == "1 unacknowledged alert"
        )
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 0, unacknowledgedAlertCount: 2, reconnectNeededCount: 0)
                .badge(for: .alerts)?.accessibilityText == "2 unacknowledged alerts"
        )
    }

    @Test("Accounts accessibility text pluralizes account needs / accounts need")
    func accountsAccessibilityPluralization() {
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 0, unacknowledgedAlertCount: 0, reconnectNeededCount: 1)
                .badge(for: .accounts)?.accessibilityText == "1 account needs reconnecting"
        )
        #expect(
            SidebarBadgeModel.make(unreviewedCount: 0, overBudgetCount: 0, unacknowledgedAlertCount: 0, reconnectNeededCount: 4)
                .badge(for: .accounts)?.accessibilityText == "4 accounts need reconnecting"
        )
    }
}

// MARK: - Sidebar grouping & ordering (the model the sidebar renders)

@Suite("Sidebar groups and ordering")
struct SidebarGroupingTests {
    @Test("Five bands in canonical IA order")
    func fiveBandsInOrder() {
        #expect(
            RouteDestination.Band.allCases == [.overview, .workflows, .insights, .money, .system]
        )
    }

    @Test("Bands map to the IA's 5 groups → 11 destinations")
    func groupsToDestinations() {
        func destinations(in band: RouteDestination.Band) -> [RouteDestination] {
            RouteDestination.allCases.filter { $0.band == band }
        }

        #expect(destinations(in: .overview) == [.dashboard])
        #expect(destinations(in: .workflows) == [.review, .transactions, .budgets, .planning, .goals])
        #expect(destinations(in: .insights) == [.insights, .alerts])
        #expect(destinations(in: .money) == [.accounts])
        #expect(destinations(in: .system) == [.settings])
    }

    @Test("Every destination belongs to exactly one band; no destination is dropped")
    func everyDestinationInExactlyOneBand() {
        let regrouped = RouteDestination.Band.allCases.flatMap { band in
            RouteDestination.allCases.filter { $0.band == band }
        }
        // Same set as allCases (nothing dropped or duplicated).
        #expect(Set(regrouped) == Set(RouteDestination.allCases))
        #expect(regrouped.count == RouteDestination.allCases.count)
        #expect(regrouped.count == 10)
    }

    @Test("Settings is the only System destination (opens the native scene, not a pane)")
    func settingsIsSystem() {
        #expect(RouteDestination.settings.band == .system)
        #expect(RouteDestination.allCases.filter { $0.band == .system } == [.settings])
    }
}
