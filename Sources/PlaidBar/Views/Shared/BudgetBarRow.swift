import PlaidBarCore
import SwiftUI

// MARK: - Budget bar row (design-elevation shared kit)
//
// A single budget-vs-actual row: category label, capsule track filled to the
// spent fraction with a visible tick at the budget position, and a trailing
// preformatted verdict ("over by $86" / "$120 left"). It follows the
// ``CategoryStatusBar`` philosophy: an over-budget row pins the fill full and
// carries the magnitude in the tick + text, never by overflowing the bar; the
// tick is a *shape* cue, not color-only. Verdict tinting is delegated to the
// shared `CategoryBudgetStatus.verdictTint` — no second tint mapping.

/// One budget-vs-actual row with a tick-marked capsule track.
///
/// Pure presentation: fractions and strings arrive precomputed and mask-aware.
/// The row reads as one VoiceOver element ("Dining: $586 spent of $500 budget.
/// Over by $86.") so track geometry never has to be interpreted by ear.
struct BudgetBarRow: View {
    let categoryLabel: String
    /// Track fill as a fraction of the *track* (0…1, clamped here). For an
    /// over-budget row pass 1 — the overage lives in `verdictText`, not in an
    /// overflowing bar.
    let fillFraction: Double
    /// Where the budget sits on the track (0…1), or `nil` to hide the tick
    /// (no budget set). Under budget this is 1 (budget at the track end);
    /// over budget it is budget/spent, so the tick shows how far past it went.
    var budgetTickFraction: Double?
    /// Budget verdict driving glyph + tint (via the shared
    /// `CategoryBudgetStatus.verdictTint`); `nil` means no budget set.
    let status: CategoryBudgetStatus?
    /// Preformatted, mask-aware verdict ("over by $86" / "$120 left" /
    /// "No budget set").
    let verdictText: String
    /// Preformatted, mask-aware spent figure for VoiceOver.
    let spentText: String
    /// Preformatted, mask-aware budget figure for VoiceOver; `nil` when unbudgeted.
    var limitText: String?
    /// Fill accent for a healthy (under-budget) row — a redundant cue only.
    var accent: Color = SemanticColors.brand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(categoryLabel)
                .font(.caption)
                .lineLimit(1)
                .frame(minWidth: 72, alignment: .leading)

            track

            // Glyph + text carry the verdict; tint is the redundant third cue.
            Label {
                Text(verdictText)
                    .microText()
                    .monospacedDigit()
            } icon: {
                Image(systemName: statusGlyph)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(status.verdictTint)
            .lineLimit(1)
            .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))

                if status != nil {
                    Capsule()
                        .fill(fillTint)
                        .frame(width: max(width * clampedFill, 3))
                        .animation(
                            MotionTokens.animation(MotionTokens.content, reduceMotion: reduceMotion),
                            value: clampedFill
                        )
                }

                // Budget-position tick: a visible shape cue (mirrors the
                // committed-recurring tick in ``CategoryStatusBar``), so the
                // budget boundary never reads by color alone.
                if let budgetTickFraction {
                    let tickFraction = min(max(budgetTickFraction, 0), 1)
                    Capsule()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 2)
                        .padding(.vertical, 1)
                        .offset(x: min(max(width * tickFraction - 1, 0), width - 2))
                }
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var clampedFill: Double {
        min(max(fillFraction, 0), 1)
    }

    /// Verdict glyph — the non-color half of the verdict cue. Delegated to the
    /// shared `CategoryBudgetStatus.iconName` vocabulary (with the same neutral
    /// no-budget fallback as `statusIconName` elsewhere), so this row never
    /// drifts from the glyphs the Budgets table and status bar use.
    private var statusGlyph: String {
        status?.iconName ?? "minus.circle"
    }

    /// Attention states (over/nearing) borrow the shared verdict tint so the
    /// bar agrees with the verdict text; a healthy fill uses the row accent
    /// (the verdict tint for `.under` is deliberately quiet secondary text).
    private var fillTint: Color {
        switch status {
        case .over, .nearing: status.verdictTint.opacity(0.85)
        default: accent.opacity(0.82)
        }
    }

    private var accessibilityText: String {
        var sentence = "\(categoryLabel): \(spentText) spent"
        if let limitText {
            sentence += " of \(limitText) budget"
        }
        sentence += ". \(verdictText)."
        return sentence
    }
}

#if canImport(PreviewsMacros)
#Preview("Budget bar rows") {
    VStack(spacing: Spacing.md) {
        BudgetBarRow(
            categoryLabel: "Dining",
            fillFraction: 1,
            budgetTickFraction: 500.0 / 586.0,
            status: .over,
            verdictText: "over by $86",
            spentText: "$586",
            limitText: "$500"
        )
        BudgetBarRow(
            categoryLabel: "Groceries",
            fillFraction: 0.86,
            budgetTickFraction: 1,
            status: .nearing,
            verdictText: "$56 left",
            spentText: "$344",
            limitText: "$400"
        )
        BudgetBarRow(
            categoryLabel: "Transport",
            fillFraction: 0.31,
            budgetTickFraction: 1,
            status: .under,
            verdictText: "$103 left",
            spentText: "$47",
            limitText: "$150"
        )
        BudgetBarRow(
            categoryLabel: "Hobbies",
            fillFraction: 0,
            budgetTickFraction: nil,
            status: nil,
            verdictText: "No budget set",
            spentText: "$62"
        )
    }
    .padding(Spacing.lg)
    .frame(width: 460)
}

#Preview("Budget bar rows — dark") {
    BudgetBarRow(
        categoryLabel: "Dining",
        fillFraction: 1,
        budgetTickFraction: 500.0 / 586.0,
        status: .over,
        verdictText: "over by $86",
        spentText: "$586",
        limitText: "$500"
    )
    .padding(Spacing.lg)
    .frame(width: 460)
    .preferredColorScheme(.dark)
}
#endif
