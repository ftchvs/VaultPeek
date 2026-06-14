import AppKit
import PlaidBarCore
import SwiftUI

/// Bridges the declarative `AppState.isDashboardDetached` flag and the menu-bar
/// popover to the imperative `DetachedDashboardWindowController` (AND-384).
///
/// Owned by the app scene as `@State` so it lives for the process lifetime and
/// survives `body` recomputes. It lazily builds the window controller on first
/// detach (so a user who never detaches never allocates an `NSPanel`), and
/// exposes the small set of intents the scene needs: `detach`, `redock`, sync
/// after a state change, the click-intercept decision, and restore-on-launch.
///
/// `@MainActor`/`@Observable`; all window work is main-actor isolated, which
/// keeps it correct under `-strict-concurrency=complete`.
@MainActor
@Observable
final class DetachedDashboardCoordinator {
    private var controller: DetachedDashboardWindowController?
    private var nonPersistedLaunchOverrideActive = false

    /// True while the floating dashboard window is on screen. Used to decide
    /// whether a menu-bar click should raise the window vs. open the popover.
    var isWindowVisible: Bool {
        controller?.isPresented ?? false
    }

    // MARK: - Intents

    /// User asked to detach: persist the intent, open the floating window, and
    /// dismiss the menu-bar popover so only one surface is up.
    func detach(appState: AppState, forcedColorScheme: ColorScheme?, reduceMotion: Bool) {
        nonPersistedLaunchOverrideActive = false
        appState.isDashboardDetached = true
        appState.isPopoverPresented = false
        present(appState: appState, forcedColorScheme: forcedColorScheme, reduceMotion: reduceMotion)
    }

    /// User asked to re-dock (close button, in-dashboard control, or toggle off):
    /// clear the intent and hide the floating window. The popover resumes opening
    /// from the menu-bar item on the next click.
    func redock(appState: AppState, reduceMotion: Bool) {
        nonPersistedLaunchOverrideActive = false
        appState.isDashboardDetached = false
        controller?.hide(reduceMotion: reduceMotion)
    }

    /// Reconciles the window with the persisted/observed `isDashboardDetached`
    /// flag. Call from `.onChange(of: appState.isDashboardDetached)` and once at
    /// launch to restore a window that was open when the app last quit.
    func sync(appState: AppState, forcedColorScheme: ColorScheme?, reduceMotion: Bool) {
        if appState.isDashboardDetached {
            present(appState: appState, forcedColorScheme: forcedColorScheme, reduceMotion: reduceMotion)
        } else {
            controller?.hide(reduceMotion: reduceMotion)
        }
    }

    /// A click on the menu-bar item while detached should raise the floating
    /// window, not open the popover. Returns true when the click was consumed by
    /// raising the window; the caller then keeps `isPopoverPresented` false.
    @discardableResult
    func handleMenuBarActivation(appState: AppState, forcedColorScheme: ColorScheme?, reduceMotion: Bool) -> Bool {
        guard appState.isDashboardDetached || nonPersistedLaunchOverrideActive else { return false }
        present(appState: appState, forcedColorScheme: forcedColorScheme, reduceMotion: reduceMotion)
        controller?.raise()
        return true
    }

    /// Open the floating window WITHOUT persisting the detached intent — for the
    /// `--detach` QA/screenshot launch flag, which must not leave a durable
    /// `dashboard.detached` preference behind (parity with `--show-popover`).
    func presentForLaunchOverride(appState: AppState, forcedColorScheme: ColorScheme?, reduceMotion: Bool) {
        nonPersistedLaunchOverrideActive = true
        appState.isPopoverPresented = false
        present(appState: appState, forcedColorScheme: forcedColorScheme, reduceMotion: reduceMotion)
    }

    // MARK: - Private

    private func present(appState: AppState, forcedColorScheme: ColorScheme?, reduceMotion: Bool) {
        let controller = controller ?? DetachedDashboardWindowController(
            appState: appState,
            forcedColorScheme: forcedColorScheme,
            onRedock: { [weak self] in
                // The close button / in-window control routes here. Use the
                // resolved Reduce Motion setting at call time so the hide matches
                // the user's current accessibility preference.
                let reduceMotionNow = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.redock(appState: appState, reduceMotion: reduceMotionNow)
            }
        )
        self.controller = controller
        controller.show(reduceMotion: reduceMotion)
    }
}
