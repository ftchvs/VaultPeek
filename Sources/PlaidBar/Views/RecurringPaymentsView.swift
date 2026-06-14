import PlaidBarCore
import SwiftUI

struct RecurringPaymentsView: View {
    let presentation: RecurringPaymentsSurfacePresentation
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.4)

            if presentation.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        summary

                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(presentation.rows) { row in
                                RecurringPaymentRow(row: row)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recurring payments. \(presentation.summaryText)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Subscriptions")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Text("Estimated \(presentation.estimatedMonthlyTotalText)/mo")
                    .microText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Close recurring payments")
            .accessibilityLabel("Close recurring payments")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Spacing.md)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(presentation.summaryText)
                .detailText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.attentionCount > 0 {
                Label("\(presentation.attentionCount) changed or stale", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SemanticColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.raised)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(presentation.emptyTitle, systemImage: "calendar.badge.clock")
        } description: {
            Text(presentation.emptyDetail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }
}

private struct RecurringPaymentRow: View {
    let row: RecurringPaymentsSurfacePresentation.Row

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.merchantName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                Text(row.amountText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.xs) {
                GridRow {
                    RecurringPaymentMetric(title: "Frequency", value: row.frequencyText)
                    RecurringPaymentMetric(title: "Last", value: row.lastChargeText)
                }
                GridRow {
                    RecurringPaymentMetric(title: "Next", value: row.nextExpectedText)
                    RecurringPaymentMetric(title: "Monthly", value: row.monthlyEquivalentText)
                }
                GridRow {
                    RecurringPaymentMetric(title: "Confidence", value: row.confidenceText)
                    Spacer(minLength: 0)
                }
            }

            if !row.flagExplanations.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(row.flagExplanations, id: \.self) { explanation in
                        Label(explanation, systemImage: row.needsAttention ? "exclamationmark.triangle" : "questionmark.circle")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(row.needsAttention ? SemanticColors.warning : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(row.needsAttention ? .emphasized(SemanticColors.warning) : .raised)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct RecurringPaymentMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
