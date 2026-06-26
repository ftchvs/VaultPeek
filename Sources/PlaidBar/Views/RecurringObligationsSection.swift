import PlaidBarCore
import SwiftUI

/// Read-only "Recurring" glance card for the Wealth Summary flyout (AND-400).
///
/// Surfaces the obligations `RecurringDetector` already finds — merchant,
/// cadence, expected amount, next date — with attention badges (price up /
/// missing) for the series that need a look. Self-hides when nothing is
/// detected so it never adds an empty card to a dense popover.
///
/// Purely presentational: ordering, flagging, and the monthly total come from
/// `RecurringObligationsPresentation` (PlaidBarCore). Mutating a series
/// (confirm / rename / ignore) is the persistence-backed half of AND-400 and is
/// intentionally not here.
struct RecurringObligationsSection: View {
    let presentation: RecurringObligationsPresentation
    var onOpenSubscriptions: (() -> Void)?
    /// When true, recurring amounts and the monthly total are masked while
    /// Privacy Mask or App Lock is active.
    var privacyMaskEnabled: Bool = false
    /// Which surface is hosting these rows. `.popover` (the default) keeps the
    /// compact glance scale; window canvases pass `.window` so the rows read at
    /// desk-distance type (``WindowDataText`` / ``WindowFigureCaption``) instead of
    /// shrunken popover caption-scale (AND-625).
    var scale: ComponentScale = .popover

    /// Keep the narrow column dense: show the most relevant few, summarize the
    /// rest. Attention-first ordering means flagged items are never hidden
    /// behind the "+N more" line as long as there are fewer than this many.
    private let visibleLimit = 5

    var body: some View {
        if !presentation.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(presentation.items.prefix(visibleLimit))) { item in
                        RecurringObligationRow(item: item, privacyMaskEnabled: privacyMaskEnabled, scale: scale)
                    }
                }

                if presentation.count > visibleLimit {
                    Text(privacyMaskEnabled ? "More recurring charges" : "+\(presentation.count - visibleLimit) more")
                        .microText()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.sm)
            .glassSurface(.raised)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            titleLabel
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            monthlyTotalLabel
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)

            if let onOpenSubscriptions {
                Button(action: onOpenSubscriptions) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
                }
                .buttonStyle(.borderless)
                .help("Open recurring payments")
                .accessibilityLabel("Open recurring payments")
            }
        }
    }

    /// "Recurring" card head — `sectionTitle` (caption, uppercase) in the popover,
    /// `windowCardTitle` (`title3`) on a window canvas so the head matches the
    /// window's other section heads (AND-625).
    @ViewBuilder
    private var titleLabel: some View {
        switch scale {
        case .popover:
            Text("Recurring").sectionTitle()
        case .window:
            Text("Recurring").windowCardTitle()
        }
    }

    /// Estimated monthly total — caption-scale in the popover, window tabular
    /// (``WindowDataText``) on a window canvas so it aligns with the rows' figures.
    @ViewBuilder
    private var monthlyTotalLabel: some View {
        let text = "~\(PrivacyMaskPresentation.currency(presentation.estimatedMonthlyTotal, format: .compact, isEnabled: privacyMaskEnabled))/mo"
        switch scale {
        case .popover:
            Text(text).microText().monospacedDigit()
        case .window:
            Text(text).windowDataText()
        }
    }

    private var accessibilitySummary: String {
        let countText = presentation.countLabel(privacyMaskEnabled: privacyMaskEnabled)
        let total = PrivacyMaskPresentation.currency(
            presentation.estimatedMonthlyTotal,
            format: .full,
            isEnabled: privacyMaskEnabled
        )
        let attention = !privacyMaskEnabled && presentation.attentionCount > 0
            ? " \(presentation.attentionCount) need attention."
            : ""
        return "\(countText), about \(total) per month.\(attention)"
    }
}

