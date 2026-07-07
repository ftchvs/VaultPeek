import AppKit
import PlaidBarCore
import SwiftUI

/// Headless render harness for the window-first shell
/// (`--demo --render-window-first <dir>`, AND-624).
///
/// The live window-first `Window` scene will not present from an automated
/// session (no foreground app, no Screen Recording permission), so it cannot be
/// screenshotted the way `Scripts/screenshots.sh` captures the on-screen
/// popover. This harness rasterizes the window-first content **without any
/// on-screen window and without Screen Recording permission**, mirroring
/// `SnapshotRenderer`'s contract: build a demo `AppState`, write one PNG per
/// surface, and `exit` non-zero when any capture fails so a CI/agent caller
/// never reads missing PNGs as success.
///
/// **What it captures**
/// - `window-<destination>.png` for each of the 9 in-shell destinations
///   (Dashboard, Review, Transactions, Budgets, Planning, Goals, Insights,
///   Alerts, Accounts — `Settings` is the native scene, never an in-split pane,
///   so it is excluded). Each is the routed `DestinationContentView` for that
///   destination, plus its `DestinationInspectorView` for 3-column destinations,
///   composed side-by-side so the inspector is exercised too.
/// - `window-shell.png` — the full `AppShellView` (`NavigationSplitView`:
///   sidebar → content → inspector) for one destination, captured best-effort.
///
/// **Layout strategy (documented).** The capture engine is a **far-off-screen,
/// briefly-presented `NSWindow` + `NSHostingView`, rasterized with
/// `cacheDisplay(in:to:)`** — the same path `SnapshotRenderer` uses for the
/// popover. Two alternatives were tried and rejected against the real views:
///   1. *`ImageRenderer` (window-less, synchronous).* Renders the 3-column
///      destinations (Tables/Lists) fine but leaves the 2-column destinations
///      (Dashboard / Planning / Insights — all `GeometryReader` + `ScrollView`
///      roots) **blank**: `GeometryReader` resolves to zero outside a presented
///      view hierarchy, so its content never lays out.
///   2. *A never-ordered off-screen `NSWindow` + `cacheDisplay`.* Same blank
///      result — without ordering the window front, SwiftUI never runs the
///      presentation/layout cycle that resolves `GeometryReader` / populates
///      `ScrollView` / draws Swift Charts.
/// Ordering the window front at an origin far beyond any physical display
/// (`-50000, -50000`) and pumping the run loop runs the *full* SwiftUI cycle
/// (so charts, scrolled and lazy content all draw) while never appearing on
/// screen and never needing Screen Recording permission. Per-destination
/// content is captured at a content-column-sized 980×800 (composed with the
/// inspector for 3-col destinations); the full `AppShellView` is *additionally*
/// captured at 1280×800 for `window-shell.png`.
///
/// **Fallback note for the full shell.** A headless `NavigationSplitView` lays
/// out its content/detail columns under this path but does **not** populate its
/// sidebar `List` (split-view sidebar geometry leans on a real on-screen
/// presentation). So `window-shell.png` shows the routed content with a blank
/// sidebar column — it is a best-effort whole-shell reference, and the
/// per-destination `window-<destination>.png` images (which never go through the
/// split view) are the contract.
@MainActor
enum WindowFirstSnapshotRenderer {
    /// The in-shell destinations the harness renders, in sidebar order.
    /// `Settings` is excluded (native scene, never an in-split pane), as are
    /// deprecated-in-place destinations (`canonicalRedirect != nil`) — the
    /// router renders their canonical target, so capturing them would emit
    /// pixel-duplicates of the destination they redirect to.
    static let destinations: [RouteDestination] = RouteDestination.allCases.filter {
        $0 != .settings && $0.canonicalRedirect == nil
    }

    /// Number of PNGs a successful run writes: one per destination plus the
    /// whole-shell reference. Exposed so the smoke test asserts the count
    /// without hard-coding it in two places.
    static var expectedImageCount: Int { destinations.count + 1 }

    /// Logical points for the per-destination content captures (content-column
    /// size) and the whole-shell capture (sidebar + content + inspector).
    private static let contentSize = CGSize(width: 980, height: 800)
    private static let shellSize = CGSize(width: 1280, height: 800)

    static func renderIfRequested(appState: AppState) -> Bool {
        guard CommandLine.arguments.contains("--demo"),
              let directory = CommandLineOptions.value(for: CommandLineOptions.renderWindowFirstFlag)
        else { return false }

        Task { @MainActor in
            let failureCount = await render(appState: appState, directory: directory)
            // Non-zero exit when any required capture failed so headless/CI
            // callers do not treat missing PNGs as success.
            exit(Int32(min(failureCount, 1)))
        }
        return true
    }

