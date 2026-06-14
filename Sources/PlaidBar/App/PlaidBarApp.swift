import AppKit
import MenuBarExtraAccess
import PlaidBarCore
import Sparkle
import SwiftUI

@main
struct PlaidBarApp: App {
    @State private var appState: AppState
    /// Owns the floating desktop-window dashboard (AND-384). `@State` so it
    /// persists across `body` recomputes for the process lifetime.
    @State private var detachedDashboard = DetachedDashboardCoordinator()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let updaterController: SPUStandardUpdaterController
    private let statusItemContextMenuController = StatusItemContextMenuController()

    init() {
        Self.applyForcedAppearance()
        Self.applyScreenshotDefaults()

        let state = AppState()
        _appState = State(initialValue: state)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
        MenuBarExtra {
            MainPopover()
                .environment(appState)
                .environment(\.dashboardPresentation, .popover(detach: {
                    detachedDashboard.detach(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme,
                        reduceMotion: reduceMotion
                    )
                }))
                .forcedAppColorScheme(Self.forcedColorScheme)
                .appliesAppAppearance()
                // Restore a window that was open at last quit, and keep the
                // floating window in lockstep with the persisted/toggled flag.
                .task {
                    detachedDashboard.sync(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme,
                        reduceMotion: reduceMotion
                    )
                }
                .onChange(of: appState.isDashboardDetached) { _, _ in
                    detachedDashboard.sync(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme,
                        reduceMotion: reduceMotion
                    )
                }
                // While detached, a status-item click sets isPopoverPresented
                // true; intercept it, snap it back to false, and raise the
                // floating window instead of opening the popover (AND-384).
                .onChange(of: appState.isPopoverPresented) { _, isPresented in
                    guard isPresented, appState.isDashboardDetached else { return }
                    appState.isPopoverPresented = false
                    detachedDashboard.handleMenuBarActivation(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme,
                        reduceMotion: reduceMotion
                    )
                }
        } label: {
            MenuBarLabel()
                .environment(appState)
                .forcedAppColorScheme(Self.forcedColorScheme)
        }
        .menuBarExtraAccess(isPresented: $appState.isPopoverPresented) { statusItem in
            statusItemContextMenuController.configure(
                statusItem: statusItem,
                actions: StatusItemContextMenuActions(
                    showDashboard: {
                        // "Open VaultPeek" raises the floating window when
                        // detached; otherwise it opens the popover (AND-384).
                        if detachedDashboard.handleMenuBarActivation(
                            appState: appState,
                            forcedColorScheme: Self.forcedColorScheme,
                            reduceMotion: reduceMotion
                        ) {
                            return
                        }
                        appState.isPopoverPresented = true
                    },
                    refreshDashboard: {
                        Task { await appState.refreshDashboard() }
                    },
                    openSettings: {
                        SettingsWindowActivationRestorer.shared.open(openSettings: openSettings)
                    },
                    checkForUpdates: {
                        updaterController.updater.checkForUpdates()
                    },
                    showAbout: {
                        NSApplication.shared.orderFrontStandardAboutPanel(nil)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    },
                    dismissPopover: {
                        appState.isPopoverPresented = false
                    }
                )
            )
        }
        .menuBarExtraStyle(.window)

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
        guard CommandLineOptions.value(for: "--appearance") == nil else { return }
        switch AppAppearanceMode(rawValue: modeRaw) ?? .followSystem {
        case .followSystem: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private extension View {
    func forcedAppColorScheme(_ cliOverride: ColorScheme?) -> some View {
        modifier(ForcedAppColorScheme(cliOverride: cliOverride))
    }

    func appliesAppAppearance() -> some View {
        modifier(AppAppearanceApplier())
    }
}
