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
        guard let window = popoverWindow(),
              let contentView = window.contentView
        else {
            print("snapshot: no visible popover window to capture for \(url.lastPathComponent)")
            for w in NSApp.windows {
                print("snapshot:   window class=\(type(of: w)) visible=\(w.isVisible) frame=\(w.frame)")
            }
            return false
        }

        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            print("snapshot: could not create bitmap for \(url.lastPathComponent)")
            return false
        }

        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)

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
