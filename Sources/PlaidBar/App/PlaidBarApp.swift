import MenuBarExtraAccess
import PlaidBarCore
import Sparkle
import SwiftUI

@main
struct PlaidBarApp: App {
    @State private var appState: AppState
    private let updaterController: SPUStandardUpdaterController

    init() {
        Self.applyScreenshotDefaults()

        let state = AppState()
        _appState = State(initialValue: state)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if CommandLine.arguments.contains("--show-popover") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                state.isPopoverPresented = true
            }
        }
        Task { @MainActor in
            await state.prewarmBundledServer()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopover()
                .environment(appState)
        } label: {
            MenuBarLabel()
                .environment(appState)
        }
        .menuBarExtraAccess(isPresented: $appState.isPopoverPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
        }
    }

    private static func applyScreenshotDefaults() {
        guard CommandLine.arguments.contains("--demo") else { return }

        if let filter = CommandLineOptions.value(for: "--screenshot-filter") {
            let normalizedFilter = ["all", "cash", "credit", "savings", "debt", "status"]
                .first { $0 == filter.lowercased() }
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }

            if let normalizedFilter {
                UserDefaults.standard.set(String(normalizedFilter), forKey: "dashboard.accountFilter")
            }
        }

        if let accountId = CommandLineOptions.value(for: "--screenshot-account") {
            UserDefaults.standard.set(accountId, forKey: "dashboard.selectedAccountId")
        } else if CommandLine.arguments.contains("--screenshot-filter") {
            UserDefaults.standard.removeObject(forKey: "dashboard.selectedAccountId")
        }

        if let settingsTab = CommandLineOptions.value(for: "--settings-tab") {
            UserDefaults.standard.set(settingsTab.lowercased(), forKey: "settings.selectedTab")
        }
    }
}
