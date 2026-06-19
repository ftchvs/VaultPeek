import PlaidBarCore
import SwiftUI

/// A single budget-pressure status bar for one category-dashboard row — a leaf
/// (AND-557) or a group rollup (AND-558).
///
/// The bar pairs a `Capsule` fill track with a glyph + text verdict so budget
/// pressure is **never** carried by color alone (ACCESSIBILITY.md): the band's
/// SF Symbol and label always read, and the tint is a redundant third cue. An
/// over-budget row pins the track full — the amount of overspend lives in the
/// numbers, not by overflowing the bar. An unbudgeted row draws an empty track
/// and an explicit "No budget set" verdict rather than a misleading sliver.
///
/// Pure presentation: every derived number (fill fraction, percent, verdict,
/// VoiceOver sentence) comes from ``CategoryStatusBarModel`` in PlaidBarCore.
struct CategoryStatusBar: View {
    let model: CategoryStatusBarModel
    /// Pre-rendered, possibly masked spend string (e.g. "$200" or "••••").
    let spentText: String
    /// Pre-rendered, possibly masked limit string; `nil` hides the budget half.
    var limitText: String?
    /// Accent used for the bar fill — a redundant cue layered over glyph + text.
    var accent: Color = SemanticColors.brand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            track
            verdictRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription(spentText: spentText, limitText: limitText))
    }

    private var track: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.quaternary.opacity(0.5))
                .overlay(alignment: .leading) {
                    if !model.trackOnly {
                        Capsule()
                            .fill(fillTint)
                            .frame(width: max(proxy.size.width * model.fillFraction, 2))
                            .animation(
                                MotionTokens.animation(MotionTokens.content, reduceMotion: reduceMotion),
                                value: model.fillFraction
                            )
                    }
                }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var verdictRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            // Glyph + text carry the verdict without color.
            Label {
                Text(model.statusText)
                    .microText()
            } icon: {
                Image(systemName: model.statusIconName)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(verdictTint)
            .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            // SPENT / BUDGET summary — the numbers the bar abstracts.
            Text(summaryText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// "$200 of $500 · 40%" when budgeted; just the spend when not.
    private var summaryText: String {
        guard model.isBudgeted, let limitText else { return spentText }
        if let percent = model.percentUsedText() {
            return "\(spentText) of \(limitText) · \(percent)"
        }
        return "\(spentText) of \(limitText)"
    }

    /// The bar fill: the row accent when budgeted, muted on an over row so the
    /// warning tint reads, and neutral when there is nothing to track.
    private var fillTint: Color {
        switch model.status {
        case .over: SemanticColors.negative.opacity(0.85)
        case .nearing: SemanticColors.warning.opacity(0.85)
        case .under: accent.opacity(0.82)
        case nil: .secondary.opacity(0.4)
        }
    }

    /// Verdict text/glyph tint — a redundant cue, never the only signal.
    private var verdictTint: Color {
        switch model.status {
        case .over: SemanticColors.negative
        case .nearing: SemanticColors.warning
        case .under: .secondary
        case nil: .secondary
        }
    }
}
