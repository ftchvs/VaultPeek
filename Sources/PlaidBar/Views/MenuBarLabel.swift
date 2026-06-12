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
        if appState.needsLoginItemCount > 0 || appState.isSyncStale {
            return "exclamationmark.triangle"
        }
        if appState.serverConnected || appState.isDemoMode {
            return "dollarsign.circle"
        }
        // Server unreachable gets its own glyph so it stays distinguishable
        // from stale-sync/login states at the same warning tier.
        return "network.slash"
    }
}
