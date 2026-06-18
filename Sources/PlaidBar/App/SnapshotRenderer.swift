import AppKit
import PlaidBarCore
import SwiftUI

/// Headless snapshot rendering for `--demo --render-snapshot <dir>`.
///
/// Opens the real popover window and rasterizes its content view via
/// `cacheDisplay(in:to:)` — no screen capture, no Screen Recording
/// permission, and indifferent to where macOS positions the window.
/// Intended for agent/CI verification; `Scripts/screenshots.sh` remains
/// the source of README assets because on-screen capture composites the
/// popover material against the actual desktop.
@MainActor
enum SnapshotRenderer {
    static func renderIfRequested(appState: AppState) -> Bool {
        guard CommandLine.arguments.contains("--demo"),
              let directory = CommandLineOptions.value(for: "--render-snapshot")
        else { return false }

        Task { @MainActor in
            let failureCount = await render(appState: appState, directory: directory)
            // Non-zero exit when any capture failed so headless/CI callers
            // do not treat missing PNGs as success.
            exit(Int32(min(failureCount, 1)))
        }
        return true
    }

    /// Returns the number of failed captures.
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
            print("snapshot: could not create \(directoryURL.path): \(error.localizedDescription)")
            return 2
        }

        var failureCount = 0

        // Dashboard with no selection.
        UserDefaults.standard.set("", forKey: "dashboard.selectedAccountId")
        appState.isPopoverPresented = true
        _ = await waitForPopoverWindow(appState: appState)
        try? await Task.sleep(for: .milliseconds(2200))
        if !capturePopoverWindow(to: directoryURL.appendingPathComponent("render-dashboard.png")) {
            failureCount += 1
        }

        // Fly-out open for the requested (or richest demo) account.
        let accountId = CommandLineOptions.value(for: "--screenshot-account") ?? "demo_visa"
        UserDefaults.standard.set(accountId, forKey: "dashboard.selectedAccountId")
        try? await Task.sleep(for: .milliseconds(2200))
        if !capturePopoverWindow(to: directoryURL.appendingPathComponent("render-flyout.png")) {
            failureCount += 1
        }

        // Settings → Appearance pane (AND-366), forced to the requested appearance.
        if !(await renderSettingsAppearance(
            to: directoryURL.appendingPathComponent("render-settings-appearance.png")
        )) {
            failureCount += 1
        }

        return failureCount
    }

    /// Polls for the popover window, re-toggling presentation when needed:
    /// the first `isPopoverPresented = true` can fire before the MenuBarExtra
    /// status item exists (commonly when the menu bar is crowded and the item
    /// starts in overflow), in which case the popover never opens.
    private static func waitForPopoverWindow(appState: AppState, attempts: Int = 20) async -> Bool {
        for attempt in 0..<attempts {
            if popoverWindow() != nil { return true }
            if attempt % 4 == 3 {
                appState.isPopoverPresented = false
                try? await Task.sleep(for: .milliseconds(150))
                appState.isPopoverPresented = true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return popoverWindow() != nil
    }

    private static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.frame.width >= 400 }
    }

    /// Returns `true` when the PNG was written.
    private static func capturePopoverWindow(to url: URL) -> Bool {
        // Headless contract: the popover is now a native NSPopover, whose frosted
        // material lives in a PRIVATE backing view that `cacheDisplay` cannot
        // rasterize. So `--render-snapshot` captures the SwiftUI content over the
        // slider's tint wash (legible — cards carry their own fills) but WITHOUT
        // the desktop frost. On-screen `Scripts/screenshots.sh` (CGWindowList /
        // screencapture) composites the real frost and remains the asset source.
        guard let window = popoverWindow(),
              let contentView = window.contentView
        else {
            print("snapshot: no visible popover window to capture for \(url.lastPathComponent)")
            for w in NSApp.windows {
                print("snapshot:   window class=\(type(of: w)) visible=\(w.isVisible) frame=\(w.frame)")
            }
            return false
        }

        return captureView(contentView, to: url)
    }

    // MARK: - Settings → Appearance (AND-366)

    /// Renders the Settings → Appearance pane (`AppearanceSettingsView`) into an
    /// off-screen hosting window and rasterizes it, forced to the requested
    /// appearance. This covers the transparency slider, the live preview +
    /// presets (AND-364), and the Display section pickers (AND-365) at the
    /// minimum settings width — no Screen Recording permission, no real data
    /// (the pane is appearance-only). Same headless-material caveat as the
    /// popover: vibrant materials composite against nothing off-screen.
    private static func renderSettingsAppearance(to url: URL) async -> Bool {
        let scheme = PlaidBarApp.forcedColorScheme
        let size = NSSize(width: 560, height: 640)

        let root = AppearanceSettingsView()
            .environment(\.colorScheme, scheme ?? .light)
            .frame(width: size.width, height: size.height, alignment: .topLeading)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        if let scheme {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // Give SwiftUI a beat to commit the hosted hierarchy before rasterizing.
        try? await Task.sleep(for: .milliseconds(800))
        hosting.layoutSubtreeIfNeeded()

        let wrote = captureView(window.contentView ?? hosting, to: url)
        // Tear the off-screen window down explicitly so adding orderFront later
        // can never turn this into a real leak.
        window.close()
        return wrote
    }

    /// Rasterizes any view into a PNG via `cacheDisplay`. Returns `true` on write.
    private static func captureView(_ view: NSView, to url: URL) -> Bool {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("snapshot: could not create bitmap for \(url.lastPathComponent)")
            return false
        }

        view.cacheDisplay(in: view.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("snapshot: PNG encoding failed for \(url.lastPathComponent)")
            return false
        }

        do {
            try data.write(to: url)
            print("snapshot: wrote \(url.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
            return true
        } catch {
            print("snapshot: write failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}
