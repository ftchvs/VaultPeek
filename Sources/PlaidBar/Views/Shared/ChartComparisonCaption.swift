import PlaidBarCore
import SwiftUI

// MARK: - Chart comparison caption (design-elevation shared kit)
//
// The single quiet line under a chart that says what changed versus the
// comparison period ("▲ 12% vs prior 30 days"). The text arrives preformatted
// (and mask-aware) from the caller; direction is carried by the glyph/arrow
// *in the text*, never by color (this caption is uniformly secondary).

/// One secondary caption line for under a chart.
///
/// `spelledAccessibilityLabel` is the words-only reading ("up 12 percent
/// versus the prior 30 days") so VoiceOver never has to guess at "▲".
struct ChartComparisonCaption: View {
    /// Optional leading SF Symbol (e.g. "chart.line.uptrend.xyaxis").
    var glyph: String?
    /// Preformatted caption text, direction included ("▲ 12% vs prior period").
    let text: String
    /// The same statement spelled in words for VoiceOver.
    let spelledAccessibilityLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spelledAccessibilityLabel)
    }
}

#if canImport(PreviewsMacros)
#Preview("Chart comparison captions") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        ChartComparisonCaption(
            glyph: "calendar",
            text: "▲ 12% vs prior 30 days",
            spelledAccessibilityLabel: "Up 12 percent versus the prior 30 days"
        )
        ChartComparisonCaption(
            text: "▼ $86 vs February",
            spelledAccessibilityLabel: "Down 86 dollars versus February"
        )
    }
    .padding(Spacing.lg)
}

#Preview("Chart comparison captions — dark") {
    ChartComparisonCaption(
        glyph: "calendar",
        text: "▲ 12% vs prior 30 days",
        spelledAccessibilityLabel: "Up 12 percent versus the prior 30 days"
    )
    .padding(Spacing.lg)
    .preferredColorScheme(.dark)
}
#endif
