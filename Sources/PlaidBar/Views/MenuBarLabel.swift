import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(SemanticColors.income)
            Text(appState.menuBarText)
                .monospacedDigit()
        }
        .help("PlaidBar \u{2014} Net: \(appState.menuBarText)")
        .accessibilityLabel("PlaidBar net balance \(appState.menuBarText)")
    }
}
