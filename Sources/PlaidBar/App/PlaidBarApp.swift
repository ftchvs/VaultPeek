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
    /// Owns the detached multi-select review Table window (AND-532). `@State` so the
    /// lazily-built window survives `body` recomputes for the process lifetime.
    @State private var reviewTableWindow = ReviewTableWindowCoordinator()
    /// Owns the global summon hotkey (⇧⌘V, AND-487). `@State` so the Carbon
    /// registration survives `body` recomputes for the process lifetime.
    @State private var summonHotkeyMonitor = SummonHotkeyMonitor()
    /// Routes the window-first primary `Window`'s open/close lifecycle through the
    /// shared refcounted activation-policy coordinator (ADR-001 / AND-620): elevate
    /// `.accessory → .regular` when the window opens, return to `.accessory` when
    /// the last managed window closes. `@State` so the single outstanding request it
    /// can hold survives `body` recomputes for the process lifetime. Inert unless
    /// the `Window` actually opens, which only happens behind the window-first flag,
    /// so flag-OFF activation behavior is unchanged.
    @State private var windowActivationPolicy = WindowActivationPolicy()
    /// The window-first ⌘K command-palette state (ADR-001, IA §3.3, AND-596).
    /// Owned at the scene level so the ⌘K `CommandMenu` and the `AppShellView`
    /// overlay share one source of truth. `@State` so it survives `body`
    /// recomputes. Inert unless the window-first surface is shown, which only
    /// happens behind the flag — so flag-OFF behavior is unchanged.
    @State private var commandPalette = CommandPaletteModel()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Identifier of the window-first primary workspace `Window` scene (ADR-001,
    /// Epic 1 / AND-591). Shared by the scene declaration and the
    /// `openWindow(id:)` affordances so they never drift.
    private static let mainWindowID = "main"
    /// Window-first hybrid opt-in (`WindowFirstFeatureFlag`, default OFF). Resolved
    /// once at launch from the CLI override / stored preference. While OFF the
    /// "Open VaultPeek" affordance never targets the `Window` scene, so the app
    /// behaves byte-identically to the popover-first build (the scene itself uses
    /// `.defaultLaunchBehavior(.suppressed)`, so an unopened window is inert).
    private let isWindowFirstEnabled = WindowFirstFeatureFlag.resolved()
    private let updaterController: SPUStandardUpdaterController
    private let statusItemContextMenuController = StatusItemContextMenuController()
    /// Draws the unreviewed review-inbox count badge on the menu-bar status item
    /// (AND-534). Configured with the live `NSStatusItem` in `menuBarExtraAccess`;
    /// updated from the always-mounted `MenuBarLabel` whenever the count or
    /// Privacy Mask changes.
    private let statusItemBadgeController = StatusItemBadgeController()

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
                // The Review Inbox header's "Open review table" affordance opens the
                // detached multi-select review Table window (AND-532). Wired here so
                // the view never touches AppKit window lifecycle.
                .environment(\.openReviewTable, {
                    reviewTableWindow.open(
                        appState: appState,
                        forcedColorScheme: Self.forcedColorScheme
                    )
                })
                // Glance attention-chip deep-linking (ADR-001 / AND-597). Only
                // install a real handler when the window-first flag is ON; with the
                // flag OFF the `openRoute` environment value stays its no-op
                // default, so a chip falls back to its existing in-place action and
                // the popover behaves byte-identically to today. When ON, a chip
                // routes a typed `Route` into the primary window through the single
                // reusable entry point (`AppState.route(to:openWindow:)`, also the
                // App Intents Epic-8 path), staging the route then opening the
                // window via `openWindow(id:)`.
                .environment(\.openRoute, glanceRouteHandler)
                .forcedAppColorScheme(Self.forcedColorScheme)
                .appliesAppAppearance()
                // Apply the in-app text-size preference once at the popover root
                // so every @ScaledMetric/Text below it scales together — macOS
                // ignores the system Dynamic Type setting for third-party apps,
                // so this control is the only way users can enlarge VaultPeek's
                // text (AND-570).
                .appliesAppTextSize()
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
                // Keep the menu-bar count badge in sync from the always-mounted
                // label (the only scene content live for the whole app lifetime,
                // so the badge updates even when the popover has never opened).
                // The visibility/text rule (hidden at zero, withheld under Privacy
                // Mask) lives in the pure `MenuBarReviewBadge`; the controller only
                // renders it. The badge view itself is attached lazily in
                // `menuBarExtraAccess` once the status item exists, so these only
                // take visible effect after that callback has fired — the
                // configure-time `update` covers the first appearance (AND-534).
                .onChange(of: appState.transactionReviewCount) { _, count in
                    statusItemBadgeController.update(
                        unreviewedCount: count,
                        isMasked: appState.shouldMaskFinancialValues
                    )
                }
                .onChange(of: appState.shouldMaskFinancialValues) { _, isMasked in
                    statusItemBadgeController.update(
                        unreviewedCount: appState.transactionReviewCount,
                        isMasked: isMasked
                    )
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
                    guard url.scheme == RouteDeepLink.scheme else { return }
                    handleDeepLink(url)
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
            // Attach the unreviewed-count badge to the live status item, then
            // paint the current count immediately so it is correct on first
            // appearance (not only after the next count/mask change). The button
            // can be recreated when the menu-bar item rebuilds, so configure is
            // idempotent and re-pins the overlay (AND-534).
            statusItemBadgeController.configure(statusItem: statusItem)
            statusItemBadgeController.update(
                unreviewedCount: appState.transactionReviewCount,
                isMasked: appState.shouldMaskFinancialValues
            )
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

        .commands {
            // "Open VaultPeek" affordance in the app menu, gated by the
            // window-first flag (ADR-001, Epic 1 / AND-591). When the flag is OFF
            // this command is not added, so the menu — and the whole app — is
            // identical to today's popover-first build. When ON it raises the
            // primary `Window` workspace via `openWindow(id:)`. The empty `if`
            // produces no commands, satisfying the `Commands` builder.
            if isWindowFirstEnabled {
                CommandGroup(after: .windowList) {
                    Button("Open VaultPeek") {
                        openWindow(id: Self.mainWindowID)
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }

                // The window-first global keyboard map (ADR-001, IA §3.4,
                // AND-596). All gated by the same flag as "Open VaultPeek" — with
                // the flag OFF none of these menus/shortcuts are added, so the
                // menu bar and the whole app are byte-identical to today. Each
                // command drives the shared per-window models / the existing
                // action paths; none reimplements behavior. (`⌘,` Settings stays
                // the native Settings scene shortcut; it is not redeclared here.)

                // Go menu — ⌘K palette, ⌘1–8 destinations, ⌘F find.
                CommandMenu("Go") {
                    Button("Command Palette…") {
                        ensureWindowOpen()
                        commandPalette.present()
                    }
                    .keyboardShortcut("k", modifiers: .command)

                    Divider()

                    // ⌘1…⌘8 jump to a destination, matching
                    // `RouteDestination.commandShortcutNumber` (Dashboard…Accounts).
                    ForEach(destinationsWithShortcut, id: \.self) { destination in
                        Button(destination.title) {
                            goToDestination(destination)
                        }
                        .keyboardShortcut(
                            shortcutKey(for: destination.commandShortcutNumber),
                            modifiers: .command
                        )
                    }

                    Divider()

                    Button("Find Transaction…") {
                        ensureWindowOpen()
                        commandPalette.dismiss()
                        runFindCommand()
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }

                // Account/Actions menu — ⌘R refresh, ⌘⇧P Privacy Mask, ⇧⌘V summon.
                CommandMenu("Actions") {
                    Button("Refresh") {
                        Task { await appState.refreshDashboard() }
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    Button(privacyMaskMenuTitle) {
                        appState.togglePrivacyMask()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    Button("Summon VaultPeek") {
                        summonDashboard()
                    }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                }
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
                .forcedAppColorScheme(Self.forcedColorScheme)
                .appliesAppAppearance()
                // Scale the Settings window too, so the user sees the text-size
                // change reflected in the very control they are adjusting (AND-570).
                .appliesAppTextSize()
        }

        // Window-first primary workspace (ADR-001, Epic 1 / AND-591). The scene is
        // always declared so the scene graph is stable, but it is inert until
        // explicitly opened: `.defaultLaunchBehavior(.suppressed)` keeps it from
        // appearing at launch, and the only affordance that opens it (the
        // "Open VaultPeek" command above) is gated behind the window-first flag.
        // So with the flag OFF — the shipping default — the window never appears
        // and the app behaves byte-identically to the popover-first build. The
        // shell is an empty `NavigationSplitView` skeleton; routing/destinations
        // and the activation-policy/appearance wiring land in later Epic 1/2 PRs.
        Window("VaultPeek", id: Self.mainWindowID) {
            AppShellView(
                paletteModel: commandPalette,
                summon: { summonDashboard() },
                // Per-destination search lands in later epics; ⌘F / the find
                // command focus the window for now (the real search-field focus
                // wires up when Transactions/Review land).
                focusSearch: { NSApplication.shared.activate(ignoringOtherApps: true) }
            )
                .environment(appState)
                .forcedAppColorScheme(Self.forcedColorScheme)
                // Fold the primary `Window` into the single `NSApp.appearance`
                // source of truth (`AppAppearance`, also applied before first paint
                // in `applyStoredAppearance()`): this carries the same live
                // appearance updater the popover/label/Settings use, so flipping
                // Light/Dark re-applies on this window too and there is no second,
                // competing setter to flash a wrong first-paint theme (R-04).
                .appliesAppAppearance()
                .appliesAppTextSize()
                // Elevate `.accessory → .regular` while this window is on screen and
                // drop back when the last managed window closes, via the shared
                // refcounted coordinator (ADR-001 / AND-620, R-01). SwiftUI gives a
                // declarative `Window` no `NSWindowController`, so the lifecycle is
                // bridged here; the helper is idempotent against repeated
                // appear/disappear. Only ever reached when the window opens (behind
                // the window-first flag), so flag-OFF behavior is unchanged.
                .onAppear { windowActivationPolicy.onWindowAppear() }
                .onDisappear { windowActivationPolicy.onWindowDisappear() }
                // Liquid Glass on chrome only (ADR-001): the window background is
                // the ultra-thin material; data surfaces inside stay opaque. This
                // is a content modifier (it walks up to the window), so it lives on
                // the scene's root view, not on the `Window` scene itself.
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        // Do not steal launch/activation: the window only appears when opened.
        .defaultLaunchBehavior(.suppressed)
        // Let macOS restore the window across launches once the user opts in.
        .restorationBehavior(.automatic)
        // Content-driven sizing with a sensible floor so the 3-column workspace
        // never collapses below a usable width.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
    }

    // MARK: - Window-first command map (AND-596)

    /// Destinations that own a `⌘N` shortcut (Dashboard…Accounts), in shortcut
    /// order. Drives the "Go" menu's numbered items off the single source of
    /// truth in `RouteDestination`, so the menu and the keymap never drift.
    private var destinationsWithShortcut: [RouteDestination] {
        RouteDestination.allCases
            .filter { $0.commandShortcutNumber != nil }
            .sorted { ($0.commandShortcutNumber ?? 0) < ($1.commandShortcutNumber ?? 0) }
    }

    /// The `KeyEquivalent` for a destination's shortcut number (1…8). Falls back
    /// to "1" defensively; `destinationsWithShortcut` only yields numbered ones.
    private func shortcutKey(for number: Int?) -> KeyEquivalent {
        guard let number, let scalar = Character(String(number)).unicodeScalars.first else {
            return "1"
        }
        return KeyEquivalent(Character(scalar))
    }

    /// The Privacy Mask menu title reflects the current state so the menu reads
    /// "Hide Balances" / "Show Balances" rather than a static label.
    private var privacyMaskMenuTitle: String {
        appState.shouldMaskFinancialValues ? "Show Balances" : "Hide Balances"
    }

    /// The glance attention-chip deep-link handler injected into `\.openRoute`
    /// (ADR-001 / AND-597). When the window-first flag is ON it routes a `Route`
    /// into the primary window via the single reusable entry point
    /// (`AppState.route(to:openWindow:)`); when OFF it is a no-op so the chip falls
    /// back to its existing in-place action and flag-OFF behavior is unchanged.
    ///
    /// Returned as an explicitly typed `@MainActor @Sendable` closure so a single
    /// `.environment(\.openRoute, …)` site type-checks under strict concurrency
    /// (a ternary of two closure literals breaks `@Sendable` inference).
    private var glanceRouteHandler: @MainActor @Sendable (Route) -> Void {
        guard isWindowFirstEnabled else { return { _ in } }
        return { route in
            appState.route(to: route) {
                openWindow(id: Self.mainWindowID)
            }
        }
    }

    /// Opens the primary window if it is not already up, so a ⌘K / ⌘1–8 pressed
    /// while only the menu bar is showing brings the workspace forward first.
    @MainActor
    private func ensureWindowOpen() {
        openWindow(id: Self.mainWindowID)
    }

    /// Navigates the primary window to a destination (the ⌘1–8 path). Opens the
    /// window first, then drives the shared per-window `NavigationModel`.
    @MainActor
    private func goToDestination(_ destination: RouteDestination) {
        ensureWindowOpen()
        appState.navigationModel.go(to: destination)
    }

    /// Runs the palette's "find" command (the ⌘F path): focus the current
    /// destination's search. Per-destination search surfaces land in later epics;
    /// today this brings the window forward so the user lands on the workspace.
    @MainActor
    private func runFindCommand() {
        NSApplication.shared.activate(ignoringOtherApps: true)
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

    /// Handles a `vaultpeek://` deep link (AND-586). App Intents, widgets, and
    /// Control Center hand the app a typed `RouteDeepLink` URL; when the
    /// window-first shell is enabled this parses it into a `Route` and routes the
    /// primary window there via the single reusable entry point
    /// (`AppState.route(to:openWindow:)`) — so "Show Spending" lands on Budgets,
    /// "Review Transactions" lands on Review, etc. When the flag is OFF (or the URL
    /// carries no recognizable route) it falls back to the existing
    /// open-the-dashboard behavior, so installed widgets keep working unchanged.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard isWindowFirstEnabled, let route = RouteDeepLink.route(from: url) else {
            openDashboardFromDeepLink()
            return
        }
        appState.route(to: route) {
            openWindow(id: Self.mainWindowID)
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

    /// The in-app text-size preference forced by the `--text-size` CLI flag
    /// (QA/screenshot aid: `--text-size default|large|xLarge|accessibility`), or
    /// `nil` to follow the stored preference. Mirrors `forcedColorScheme`; lets a
    /// QA pass cover the enlarged layouts without leaving a durable preference
    /// behind (AND-570).
    static var forcedTextSizePreference: TextSizePreference? {
        CommandLineOptions.value(for: "--text-size").flatMap(TextSizePreference.init(rawValue:))
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

/// Applies the stored in-app text-size preference as a `dynamicTypeSize`
/// environment value at the scene root, so every `@ScaledMetric`/`Text` below it
/// scales together (AND-570). macOS ignores the system Dynamic Type setting for
/// third-party apps, so this is the only lever users have to enlarge VaultPeek's
/// text. The `--text-size` CLI override (QA aid) wins over the stored preference,
/// mirroring `ForcedAppColorScheme`. Reading `@AppStorage` here means the whole
/// subtree re-renders live the moment the Settings picker changes the value.
struct AppTextSizeApplier: ViewModifier {
    @AppStorage(TextSizePreference.storageKey) private var preferenceRaw = TextSizePreference.defaultValue.rawValue

    private var resolvedSize: DynamicTypeSize {
        let stored = TextSizePreference(rawValue: preferenceRaw) ?? .default
        let forced = TextSizePreference.resolved(
            cliOverride: PlaidBarApp.forcedTextSizePreference,
            storedPreference: stored
        )
        return DynamicTypeSize(forced)
    }

    func body(content: Content) -> some View {
        content.dynamicTypeSize(resolvedSize)
    }
}

/// Bridges the SwiftUI-free Core `ForcedDynamicTypeSize` to SwiftUI's
/// `DynamicTypeSize`. The Core enum keeps the case → size decision testable
/// without importing SwiftUI; this 1:1 switch is the only place the two enums
/// meet (parity with `ForcedColorScheme` → `ColorScheme`).
extension DynamicTypeSize {
    init(_ forced: ForcedDynamicTypeSize) {
        switch forced {
        case .large: self = .large
        case .xLarge: self = .xLarge
        case .xxLarge: self = .xxLarge
        case .accessibility1: self = .accessibility1
        }
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

extension View {
    /// Applies the stored in-app text-size preference at this point in the tree
    /// (AND-570). Used at every scene/window root — the popover, Settings, and
    /// the three detached AppKit-hosted windows — so the choice scales every
    /// surface uniformly. Internal (not file-private) so the window controllers
    /// in `App/` can share the one definition.
    func appliesAppTextSize() -> some View {
        modifier(AppTextSizeApplier())
    }
}
