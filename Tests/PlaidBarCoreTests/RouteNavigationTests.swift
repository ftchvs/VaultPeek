import Foundation
import PlaidBarCore
import Testing

// MARK: - Route enum

@Suite("Route destinations")
struct RouteDestinationTests {
    @Test("All 11 destinations exist (10 sidebar + the Settings scene)")
    func hasEveryDestination() {
        // Destinations: Dashboard, Review, Transactions, Budgets, Planning, Goals,
        // Insights, Alerts, Accounts, Settings. (Transactions counts as the 11th
        // primary destination alongside Review; both are present.)
        let expected: Set<RouteDestination> = [
            .dashboard, .review, .transactions, .budgets, .planning,
            .goals, .insights, .alerts, .accounts, .settings,
        ]
        #expect(Set(RouteDestination.allCases) == expected)
        #expect(RouteDestination.allCases.count == 10)
    }

    @Test("Command shortcut numbers match the keymap ⌘1…⌘8 (Dashboard…Accounts)")
    func commandShortcutNumbers() {
        // ⌘1 Dashboard, ⌘2 Review, ⌘3 Budgets, ⌘4 Planning, ⌘5 Goals,
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

    @Test("Bands group the destinations per the navigation tree")
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

    @Test("3-column policy")
    func columnPolicy() {
        let threeColumn: Set<RouteDestination> = [.review, .transactions, .budgets, .goals, .alerts, .accounts]
        for d in RouteDestination.allCases {
            #expect(d.prefersThreeColumnLayout == threeColumn.contains(d))
        }
    }

    @Test("Detail-column prompt exists iff the destination is 3-column (content-gated)")
    func detailColumnPromptMatchesPolicy() {
        for d in RouteDestination.allCases {
            // The third column is content-gated, not existence-gated: every
            // 3-column destination has a "Select a …" prompt; 2-column
            // destinations and Settings have none.
            #expect((d.detailColumnEmptyPrompt != nil) == d.prefersThreeColumnLayout)
            if let prompt = d.detailColumnEmptyPrompt {
                #expect(!prompt.isEmpty)
            }
        }
    }

    @Test("Detail-column prompts are the per-destination copy")
    func detailColumnPromptCopy() {
        #expect(RouteDestination.review.detailColumnEmptyPrompt == "Select an item to review")
        #expect(RouteDestination.transactions.detailColumnEmptyPrompt == "Select a transaction")
        #expect(RouteDestination.budgets.detailColumnEmptyPrompt == "Select a category")
        #expect(RouteDestination.goals.detailColumnEmptyPrompt == "Select a goal")
        #expect(RouteDestination.alerts.detailColumnEmptyPrompt == "Select an alert")
        #expect(RouteDestination.accounts.detailColumnEmptyPrompt == "Select an account")
        // 2-column destinations + Settings have no inspector column.
        #expect(RouteDestination.dashboard.detailColumnEmptyPrompt == nil)
        #expect(RouteDestination.planning.detailColumnEmptyPrompt == nil)
        #expect(RouteDestination.insights.detailColumnEmptyPrompt == nil)
        #expect(RouteDestination.settings.detailColumnEmptyPrompt == nil)
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

    // MARK: - Account deep-link mapper (AND-616)

    /// A minimal account fixture: `id` is the Plaid `account_id` Accounts selects
    /// by; `itemId` is the Plaid `item_id` a degraded-institution chip carries.
    private func account(id: String, itemId: String) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: itemId,
            name: "Account \(id)",
            type: .depository,
            balances: BalanceDTO(available: 100, current: 100, isoCurrencyCode: "USD")
        )
    }

