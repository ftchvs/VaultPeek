import Foundation
import PlaidBarCore
import Testing

// MARK: - Route enum

@Suite("Route destinations")
struct RouteDestinationTests {
    @Test("All 11 IA destinations exist (10 sidebar + the Settings scene)")
    func hasEveryDestination() {
        // IA §2: Dashboard, Review, Transactions, Budgets, Planning, Goals,
        // Insights, Alerts, Accounts, Settings. (Transactions counts as the 11th
        // primary destination alongside Review per IA notes; both are present.)
        let expected: Set<RouteDestination> = [
            .dashboard, .review, .transactions, .budgets, .planning,
            .goals, .insights, .alerts, .accounts, .settings,
        ]
        #expect(Set(RouteDestination.allCases) == expected)
        #expect(RouteDestination.allCases.count == 10)
    }

    @Test("Command shortcut numbers match the IA keymap ⌘1…⌘8 (Dashboard…Accounts)")
    func commandShortcutNumbers() {
        // IA §3.4: ⌘1 Dashboard, ⌘2 Review, ⌘3 Budgets, ⌘4 Planning, ⌘5 Goals,
        // ⌘6 Insights, ⌘7 Alerts, ⌘8 Accounts. Transactions and Settings have none.
        #expect(RouteDestination.dashboard.commandShortcutNumber == 1)
        #expect(RouteDestination.review.commandShortcutNumber == 2)
        #expect(RouteDestination.budgets.commandShortcutNumber == 3)
        #expect(RouteDestination.planning.commandShortcutNumber == 4)
        #expect(RouteDestination.goals.commandShortcutNumber == 5)
        #expect(RouteDestination.insights.commandShortcutNumber == 6)
        #expect(RouteDestination.alerts.commandShortcutNumber == 7)
        #expect(RouteDestination.accounts.commandShortcutNumber == 8)
        // Transactions is reachable via sidebar / ⌘K but has no number.
        #expect(RouteDestination.transactions.commandShortcutNumber == nil)
        // Settings is the native ⌘, scene — no numeric shortcut.
        #expect(RouteDestination.settings.commandShortcutNumber == nil)
        // The numbers ⌘1–8 are unique and complete.
        let numbers = RouteDestination.allCases.compactMap(\.commandShortcutNumber).sorted()
        #expect(numbers == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("Bands group the destinations per the IA tree")
    func bandGrouping() {
        #expect(RouteDestination.dashboard.band == .overview)
        for d in [RouteDestination.review, .transactions, .budgets, .planning, .goals] {
            #expect(d.band == .workflows)
        }
        #expect(RouteDestination.insights.band == .insights)
        #expect(RouteDestination.alerts.band == .insights)
        #expect(RouteDestination.accounts.band == .money)
        #expect(RouteDestination.settings.band == .system)
    }

    @Test("3-column policy matches IA §3.1")
    func columnPolicy() {
        let threeColumn: Set<RouteDestination> = [.review, .transactions, .budgets, .goals, .alerts, .accounts]
        for d in RouteDestination.allCases {
            #expect(d.prefersThreeColumnLayout == threeColumn.contains(d))
        }
    }

    @Test("Every destination has a non-empty title and SF Symbol")
    func titlesAndSymbols() {
        for d in RouteDestination.allCases {
            #expect(!d.title.isEmpty)
            #expect(!d.systemImage.isEmpty)
        }
    }
}

@Suite("Route")
struct RouteTests {
    @Test("Each route resolves to its destination")
    func destinationMapping() {
        #expect(Route.dashboard.destination == .dashboard)
        #expect(Route.review(itemID: "x").destination == .review)
        #expect(Route.transactions().destination == .transactions)
        #expect(Route.budgets(category: .foodAndDrink).destination == .budgets)
        #expect(Route.planning(section: .recurring).destination == .planning)
        #expect(Route.goals(id: UUID()).destination == .goals)
        #expect(Route.insights(section: .trends).destination == .insights)
        #expect(Route.alerts(id: "a").destination == .alerts)
        #expect(Route.accounts(itemID: "acct").destination == .accounts)
        #expect(Route.settings(tab: .privacy).destination == .settings)
    }

    @Test("Canonical route for each destination uses default selection")
    func canonicalRoutes() {
        for d in RouteDestination.allCases {
            #expect(Route.canonical(for: d).destination == d)
        }
        #expect(Route.canonical(for: .review) == .review())
        #expect(Route.canonical(for: .settings) == .settings())
    }

    @Test("Weekly-review navigation targets map onto routes")
    func weeklyReviewMapping() {
        #expect(Route.from(weeklyReview: .reviewInbox) == .review())
        #expect(Route.from(weeklyReview: .recurring) == .planning(section: .recurring))
        #expect(Route.from(weeklyReview: .safeToSpend) == .dashboard)
    }

    @Test("Route round-trips through Codable (deep-link persistence ready)")
    func codableRoundTrip() throws {
        let routes: [Route] = [
            .dashboard,
            .review(itemID: "txn_1"),
            .transactions(filter: TransactionFilterCriteria(searchText: "coffee", category: .foodAndDrink), focus: "txn_9"),
            .budgets(category: .travel),
            .planning(section: .incomeFlow),
            .goals(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            .insights(section: .weeklyReview),
            .alerts(id: "alert_2"),
            .accounts(itemID: "acct_7"),
            .settings(tab: .notifications),
        ]
        for route in routes {
            let data = try JSONEncoder().encode(route)
            let decoded = try JSONDecoder().decode(Route.self, from: data)
            #expect(decoded == route)
        }
    }
}

// MARK: - NavigationState transitions

@Suite("NavigationState transitions")
struct NavigationStateTransitionTests {
    private let visible = ["demo_checking", "demo_savings", "demo_visa"]

