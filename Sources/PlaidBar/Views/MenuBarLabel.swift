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
            // Glyph precedence (all monochrome template-style, meaning carried
            // by SHAPE never color):
            //   1. Live signal meter (AND-485) — when its toggle is on AND the
            //      status is healthy (the meter model is non-nil only then),
            //      draw the code-rendered template meter. The degraded glyph
            //      ladder still wins because the meter model is nil for any
            //      non-healthy state, so a problem is never hidden behind a meter.
            //   2. Static Vault custom glyph (feat/menu-bar-glyph) — the healthy
            //      Vault icon style has no SF Symbol; it renders from a code-drawn
            //      monochrome template image. Degraded states still swap in their
            //      SF Symbol ladder, so the token only appears here when healthy.
            //   3. SF Symbol — every other style and every degraded state.
            // The live-meter toggle disables the icon-style picker in Settings,
            // so (1) and the chosen static style (2/3) never both apply — the
            // meter simply takes precedence while active.
            if let signalModel = appState.menuBarSignalGlyph,
               let signalImage = SignalGlyphImage.make(model: signalModel) {
                Image(nsImage: signalImage)
            } else if presentation.symbolName == MenuBarIconStyle.customGlyphToken {
                // SF Symbols 7 motion review (AND-514, F3): the new symbol
                // primitives (`.drawOn`/`.drawOff`, `.breathe`, `.wiggle`,
                // magic `.replace`) animate genuine SF Symbols via
                // `symbolEffect`; they do not apply to a custom `NSImage`. The
                // Vault mark is a static template image, so it gains nothing
                // here. `.replace` is kept as the SwiftUI-level cross-fade for
                // the glyph swap; the richer primitives would only ever land on
                // the SF Symbol ladder below, and broadening the shared
                // `SymbolMotion` vocabulary belongs in SharedModifiers (Epic C),
                // so no new motion is added in this epic.
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
        .accessibilityLabel(accessibilityLabel)
    }

    /// The spoken label for the whole status item. The parent `.accessibilityLabel`
    /// replaces the child glyph image's own description, so when the live signal
    /// meter is active its value/over-threshold/stale signal would be silent for
    /// any non-utilization title mode. Fold the meter's word-only description
    /// (never color) into the parent label so VoiceOver still hears it.
    private var accessibilityLabel: String {
        let base = appState.menuBarAccessibilityLabel
        guard let meter = appState.menuBarSignalGlyph?.accessibilityDescription else {
            return base
        }
        return "\(base) \(meter)."
    }
}
