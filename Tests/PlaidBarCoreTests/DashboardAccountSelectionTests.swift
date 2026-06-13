import PlaidBarCore
import Testing

@Suite("Dashboard account selection resolution")
struct DashboardAccountSelectionTests {
    private let visible = ["demo_checking", "demo_savings", "demo_visa"]

    @Test("An empty selection resolves to nil")
    func emptySelection() {
        #expect(DashboardAccountSelection.resolvedSelectedId("", visibleAccountIds: visible) == nil)
    }

    @Test("A selection still in the visible list is kept")
    func presentSelectionKept() {
        #expect(
            DashboardAccountSelection.resolvedSelectedId("demo_visa", visibleAccountIds: visible) == "demo_visa"
        )
    }

    @Test("A selection no longer visible (filter change / removal) deselects")
    func absentSelectionCleared() {
        // demo_visa is a credit account; switching to the Cash filter drops it
        // from the visible list, which must close the inspector.
        let cashOnly = ["demo_checking", "demo_savings"]
        #expect(DashboardAccountSelection.resolvedSelectedId("demo_visa", visibleAccountIds: cashOnly) == nil)
    }

    @Test("Any selection resolves to nil when no accounts are visible")
    func emptyListClears() {
        #expect(DashboardAccountSelection.resolvedSelectedId("demo_visa", visibleAccountIds: []) == nil)
    }
}
