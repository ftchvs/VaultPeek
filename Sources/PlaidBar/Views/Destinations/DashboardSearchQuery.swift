import SwiftUI

/// The window's Dashboard search query, threaded from the shell's `.searchable`
/// toolbar field into the Dashboard canvas (AND-624).
///
/// The window-first shell owns the unified `.searchable` toolbar (so search lives
/// in the window chrome, not inside the canvas), and the Dashboard reads the live
/// query from the environment to filter its account rows. Routing it through the
/// environment (rather than a threaded binding) keeps the content-column router
/// (`DestinationContentView`) signature untouched, so the propagation pass can
/// adopt the same pattern per destination without a shared plumbing change.
///
/// Empty string ⇒ no filter (the default), so the popover build — which never
/// mounts the shell — is unaffected.
private struct DashboardSearchQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// The live Dashboard search query from the shell's `.searchable` field.
    /// Trimmed/empty means "no filter".
    var dashboardSearchQuery: String {
        get { self[DashboardSearchQueryKey.self] }
        set { self[DashboardSearchQueryKey.self] = newValue }
    }
}
