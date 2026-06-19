import AppKit
import PlaidBarCore
import SwiftUI

/// Owns the lazily-created ``CategoryDashboardWindowController`` for the detached
/// full Category Dashboard window (AND-539), bridging the popover card's
/// declarative "open dashboard" intent to the imperative AppKit window.
///
/// Held by the app scene as `@State` so it lives for the process lifetime and
/// survives `body` recomputes. The controller (and its `NSWindow`) is built only on
/// first open, so a user who never opens the dashboard never allocates a window.
/// Mirrors `DetachedDashboardCoordinator` (AND-384), scoped to this one surface.
///
/// `@MainActor`/`@Observable`; all window work is main-actor isolated, correct
/// under `-strict-concurrency=complete`.
@MainActor
@Observable
final class CategoryDashboardWindowCoordinator {
    private var controller: CategoryDashboardWindowController?

    /// User asked to open the full Category Dashboard window (the card's
    /// "Open dashboard" affordance). Builds the window on first call, then shows /
    /// raises it.
    func open(appState: AppState, forcedColorScheme: ColorScheme?) {
        let controller = controller ?? CategoryDashboardWindowController(
            appState: appState,
            forcedColorScheme: forcedColorScheme,
            onWindowBecomeKey: {
                // Focusing the window prompts to unlock when App Lock is engaged,
                // mirroring the popover-open trigger. `unlockApp()` is a no-op when
                // App Lock is off or already unlocked, so the guard keeps the system
                // auth sheet from re-prompting in a loop (AND-462).
                guard appState.isAppLocked else { return }
                Task { await appState.unlockApp() }
            }
        )
        self.controller = controller
        controller.show()
    }
}
