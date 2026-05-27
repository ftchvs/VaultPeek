import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(appState.serverConnected || appState.isDemoMode ? SemanticColors.income : .secondary)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: 1)
                }
            if !appState.menuBarText.isEmpty {
                Text(appState.menuBarText)
                    .monospacedDigit()
            }
        }
        .help(appState.menuBarHelpText)
        .accessibilityLabel(appState.menuBarAccessibilityLabel)
    }

    private var statusTint: Color {
        if appState.error != nil || appState.erroredItemCount > 0 {
            return SemanticColors.negative
        }
        if appState.needsLoginItemCount > 0 || appState.isSyncStale {
            return SemanticColors.warning
        }
        if appState.serverConnected || appState.isDemoMode {
            return SemanticColors.positive
        }
        return .secondary
    }
}
