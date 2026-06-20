import PlaidBarCore
import SwiftUI

/// Present/dismiss state + the command registry for the ⌘K palette (AND-596).
///
/// `@Observable @MainActor` so the `AppShellView` overlay and the ⌘K command
/// share one source of truth. It is per-window scene state (one per
/// `AppShellView`), mirroring `NavigationModel`'s per-window ownership (R-10) —
/// the palette in one window does not present in another.
///
/// Holds the pure ``CommandRegistry`` (the searchable command set); the search /
/// ranking is the registry's own pure method, so this wrapper only carries the
/// `isPresented` flag and the registry instance.
@Observable
@MainActor
final class CommandPaletteModel {
    /// Whether the palette overlay is showing. Toggled by the ⌘K command and the
    /// palette's own dismiss paths (Esc, scrim tap, after executing a command).
    var isPresented = false

    /// The command set the palette searches. The default registry (every
    /// destination + the four global verbs + find) is the complete AND-596 set.
    let registry: CommandRegistry

    init(registry: CommandRegistry = .makeDefault()) {
        self.registry = registry
    }

    func present() { isPresented = true }
    func dismiss() { isPresented = false }
    func toggle() { isPresented.toggle() }
}

/// Executes a chosen palette command's `Kind` against the **existing** app
/// actions (AND-596). The palette never reimplements behavior — it routes the
/// command back to the same paths the menu-bar / global shortcuts use:
///
/// - **navigate** → `NavigationModel.go(to:)` (sets the window's destination).
/// - **act(.refresh)** → `AppState.refreshDashboard()`.
/// - **act(.togglePrivacyMask)** → `AppState.togglePrivacyMask()`.
/// - **act(.openSettings)** → the scene's `openSettings` closure.
/// - **act(.summon)** → the scene's summon closure.
/// - **find** → the scene's focus-search closure (the ⌘F path).
///
/// `openSettings` / `summon` / `focusSearch` are owned by the SwiftUI scene
/// (`PlaidBarApp`), so they are injected as closures rather than reached through
/// `AppState`. `@MainActor`; a value type holding `@MainActor` closures, so it is
/// cheap to construct per `body`.
@MainActor
struct CommandDispatcher {
    let appState: AppState
    let navigationModel: NavigationModel
    /// Opens the native Settings scene (`openSettings()` environment action).
    let openSettings: () -> Void
    /// Brings VaultPeek to the front (the summon-hotkey path).
    let summon: () -> Void
    /// Focuses the current destination's search field (the ⌘F path). The
    /// per-destination search surfaces land in later epics; today this is a hook
    /// the find command and ⌘F share.
    let focusSearch: () -> Void

    func run(_ kind: CommandRegistry.Kind) {
        switch kind {
        case .navigate(let destination):
            navigate(to: destination)
        case .act(let action):
            perform(action)
        case .find:
            focusSearch()
        }
    }

    /// Navigates the window to a destination. Settings is the native scene, so it
    /// opens that window rather than parking the split-view on a content-less
    /// destination (mirrors `AppShellView`'s sidebar binding).
    func navigate(to destination: RouteDestination) {
        if destination == .settings {
            openSettings()
        } else {
            navigationModel.go(to: destination)
        }
    }

    func perform(_ action: CommandRegistry.Action) {
        switch action {
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .togglePrivacyMask:
            appState.togglePrivacyMask()
        case .openSettings:
            openSettings()
        case .summon:
            summon()
        }
    }
}