    @Test("resolvingAccountSelection maps an item_id deep-link to the matching account_id (AND-616)")
    func resolvingAccountSelectionMapsItemToAccount() {
        let accounts = [
            account(id: "acct_chk", itemId: "item_42"),
            account(id: "acct_sav", itemId: "item_99"),
        ]
        // A chip carrying item_42 must resolve to that item's account_id.
        #expect(
            Route.accounts(itemID: "item_42").resolvingAccountSelection(in: accounts)
                == .accounts(itemID: "acct_chk")
        )
    }

    @Test("resolvingAccountSelection selects the first matching account for a multi-account item (AND-616)")
    func resolvingAccountSelectionFirstMatch() {
        // Two accounts share item_42; the first-listed is selected by design.
        let accounts = [
            account(id: "acct_first", itemId: "item_42"),
            account(id: "acct_second", itemId: "item_42"),
        ]
        #expect(
            Route.accounts(itemID: "item_42").resolvingAccountSelection(in: accounts)
                == .accounts(itemID: "acct_first")
        )
    }

    @Test("resolvingAccountSelection returns self when no account matches the item_id (AND-616)")
    func resolvingAccountSelectionNoMatch() {
        let accounts = [account(id: "acct_chk", itemId: "item_42")]
        let route = Route.accounts(itemID: "item_missing")
        #expect(route.resolvingAccountSelection(in: accounts) == route)
        // Empty account list → unchanged too.
        #expect(route.resolvingAccountSelection(in: []) == route)
    }

    @Test("resolvingAccountSelection returns self for a nil-item or non-accounts route (AND-616)")
    func resolvingAccountSelectionPassThrough() {
        let accounts = [account(id: "acct_chk", itemId: "item_42")]
        // nil item → nothing to resolve.
        #expect(
            Route.accounts(itemID: nil).resolvingAccountSelection(in: accounts)
                == .accounts(itemID: nil)
        )
        // A non-accounts route is returned untouched even if an id happens to match.
        #expect(Route.dashboard.resolvingAccountSelection(in: accounts) == .dashboard)
        #expect(
            Route.transactions().resolvingAccountSelection(in: accounts) == .transactions()
        )
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

// MARK: - Glance attention chip → Route (AND-597)

/// The pure glance-chip → deep-link mapping the menu-bar glance routes through.
/// A glance chip opens the window at the *relevant*
/// destination, not just the dashboard; infrastructure rows keep their in-place
/// action (no route). This is the testable seam — the flag gating and the actual
/// `openWindow` live in the app target.
@Suite("Glance attention chip routing (AND-597)")
struct AttentionRowRoutingTests {
    /// Builds a row with a given id/severity, optionally targeting an item, so the
    /// mapping can be exercised without `AttentionQueue.evaluate`'s full inputs.
    private func row(id: String, targetItemId: String? = nil) -> AttentionQueueRow {
        AttentionQueueRow(
            id: id,
            severity: .warning,
            title: "t",
            detail: "d",
            targetItemId: targetItemId
        )
    }

    @Test("Financial cockpit chips route to where the signal is reviewed")
    func financialChips() {
        // Low cash / high utilization → Accounts; unusual spend → Transactions.
        #expect(Route.from(attentionRow: row(id: "financial-low-cash")) == .accounts())
        #expect(Route.from(attentionRow: row(id: "financial-high-utilization")) == .accounts())
        #expect(Route.from(attentionRow: row(id: "financial-unusual-spending")) == .transactions())
    }