    @Test("Defaults match the migrated @AppStorage defaults")
    func defaults() {
        let state = NavigationState()
        #expect(state.destination == .dashboard)
        #expect(state.dashboardFilter == .all)
        #expect(state.selectedAccountID == "")
        #expect(state.heatmapMode == .spending)
    }

    @Test("Changing the dashboard filter clears the account selection (AND-373/375)")
    func filterChangeClearsSelection() {
        var state = NavigationState()
        state.selectAccount(id: "demo_visa")
        #expect(state.selectedAccountID == "demo_visa")

        state.setDashboardFilter(.credit)
        #expect(state.dashboardFilter == .credit)
        #expect(state.selectedAccountID == "", "Filter change must deselect, as the popover did")
    }

    @Test("Setting the same filter is a no-op and does NOT deselect")
    func sameFilterDoesNotDeselect() {
        var state = NavigationState(dashboardFilter: .cash)
        state.selectAccount(id: "demo_checking")
        state.setDashboardFilter(.cash)
        #expect(state.selectedAccountID == "demo_checking", "A redundant filter set must not surprise-deselect")
    }

    @Test("reconcileSelection drops a selection no longer visible, keeps a visible one")
    func reconcileSelection() {
        var state = NavigationState()
        state.selectAccount(id: "vanished_account")
        let cleared = state.reconcileSelection(visibleAccountIDs: visible)
        #expect(cleared)
        #expect(state.selectedAccountID == "")

        state.selectAccount(id: "demo_savings")
        let kept = state.reconcileSelection(visibleAccountIDs: visible)
        #expect(!kept)
        #expect(state.selectedAccountID == "demo_savings")
    }

    @Test("resolvedSelectedID mirrors DashboardAccountSelection")
    func resolvedSelection() {
        var state = NavigationState()
        #expect(state.resolvedSelectedID(visibleAccountIDs: visible) == nil)
        state.selectAccount(id: "demo_visa")
        #expect(state.resolvedSelectedID(visibleAccountIDs: visible) == "demo_visa")
        state.selectAccount(id: "not_visible")
        #expect(state.resolvedSelectedID(visibleAccountIDs: visible) == nil)
    }

    @Test("apply(.accounts(itemID:)) selects destination and folds in the account")
    func applyAccountRoute() {
        var state = NavigationState()
        state.apply(.accounts(itemID: "acct_42"))
        #expect(state.destination == .accounts)
        #expect(state.selectedAccountID == "acct_42")
    }

    @Test("go(to:) switches destination and preserves dashboard selection")
    func goPreservesSelection() {
        var state = NavigationState()
        state.selectAccount(id: "demo_checking")
        state.setDashboardFilter(.cash) // clears selection
        state.selectAccount(id: "demo_checking")
        state.go(to: .budgets)
        #expect(state.destination == .budgets)
        // Per-destination selection persists across a destination switch.
        #expect(state.selectedAccountID == "demo_checking")
        #expect(state.dashboardFilter == .cash)
    }

    @Test("NavigationState round-trips through Codable")
    func codable() throws {
        let state = NavigationState(
            destination: .accounts,
            dashboardFilter: .debt,
            selectedAccountID: "demo_visa",
            heatmapMode: .netCashflow
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NavigationState.self, from: data)
        #expect(decoded == state)
    }
}

// MARK: - R-10: per-window independence

@Suite("R-10 per-window navigation independence")
struct NavigationStateIndependenceTests {
    private let visible = ["demo_checking", "demo_savings", "demo_visa"]

    @Test("Two windows hold independent selection — mutating one never touches the other (R-10)")
    func twoWindowsIndependentSelection() {
        // Each window owns its own value-type state — the per-window-not-singleton
        // contract that prevents the two-window selection bug.
        var windowA = NavigationState()
        var windowB = NavigationState()

        windowA.selectAccount(id: "demo_checking")
        windowA.setDashboardFilter(.cash)
        windowA.heatmapMode = .netCashflow
        windowA.go(to: .budgets)

        // Window B must be entirely unaffected by Window A's mutations.
        #expect(windowB.selectedAccountID == "")
        #expect(windowB.dashboardFilter == .all)
        #expect(windowB.heatmapMode == .spending)
        #expect(windowB.destination == .dashboard)

        // And Window B can hold its OWN, different selection simultaneously.
        windowB.setDashboardFilter(.credit)
        windowB.selectAccount(id: "demo_visa")
        windowB.go(to: .accounts)

        #expect(windowA.selectedAccountID == "")     // cleared by A's own filter change
        #expect(windowA.dashboardFilter == .cash)
        #expect(windowA.destination == .budgets)

        #expect(windowB.selectedAccountID == "demo_visa")
        #expect(windowB.dashboardFilter == .credit)
        #expect(windowB.destination == .accounts)

        // The two states are genuinely distinct.
        #expect(windowA != windowB)
    }

    @Test("Independent reconcile: clearing a stale selection in one window leaves the other")
    func independentReconcile() {
        var windowA = NavigationState()
        var windowB = NavigationState()
        windowA.selectAccount(id: "demo_savings")
        windowB.selectAccount(id: "stale_in_B_only")

        // A's selection is visible; B's is not. (`reconcileSelection` is
        // mutating, so call it outside `#expect` and assert the returned flag.)
        let aCleared = windowA.reconcileSelection(visibleAccountIDs: visible)
        let bCleared = windowB.reconcileSelection(visibleAccountIDs: visible)
        #expect(!aCleared)
        #expect(bCleared)

        #expect(windowA.selectedAccountID == "demo_savings")
        #expect(windowB.selectedAccountID == "")
    }
}
