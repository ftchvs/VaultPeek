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
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                MainActor.assumeIsolated {
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
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
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

        if let forcedColorScheme {
            panel.appearance = NSAppearance(named: forcedColorScheme == .dark ? .darkAqua : .aqua)
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
