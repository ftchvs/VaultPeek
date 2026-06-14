import SwiftUI

/// How the dashboard (`MainPopover`) is currently being presented, plus the
/// affordance to switch surfaces (AND-384).
///
/// The same `MainPopover` view renders in two hosts: the menu-bar popover and a
/// floating desktop window. This environment value tells the view which host it
/// is in so it can show the right control — a "Detach" pin in popover mode, a
/// "Re-dock" control in detached mode — without the view ever touching AppKit
/// window lifecycle. The closures are supplied by the host (the app scene for
/// detach, the window controller for re-dock).
enum DashboardPresentation: Sendable {
    /// Rendered inside the menu-bar popover. `detach` opens the floating window.
    case popover(detach: @MainActor @Sendable () -> Void)
    /// Rendered inside the floating desktop window. `redock` returns to the
    /// popover.
    case detached(redock: @MainActor @Sendable () -> Void)

    var isDetached: Bool {
        if case .detached = self { return true }
        return false
    }
}

private struct DashboardPresentationKey: EnvironmentKey {
    /// Default: a popover with a no-op detach, used by previews, the snapshot
    /// renderer, and any host that does not wire detaching. The control still
    /// renders but does nothing, so headless renders are unaffected.
    static let defaultValue: DashboardPresentation = .popover(detach: {})
}

extension EnvironmentValues {
    var dashboardPresentation: DashboardPresentation {
        get { self[DashboardPresentationKey.self] }
        set { self[DashboardPresentationKey.self] = newValue }
    }
}
