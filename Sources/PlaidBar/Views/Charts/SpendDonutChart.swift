import Charts
import PlaidBarCore
import SwiftUI

/// Spend donut + center total (AND-537) — a Swift Charts `SectorMark` ring of this
/// month's spend by ``CategoryGroup``, with the overall total in the hole.
///
/// It is a **thin renderer**: all spend, ordering, shares, and label text come from
/// the injected ``SpendDonutModel`` (built from the existing override-aware
/// ``CategoryDashboardPresentation`` — no recompute, spec §3/§4, Option A). The view
/// owns only geometry, color, and motion.
///
/// Accessibility (ACCESSIBILITY.md): color is never the only signal. A glyph+text
/// legend lists every slice's group, amount, and share, so the breakdown reads
/// without distinguishing hues; the chart itself is one VoiceOver element whose label
/// is the model's spoken summary, and each legend row is its own labeled element.
struct SpendDonutChart: View {
    let model: SpendDonutModel
    /// When true (Privacy Mask on), every amount the donut exposes — center total,
    /// legend amounts, and the VoiceOver figures — is masked. Slice geometry, group
    /// titles, and shares still render so the chart's shape and structure stay legible.
    var isPrivacyMasked: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealFraction: CGFloat = 0

    private let ringHeight: CGFloat = 168
    private let innerRatio: CGFloat = 0.62

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ring
            legend
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Ring

    private var ring: some View {
        Chart(model.slices) { slice in
            SectorMark(
                angle: .value("Spend", slice.amount),
                innerRadius: .ratio(innerRatio),
                angularInset: 1.5
            )
            .cornerRadius(3)
            // Fill resolved through the foreground-style scale (keyed by group title)
            // so each sector gets its design-system group accent.
            .foregroundStyle(by: .value("Group", slice.title))
            .opacity(revealFraction)
        }
        .chartForegroundStyleScale(domain: model.slices.map(\.title), range: sliceColors)
        .chartLegend(.hidden) // Custom glyph+text legend below carries amounts + shares.
        .frame(height: ringHeight)
        .frame(maxWidth: .infinity)
        .overlay {
            centerTotal
                .opacity(revealFraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel)
        // VoiceOver audio graph: walk each category's spend as pitch. Honors
        // Privacy Mask — pitch conveys relative magnitude, labels hide amounts.
        .audioGraph(ChartAudioGraph.donut(model, isPrivacyMasked: isPrivacyMasked))
        .onAppear(perform: animateReveal)
    }

    private var centerTotal: some View {
        VStack(spacing: Spacing.xxs) {
            Text(masked(model.totalText))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(model.centerCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .accessibilityHidden(true) // Spoken via the chart's combined label instead.
    }

    // MARK: - Legend (glyph + text, color-independent)

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(model.slices) { slice in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: glyph(for: slice.group))
                        .font(.caption)
                        .foregroundStyle(color(for: slice.group))
                        .frame(width: Sizing.glyphSmall, alignment: .center)
                        .accessibilityHidden(true)
                    Text(slice.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    Text(slice.shareText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(masked(slice.amountText))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(legendAccessibilityLabel(for: slice))
            }
        }
    }

    // MARK: - Privacy masking

    private func masked(_ value: String) -> String {
        PrivacyMaskPresentation.value(value, isEnabled: isPrivacyMasked)
    }

    // MARK: - Accessibility text

    /// Combined VoiceOver label for the ring. When masked, the structure (groups +
    /// shares) is preserved but every amount is hidden so the donut never speaks
    /// exact financial values while Privacy Mask is on.
    private var chartAccessibilityLabel: String {
        guard isPrivacyMasked else { return model.accessibilityLabel }
        guard !model.isEmpty else { return model.accessibilityLabel }
        let hidden = PrivacyMaskPresentation.compactValue
        let breakdown = model.slices
            .map { "\($0.title), \(hidden), \($0.shareText)" }
            .joined(separator: ". ")
        return "Spending by category. \(hidden) spent this month across \(model.sliceCount) "
            + "\(model.sliceCount == 1 ? "group" : "groups"). \(breakdown). "
            + "Amounts hidden while Privacy Mask is on."
    }

    private func legendAccessibilityLabel(for slice: SpendDonutModel.Slice) -> String {
        let amount = isPrivacyMasked ? PrivacyMaskPresentation.compactValue : slice.amountText
        return "\(slice.title), \(amount), \(slice.shareText)"
    }

    // MARK: - Color + glyph

    private var sliceColors: [Color] {
        model.slices.map { color(for: $0.group) }
    }

    /// A group's accent is its first (canonical-order) leaf's design-system chart
    /// color — `CategoryAccentTokens` already returns appearance-aware SwiftUI colors,
    /// matching the per-leaf hues used elsewhere (e.g. the income-flow chart).
    private func color(for group: CategoryGroup) -> Color {
        guard let representative = group.categories.first else { return .secondary }
        return CategoryAccentTokens.color(for: representative)
    }

    private func glyph(for group: CategoryGroup) -> String {
        group.categories.first?.iconName ?? "circle.fill"
    }

    // MARK: - Motion

    private func animateReveal() {
        guard !reduceMotion else { revealFraction = 1; return }
        revealFraction = 0
        withAnimation(MotionTokens.chartReveal.delay(0.1)) {
            revealFraction = 1
        }
    }
}
