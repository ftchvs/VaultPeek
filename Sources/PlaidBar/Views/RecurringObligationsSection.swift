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
                        RecurringObligationRow(item: item)
                    }
                }

                if presentation.count > visibleLimit {
                    Text("+\(presentation.count - visibleLimit) more")
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
            Text("Recurring")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            Text("~\(Formatters.currency(presentation.estimatedMonthlyTotal, format: .compact))/mo")
                .microText()
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private var accessibilitySummary: String {
        let countText = "\(presentation.count) recurring \(presentation.count == 1 ? "charge" : "charges")"
        let total = Formatters.currency(presentation.estimatedMonthlyTotal, format: .full)
        let attention = presentation.attentionCount > 0
            ? " \(presentation.attentionCount) need attention."
            : ""
        return "\(countText), about \(total) per month.\(attention)"
    }
}

private struct RecurringObligationRow: View {
    let item: RecurringObligationsPresentation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Label {
                    Text(item.merchantName)
                        .font(.subheadline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: item.frequency.iconName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                Text(Formatters.currency(item.expectedAmount, format: .compact))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)
            }

            HStack(spacing: Spacing.xs) {
                Text("\(item.frequency.displayName) · next \(Formatters.displayTransactionDate(item.nextExpectedDate))")
                    .microText()
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

    /// Deterministic flag order so badges don't reshuffle between renders.
    private var orderedFlags: [RecurringStreamFlag] {
        RecurringStreamFlag.allCases.filter { item.flags.contains($0) }
    }

    private var accessibilityLabel: String {
        var parts = [
            item.merchantName,
            item.frequency.displayName,
            "expected \(Formatters.currency(item.expectedAmount, format: .full))",
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

private struct LowConfidenceBadge: View {
    var body: some View {
        Label {
            Text(RecurringConfidenceLevel.low.label)
        } icon: {
            Image(systemName: RecurringConfidenceLevel.low.iconName)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .lineLimit(1)
    }
}
