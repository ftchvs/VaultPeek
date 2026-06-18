import AppKit
import Combine
import PlaidBarCore
import Sparkle
import SwiftUI

@main
struct PlaidBarApp: App {
    // The menu-bar status item + popover are owned by an AppKit delegate so the
    // popover can be a real NSPopover (native frosted glass — MenuBarExtra(.window)
    // can't be made translucent). The delegate reads its dependencies from
    // MenuBarAppContext, filled in below.
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @State private var appState: AppState
    /// Owns the floating desktop-window dashboard (AND-384).
    private let detachedDashboard = DetachedDashboardCoordinator()
    private let updaterController: SPUStandardUpdaterController
    private let statusItemContextMenuController = StatusItemContextMenuController()

    init() {
        Self.applyForcedAppearance()
        Self.applyStoredAppearance()
        Self.applyScreenshotDefaults()

        let state = AppState()
        _appState = State(initialValue: state)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Hand the process-lifetime dependencies to the AppKit delegate (which
        // @NSApplicationDelegateAdaptor constructs itself). App.init runs on the
        // main thread, and the delegate reads these in applicationDidFinishLaunching
        // (after init), so assumeIsolated is safe and the values are ready in time.
        MainActor.assumeIsolated {
            MenuBarAppContext.appState = state
            MenuBarAppContext.detachedDashboard = detachedDashboard
            MenuBarAppContext.updaterController = updaterController
            MenuBarAppContext.contextMenuController = statusItemContextMenuController
            MenuBarAppContext.forcedColorScheme = Self.forcedColorScheme
        }
        if CommandLine.arguments.contains("--show-popover") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                state.isPopoverPresented = true

                // Debug aid: when the status item is hidden in menu bar
                // overflow, macOS anchors the popover window beyond every
                // display, where screenshot tooling cannot capture it.
                // "--popover-origin x,y" moves it to a visible position.
                if let origin = CommandLineOptions.value(for: "--popover-origin") {
                    let parts = origin.split(separator: ",").compactMap { Double($0) }
                    if parts.count == 2 {
                        try? await Task.sleep(for: .milliseconds(600))
                        NSApplication.shared.windows
                            .first { $0.frame.width >= 400 }?
                            .setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
                    }
                }
            }
        }
        _ = SnapshotRenderer.renderIfRequested(appState: state)
        // Debug aid: register as a regular app (Dock icon, app switcher) so
        // automation/permission systems that skip accessory apps can see it.
        if CommandLine.arguments.contains("--regular-activation") {
            Task { @MainActor in
                NSApplication.shared.setActivationPolicy(.regular)
            }
        }
        Task { @MainActor in
            await state.prewarmBundledServer()
        }
    }

    var body: some Scene {
        // The menu bar status item + NSPopover live in MenuBarAppDelegate; the
        // only SwiftUI scene is Settings. A Settings-only scene is the canonical
        // shape for an LSUIElement/.accessory menu-bar app and keeps
        // @Environment(\.openSettings) + SettingsWindowActivationRestorer working.
        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
                .forcedAppColorScheme(Self.forcedColorScheme)
                .appliesAppAppearance()
        }
    }

    /// QA aid: "--appearance light|dark" pins the whole app to one appearance
    /// so screenshot and `--render-snapshot` passes can cover both modes
    /// regardless of the host's system setting (docs/qa-matrix.md). Unknown
    /// values are ignored and the system appearance stays in charge.
    private static func applyForcedAppearance() {
        guard let mode = CommandLineOptions.value(for: "--appearance") else { return }

        switch mode.lowercased() {
        case "light":
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default:
            break
        }
    }

    /// Applies the *stored* appearance-mode preference to `NSApplication.appearance`
    /// **before first paint**, so the very first frame renders in the chosen
    /// Light/Dark — window chrome and AppKit materials included — instead of
    /// flashing the system appearance and correcting `onAppear`. `NSApp.appearance`
    /// is the only API that cascades to chrome + materials; `environment(\.colorScheme)`
    /// moves SwiftUI content only. The `--appearance` CLI override wins:
    /// `applyForcedAppearance()` already pinned it and `applyToNSApp` no-ops when set.
    private static func applyStoredAppearance() {
        AppAppearance.applyToNSApp(
            modeRaw: UserDefaults.standard.string(forKey: AppAppearanceMode.storageKey)
                ?? AppAppearanceMode.defaultValue.rawValue
        )
    }

    /// The color scheme forced by the `--appearance` CLI flag (QA aid), or `nil`
    /// to follow the system/app preference. Shared with `SnapshotRenderer`.
    static var forcedColorScheme: ColorScheme? {
        guard let mode = CommandLineOptions.value(for: "--appearance") else { return nil }

        switch mode.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private static func applyScreenshotDefaults() {
        guard CommandLine.arguments.contains("--demo") else { return }

        if let filter = CommandLineOptions.value(for: "--screenshot-filter") {
            let normalizedFilter = ["all", "cash", "credit", "savings", "debt", "status"]
                .first { $0 == filter.lowercased() }
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }

            if let normalizedFilter {
                UserDefaults.standard.set(String(normalizedFilter), forKey: "dashboard.accountFilter")
            }
        }

        if let accountId = CommandLineOptions.value(for: "--screenshot-account") {
            UserDefaults.standard.set(accountId, forKey: "dashboard.selectedAccountId")
        } else if CommandLine.arguments.contains("--screenshot-filter") {
            UserDefaults.standard.removeObject(forKey: "dashboard.selectedAccountId")
        }

        if let settingsTab = CommandLineOptions.value(for: "--settings-tab") {
            UserDefaults.standard.set(settingsTab.lowercased(), forKey: "settings.selectedTab")
        }
    }
}

