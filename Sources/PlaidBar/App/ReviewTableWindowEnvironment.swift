import SwiftUI

/// Environment hook the popover's Review Inbox header uses to open the detached
/// multi-select **review Table** window (AND-532), without the view ever touching
/// AppKit window lifecycle.
///
/// The closure is supplied by the app scene (which owns the
/// ``ReviewTableWindowCoordinator``). Previews, the snapshot renderer, and any host
/// that does not wire the window default to a no-op, so the "Open review table"
/// affordance still renders but does nothing — headless renders are unaffected.
/// This mirrors the ``openCategoryDashboard`` hook the Category Dashboard card uses
/// for its own detached window (AND-539).
private struct OpenReviewTableKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the detached multi-select review Table window. No-op by default.
    var openReviewTable: @MainActor @Sendable () -> Void {
        get { self[OpenReviewTableKey.self] }
        set { self[OpenReviewTableKey.self] = newValue }
    }
}
