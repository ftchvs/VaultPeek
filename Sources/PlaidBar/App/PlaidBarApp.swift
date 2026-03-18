import SwiftUI
import MenuBarExtraAccess

@main
struct PlaidBarApp: App {
    @State private var appState = AppState()

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
            SettingsView()
                .environment(appState)
        }
    }
}
