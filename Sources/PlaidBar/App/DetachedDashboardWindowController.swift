import AppKit
import PlaidBarCore
import SwiftUI

/// Hosts the dashboard (`MainPopover`) in a real, draggable, resizable desktop
/// window so the user can pull it off the menu bar and move it anywhere (AND-384).
///
/// The window is a managed `NSWindow` (titled, closable, miniaturizable,
/// resizable) at the normal window level with the default (Managed) collection
/// behavior, so it drags, resizes, minimizes, tiles, and participates in Mission
/// Control / Spaces / Stage Manager like any first-class app window — *not* a
/// floating utility palette. It is movable by dragging anywhere on its surface
/// (`isMovableByWindowBackground`) and translucent (a behind-window
/// `NSVisualEffectView` backdrop over a non-opaque, clear window) so the desktop
/// shows through. It hosts the *same* `MainPopover` view bound to the *same*
/// `AppState`, so there is no duplicate data, sync timer, or server client — only
/// a second presentation surface.
///
/// Frame (origin + size) is persisted by AppKit via `frameAutosaveName`, so the
/// window reopens where the user left it. Open/closed intent is persisted
/// separately by `AppState.isDashboardDetached`. Window appearance is left to
/// inherit the single `NSApp.appearance` owner (pinned only for the `--appearance`
/// QA override) so flipping Light/Dark updates the window live.
///
/// `@MainActor`-isolated; all AppKit window mutation happens on the main actor,
/// which keeps it correct under `-strict-concurrency=complete`.
@MainActor
final class DetachedDashboardWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let forcedColorScheme: ColorScheme?
    /// Re-docks the dashboard back into the menu-bar popover when the panel is
    /// closed (via the close button or the in-dashboard re-dock control). Set by
    /// the owner so the controller does not reach back into app state policy.
    private let onRedock: @MainActor () -> Void

    private var panel: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    /// Monotonic counter bumped on every `show`/`raise`. A pending hide
    /// fade-out captures the value at the time it started and only orders the
    /// panel out if it is still the latest — so quickly re-showing the window
    /// while a hide animation is in flight cannot order out the freshly-shown
    /// panel (which would leave `isDashboardDetached == true` with no window).
    private var presentationGeneration = 0
    /// Observes `dashboard.selectedAccountId` so the panel's real resize floor
    /// (`contentMinSize`) tracks whether the trailing inspector is showing.
    ///
    /// No `deinit` removal: this controller is owned by the app scene's
    /// process-lifetime `DetachedDashboardCoordinator`, so it is never
    /// deallocated during a run, and a nonisolated `deinit` cannot legally touch
    /// this main-actor, non-`Sendable` token under Swift 6 anyway. The closure
    /// captures `self` weakly, so even an orphaned observation is a harmless
    /// no-op.
    private var selectionObserver: NSObjectProtocol?
    /// The app's activation policy before the detached window was first shown. A
    /// menu-bar app runs `.accessory`; while the floating dashboard is open we flip
    /// to `.regular` so the window comes to the front and gains a Dock / ⌘-Tab
    /// presence (a normal window from an `.accessory` app otherwise opens *behind*
    /// the active app). Restored on re-dock so the app returns to menu-bar-only.
    private var activationPolicyBeforeDetach: NSApplication.ActivationPolicy?

    init(
        appState: AppState,
        forcedColorScheme: ColorScheme?,
        onRedock: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.forcedColorScheme = forcedColorScheme
        self.onRedock = onRedock
        super.init()
    }

    /// True while the floating panel exists and is on screen.
    var isPresented: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Lifecycle

    /// Shows the floating dashboard, creating the panel on first use. Idempotent:
    /// when the panel already exists it is raised and re-focused instead of
    /// recreated, so a second "detach" or a status-item click while detached
    /// just brings the existing window forward (no duplicate windows).
    func show(reduceMotion: Bool) {
        let panel = panel ?? makePanel()
        self.panel = panel

        // A show supersedes any in-flight hide: bump the generation so a pending
        // fade-out completion does not order this panel back out.
        presentationGeneration += 1
        // Make sure the resize floor reflects the current inspector state before
        // the window appears (a launch-restore could already have a selection).
        updateContentMinSize()
        // Become a regular app while the window is up so it comes to the front
        // and is reachable from the Dock / ⌘-Tab; restored to the prior policy
        // (menu-bar-only `.accessory`) on re-dock.
        elevateActivationPolicyForWindow()

        if panel.isVisible {
            raise()
            return
        }

        // Reduce Motion: appear instantly. Otherwise a brief cross-fade in so the
        // window does not pop. The window's content alpha is animated, not a
        // layout move, so it never shifts the dashboard.
        if reduceMotion {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        }
        // Force the window to the front. `ignoringOtherApps: true` matches the
        // proven `SettingsWindowActivationRestorer` path; the cooperative
        // `activate()` does not steal focus, so the window would otherwise open
        // behind the active app.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Hides the floating dashboard without tearing it down, so the next `show`
    /// is instant and the hosted SwiftUI state survives. Respects Reduce Motion.
    func hide(reduceMotion: Bool) {
        guard let panel, panel.isVisible else { return }

        if reduceMotion {
            panel.orderOut(nil)
            restoreActivationPolicy()
        } else {
            // Capture the generation this hide belongs to; if a `show`/`raise`
            // bumps it before the fade completes, the panel was re-presented and
            // must NOT be ordered out by this stale completion.
            let hideGeneration = presentationGeneration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    guard let self, self.presentationGeneration == hideGeneration else {
                        // Superseded by a newer show/raise — leave it visible.
                        panel?.alphaValue = 1
                        return
                    }
                    panel?.orderOut(nil)
                    panel?.alphaValue = 1
                    // The window is actually gone now — return the app to its
                    // prior (menu-bar-only) activation policy.
                    self.restoreActivationPolicy()
                }
            }
        }
    }

    /// Brings an already-visible panel to the front and gives it key focus, so a
    /// click on the menu-bar item while detached surfaces the window instead of
    /// opening the popover.
    func raise() {
        guard let panel else { return }
        // A raise also supersedes an in-flight hide.
        presentationGeneration += 1
        panel.alphaValue = 1
        elevateActivationPolicyForWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Activation policy

    /// Flip the app to `.regular` while the detached window is on screen, saving
    /// the prior policy once so re-dock can restore it. A normal window from an
    /// `.accessory` (menu-bar) app otherwise opens behind the active app and never
    /// takes focus. Idempotent.
    private func elevateActivationPolicyForWindow() {
        if activationPolicyBeforeDetach == nil {
            activationPolicyBeforeDetach = NSApp.activationPolicy()
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// Restore the activation policy captured before the window was shown
    /// (menu-bar `.accessory`), so closing the window returns the app to
    /// menu-bar-only. No-op when nothing was captured.
    private func restoreActivationPolicy() {
        guard let prior = activationPolicyBeforeDetach else { return }
        activationPolicyBeforeDetach = nil
        if NSApp.activationPolicy() != prior {
            NSApp.setActivationPolicy(prior)
        }
    }

    // MARK: - Resize floor

    /// Keeps the panel's real resize floor (`contentMinSize`) in step with the
    /// trailing inspector: the SwiftUI `frame(minWidth:)` only constrains layout
    /// *inside* the hosting view, so without this a window already resized down
    /// to the two-column minimum could stay narrower than the three-column
    /// (982pt) layout and clip the inspector when an account is selected.
    private func updateContentMinSize() {
        guard let panel else { return }
        let inspectorOpen = !Self.selectedAccountId().isEmpty
        let minWidth = DetachedDashboardPreferences.minContentWidth(isInspectorOpen: inspectorOpen)
        panel.contentMinSize = CGSize(
            width: minWidth,
            height: DetachedDashboardPreferences.minContentHeight
        )
        // If the user had already shrunk the window below the new floor, grow it
        // so the inspector is not clipped the instant it opens.
        if panel.frame.width < minWidth {
            var frame = panel.frame
            // Grow rightward from the existing origin (keeps the left edge put).
            frame.size.width = minWidth
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    private static func selectedAccountId() -> String {
        UserDefaults.standard.string(forKey: "dashboard.selectedAccountId") ?? ""
    }

    // MARK: - Panel construction

    private func makePanel() -> NSWindow {
        let size = DetachedDashboardPreferences.defaultContentSize

        // A real, managed desktop window — deliberately NOT an NSPanel. An
        // NSPanel at `.floating` level with `.utilityWindow`/`.nonactivatingPanel`
        // is a floating palette: it sits above every app, shows on all Spaces,
        // can't minimize, and is invisible to Mission Control / Stage Manager /
        // window tiling — exactly what made the dashboard "feel stuck to the menu
        // bar." A titled, miniaturizable, resizable `NSWindow` at the normal level
        // with the default (Managed) collection behavior drags, resizes,
        // minimizes, tiles, and lives on one Space like a first-class window.
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = DetachedDashboardPreferences.windowTitle
        // Drag the whole surface — the dashboard has no title-bar-only grab area,
        // so the user can move it by grabbing anywhere not interactive (AND-384).
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Chrome-light look: keep the traffic lights but let the dashboard content
        // run to the top edge (the AppKit equivalent of
        // `.windowStyle(.hiddenTitleBar)`).
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // Leave `level` at `.normal` and `collectionBehavior` at its default
        // (Managed): the window lives on one Space in normal z-order and
        // Mission-Controls / Stage-Manages / tiles normally. A non-normal level or
        // `.canJoinAllSpaces` is what made the old panel behave like a HUD.

        // True translucency: an opaque window fully paints its rect, so the
        // material/glass had only the window's own solid backing to sample and
        // rendered flat/gray. A non-opaque, clear window plus the behind-window
        // `NSVisualEffectView` backdrop (added below) lets the desktop show
        // through with a real frosted blur (AND-384).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.contentMinSize = DetachedDashboardPreferences.minContentSize
        panel.delegate = self

        // Keep the resize floor in step with account selection while the window
        // is open: selecting an account opens the inspector, which needs the
        // wider three-column floor. `dashboard.selectedAccountId` is the same
        // `@AppStorage` key `MainPopover` drives, so observing UserDefaults
        // reflects both in-window selection and persisted restores.
        if selectionObserver == nil {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateContentMinSize()
                }
            }
        }

        // Leave `panel.appearance == nil` so the window inherits the single
        // `NSApp.appearance` owner live — flipping Light/Dark in Settings updates
        // the detached window while it is open. Pin explicitly ONLY for the
        // `--appearance` CLI QA override, which `AppAppearance.applyToNSApp`
        // deliberately leaves off `NSApp.appearance`.
        if let forcedColorScheme {
            panel.appearance = NSAppearance(named: forcedColorScheme == .dark ? .darkAqua : .aqua)
        }

        // Behind-window vibrancy backdrop: `.behindWindow` samples the desktop
        // (the only blending mode that yields real translucency) and `.active`
        // keeps the blur even when this window is not key. The hosted SwiftUI
        // fills it edge-to-edge; while detached, `MainPopover` renders a clear
        // root background so this backdrop *is* the translucent surface rather
        // than an opaque material painted over an opaque window.
        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active

        let hosting = NSHostingController(rootView: makeRootView())
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        panel.contentView = backdrop
        self.hostingController = hosting

        // Restore the persisted frame (origin + size) if one exists; otherwise
        // center the default-sized window. setFrameUsingName returns false the
        // first time, before any frame has been autosaved.
        panel.setFrameAutosaveName(DetachedDashboardPreferences.frameAutosaveName)
        if !panel.setFrameUsingName(DetachedDashboardPreferences.frameAutosaveName) {
            panel.setContentSize(size)
            panel.center()
        }

        return panel
    }

    /// The hosted dashboard: the SAME `MainPopover` the menu-bar popover shows,
    /// bound to the SAME `AppState`. A re-dock affordance is injected via the
    /// environment so the dashboard's pin control can return to popover mode
    /// without the view knowing about AppKit windows.
    private func makeRootView() -> AnyView {
        AnyView(
            MainPopover()
                .environment(appState)
                .environment(\.dashboardPresentation, .detached(redock: { [weak self] in
                    self?.onRedock()
                }))
                // Pin the SwiftUI color scheme ONLY for the `--appearance` CLI QA
                // override; otherwise leave it unset so the content inherits the
                // window's live (NSApp-driven) appearance and follows Light/Dark
                // changes made while the window is open.
                .forcedDetachedColorScheme(forcedColorScheme)
                // The panel owns its own width via resize; let the dashboard fill
                // it rather than imposing the popover's screen-anchored width math.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    // MARK: - NSWindowDelegate

    /// Closing the window (red close button) re-docks to the popover, so the
    /// menu-bar item resumes opening the popover and the toggle reflects reality.
    /// `windowShouldClose` lets the owner drive teardown through the same
    /// `onRedock` path the in-dashboard control uses, keeping one source of truth
    /// for the detached → docked transition.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onRedock()
        // Return false: the owner hides the panel through `hide(reduceMotion:)`
        // as part of re-docking, so we never let AppKit destroy the panel and its
        // hosted SwiftUI state out from under us.
        return false
    }
}

// MARK: - Forced appearance helper

private extension View {
    /// Mirrors `PlaidBarApp`'s `--appearance` CLI override into the hosted
    /// dashboard so the floating window honors the same forced light/dark pin as
    /// the popover and Settings (QA aid / AND-365 parity).
    @ViewBuilder
    func forcedDetachedColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
