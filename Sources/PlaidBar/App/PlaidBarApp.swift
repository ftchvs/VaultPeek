import SwiftUI
import MenuBarExtraAccess
import Sparkle

@main
struct PlaidBarApp: App {
    @State private var appState: AppState
    private let updaterController: SPUStandardUpdaterController

    init() {
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
}