private struct ForcedAppColorScheme: ViewModifier {
    /// The `--appearance` CLI override; when non-nil it wins over the stored
    /// app appearance-mode preference (AND-365).
    let cliOverride: ColorScheme?
    @AppStorage(AppAppearanceMode.storageKey) private var modeRaw = AppAppearanceMode.defaultValue.rawValue

    private var effectiveScheme: ColorScheme? {
        if let cliOverride { return cliOverride }
        switch AppAppearanceMode(rawValue: modeRaw) ?? .followSystem {
        case .followSystem: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func body(content: Content) -> some View {
        if let effectiveScheme {
            content.environment(\.colorScheme, effectiveScheme)
        } else {
            content
        }
    }
}

/// Applies the stored appearance-mode preference to `NSApplication.appearance`
/// so window chrome (e.g. the Settings titlebar) follows the choice too, not
/// just SwiftUI content. The `--appearance` CLI override wins: when it is set,
/// `applyForcedAppearance()` already pinned the app appearance, so this no-ops.
private struct AppAppearanceApplier: ViewModifier {
    @AppStorage(AppAppearanceMode.storageKey) private var modeRaw = AppAppearanceMode.defaultValue.rawValue

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: modeRaw) { _, _ in apply() }
    }

    @MainActor private func apply() {
        AppAppearance.applyToNSApp(modeRaw: modeRaw)
    }
}

/// Single mapping from the stored appearance mode to `NSApplication.appearance`,
/// shared by the launch-time application (`PlaidBarApp.applyStoredAppearance`,
/// before first paint) and the live `AppAppearanceApplier` (`onChange`). Making
/// this the one writer of `NSApp.appearance` for the stored preference gives every
/// window — popover, Settings, and the detached dashboard (whose panel leaves
/// `appearance == nil` so it inherits) — a single source of truth, so flipping
/// Light/Dark updates all surfaces live. The `--appearance` CLI override wins and
/// makes this a no-op.
enum AppAppearance {
    @MainActor static func applyToNSApp(modeRaw: String) {
        guard CommandLineOptions.value(for: "--appearance") == nil else { return }
        switch AppAppearanceMode(rawValue: modeRaw) ?? .followSystem {
        case .followSystem: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension View {
    // Module-visible: also used by MenuBarAppDelegate's hosted MainPopover/MenuBarLabel.
    func forcedAppColorScheme(_ cliOverride: ColorScheme?) -> some View {
        modifier(ForcedAppColorScheme(cliOverride: cliOverride))
    }

    func appliesAppAppearance() -> some View {
        modifier(AppAppearanceApplier())
    }
}

/// Lets `MenuBarAppContext` hold the Sparkle updater controller without the
/// AppKit delegate importing Sparkle.
extension SPUStandardUpdaterController: SPUUpdaterControlling {
    public func checkForUpdatesFromMenu() {
        updater.checkForUpdates()
    }
}
