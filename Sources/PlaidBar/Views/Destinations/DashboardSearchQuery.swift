import SwiftUI

/// The window shell's unified search query, threaded from the shell's `.searchable`
/// toolbar field into whichever destination canvas adopts it (AND-624 / AND-625).
///
/// The window-first shell owns ONE unified `.searchable` toolbar (so search lives
/// in the window chrome, not inside each canvas), and the search-adopting
/// destinations read the live query from the environment to filter their own rows
/// — the Dashboard and Accounts filter their account list by display name. Routing
/// it through the environment (rather than a threaded binding) keeps the
/// content-column router (`DestinationContentView`) signature untouched, so the
/// propagation pass adopts the same pattern per destination without a shared
/// plumbing change.
///
/// Empty string ⇒ no filter (the default), so the popover build — which never
/// mounts the shell — is unaffected.
private struct ShellSearchQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// The live unified search query from the shell's `.searchable` field, scoped to
    /// the destination that adopts it. Trimmed/empty means "no filter".
    var shellSearchQuery: String {
        get { self[ShellSearchQueryKey.self] }
        set { self[ShellSearchQueryKey.self] = newValue }
    }
}
