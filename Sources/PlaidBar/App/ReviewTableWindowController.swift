import AppKit
import PlaidBarCore
import SwiftUI

/// Hosts the detached multi-select **review Table** (`ReviewTableWindow`) in a
/// real, managed desktop window (AND-532) — the power-review surface that pulls the
/// popover's Review Inbox into its own resizable window with a multi-select
/// `Table`, a per-row context menu, and bulk recategorize.
///
/// This deliberately reuses the proven ``CategoryDashboardWindowController`` pattern
/// (AND-539 / AND-384): a titled / closable / miniaturizable / resizable `NSWindow`
/// (not an `NSPanel`) at the normal level so it drags, resizes, minimizes, tiles,
/// and participates in Mission Control / Spaces / Stage Manager like a first-class
/// app window; a non-opaque, clear window over a behind-window `NSVisualEffectView`
/// backdrop for real desktop read-through; frame persisted via `frameAutosaveName`;
/// and `.regular` activation requested through the shared, refcounted
/// ``AppActivationPolicyCoordinator`` so the menu-bar-only app comes to the front
/// while the window is up and returns to `.accessory` when no surface needs it.
///
/// It carries a **distinct window identity** (title + `frameAutosaveName`) from the
/// Category Dashboard window so the two persist and restore independently. It hosts
/// the *same* `AppState`, so there is no duplicate data, sync timer, or server
/// client — only a second presentation surface; `isReleasedWhenClosed` is false so
/// closing hides (not destroys) the window and its SwiftUI state survives.
///
/// `@MainActor`-isolated; all AppKit mutation is on the main actor, correct under
/// `-strict-concurrency=complete`.
@MainActor
final class ReviewTableWindowController: NSObject, NSWindowDelegate {
    /// Dedicated window identity — distinct from the Category Dashboard window.
    static let windowTitle = "Review Transactions"
    static let frameAutosaveName = "VaultPeekReviewTable"
    static let defaultContentSize = CGSize(width: 760, height: 560)
    static let minContentSize = CGSize(width: 560, height: 420)

    private let appState: AppState
    private let forcedColorScheme: ColorScheme?
    /// Invoked when the window becomes key (focused). The owner uses it to drive the
    /// App Lock unlock prompt, mirroring the popover-open and dashboard-window
    /// triggers so a locked app with this window open is not stuck (AND-462). The
    /// controller stays unaware of lock policy.
    private let onWindowBecomeKey: @MainActor () -> Void

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var becomeKeyObserver: NSObjectProtocol?
    /// True while this window holds a `.regular` activation request. Tracked so show
    /// requests exactly once and close releases exactly once.
    private var holdsRegularRequest = false

    init(
        appState: AppState,
        forcedColorScheme: ColorScheme?,
        onWindowBecomeKey: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.forcedColorScheme = forcedColorScheme
        self.onWindowBecomeKey = onWindowBecomeKey
        super.init()
    }

    /// True while the window exists and is on screen.
    var isPresented: Bool { window?.isVisible ?? false }

    // MARK: - Lifecycle

    /// Shows the window, creating it on first use. Idempotent: an existing window is
    /// raised and re-focused rather than recreated, so a second "Open review table"
    /// just brings the window forward (no duplicate windows).
    func show() {
        let window = window ?? makeWindow()
        self.window = window
        elevateActivationPolicy()
        bringForward(window)
    }

    /// Hides the window without tearing it down, so the next `show` is instant and
    /// the hosted SwiftUI state (including the current selection) survives.
    func hide() {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
        restoreActivationPolicy()
    }

    // MARK: - Activation policy

    private func elevateActivationPolicy() {
        guard !holdsRegularRequest else { return }
        holdsRegularRequest = true
        AppActivationPolicyCoordinator.shared.requestRegular()
    }

    private func restoreActivationPolicy() {
        guard holdsRegularRequest else { return }
        holdsRegularRequest = false
        AppActivationPolicyCoordinator.shared.releaseRegular()
    }

    private func bringForward(_ window: NSWindow) {
        elevateActivationPolicy()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = Self.windowTitle
        window.titlebarAppearsTransparent = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentMinSize = Self.minContentSize
        window.delegate = self

        // App Lock unlock trigger: focusing the window prompts to unlock, mirroring
        // the popover-open and Category Dashboard window triggers (AND-462). Scoped
        // to this window via the notification `object` so other windows are ignored.
        // The owner's callback guards on `isAppLocked`, so this cannot loop.
        if becomeKeyObserver == nil {
            becomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onWindowBecomeKey() }
            }
        }

        // Pin appearance ONLY for the `--appearance` CLI QA override; otherwise
        // inherit the live `NSApp.appearance` so Light/Dark flips update the window.
        if let forcedColorScheme {
            window.appearance = NSAppearance(named: forcedColorScheme == .dark ? .darkAqua : .aqua)
        }

        // Behind-window vibrancy backdrop: `.behindWindow` is the one blending mode
        // confirmed to yield real desktop read-through on a hosted NSWindow in this
        // project (mirrors CategoryDashboardWindowController / the AND-511 spike).
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
        window.contentView = backdrop
        self.hostingController = hosting

        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.setContentSize(Self.defaultContentSize)
            window.center()
        }
        return window
    }

    private func makeRootView() -> AnyView {
        AnyView(
            ReviewTableWindow()
                .environment(appState)
                .forcedReviewTableColorScheme(forcedColorScheme)
                // Scale the detached review Table with the same in-app text-size
                // preference as every other surface (AND-570).
                .appliesAppTextSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    // MARK: - NSWindowDelegate

    /// Closing the window hides it (state survives) and releases the activation
    /// request. Returning false keeps AppKit from destroying the hosted SwiftUI.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

// MARK: - Forced appearance helper

private extension View {
    @ViewBuilder
    func forcedReviewTableColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
