import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // State is carried by the symbol shape, not color: the menu bar
            // renders template-style monochrome like every other status item,
            // and degraded states swap the glyph instead of tinting a dot.
            Image(systemName: statusSymbolName)
            if let attentionText = appState.menuBarAttentionText {
                Text(attentionText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            if !appState.menuBarText.isEmpty {
                Text(appState.menuBarText)
                    .monospacedDigit()
            }
        }
        .help(appState.menuBarHelpText)
        .accessibilityLabel(appState.menuBarAccessibilityLabel)
    }

    private var statusSymbolName: String {
        if appState.error != nil || appState.erroredItemCount > 0 {
            return "exclamationmark.octagon"
        }
        // Offline is checked before stale/login: when the server is
        // unreachable, isSyncStale is usually also true (no recent or no
        // first sync), so the offline glyph must win to stay distinct.
        if !appState.serverConnected, !appState.isDemoMode {
            return "network.slash"
        }
        if appState.needsLoginItemCount > 0 || appState.isSyncStale {
            return "exclamationmark.triangle"
        }
        return "dollarsign.circle"
    }
}
