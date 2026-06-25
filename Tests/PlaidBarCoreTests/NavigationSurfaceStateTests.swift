import Testing
@testable import PlaidBarCore

/// Tests for the surface-presentation state migrated off the retired
/// single-surface `AppState` flags onto the per-window ``NavigationState``
/// (AND-600): `isPopoverPresented` (the menu-bar popover's presentation) and
/// `isDashboardDetached` (the floating-window intent). The whole point of the
/// migration is that two windows hold *independent* presentation/detach state,
/// so the per-window-independence cases below pin that contract at the pure
/// value-type layer (where the `NavigationModel` wrapper derives its behavior).
@Suite("AND-600 per-window surface presentation state")
struct NavigationSurfaceStateTests {

    // MARK: - Defaults

    @Test("Popover and detached default to false on a fresh window")
    func defaults() {
        let state = NavigationState()
        #expect(!state.isPopoverPresented)
        #expect(!state.isDashboardDetached)
    }

    // MARK: - Popover presentation

    @Test("setPopoverPresented toggles the popover presentation flag")
    func setPopoverPresented() {
        var state = NavigationState()
        state.setPopoverPresented(true)
        #expect(state.isPopoverPresented)
        state.setPopoverPresented(false)
        #expect(!state.isPopoverPresented)
    }

    // MARK: - Detach / re-dock

    @Test("detachDashboard sets the intent AND dismisses the popover (one surface up)")
    func detachDismissesPopover() {
        // The popover is open; detaching must close it so only one surface is up —
        // the rule the AppState `detach` path enforced before AND-600.
        var state = NavigationState(isPopoverPresented: true)
        state.detachDashboard()
        #expect(state.isDashboardDetached)
        #expect(!state.isPopoverPresented)
    }

    @Test("redockDashboard clears the detached intent")
    func redockClearsDetached() {
        var state = NavigationState(isDashboardDetached: true)
        state.redockDashboard()
        #expect(!state.isDashboardDetached)
    }

    @Test("Detach then re-dock round-trips back to the popover")
    func detachRedockRoundTrip() {
        var state = NavigationState()
        state.detachDashboard()
        #expect(state.isDashboardDetached)
        state.redockDashboard()
        #expect(!state.isDashboardDetached)
    }

    // MARK: - Per-window independence (R-10 — the migration's reason for existing)

    @Test("Two windows hold independent popover presentation (AND-600)")
    func independentPopoverPresentation() {
        var windowA = NavigationState()
        var windowB = NavigationState()

        windowA.setPopoverPresented(true)

        // B is entirely unaffected — the single-surface flag could never express this.
        #expect(windowA.isPopoverPresented)
        #expect(!windowB.isPopoverPresented)

        // And B can hold its own, opposite presentation simultaneously.
        windowB.setPopoverPresented(true)
        windowA.setPopoverPresented(false)
        #expect(!windowA.isPopoverPresented)
        #expect(windowB.isPopoverPresented)
    }

    @Test("Two windows hold independent detach intent (AND-600)")
    func independentDetachIntent() {
        var windowA = NavigationState()
        var windowB = NavigationState()

        windowA.detachDashboard()

        // Detaching A's dashboard leaves B docked.
        #expect(windowA.isDashboardDetached)
        #expect(!windowB.isDashboardDetached)

        // B re-docks/detaches on its own without disturbing A.
        windowB.detachDashboard()
        windowA.redockDashboard()
        #expect(!windowA.isDashboardDetached)
        #expect(windowB.isDashboardDetached)
    }

    @Test("Detaching one window's dashboard does not dismiss another window's popover")
    func detachDoesNotCrossDismissPopover() {
        // Window B has its popover open; window A detaching must not reach across
        // and close B's popover — the cross-surface bug the global flag invited.
        var windowA = NavigationState()
        var windowB = NavigationState(isPopoverPresented: true)

        windowA.detachDashboard()

        #expect(windowA.isDashboardDetached)
        #expect(!windowA.isPopoverPresented)
        #expect(windowB.isPopoverPresented)
        #expect(!windowB.isDashboardDetached)
    }

    // MARK: - Codable (persisted alongside the rest of the navigation state)

    @Test("Surface presentation state round-trips through Codable")
    func codable() throws {
        let state = NavigationState(isPopoverPresented: true, isDashboardDetached: true)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NavigationState.self, from: data)
        #expect(decoded.isPopoverPresented)
        #expect(decoded.isDashboardDetached)
        #expect(decoded == state)
    }
}
