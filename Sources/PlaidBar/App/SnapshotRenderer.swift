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
            await render(appState: appState, directory: directory)
            exit(0)
        }
        return true
    }

    private static func render(appState: AppState, directory: String) async {
        await appState.loadInitialData()

        let directoryURL = URL(
            fileURLWithPath: (directory as NSString).expandingTildeInPath,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Dashboard with no selection.
        UserDefaults.standard.set("", forKey: "dashboard.selectedAccountId")
        appState.isPopoverPresented = true
        try? await Task.sleep(for: .milliseconds(2200))
        capturePopoverWindow(to: directoryURL.appendingPathComponent("render-dashboard.png"))

        // Fly-out open for the requested (or richest demo) account.
        let accountId = CommandLineOptions.value(for: "--screenshot-account") ?? "demo_visa"
        UserDefaults.standard.set(accountId, forKey: "dashboard.selectedAccountId")
        try? await Task.sleep(for: .milliseconds(2200))
        capturePopoverWindow(to: directoryURL.appendingPathComponent("render-flyout.png"))
    }

    private static func capturePopoverWindow(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 400 }),
              let contentView = window.contentView
        else {
            print("snapshot: no visible popover window to capture for \(url.lastPathComponent)")
            for w in NSApp.windows {
                print("snapshot:   window class=\(type(of: w)) visible=\(w.isVisible) frame=\(w.frame)")
            }
            return
        }

        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            print("snapshot: could not create bitmap for \(url.lastPathComponent)")
            return
        }

        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("snapshot: PNG encoding failed for \(url.lastPathComponent)")
            return
        }

        do {
            try data.write(to: url)
            print("snapshot: wrote \(url.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
        } catch {
            print("snapshot: write failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
