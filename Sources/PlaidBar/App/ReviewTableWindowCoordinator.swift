import AppKit
import PlaidBarCore
import SwiftUI

/// Owns the lazily-created ``ReviewTableWindowController`` for the detached
/// multi-select review Table window (AND-532), bridging the popover's "open review
/// table" intent to the imperative AppKit window.
///
/// Held by the app scene as `@State` so it lives for the process lifetime and
/// survives `body` recomputes. The controller (and its `NSWindow`) is built only on
/// first open, so a user who never opens the table never allocates a window.
/// Mirrors ``CategoryDashboardWindowCoordinator`` (AND-539), scoped to this surface.
///
/// `@MainActor`/`@Observable`; all window work is main-actor isolated, correct
/// under `-strict-concurrency=complete`.
@MainActor
@Observable
final class ReviewTableWindowCoordinator {
    private var controller: ReviewTableWindowController?

    /// User asked to open the detached review Table window (the inbox header's
    /// "Open review table" affordance). Builds the window on first call, then shows
    /// / raises it.
    func open(appState: AppState, forcedColorScheme: ColorScheme?) {
        let controller = controller ?? ReviewTableWindowController(
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
