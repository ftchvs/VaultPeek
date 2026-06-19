import SwiftUI

/// Environment hook the popover's ``CategoryDashboardCard`` uses to open the full
/// detached Category Dashboard window (AND-539), without the view ever touching
/// AppKit window lifecycle.
///
/// The closure is supplied by the app scene (which owns the
/// ``CategoryDashboardWindowCoordinator``). Previews, the snapshot renderer, and
/// any host that does not wire the window default to a no-op, so the
/// "Open dashboard" affordance still renders but does nothing — headless renders
/// are unaffected. This mirrors the `dashboardPresentation` detach/redock pattern
/// already used for the full dashboard window (AND-384).
private struct OpenCategoryDashboardKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the detached full Category Dashboard window. No-op by default.
    var openCategoryDashboard: @MainActor @Sendable () -> Void {
        get { self[OpenCategoryDashboardKey.self] }
        set { self[OpenCategoryDashboardKey.self] = newValue }
    }
}
