import PlaidBarCore
import SwiftUI

/// Compact, explainable "safe to spend" card.
///
/// Shows the headline number, a last-updated timestamp, a confidence cue (text
/// + SF Symbol, never color alone — ACCESSIBILITY.md), and an expandable,
/// signed breakdown that reconciles to the number. The card is purely
/// presentational: all math lives in `SafeToSpendCalculator` (PlaidBarCore).
struct SafeToSpendCard: View {
    let result: SafeToSpendResult
    /// Relative "last updated" text (e.g. "2 minutes ago"). Nil hides the line.
    var lastUpdatedRelative: String?
    /// When true, every currency figure (headline + breakdown) is masked while
    /// Privacy Mask or App Lock is active.
    var privacyMaskEnabled: Bool = false

    @State private var isBreakdownExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            amountRow

            confidenceCue

            breakdownDisclosure
        }
        .padding(Spacing.sm)
        .solidDataSurface(cornerRadius: Radius.panel, fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.controlFillOpacity)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("Safe to spend")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            // The amount is never shown without a freshness cue (AND-401 AC):
            // fall back to "Not yet updated" when no sync has happened.
            Label(lastUpdatedText, systemImage: "clock")
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(lastUpdatedAccessibilityText)
        }
    }

    private var amountRow: some View {
        let amount = PrivacyMaskPresentation.currency(
            result.amount,
            format: .full,
            isEnabled: privacyMaskEnabled,
            // Masked value shows dots, not the word "Private" (consistent with
            // the rest of the dashboard). `.hero` stays on the VoiceOver label.
            style: .compact
        )
        return Text(amount)
            .dataText()
            .foregroundStyle(amountTint)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel("\(amount) safe to spend through \(horizonText)")
    }

    private var confidenceCue: some View {
        // Text + symbol carry the confidence; the tint is a redundant cue, not
        // the only one.
        Label {
            Text(result.confidence.label)
                .microText()
                .lineLimit(1)
        } icon: {
            Image(systemName: result.confidence.iconName)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(confidenceTint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .accessibilityLabel("Confidence: \(result.confidence.label)")
    }

    private var breakdownDisclosure: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                    isBreakdownExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isBreakdownExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(isBreakdownExpanded ? "Hide breakdown" : "Show breakdown")
                        .microText()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBreakdownExpanded ? "Hide breakdown" : "Show breakdown")

            if isBreakdownExpanded {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(result.visibleComponents) { component in
                        SafeToSpendBreakdownRow(component: component, privacyMaskEnabled: privacyMaskEnabled)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var amountTint: Color {
        // Negative spendable balance is a genuine warning; otherwise neutral.
        result.amount < 0 ? SemanticColors.negative : AppearanceTextColors.primary
    }

    private var confidenceTint: Color {
        switch result.confidence {
        case .ok:
            .secondary
        case .lowConfidence:
            SemanticColors.warning
        case .insufficientData:
            .secondary
        }
    }

    private var lastUpdatedText: String {
        lastUpdatedRelative ?? "Not yet updated"
    }

    private var lastUpdatedAccessibilityText: String {
        lastUpdatedRelative.map { "Updated \($0)" } ?? "Not yet updated"
    }

    private var horizonText: String {
        Formatters.displayDate(result.horizonEnd)
    }

    private var accessibilitySummary: String {
        let amount = PrivacyMaskPresentation.currency(
            result.amount,
            format: .full,
            isEnabled: privacyMaskEnabled,
            style: .hero
        )
        let updated = lastUpdatedRelative.map { " Updated \($0)." } ?? " Not yet updated."
        return "Safe to spend \(amount) through \(horizonText). Confidence: \(result.confidence.label).\(updated)"
    }
}

private struct SafeToSpendBreakdownRow: View {
    let component: SafeToSpendComponent
    var privacyMaskEnabled: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label {
                Text(component.label)
                    .microText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: component.kind.iconName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Text(amountText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amountTint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(component.label): \(accessibilityAmountText)")
    }

    private var amountText: String {
        Formatters.signedCurrency(component.amount, format: .compact, masked: privacyMaskEnabled)
    }

    private var accessibilityAmountText: String {
        guard !privacyMaskEnabled else { return PrivacyMaskPresentation.compactValue }
        let magnitude = Formatters.currency(abs(component.amount), format: .full)
        if component.amount > 0 { return "plus \(magnitude)" }
        if component.amount < 0 { return "minus \(magnitude)" }
        return magnitude
    }

    private var amountTint: Color {
        if component.amount > 0 { return SemanticColors.positive }
        if component.amount < 0 { return AppearanceTextColors.primary }
        return AppearanceTextColors.secondary
    }
}
