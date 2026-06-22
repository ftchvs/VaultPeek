import PlaidBarCore
import SwiftUI

/// The local-only insight receipt for the window-first **Dashboard** destination
/// (AND-622), surfaced from the same Core ``LocalAIInsightReceipt`` the menu-bar
/// popover renders (its `LocalInsightsCard` is private to `MainPopover`). It shows
/// the on-device summary headline, the evidence chips, the confidence /
/// limitations lines, and the local-only provenance badge — all computed from the
/// same `AppState.localAIActivitySummaries` + availability.
///
/// **Surface only — no AI/model logic here.** The receipt, its chips, and the
/// availability state come from Core. On-device AI is **off by default with a
/// visible status** (AND-564); the availability label carries the current state so
/// the user always sees whether anything ran locally. Honors Privacy Mask via the
/// receipt's `privacyMaskEnabled` input, and never carries meaning by color alone.
///
/// Like its self-carding Dashboard siblings (``DashboardRecurringCard``,
/// ``CategoryDashboardCard``) and the Insights hero (``InsightsAIInsightView``),
/// the card wraps its body in a ``WindowSection`` so it inherits the solid
/// ``windowCardSurface()`` + 20pt (``WindowMetrics/md``) padding + `title3`
/// (``WindowCardTitle``) header. Data stays solid — Liquid Glass goes on chrome,
/// not on the financial figures ("glass on chrome, not data").
struct DashboardLocalInsightCard: View {
    @Environment(AppState.self) private var appState

    private var summaries: [LocalAIActivitySummary] {
        appState.localAIActivitySummaries
    }

    private var primarySummary: LocalAIActivitySummary? {
        summaries.first { $0.window == .lastMonth } ?? summaries.first
    }

    private var availability: LocalAIAvailability {
        primarySummary?.availability ?? appState.localAIAvailability
    }

    private var receipt: LocalAIInsightReceipt {
        LocalAIInsightReceipt.make(
            summary: primarySummary,
            availability: availability,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
    }

    var body: some View {
        let receipt = receipt

        // A titled window-section card so the receipt inherits the solid surface,
        // 20pt padding, and `title3` header from the shared component — matching
        // every sibling Dashboard card. The availability state rides in the header
        // accessory (text + glyph, never color alone).
        WindowSection(receipt.title, systemImage: "sparkles") {
            availabilityLabel
        } content: {
            VStack(alignment: .leading, spacing: WindowMetrics.sm) {
                Text(receipt.headline)
                    .windowCardTitle()
                    .fixedSize(horizontal: false, vertical: true)

                if !receipt.evidenceChips.isEmpty {
                    HStack(spacing: WindowMetrics.sm) {
                        ForEach(receipt.evidenceChips) { chip in
                            evidenceChip(chip)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                    ForEach(Array(detailLines(receipt).enumerated()), id: \.offset) { _, detail in
                        HStack(alignment: .top, spacing: WindowMetrics.sm) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(detail)
                                .windowSupportingText()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack(spacing: WindowMetrics.xs) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("\(receipt.localOnlyBadge). \(receipt.reversibleActionCopy)")
                        .windowSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: WindowMetrics.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(receipt.accessibilitySummary)
    }

    private var availabilityLabel: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: LocalAIAvailabilityPresentation.iconName(for: availability.state))
                .font(.caption2.weight(.medium))
            Text(LocalAIAvailabilityPresentation.popoverLabel(for: availability))
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(availabilityTint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .help(LocalAIAvailabilityPresentation.helpText(for: availability))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LocalAIAvailabilityPresentation.popoverLabel(for: availability))
    }

    private var availabilityTint: Color {
        switch availability.state {
        case .available: SemanticColors.positive
        case .disabled, .checking: AppearanceTextColors.secondary
        case .unavailable: SemanticColors.warning
        }
    }

    private func detailLines(_ receipt: LocalAIInsightReceipt) -> [String] {
        var lines = [receipt.confidence]
        if let unavailableState = receipt.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: receipt.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    private func evidenceChip(_ chip: LocalAIInsightReceipt.EvidenceChip) -> some View {
        VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            HStack(spacing: 4) {
                Image(systemName: chip.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(chip.label)
                    .lineLimit(1)
            }
            .microText()
            .foregroundStyle(.secondary)

            Text(chip.value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        // A quiet `.quaternary` inner fill rather than Liquid Glass: even an inner
        // evidence chip carries figures (data), so it stays solid.
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.control))
        .help("\(chip.label): \(chip.value)")
    }
}