private struct RecurringObligationRow: View {
    let item: RecurringObligationsPresentation.Item
    var privacyMaskEnabled: Bool = false
    var scale: ComponentScale = .popover

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Label {
                    merchantNameLabel
                        .lineLimit(1)
                } icon: {
                    Image(systemName: item.frequency.iconName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                amountLabel
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)
            }

            HStack(spacing: Spacing.xs) {
                detailLabel
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ForEach(orderedFlags, id: \.self) { flag in
                    FlagBadge(flag: flag)
                }

                if item.confidenceLevel == .low {
                    LowConfidenceBadge()
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Merchant name — popover `.subheadline`, window `.body` (``WindowBodyText``).
    @ViewBuilder
    private var merchantNameLabel: some View {
        switch scale {
        case .popover:
            Text(item.merchantName).font(.subheadline)
        case .window:
            Text(item.merchantName).windowBodyText()
        }
    }

    /// Expected amount — popover `.subheadline` semibold, window tabular
    /// (``WindowDataText``) so the figure aligns with the window's other rows.
    @ViewBuilder
    private var amountLabel: some View {
        let text = PrivacyMaskPresentation.currency(item.expectedAmount, format: .compact, isEnabled: privacyMaskEnabled)
        switch scale {
        case .popover:
            Text(text).font(.subheadline.weight(.semibold)).monospacedDigit()
        case .window:
            Text(text).windowDataText()
        }
    }

    /// Cadence + next-date detail line — popover `microText`, window
    /// `windowFigureCaption` so the sub-label reads at the window's caption scale.
    @ViewBuilder
    private var detailLabel: some View {
        let text = "\(item.frequency.displayName) · next \(Formatters.displayTransactionDate(item.nextExpectedDate))"
        switch scale {
        case .popover:
            Text(text).microText()
        case .window:
            Text(text).windowFigureCaption()
        }
    }

    /// Deterministic flag order so badges don't reshuffle between renders.
    private var orderedFlags: [RecurringStreamFlag] {
        RecurringStreamFlag.allCases.filter { item.flags.contains($0) }
    }

    private var accessibilityLabel: String {
        var parts = [
            item.merchantName,
            item.frequency.displayName,
            "expected \(PrivacyMaskPresentation.currency(item.expectedAmount, format: .full, isEnabled: privacyMaskEnabled))",
            "next \(Formatters.displayTransactionDate(item.nextExpectedDate))",
        ]
        parts.append(contentsOf: orderedFlags.map(\.accessibilityDescription))
        if item.confidenceLevel == .low { parts.append("low confidence") }
        return parts.joined(separator: ", ")
    }
}

/// Attention badge — text + SF Symbol, never color alone (ACCESSIBILITY.md).
private struct FlagBadge: View {
    let flag: RecurringStreamFlag

    var body: some View {
        Label {
            Text(flag.label)
        } icon: {
            Image(systemName: flag.iconName)
        }
        .font(.caption2.weight(.semibold))
        // Both flags are attention states; the warm tint is a redundant cue that
        // draws the eye (text + symbol already distinguish which flag it is, so
        // the badge never reads through color alone — ACCESSIBILITY.md). Tinting
        // one flag and not the other would make color the type discriminator.
        .foregroundStyle(SemanticColors.warning)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .lineLimit(1)
    }
}

/// A quiet, icon-only "low confidence" cue (AND-729). The full "Low confidence"
/// text capsule, repeated on every estimated row, read as a wall of hedges and
/// competed with the actionable attention flags. Reduced to a single subtle
/// glyph with the wording on hover: the actionable ``FlagBadge``s stay loud
/// (text + capsule), while the confidence caveat recedes. The glyph shape — not
/// color — carries the cue, and the row's accessibility label still voices "low
/// confidence" (never color alone, ACCESSIBILITY.md).
private struct LowConfidenceBadge: View {
    var body: some View {
        Image(systemName: RecurringConfidenceLevel.low.iconName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
            .help(RecurringConfidenceLevel.low.label)
            .accessibilityHidden(true)
    }
}
