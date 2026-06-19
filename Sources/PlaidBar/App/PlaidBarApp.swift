import AppKit
import Combine
import CoreSpotlight
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
    /// Owns the detached full Category Dashboard window (AND-539). `@State` so the
    /// lazily-built window survives `body` recomputes for the process lifetime.
    @State private var categoryDashboardWindow = CategoryDashboardWindowCoordinator()
    /// Owns the global summon hotkey (⇧⌘V, AND-487). `@State` so the Carbon
    /// registration survives `body` recomputes for the process lifetime.
    @State private var summonHotkeyMonitor = SummonHotkeyMonitor()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                // The Category Dashboard card's "Open dashboard" affordance opens
                // the detached full dashboard window (AND-539). Wired here so the
                // view never touches AppKit window lifecycle.
                .environment(\.openCategoryDashboard, {
                    categoryDashboardWindow.open(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme
                    )
                })
                .forcedAppColorScheme(Self.forcedColorScheme)
                .appliesAppAppearance()
        } label: {
            MenuBarLabel()
                .environment(appState)
                .forcedAppColorScheme(Self.forcedColorScheme)
                // The label is the only scene content mounted for the whole app
                // lifetime, so it also carries the live appearance updater: with
                // it here, flipping Light/Dark re-applies NSApp.appearance even
                // when the popover and Settings are both closed (the popover and
                // Settings keep their own copies for when they are the only
                // mounted scene). Without this, a change made while only the label
                // is up would not take effect until the popover next opened.
                .appliesAppAppearance()
                // The menu-bar label is the only scene content that is mounted
                // for the whole app lifetime — `MainPopover` is mounted lazily,
                // only while the popover/menu-extra window is presented, and
                // `Settings` likewise. So the floating-window restore-at-launch,
                // the persisted/toggled-intent sync, AND the click interceptor
                // all live here: otherwise a saved `dashboard.detached = true`
                // would not reopen the window until the user first opened the
                // popover, a Settings-only toggle would not take effect until
                // then, and — critically — a status-item click while detached
                // (before the popover ever mounted) would set
                // `isPopoverPresented = true` with no observer installed yet, so
                // SwiftUI would open the popover instead of raising the floating
                // window (AND-384).
                .task {
                    detachedDashboard.sync(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme,
                        reduceMotion: reduceMotion
                    )
                    // Register the global summon hotkey (⇧⌘V) on first mount when
                    // enabled; the .onChange below keeps it in sync afterward.
                    applySummonHotkeyState()
                    // QA/screenshot aid: "--detach" opens the floating window at
                    // launch (parallel to "--show-popover") WITHOUT persisting the
                    // detached intent, so a QA run never leaves a durable
                    // `dashboard.detached` preference behind.
                    if CommandLine.arguments.contains("--detach") {
                        detachedDashboard.presentForLaunchOverride(
                            appState: appState,
                            forcedColorScheme: Self.forcedColorScheme,
                            reduceMotion: reduceMotion
                        )
                    }
                }
                // While detached, a status-item click sets isPopoverPresented
                // true; intercept it on the always-mounted label, snap it back to
                // false, and raise the floating window instead of the popover.
                // A `--detach` launch override also has a visible detached window
                // but intentionally leaves the persisted detached preference off,
                // so include window visibility in the intercept.
                .onChange(of: appState.isPopoverPresented) { _, isPresented in
                    guard isPresented, appState.isDashboardDetached || detachedDashboard.isWindowVisible else { return }
                    appState.isPopoverPresented = false
                    detachedDashboard.handleMenuBarActivation(
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
                // Register/unregister the global summon hotkey when the user
                // toggles it in Settings (AND-487).
                .onChange(of: appState.summonHotkeyEnabled) { _, _ in
                    applySummonHotkeyState()
                }
                .onOpenURL { url in
                    guard url.scheme == "vaultpeek" else { return }
                    openDashboardFromDeepLink()
                }
                // Selecting an indexed account in Spotlight does NOT arrive via
                // `.onOpenURL` even though the searchable item carries a
                // `contentURL`: Core Spotlight delivers the tap as an
                // `NSUserActivity` of type `CSSearchableItemActionType` instead.
                // All account results point at the shared `vaultpeek://dashboard`
                // deep link (no per-account payload — see AccountSpotlightIndexer),
                // so route every selection through the same open-dashboard path
                // the deep link uses (AND-513).
                .onContinueUserActivity(CSSearchableItemActionType) { _ in
                    openDashboardFromDeepLink()
                }
                // The "Refresh balances" widget control opens the app via an
                // `openAppWhenRun` App Intent that writes a pending command but,
                // unlike the widget's deep link above, opens neither the popover
                // nor the detached window — so neither `loadInitialData()` nor a
                // dashboard refresh runs to consume it, and the control feels
                // inert. Consume it here on the always-mounted label whenever the
                // app becomes active (the intent activates it, whether it was
                // already running or freshly launched). A no-op when no command
                // is pending, so it is cheap on every activation (AND-385).
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await appState.consumePendingGlanceCommand() }
                    // Apply the Control Center "Privacy Mask" toggle (AND-513).
                    // Like the refresh control above, the toggle runs in the
                    // WidgetKit extension and cannot mutate app state directly —
                    // it drops a command file the app consumes on activation.
                    // Synchronous and a cheap no-op when nothing is pending, so it
                    // is safe to run on every activation. Routes through the same
                    // `appLockPreferences.privacyMaskEnabled` path as the in-app
                    // eye toggle, so persistence and the masked-snapshot rewrite
                    // happen through the existing flow.
                    appState.applyPendingPrivacyMaskControlCommand()
                }
                // App Lock trigger: lock when VaultPeek loses focus (the user
                // clicks away / the popover closes) so balances re-mask behind
                // the lock. A cheap no-op when App Lock or lock-when-backgrounded
                // is off. The unlock prompt is driven from the popover-open path
                // below, not from didBecomeActive, so presenting the system auth
                // sheet (which deactivates this app) cannot start a lock/unlock
                // loop (AND-462).
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    appState.lockOnResignActiveIfNeeded()
                }
                // Opening the popover while locked prompts for authentication to
                // reveal balances; `unlockApp()` is a no-op when App Lock is off
                // or already unlocked.
                .onChange(of: appState.isPopoverPresented) { _, isPresented in
                    guard isPresented, appState.isAppLocked else { return }
                    Task { await appState.unlockApp() }
                }
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
                    openInWindow: {
                        // Detach into the floating desktop window directly, so the
                        // window is reachable without hunting for the footer glyph.
                        detachedDashboard.detach(
                            appState: appState,
                            forcedColorScheme: Self.forcedColorScheme,
                            reduceMotion: reduceMotion
                        )
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
                    },
                    togglePrivacyMask: {
                        appState.togglePrivacyMask()
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

    /// Registers or unregisters the global summon hotkey to match the persisted
    /// `summonHotkeyEnabled` preference (AND-487). Idempotent.
    @MainActor
    private func applySummonHotkeyState() {
        if appState.summonHotkeyEnabled {
            summonHotkeyMonitor.start { summonDashboard() }
        } else {
            summonHotkeyMonitor.stop()
        }
    }

    /// Opens the dashboard for a `vaultpeek://` deep link — raising the floating
    /// window when detached, otherwise opening the popover. Shared by the
    /// `.onOpenURL` handler (widget / control deep links) and the Spotlight
    /// `CSSearchableItemActionType` continuation (tapping an indexed account),
    /// since both resolve to the same dashboard target (AND-513).
    @MainActor
    private func openDashboardFromDeepLink() {
        if detachedDashboard.handleMenuBarActivation(
            appState: appState,
            forcedColorScheme: Self.forcedColorScheme,
            reduceMotion: reduceMotion
        ) {
            return
        }
        appState.isPopoverPresented = true
    }

    /// Brings VaultPeek to the front and shows the dashboard — raising the
    /// floating window when detached, otherwise activating the app and opening
    /// the popover. Mirrors the `vaultpeek://` deep-link summon path.
    @MainActor
    private func summonDashboard() {
        if detachedDashboard.handleMenuBarActivation(
            appState: appState,
            forcedColorScheme: Self.forcedColorScheme,
            reduceMotion: reduceMotion
        ) {
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        appState.isPopoverPresented = true
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

private extension View {
    func forcedAppColorScheme(_ cliOverride: ColorScheme?) -> some View {
        modifier(ForcedAppColorScheme(cliOverride: cliOverride))
    }

    func appliesAppAppearance() -> some View {
        modifier(AppAppearanceApplier())
    }
}
