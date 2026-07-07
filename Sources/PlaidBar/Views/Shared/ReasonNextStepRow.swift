import PlaidBarCore
import SwiftUI

// MARK: - Reason + next-step row (design-elevation shared kit)
//
// The standard "why + what next" grammar for attention/review surfaces:
//
//     [glyph] [reason] — [consequence]           [action]
//
// Pure presentation: the caller passes an already mask-aware reason/consequence
// (typically built from the `TransactionReviewReason` taxonomy's
// `displayName`/`glyphName`) and exactly one next step. There is deliberately
// no action-less mode — a surfaced reason without a next step is a dead end,
// and the kit refuses to render one.

/// One reason line with a single trailing next-step action.
///
/// The glyph + reason text carry the meaning; `tint` is reinforcement only and
/// never the sole signal (ACCESSIBILITY.md). The row reads as one VoiceOver
/// element ("<reason>. <consequence>. Button: <actionTitle>") and activates the
/// action directly, so assistive users get the grammar in one swipe.
struct ReasonNextStepRow: View {
    /// SF Symbol name, usually `TransactionReviewReason.glyphName`.
    let glyph: String
    /// Short reason text, usually `TransactionReviewReason.displayName`.
    let reason: String
    /// Optional one-sentence consequence ("This can double-count March.").
    var consequence: String?
    /// Reinforcement tint for the glyph only — meaning lives in glyph + text.
    var tint: Color = SemanticColors.warning
    /// The single next step. Required: no dead-end reasons.
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: glyph)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(minWidth: Sizing.iconInline)

            // Reason (primary) and consequence (secondary) flow as one line and
            // wrap together when the row is narrow.
            reasonText
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.sm)

            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    /// Reason (primary) + em-dash consequence (secondary) as one wrapping run
    /// of text, via `Text` interpolation (the `+` concatenation API is
    /// deprecated on macOS 26).
    private var reasonText: Text {
        guard let consequence else { return Text(reason) }
        return Text("\(reason) — \(Text(consequence).foregroundStyle(.secondary))")
    }

    private var accessibilityText: String {
        var parts = [reason]
        if let consequence { parts.append(consequence) }
        parts.append("Button: \(actionTitle)")
        return parts.joined(separator: ". ")
    }
}

#if canImport(PreviewsMacros)
#Preview("Reason rows") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        ReasonNextStepRow(
            glyph: "arrow.triangle.2.circlepath",
            reason: "Possible duplicate",
            consequence: "Counting both inflates March dining by $42.",
            tint: SemanticColors.warning,
            actionTitle: "Compare"
        ) {}
        ReasonNextStepRow(
            glyph: "questionmark.circle",
            reason: "Uncategorized",
            consequence: "Not counted in any budget yet.",
            tint: SemanticColors.recurring,
            actionTitle: "Categorize"
        ) {}
        ReasonNextStepRow(
            glyph: "chart.line.uptrend.xyaxis",
            reason: "Unusual amount",
            tint: SemanticColors.negative,
            actionTitle: "Review"
        ) {}
    }
    .padding(Spacing.lg)
    .frame(width: 420)
}

#Preview("Reason rows — dark") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        ReasonNextStepRow(
            glyph: "arrow.triangle.2.circlepath",
            reason: "Possible duplicate",
            consequence: "Counting both inflates March dining by $42.",
            actionTitle: "Compare"
        ) {}
    }
    .padding(Spacing.lg)
    .frame(width: 420)
    .preferredColorScheme(.dark)
}
#endif
