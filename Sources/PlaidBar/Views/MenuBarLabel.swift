import PlaidBarCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // State is carried by the symbol shape and attention text, not
        // color: the menu bar renders template-style monochrome like every
        // other status item, and degraded states swap the glyph instead of
        // tinting a dot. The blocking/advisory split lives in
        // MenuBarStatusPresentation (PlaidBarCore): advisory failures step
        // down to the warning glyph and never paint attention text here.
        let presentation = appState.menuBarStatusPresentation
        HStack(spacing: Spacing.xs) {
            // The healthy Vault style has no SF Symbol; it renders from a
            // code-drawn monochrome template image. Degraded states still swap
            // in their SF Symbol ladder, so the token only ever appears here in
            // the healthy state.
            if presentation.symbolName == MenuBarIconStyle.customGlyphToken {
                Image(nsImage: VaultMenuBarGlyph.image)
                    .symbolMotion(.replace, reduceMotion: reduceMotion)
            } else {
                Image(systemName: presentation.symbolName)
                    // One-shot Apple-native cross-fade when the status glyph
                    // changes; meaning still lives in the symbol shape + text, so
                    // this is purely calm polish. Disabled under Reduce Motion so
                    // the glyph swaps instantly with no animation (AND-358 helper).
                    .symbolMotion(.replace, reduceMotion: reduceMotion)
            }
            if let attentionText = presentation.attentionText {
                Text(attentionText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            if presentation.attentionText == nil,
               let reviewText = appState.menuBarReviewText {
                Text(reviewText)
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
}