    /// Returns the number of failed captures (0 == full success).
    private static func render(appState: AppState, directory: String) async -> Int {
        await appState.loadInitialData()

        let directoryURL = URL(
            fileURLWithPath: (directory as NSString).expandingTildeInPath,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            print("window-first: could not create \(directoryURL.path): \(error.localizedDescription)")
            return 2
        }

        let scheme = PlaidBarApp.forcedColorScheme
        var failureCount = 0

        // One PNG per destination: the routed content view (plus inspector for
        // 3-column destinations), rendered directly at content-column size.
        for destination in destinations {
            // Route the per-window model to this destination so any view that
            // reads `navigationModel.destination` (or a restored selection)
            // matches the surface being captured.
            appState.navigationModel.go(to: destination)

            // Give the just-routed views a turn of the run loop to settle any
            // `.task`/`.onChange` work before the synchronous render.
            await settle()

            let url = directoryURL.appendingPathComponent("window-\(destination.rawValue).png")
            let view = destinationContent(for: destination, appState: appState, scheme: scheme)
            if !(await render(view, size: contentSize, scheme: scheme, to: url)) {
                failureCount += 1
            }
        }

        // Whole-shell reference (best-effort). Route to Dashboard so the shell
        // opens on a populated 2-column surface. A column-collapsed shell here is
        // a known headless `NavigationSplitView` limitation and is NOT counted as
        // a failure — the per-destination images above are the contract.
        appState.navigationModel.go(to: .dashboard)
        await settle()
        let shell = AppShellView()
            .environment(appState)
            .applyForcedScheme(scheme)
        let shellURL = directoryURL.appendingPathComponent("window-shell.png")
        if !(await render(shell, size: shellSize, scheme: scheme, to: shellURL)) {
            failureCount += 1
        }

        return failureCount
    }

    /// The routed content for a destination, composed with its inspector for
    /// 3-column destinations so the detail pane is exercised too. Wrapped with
    /// the demo `AppState` environment and the forced color scheme.
    private static func destinationContent(
        for destination: RouteDestination,
        appState: AppState,
        scheme: ColorScheme?
    ) -> AnyView {
        let composed: AnyView
        if destination.prefersThreeColumnLayout {
            composed = AnyView(
                HStack(spacing: 0) {
                    DestinationContentView(destination: destination)
                        .frame(maxWidth: .infinity)
                    Divider()
                    DestinationInspectorView(destination: destination)
                        .frame(width: 320)
                }
            )
        } else {
            // 2-column destinations are `GeometryReader { … ScrollView … }`
            // roots; the hosting window's size flows into them once the window
            // is presented (see `render`). No special wrapping needed.
            composed = AnyView(DestinationContentView(destination: destination))
        }

        return AnyView(
            composed
                .environment(appState)
                .applyForcedScheme(scheme)
        )
    }

    /// Renders a SwiftUI view to a PNG at `size` by hosting it in a far-off-screen
    /// `NSWindow`, ordering the window front (so SwiftUI runs the full
    /// presentation/layout cycle that populates `GeometryReader` / `ScrollView` /
    /// Swift Charts), pumping the run loop, and rasterizing the hosting view with
    /// `cacheDisplay`. Returns `true` when the PNG was written. Mirrors
    /// `SnapshotRenderer.captureView`'s failure semantics and logging family.
    private static func render(
        _ view: some View,
        size: CGSize,
        scheme: ColorScheme?,
        to url: URL
    ) async -> Bool {
        let framed = view
            // Opaque platform backdrop so transparent chrome (the window-first
            // glass composites against the window) reads as the window
            // background rather than a transparent/checkerboard PNG.
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(width: size.width, height: size.height, alignment: .topLeading)

        // Host in a real (but far-off-screen) window and let AppKit/SwiftUI run
        // the full presentation + layout cycle, then `cacheDisplay`. This is the
        // path `SnapshotRenderer` uses for the popover, which likewise contains
        // `ScrollView` + Swift Charts + materials; an `ImageRenderer`-only path
        // leaves `GeometryReader`-rooted 2-column destinations blank because
        // `GeometryReader` resolves to zero outside a presented hierarchy.
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(origin: .zero, size: size)

        let offscreenOrigin = NSPoint(x: -50_000, y: -50_000)
        let window = NSWindow(
            contentRect: NSRect(origin: offscreenOrigin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // ARC owns the window; opt out of the MRR-era release-on-close so the
        // teardown does not double-free (the autorelease-pool over-release that
        // crashed the harness when looping over many windows).
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        if let scheme {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        }
        window.contentView = hosting
        window.setFrameOrigin(offscreenOrigin)
        window.orderFrontRegardless()

        // Let the main run loop process so SwiftUI mounts, runs
        // `.task`/`.onAppear`, resolves `GeometryReader` sizes, and draws
        // charts/lazy content before capture. The window is ordered front, so
        // suspending this `@MainActor` task hands the run loop time to do that
        // work — no manual run-loop pumping (unavailable from async contexts
        // under Swift 6) is needed. Re-layout/redisplay between waits so each
        // committed pass is reflected before we rasterize.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(200))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        let ok = captureView(hosting, to: url)
        window.orderOut(nil)
        window.contentView = nil
        return ok
    }

    /// Rasterizes a view into a PNG via `cacheDisplay`. Returns `true` on write.
    /// Mirrors `SnapshotRenderer.captureView`.
    private static func captureView(_ view: NSView, to url: URL) -> Bool {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("window-first: could not create bitmap for \(url.lastPathComponent)")
            return false
        }

        view.cacheDisplay(in: view.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("window-first: PNG encoding failed for \(url.lastPathComponent)")
            return false
        }

        do {
            try data.write(to: url)
            print("window-first: wrote \(url.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
            return true
        } catch {
            print("window-first: write failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    /// Yields a few run-loop turns so SwiftUI commits the just-applied state
    /// change (the routed destination) and any cheap `.task` work settles before
    /// the off-screen window is hosted and rasterized.
    private static func settle() async {
        for _ in 0..<3 {
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(120))
    }
}

private extension View {
    /// Applies the forced color scheme when one is set, else leaves the view to
    /// follow the host appearance — keeps the call sites terse.
    @ViewBuilder
    func applyForcedScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
