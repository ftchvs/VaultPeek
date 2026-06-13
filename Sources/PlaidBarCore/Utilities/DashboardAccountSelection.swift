/// Resolution rule for the dashboard's persisted account selection.
///
/// A selection survives only while the account is still in the visible (filtered)
/// list, so changing the filter or losing the account (sync / removal) deselects
/// it — which closes the right inspector and returns the popover to the
/// two-column state. Pure and unit-testable; mirrors the rule the `MainPopover`
/// selection and deselection paths rely on (AND-373/375).
public enum DashboardAccountSelection {
    /// The selected id resolved against the currently visible account ids.
    /// Returns `nil` when the selection is empty or no longer present.
    public static func resolvedSelectedId(
        _ selectedId: String,
        visibleAccountIds: [String]
    ) -> String? {
        guard !selectedId.isEmpty, visibleAccountIds.contains(selectedId) else {
            return nil
        }
        return selectedId
    }
}