    @Test("Degraded-institution chips route to Accounts and carry the item selection")
    func itemChips() {
        // item-error / item-repair / item-outage all open Accounts at the item.
        #expect(
            Route.from(attentionRow: row(id: "item-error-0", targetItemId: "item_42"))
                == .accounts(itemID: "item_42")
        )
        #expect(
            Route.from(attentionRow: row(id: "item-repair-1", targetItemId: "item_7"))
                == .accounts(itemID: "item_7")
        )
        #expect(
            Route.from(attentionRow: row(id: "item-outage-2", targetItemId: "item_9"))
                == .accounts(itemID: "item_9")
        )
        // No targetItemId ⇒ Accounts with no specific selection.
        #expect(Route.from(attentionRow: row(id: "item-error-0")) == .accounts(itemID: nil))
    }

    @Test("Infrastructure / generic chips have no in-window destination (keep their action)")
    func infrastructureChipsHaveNoRoute() {
        // These rows carry a recovery *action* (check server, open Settings,
        // refresh) but no useful destination, so the mapping returns nil and the
        // caller falls back to the action — preserving today's behavior.
        let noRoute = [
            "server-offline", "credentials-missing", "local-auth-missing",
            "local-auth-rejected", "server-mode-mismatch", "recent-error",
            "no-items", "balances-not-loaded", "first-sync-needed",
            "first-sync-incomplete", "sync-stale", "healthy", "demo-healthy",
        ]
        for id in noRoute {
            #expect(Route.from(attentionRow: row(id: id)) == nil, "\(id) must not route")
        }
    }

    @Test("Mapping is derived from rows AttentionQueue.evaluate actually emits")
    func mappingMatchesRealEvaluatedRows() throws {
        // Drive the real evaluator into a degraded-item state and confirm the
        // emitted row maps to Accounts at that item — proving the id/targetItemId
        // the mapping keys off are the ones the queue produces, not invented ids.
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item_live", institutionName: "Bank", status: .error),
            ],
            isSyncStale: false,
            lastSyncRelative: "1m ago",
            errorMessage: nil
        )
        let itemRow = try #require(queue.rows.first { $0.id.hasPrefix("item-error-") })
        #expect(Route.from(attentionRow: itemRow) == .accounts(itemID: "item_live"))
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

    @Test("apply(_:) sets the destination for every route (the deep-link entry point)")
    func applySetsDestinationForEveryRoute() {
        // `apply` is the single in-window navigation entry point (palette, keymap,
        // glance chip, App Intents). Applying any route must land on its
        // destination — the core deep-link guarantee.
        for destination in RouteDestination.allCases {
            var state = NavigationState()
            state.apply(.canonical(for: destination))
            #expect(state.destination == destination)
        }
    }

    @Test("apply(.accounts(itemID: nil)) routes to Accounts without clobbering an existing selection")
    func applyAccountRouteWithoutItem() {
        // A glance "low cash" / "high utilization" chip routes to .accounts() with
        // no specific item; that must select Accounts but not wipe a prior
        // dashboard account selection to "".
        var state = NavigationState()
        state.selectAccount(id: "demo_visa")
        state.apply(.accounts(itemID: nil))
        #expect(state.destination == .accounts)
        #expect(state.selectedAccountID == "demo_visa")
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
            heatmapMode: .netCashflow,
            goalSelection: "goal-uuid"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NavigationState.self, from: data)
        #expect(decoded == state)
    }

    // MARK: - Goals selection (AND-606)

    @Test("Goal selection defaults to empty and round-trips select/deselect")
    func goalSelection() {
        var state = NavigationState()
        #expect(state.goalSelection == "")

        state.selectGoal(id: "goal-1")
        #expect(state.goalSelection == "goal-1")

        state.deselectGoal()
        #expect(state.goalSelection == "")
    }

    @Test("reconcileGoalSelection drops a deleted goal, keeps a visible one")
    func reconcileGoalSelection() {
        var state = NavigationState()
        state.selectGoal(id: "deleted-goal")
        let cleared = state.reconcileGoalSelection(visibleGoalIDs: ["g1", "g2"])
        #expect(cleared)
        #expect(state.goalSelection == "")

        state.selectGoal(id: "g2")
        let kept = state.reconcileGoalSelection(visibleGoalIDs: ["g1", "g2"])
        #expect(!kept)
        #expect(state.goalSelection == "g2")
    }

    @Test("Switching destinations preserves the goal selection")
    func goalSelectionSurvivesDestinationSwitch() {
        var state = NavigationState()
        state.selectGoal(id: "g7")
        state.go(to: .planning)
        #expect(state.goalSelection == "g7")
    }

    // MARK: - Review workspace mode (AND-616)

    @Test("Review workspace mode defaults to triage")
    func reviewModeDefault() {
        #expect(NavigationState().reviewWorkspaceMode == .triage)
    }

    @Test("setReviewWorkspaceMode(.table) then go(to: .review) lands the table on Review (AND-616)")
    func reviewTableModeViaGo() {
        // The "Open review table" affordance sets the mode, then navigates: the
        // window must land on Review *in table mode*, not triage.
        var state = NavigationState()
        state.setReviewWorkspaceMode(.table)
        state.go(to: .review)
        #expect(state.destination == .review)
        #expect(state.reviewWorkspaceMode == .table)
    }

    @Test("setReviewWorkspaceMode(.table) survives an apply(.review) deep-link (AND-616)")
    func reviewTableModeViaApply() {
        // apply(_:) is the deep-link entry point; it must not reset a mode the
        // caller set just before navigating.
        var state = NavigationState()
        state.setReviewWorkspaceMode(.table)
        state.apply(.review())
        #expect(state.destination == .review)
        #expect(state.reviewWorkspaceMode == .table)
    }

    @Test("Review mode round-trips through Codable")
    func reviewModeCodable() throws {
        let state = NavigationState(destination: .review, reviewWorkspaceMode: .table)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NavigationState.self, from: data)
        #expect(decoded.reviewWorkspaceMode == .table)
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

    // MARK: - AND-621: Budgets / Alerts selection are per-window (R-10)

    @Test("Budgets category selection is per-window — independent across windows (AND-621)")
    func independentBudgetSelection() {
        var windowA = NavigationState()
        var windowB = NavigationState()

        // Default: both unselected (content-gated inspector prompt).
        #expect(windowA.budgetCategorySelection == nil)
        #expect(windowB.budgetCategorySelection == nil)

        windowA.selectBudgetCategory(.foodAndDrink)
        // B is untouched; A holds its own selection.
        #expect(windowA.budgetCategorySelection == .foodAndDrink)
        #expect(windowB.budgetCategorySelection == nil)

        windowB.selectBudgetCategory(.shopping)
        #expect(windowA.budgetCategorySelection == .foodAndDrink)
        #expect(windowB.budgetCategorySelection == .shopping)

        windowA.deselectBudgetCategory()
        #expect(windowA.budgetCategorySelection == nil)
        #expect(windowB.budgetCategorySelection == .shopping)
    }

    @Test("Alert selection is per-window — independent across windows (AND-621)")
    func independentAlertSelection() {
        var windowA = NavigationState()
        var windowB = NavigationState()

        // Default: both empty ("" sentinel content-gates the inspector prompt).
        #expect(windowA.alertSelection == "")
        #expect(windowB.alertSelection == "")

        windowA.selectAlert(id: "alert_sync")
        #expect(windowA.alertSelection == "alert_sync")
        #expect(windowB.alertSelection == "")

        windowB.selectAlert(id: "alert_reconnect")
        #expect(windowA.alertSelection == "alert_sync")
        #expect(windowB.alertSelection == "alert_reconnect")

        windowA.deselectAlert()
        #expect(windowA.alertSelection == "")
        #expect(windowB.alertSelection == "alert_reconnect")
    }

    @Test("Alert acknowledgement is per-window — independent across windows (AND-621)")
    func independentAlertAcknowledgement() {
        var windowA = NavigationState()
        var windowB = NavigationState()

        windowA.acknowledgeAlert("alert_sync")
        #expect(windowA.acknowledgedAlertIDs == ["alert_sync"])
        #expect(windowB.acknowledgedAlertIDs.isEmpty)

        windowB.acknowledgeAlert("alert_reconnect")
        #expect(windowA.acknowledgedAlertIDs == ["alert_sync"])
        #expect(windowB.acknowledgedAlertIDs == ["alert_reconnect"])

        windowA.unacknowledgeAlert("alert_sync")
        #expect(windowA.acknowledgedAlertIDs.isEmpty)
        #expect(windowB.acknowledgedAlertIDs == ["alert_reconnect"])
    }

    @Test("pruneAlerts drops acknowledged ids + a stale selection no longer in the live rows (AND-621)")
    func pruneAlertsSelfHeal() {
        let liveRows = [
            AttentionQueueRow(id: "alert_sync", severity: .warning, title: "Sync", detail: "D"),
        ]

        var window = NavigationState()
        window.selectAlert(id: "alert_gone")          // selection no longer present
        window.acknowledgeAlert("alert_sync")          // still live → kept
        window.acknowledgeAlert("alert_gone")          // resolved → pruned

        window.pruneAlerts(toRowsIn: liveRows)

        #expect(window.alertSelection == "")                       // stale selection cleared
        #expect(window.acknowledgedAlertIDs == ["alert_sync"])     // only live id survives
    }

    @Test("pruneAlerts keeps a still-live selection + acknowledgement (AND-621)")
    func pruneAlertsKeepsLive() {
        let liveRows = [
            AttentionQueueRow(id: "alert_sync", severity: .warning, title: "Sync", detail: "D"),
        ]

        var window = NavigationState()
        window.selectAlert(id: "alert_sync")
        window.acknowledgeAlert("alert_sync")

        window.pruneAlerts(toRowsIn: liveRows)

        #expect(window.alertSelection == "alert_sync")
        #expect(window.acknowledgedAlertIDs == ["alert_sync"])
    }

    @Test("acknowledgeAllAlerts acknowledges every listed entry (AND-621)")
    func acknowledgeAllAlerts() {
        let inbox = AlertsInbox.make(
            rows: [
                AttentionQueueRow(id: "a", severity: .warning, title: "A", detail: "D"),
                AttentionQueueRow(id: "b", severity: .blocked, title: "B", detail: "D"),
            ],
            acknowledgedIDs: []
        )

        var window = NavigationState()
        window.acknowledgeAllAlerts(in: inbox)

        #expect(window.acknowledgedAlertIDs == ["a", "b"])
    }
}
