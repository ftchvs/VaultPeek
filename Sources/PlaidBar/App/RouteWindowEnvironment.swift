import PlaidBarCore
import SwiftUI

/// Environment hook the menu-bar glance uses to deep-link a typed ``Route`` into
/// the window-first primary `Window` (ADR-001 / AND-597).
///
/// A glance attention chip is a launcher (IA §3.6 / §6): tapping it should open
/// the workspace **at the relevant destination**, not just raise the dashboard.
/// The closure is supplied by the app scene (which owns SwiftUI's
/// `openWindow(id:)` action) and forwards to `AppState.route(to:openWindow:)`, so
/// the chip never touches window lifecycle.
///
/// The default is a **no-op**, which is exactly the flag-OFF / preview / snapshot
/// behavior: with the window-first flag OFF the scene does not install a real
/// handler, so a chip that would route instead falls back to its existing
/// in-place action — flag-OFF behavior is unchanged. This mirrors the
/// `openCategoryDashboard` / `openReviewTable` environment hooks.
private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Route) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Deep-links a ``Route`` into the window-first primary window. No-op by
    /// default (flag-OFF / preview / headless), in which case the caller keeps its
    /// existing non-routing behavior.
    var openRoute: @MainActor @Sendable (Route) -> Void {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}

/// Environment hook the menu-bar **glance** uses to open the primary `Window`
/// without a destination — the "Open VaultPeek" button (ADR-001 §6, AND-616).
///
/// Supplied by the app scene (which owns SwiftUI's `openWindow(id:)`). The
/// default is a no-op so previews / snapshots / any host that does not wire the
/// window render the button inertly, mirroring ``openRoute``.
private struct OpenPrimaryWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the window-first primary window (no destination change). No-op by
    /// default.
    var openPrimaryWindow: @MainActor @Sendable () -> Void {
        get { self[OpenPrimaryWindowKey.self] }
        set { self[OpenPrimaryWindowKey.self] = newValue }
    }
}
