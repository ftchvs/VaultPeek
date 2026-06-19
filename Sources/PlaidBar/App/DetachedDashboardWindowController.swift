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
    /// Invoked whenever the detached panel becomes key (the user focuses the
    /// window). The owner uses it to drive the App Lock unlock prompt, mirroring
    /// the popover-open unlock trigger so a locked app with a detached window is
    /// not stuck (AND-462). The controller stays unaware of lock policy.
    private let onWindowBecomeKey: @MainActor () -> Void

    private var panel: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    /// Monotonic counter bumped on every `show`/`raise`. A pending hide
    /// fade-out captures the value at the time it started and only orders the
    /// panel out if it is still the latest — so quickly re-showing the window
    /// while a hide animation is in flight cannot order out the freshly-shown
    /// panel (which would leave `isDashboardDetached == true` with no window).
    private var presentationGeneration = 0
    /// Observes `UserDefaults.didChangeNotification` so the window picks up live
    /// changes to the "keep on top" preference (and re-asserts its resize floor)
    /// without a re-dock.
    ///
    /// No `deinit` removal: this controller is owned by the app scene's
    /// process-lifetime `DetachedDashboardCoordinator`, so it is never
    /// deallocated during a run, and a nonisolated `deinit` cannot legally touch
    /// this main-actor, non-`Sendable` token under Swift 6 anyway. The closure
    /// captures `self` weakly, so even an orphaned observation is a harmless
    /// no-op.
    private var selectionObserver: NSObjectProtocol?
    /// Observes the panel's `didBecomeKeyNotification` so focusing the detached
    /// window triggers the App Lock unlock prompt (AND-462). Scoped to the panel
    /// object so it never fires for other windows. Same no-`deinit` rationale as
    /// `selectionObserver`: the controller lives for the process and the closure
    /// captures `self` weakly.
    private var becomeKeyObserver: NSObjectProtocol?
    /// True while this window holds a `.regular` activation request with the shared
    /// `AppActivationPolicyCoordinator` (managed mode only). Tracked so show/raise
    /// request exactly once and re-dock releases exactly once.
    private var holdsRegularRequest = false

    init(
        appState: AppState,
        forcedColorScheme: ColorScheme?,
        onRedock: @escaping @MainActor () -> Void,
        onWindowBecomeKey: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.forcedColorScheme = forcedColorScheme
        self.onRedock = onRedock
        self.onWindowBecomeKey = onWindowBecomeKey
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
            bringWindowForward(panel)
        } else {
            panel.alphaValue = 0
            bringWindowForward(panel)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        }
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
        bringWindowForward(panel)
    }

    // MARK: - Activation policy & window level

    /// Whether the user wants the floating dashboard to stay above other windows
    /// (a non-activating glance HUD) instead of behaving as a normal managed
    /// window. Read from UserDefaults so the SettingsView `@AppStorage` toggle and
    /// the window stay in sync via the defaults-change observer.
    private var keepDashboardOnTop: Bool {
        UserDefaults.standard.bool(forKey: DetachedDashboardPreferences.keepOnTopStorageKey)
    }

    /// Apply the window level + Spaces behavior for the current "keep on top"
    /// preference: a floating, all-Spaces glance HUD when on; a managed normal
    /// window (one Space, default collection behavior) when off.
    private func applyWindowLevelBehavior(to panel: NSWindow) {
        if keepDashboardOnTop {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        } else {
            panel.level = .normal
            panel.collectionBehavior = []
        }
    }

    /// Order the window in. In "keep on top" mode it floats above without stealing
    /// focus from the active app (a glance HUD); otherwise it becomes a regular,
    /// frontmost app window with Dock / ⌘-Tab presence.
    private func bringWindowForward(_ panel: NSWindow) {
        if keepDashboardOnTop {
            panel.orderFrontRegardless()
        } else {
            elevateActivationPolicyForWindow()
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Request `.regular` (front + Dock presence) for the window via the shared,
    /// refcounted coordinator. Idempotent: holds at most one request so it does
    /// not double-count or fight the Settings window's own elevation.
    private func elevateActivationPolicyForWindow() {
        guard !holdsRegularRequest else { return }
        holdsRegularRequest = true
        AppActivationPolicyCoordinator.shared.requestRegular()
    }

    /// Release this window's `.regular` request. The coordinator returns the app
    /// to menu-bar-only `.accessory` only when no other surface (e.g. Settings)
    /// still needs `.regular`. No-op when this window held no request (glance mode).
    private func restoreActivationPolicy() {
        guard holdsRegularRequest else { return }
        holdsRegularRequest = false
        AppActivationPolicyCoordinator.shared.releaseRegular()
    }

    // MARK: - Resize floor

    /// Keeps the panel's real resize floor (`contentMinSize`) in step with the
    /// trailing inspector: the SwiftUI `frame(minWidth:)` only constrains layout
    /// *inside* the hosting view, so without this a window already resized down
    /// to the two-column minimum could stay narrower than the three-column
    /// (982pt) layout and clip the inspector when an account is selected.
    private func updateContentMinSize() {
        guard let panel else { return }
        // The inspector column is always present (three-column-always), so the
        // resize floor always reserves it — the window can never be sized narrower
        // than the full three-column layout and clip the empty inspector.
        let minWidth = DetachedDashboardPreferences.minContentWidth(isInspectorOpen: true)
        panel.contentMinSize = CGSize(
            width: minWidth,
            height: DetachedDashboardPreferences.minContentHeight
        )
        // If a restored or pre-existing frame is below the new floor, grow it so
        // the inspector is not clipped.
        if panel.frame.width < minWidth {
            var frame = panel.frame
            // Grow rightward from the existing origin (keeps the left edge put).
            frame.size.width = minWidth
            panel.setFrame(frame, display: true, animate: false)
        }
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
        // Window level + Spaces behavior follow the "keep on top" preference:
        // a managed normal window by default, or a floating glance HUD when the
        // user opts in. Applied here and re-applied live when the toggle changes.
        applyWindowLevelBehavior(to: panel)

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
                    guard let self else { return }
                    self.updateContentMinSize()
                    // Pick up live changes to the "keep on top" toggle so the
                    // window's level / Spaces behavior updates without a re-dock.
                    if let panel = self.panel {
                        self.applyWindowLevelBehavior(to: panel)
                    }
                }
            }
        }

        // App Lock unlock trigger for the detached surface: focusing the window
        // prompts to unlock, mirroring the popover-open trigger so a locked app
        // with a detached window is not stuck (AND-462). Scoped to this panel via
        // the notification `object`, so other windows becoming key are ignored.
        // The owner's callback guards on `isAppLocked` and is a cheap no-op
        // otherwise, so this cannot start a lock/unlock loop.
        if becomeKeyObserver == nil {
            becomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onWindowBecomeKey()
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
        //
        // AND-511 SPIKE — evaluated replacing this NSVisualEffectView with a
        // SwiftUI `.glassEffect(.regular)` (or `.backgroundExtensionEffect`) root
        // painted directly onto the transparent NSWindow. Decision: KEEP the
        // behind-window NSVisualEffectView. SwiftUI glass on a borderless/clear
        // NSWindow does NOT reliably sample what is *behind the window* — it
        // samples within the window's own (clear) backing, so it renders flat
        // instead of frosting the desktop. Behind-window translucency on a hosted
        // NSWindow has regressed in this project before; NSVisualEffectView with
        // `.behindWindow` is the one path confirmed to yield real desktop
        // read-through here, so it stays. The in-content glass chrome
        // (PopoverMaterialBackground / glassSurface) handles the popover host,
        // where there is no window-level vibrancy to sample.
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
                // Apply the in-app text-size preference so the floating desktop
                // dashboard scales with the same control as the popover (AND-570).
                .appliesAppTextSize()
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
