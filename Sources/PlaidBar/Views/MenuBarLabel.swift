import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(.green)
            Text(appState.menuBarText)
                .monospacedDigit()
        }
        .help("PlaidBar — Net: \(appState.menuBarText)")
    }
}
