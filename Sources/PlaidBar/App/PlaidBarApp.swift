import SwiftUI
import MenuBarExtraAccess
import Sparkle

@main
struct PlaidBarApp: App {
    @State private var appState = AppState()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
