import AppKit
import PlaidBarCore
import SwiftUI

/// Process-lifetime hand-off from the SwiftUI `App` (which owns init ordering /
/// appearance-before-paint and the `Settings` scene) to the AppKit
/// `MenuBarAppDelegate` (which `@NSApplicationDelegateAdaptor` constructs itself,
/// so it can't be handed dependencies via init). `PlaidBarApp.init` fills this in
/// on the main thread; the delegate reads it in `applicationDidFinishLaunching`,
/// which always runs after `App.init`.
@MainActor
enum MenuBarAppContext {
    static var appState: AppState?
    static var detachedDashboard: DetachedDashboardCoordinator?
    static var updaterController: SPUUpdaterControlling?
    static var contextMenuController: StatusItemContextMenuController?
    static var forcedColorScheme: ColorScheme?
}

/// Minimal protocol so the context can hold the Sparkle updater controller
/// without this file importing Sparkle (the App already owns the real one).
@MainActor
protocol SPUUpdaterControlling: AnyObject {
    func checkForUpdatesFromMenu()
}

/// Owns the menu-bar `NSStatusItem` and the `NSPopover` that hosts `MainPopover`.
///
/// Replaces SwiftUI `MenuBarExtra(.window)` (which cannot be made translucent —
/// Apple exposes no API for its window background). An `NSPopover` renders the
/// native frosted-glass popover material for free; we only need a clear content
/// root. Every behavior MenuBarExtra used to provide off the always-mounted
/// label is re-homed here so none silently break.
@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var labelHostingView: NSView?

    // Click-away dismissal needs BOTH monitors: global catches clicks in other
    // apps, local catches clicks in our own other windows (Settings / detached).
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyDownMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// Guards the observation bridge against re-entrancy (show/close write the
    /// same flag they observe).
    private var isSyncingPresentation = false

    private var appState: AppState? { MenuBarAppContext.appState }
    private var detachedDashboard: DetachedDashboardCoordinator? { MenuBarAppContext.detachedDashboard }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else { return }

        setUpStatusItem(appState: appState)
        setUpPopover(appState: appState)
        configureContextMenu(appState: appState)
        installLifecycleObservers(appState: appState)
        bridgePresentationFlag(appState: appState)

        // Restore a persisted detached window, then honor the --detach QA flag,
        // mirroring the old always-mounted-label .task (AND-384).
        detachedDashboard?.sync(
            appState: appState,
            forcedColorScheme: MenuBarAppContext.forcedColorScheme,
            reduceMotion: reduceMotion
        )
        if CommandLine.arguments.contains("--detach") {
            detachedDashboard?.presentForLaunchOverride(
                appState: appState,
                forcedColorScheme: MenuBarAppContext.forcedColorScheme,
                reduceMotion: reduceMotion
            )
        }
    }

    /// vaultpeek:// deep link (widget / external). Raises the detached window if
    /// detached, otherwise opens the popover via the presentation flag.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let appState, urls.contains(where: { $0.scheme == "vaultpeek" }) else { return }
        if detachedDashboard?.handleMenuBarActivation(
            appState: appState,
            forcedColorScheme: MenuBarAppContext.forcedColorScheme,
            reduceMotion: reduceMotion
        ) == true {
            return
        }
        appState.isPopoverPresented = true
    }

    // MARK: - Status item

    private func setUpStatusItem(appState: AppState) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        let host = NSHostingView(
            rootView: MenuBarLabel()
                .environment(appState)
                .forcedAppColorScheme(MenuBarAppContext.forcedColorScheme)
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        labelHostingView = host

        button.target = self
        button.action = #selector(togglePopover)
        // Right-click is owned by StatusItemContextMenuController's local
        // monitor; only route LEFT clicks here to avoid a down/up double-fire.
        button.sendAction(on: [.leftMouseUp])

        statusItem = item
    }

    // MARK: - Popover

    private func setUpPopover(appState: AppState) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MainPopover()
                .environment(appState)
                .environment(\.dashboardPresentation, .popover(detach: { [weak self] in
                    guard let self, let appState = self.appState else { return }
                    self.detachedDashboard?.detach(
                        appState: appState,
                        forcedColorScheme: MenuBarAppContext.forcedColorScheme,
                        reduceMotion: self.reduceMotion
                    )
                }))
                .forcedAppColorScheme(MenuBarAppContext.forcedColorScheme)
        )
        self.popover = popover
    }

    private func configureContextMenu(appState: AppState) {
        guard let statusItem, let controller = MenuBarAppContext.contextMenuController else { return }
        controller.configure(
            statusItem: statusItem,
            actions: StatusItemContextMenuActions(
                showDashboard: { [weak self] in self?.showDashboardFromMenu() },
                openInWindow: { [weak self] in
                    guard let self, let appState = self.appState else { return }
                    self.detachedDashboard?.detach(
                        appState: appState,
                        forcedColorScheme: MenuBarAppContext.forcedColorScheme,
                        reduceMotion: self.reduceMotion
                    )
                },
                refreshDashboard: { Task { await appState.refreshDashboard() } },
                openSettings: { SettingsWindowActivationRestorer.shared.open() },
                checkForUpdates: { MenuBarAppContext.updaterController?.checkForUpdatesFromMenu() },
                showAbout: {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                dismissPopover: { [weak self] in self?.closePopover() }
            )
        )
    }

    private func showDashboardFromMenu() {
        guard let appState else { return }
        // "Open VaultPeek" raises the floating window when detached (AND-384),
        // otherwise opens the popover. The menu has no SwiftUI observer behind
        // it, so open the popover explicitly here.
        if detachedDashboard?.handleMenuBarActivation(
            appState: appState,
            forcedColorScheme: MenuBarAppContext.forcedColorScheme,
            reduceMotion: reduceMotion
        ) == true {
            return
        }
        showPopover()
    }

    // MARK: - Toggle / show / close

    @objc private func togglePopover() {
        guard let appState else { return }
        // Detach intercept FIRST: a click while detached raises the floating
        // window instead of the popover (AND-384). handleMenuBarActivation
        // returns true when it consumed the click.
        if detachedDashboard?.handleMenuBarActivation(
            appState: appState,
            forcedColorScheme: MenuBarAppContext.forcedColorScheme,
            reduceMotion: reduceMotion
        ) == true {
            return
        }
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A .transient popover doesn't become key under LSUIElement/.accessory,
        // so TextField focus / Esc would be dead — activate + make key.
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        button.isHighlighted = true
        setPresented(true)
        // App Lock: opening while locked prompts auth (no-op otherwise). Driven
        // from popover-open ONLY, never didBecomeActive, so the auth sheet's
        // app-deactivation can't start a lock/unlock loop (AND-462).
        if appState?.isAppLocked == true {
            Task { [weak appState] in await appState?.unlockApp() }
        }
        installClickMonitors()
    }

    private func closePopover() {
        guard let popover else { return }
        popover.performClose(nil)
        statusItem?.button?.isHighlighted = false
        setPresented(false)
        removeClickMonitors()
    }

    /// Writes the canonical flag without re-triggering the observation bridge.
    private func setPresented(_ value: Bool) {
        isSyncingPresentation = true
        appState?.isPopoverPresented = value
        isSyncingPresentation = false
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.isHighlighted = false
        setPresented(false)
        removeClickMonitors()
    }

    // MARK: - Click-away + Esc

    private func installClickMonitors() {
        removeClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            // Dismiss when the click lands in another VaultPeek window (Settings,
            // detached). Clicks inside the popover keep it open.
            MainActor.assumeIsolated {
                if let self, event.window !== self.popover?.contentViewController?.view.window {
                    self.closePopover()
                }
            }
            return event
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Esc closes the popover when nothing inside consumes it first
            // (MainPopover's inspector handles Esc-to-deselect before this).
            guard event.keyCode == 53 else { return event }
            var handled = false
            MainActor.assumeIsolated {
                if let self, self.popover?.isShown == true {
                    self.closePopover()
                    handled = true
                }
            }
            return handled ? nil : event
        }
    }

    private func removeClickMonitors() {
        for monitor in [globalClickMonitor, localClickMonitor, keyDownMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalClickMonitor = nil
        localClickMonitor = nil
        keyDownMonitor = nil
    }

    // MARK: - Lifecycle observers (re-homed from the always-mounted label)

    private func installLifecycleObservers(appState: AppState) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in _ = await appState.consumePendingGlanceCommand() }
        })
        // Lock on focus loss. CRITICALLY does NOT close the popover — closing on
        // resign would tear down the popover the user is unlocking when the auth
        // sheet deactivates the app (AND-462). Transient + monitors own dismissal.
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { appState.lockOnResignActiveIfNeeded() }
        })
        // Live appearance updater: process-lifetime, so it can't live in the
        // (lazily mounted) popover content. Re-apply NSApp.appearance whenever
        // the stored mode changes. Cheap and a no-op under the --appearance flag.
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppAppearance.applyToNSApp(
                    modeRaw: UserDefaults.standard.string(forKey: AppAppearanceMode.storageKey)
                        ?? AppAppearanceMode.defaultValue.rawValue
                )
            }
        })
    }

    // MARK: - Presentation flag bridge (flag-only callers: --show-popover, deep link, snapshot)

    private func bridgePresentationFlag(appState: AppState) {
        armPresentationObservation(appState: appState)
    }

    /// Re-arming `withObservationTracking`: each change fires once, so re-arm on
    /// the main actor after responding. Uses a method (not a self-capturing local
    /// func) so the `@Sendable` onChange closure only captures Sendable values.
    private func armPresentationObservation(appState: AppState) {
        withObservationTracking {
            _ = appState.isPopoverPresented
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.respondToPresentationFlag(appState.isPopoverPresented)
                self.armPresentationObservation(appState: appState)
            }
        }
    }

    private func respondToPresentationFlag(_ isPresented: Bool) {
        guard !isSyncingPresentation else { return }
        if isPresented {
            // A flag-only open while detached must raise the window, not the popover.
            if let appState, detachedDashboard?.handleMenuBarActivation(
                appState: appState,
                forcedColorScheme: MenuBarAppContext.forcedColorScheme,
                reduceMotion: reduceMotion
            ) == true {
                setPresented(false)
                return
            }
            showPopover()
        } else if popover?.isShown == true {
            closePopover()
        }
    }
}
