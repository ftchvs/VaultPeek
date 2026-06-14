import AppKit
import PlaidBarCore
import SwiftUI

/// Hosts the dashboard (`MainPopover`) in a floating, draggable desktop window
/// so the user can pull it off the menu bar and move it anywhere (AND-384).
///
/// The window is a non-activating `NSPanel` at `.floating` level: it survives
/// app-switches (it does not vanish on focus loss the way the menu-bar popover
/// does), shows across Spaces, and is movable by dragging anywhere on its
/// surface (`isMovableByWindowBackground`). It hosts the *same* `MainPopover`
/// view bound to the *same* `AppState`, so there is no duplicate data, sync
/// timer, or server client — only a second presentation surface.
///
/// Frame (origin + size) is persisted by AppKit via `frameAutosaveName`, so the
/// window reopens where the user left it. Open/closed intent is persisted
/// separately by `AppState.isDashboardDetached`.
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

    private var panel: NSPanel?
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

        if panel.isVisible {
            raise()
            return
        }

        // Reduce Motion: appear instantly. Otherwise a brief cross-fade in so the
        // window does not pop. The window's content alpha is animated, not a
        // layout move, so it never shifts the dashboard.
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
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
        panel.orderFrontRegardless()
        panel.makeKey()
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

    private func makePanel() -> NSPanel {
        let size = DetachedDashboardPreferences.defaultContentSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            // .nonactivatingPanel keeps the rest of the app from losing focus
            // when the window comes forward; titled/closable/resizable give it
            // standard window chrome (drag, close, resize handles).
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = DetachedDashboardPreferences.windowTitle
        // Float above ordinary windows but below modal panels, so the dashboard
        // stays glanceable over other apps the way the popover does.
        panel.level = .floating
        // Drag the whole surface — the dashboard has no title-bar-only grab area,
        // so the user can move it by grabbing anywhere not interactive (AND-384).
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        // Show on every Space and stay up in full-screen apps, so the dashboard
        // is reachable from wherever the user is working.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .moveToActiveSpace,
        ]
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

        // Appearance for the window chrome. The CLI `--appearance` override
        // wins; otherwise honor the stored app appearance preference so a
        // detached window restored at launch (created from the menu-bar label,
        // before any `.appliesAppAppearance()` scene mounts) follows the user's
        // Light/Dark setting instead of defaulting to the system appearance.
        // `.followSystem` leaves `panel.appearance` nil so AppKit follows the
        // system, matching the rest of the app.
        if let scheme = Self.effectiveColorScheme(forcedColorScheme: forcedColorScheme) {
            panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        }

        // No `.preferredContentSize`: the dashboard fills the resizable panel
        // (maxWidth/maxHeight: .infinity) and the panel's frame drives the
        // hosting view, so dragging the resize handle resizes the content rather
        // than SwiftUI's intrinsic size fighting the user's chosen frame.
        let hosting = NSHostingController(rootView: makeRootView())
        panel.contentViewController = hosting
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
                // Same precedence as the panel chrome: CLI override, else the
                // stored Light/Dark preference, else follow the system.
                .forcedDetachedColorScheme(Self.effectiveColorScheme(forcedColorScheme: forcedColorScheme))
                // The panel owns its own width via resize; let the dashboard fill
                // it rather than imposing the popover's screen-anchored width math.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    /// The color scheme to pin the detached window to: the CLI `--appearance`
    /// override if present, otherwise the stored app appearance preference
    /// (`AppAppearanceMode`), otherwise `nil` to follow the system. Resolving the
    /// stored preference here is what lets a launch-restored detached window
    /// honor Light/Dark before any `.appliesAppAppearance()` scene has mounted.
    static func effectiveColorScheme(forcedColorScheme: ColorScheme?) -> ColorScheme? {
        if let forcedColorScheme { return forcedColorScheme }
        let raw = UserDefaults.standard.string(forKey: AppAppearanceMode.storageKey)
        switch AppAppearanceMode(rawValue: raw ?? "") ?? .followSystem {
        case .followSystem: return nil
        case .light: return .light
        case .dark: return .dark
        }
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
