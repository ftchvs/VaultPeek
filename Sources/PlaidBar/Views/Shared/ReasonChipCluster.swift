import PlaidBarCore
import SwiftUI

// MARK: - Reason chip cluster (design-elevation shared kit)
//
// A dense row can carry many review reasons, but only the highest-priority one
// earns pixels: one primary capsule (glyph + short label) plus, when more
// reasons exist, a neutral "+N" overflow capsule. The full list lives in the
// tooltip and the accessibility label, so nothing is lost — only deferred.

/// One primary reason capsule + optional "+N" overflow capsule.
///
/// The primary chip's tint is a low-opacity capsule wash behind primary-color
/// text (≥ 4.5:1 — the tint never carries the text); glyph + label carry the
/// meaning (ACCESSIBILITY.md). The whole cluster is one VoiceOver element and
/// one `.help()` tooltip, both voicing `allReasonsSummary`.
struct ReasonChipCluster: View {
    /// SF Symbol for the primary reason, usually `TransactionReviewReason.glyphName`.
    let glyph: String
    /// Short primary-reason label, usually `TransactionReviewReason.displayName`.
    let label: String
    /// Reinforcement wash behind the primary chip — never the only signal.
    var tint: Color = SemanticColors.warning
    /// How many further reasons the "+N" capsule stands in for. 0 hides it.
    var overflowCount: Int = 0
    /// Full "all reasons" sentence for the tooltip and VoiceOver.
    let allReasonsSummary: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Label {
                Text(label)
                    .microText()
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: glyph)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.chipVertical)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.16), lineWidth: 1))

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .microText()
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.chipVertical)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .help(allReasonsSummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(allReasonsSummary)
    }
}

#if canImport(PreviewsMacros)
#Preview("Reason chips") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        ReasonChipCluster(
            glyph: "arrow.triangle.2.circlepath",
            label: "Duplicate?",
            tint: SemanticColors.warning,
            overflowCount: 2,
            allReasonsSummary: "Possible duplicate, uncategorized, and unusual amount."
        )
        ReasonChipCluster(
            glyph: "questionmark.circle",
            label: "Uncategorized",
            tint: SemanticColors.recurring,
            allReasonsSummary: "Uncategorized."
        )
    }
    .padding(Spacing.lg)
    .frame(width: 360)
}

#Preview("Reason chips — dark") {
    ReasonChipCluster(
        glyph: "arrow.triangle.2.circlepath",
        label: "Duplicate?",
        overflowCount: 1,
        allReasonsSummary: "Possible duplicate and pending."
    )
    .padding(Spacing.lg)
    .preferredColorScheme(.dark)
}
#endif
