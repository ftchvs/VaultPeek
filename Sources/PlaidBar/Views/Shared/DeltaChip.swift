import PlaidBarCore
import SwiftUI

// MARK: - Delta chip (design-elevation shared kit)
//
// The one-line "so what?" comparison next to a hero number: a direction glyph
// plus the preformatted delta text from `MetricDeltaChip` (PlaidBarCore), e.g.
// "▲ +$420 vs last month". All math, thresholds, and Privacy Mask suppression
// live in Core (`MetricDeltaChip.make` returns `nil` when masked or
// insignificant) — this view only renders a chip it is handed.
//
// Meaning is carried by the glyph *and* the signed text; the sentiment tint on
// the glyph is reinforcement only, never the sole signal (ACCESSIBILITY.md).

/// Renders a Core ``MetricDeltaChip`` as a quiet supporting line.
///
/// Reads as one VoiceOver element speaking the chip's spelled-out
/// `accessibilityLabel` ("Up 420 dollars versus last month"); the glyph text is
/// hidden so VoiceOver never guesses at "▲". Hosts that fold the chip into a
/// larger combined element (e.g. ``WindowHeroMetricTile``) append
/// `chip.accessibilityLabel` themselves.
struct DeltaChip: View {
    let chip: MetricDeltaChip

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(chip.glyph)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(chip.sentiment.tint)
                .accessibilityHidden(true)
            Text(chip.text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
    }
}

#if canImport(PreviewsMacros)
#Preview("Delta chips") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        DeltaChip(chip: MetricDeltaChip(
            glyph: "▲",
            text: "+$420 vs last month",
            sentiment: .positive,
            accessibilityLabel: "Up 420 dollars versus last month"
        ))
        DeltaChip(chip: MetricDeltaChip(
            glyph: "▲",
            text: "+$96 vs prior 30 days",
            sentiment: .negative,
            accessibilityLabel: "Up 96 dollars versus prior 30 days"
        ))
        DeltaChip(chip: MetricDeltaChip(
            glyph: "■",
            text: "Unchanged vs last month",
            sentiment: .neutral,
            accessibilityLabel: "Unchanged versus last month"
        ))
    }
    .padding(Spacing.lg)
}

#Preview("Delta chips — dark") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        DeltaChip(chip: MetricDeltaChip(
            glyph: "▼",
            text: "-$63 (-8%) vs last month",
            sentiment: .positive,
            accessibilityLabel: "Down 63 dollars, 8 percent versus last month"
        ))
        DeltaChip(chip: MetricDeltaChip(
            glyph: "▼",
            text: "-$1,180 vs prior 30 days",
            sentiment: .negative,
            accessibilityLabel: "Down 1180 dollars versus prior 30 days"
        ))
    }
    .padding(Spacing.lg)
    .preferredColorScheme(.dark)
}
#endif
