import AppKit
import PlaidBarCore
import SwiftUI

struct RecurringPaymentsView: View {
    let presentation: RecurringPaymentsSurfacePresentation
    var loadState: DashboardLoadState?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.4)

            if presentation.isEmpty {
                // Honor load phase before declaring "nothing recurring": an
                // empty rows list during loading/offline/error should not read
                // as a confident "no recurring payments detected".
                switch loadState?.phase {
                case .loading:
                    loadingState
                case .offline:
                    offlineState
                case .error:
                    errorState
                default:
                    emptyState
                }
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

            if let forgottenCallout = presentation.forgottenCalloutText {
                Label(forgottenCallout, systemImage: "questionmark.app.dashed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SemanticColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if presentation.attentionCount > 0 {
                Label("\(presentation.attentionCount) changed or stale", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SemanticColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidDataSurface(cornerRadius: Radius.panel, fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.controlFillOpacity)))
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

    private var loadingState: some View {
        ContentUnavailableView {
            Label(DashboardLoadSurface.recurring.loadingTitle, systemImage: "calendar.badge.clock")
        } description: {
            Text(DashboardLoadSurface.recurring.loadingDetail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
        .accessibilityLabel(loadState?.loadingAccessibilityLabel ?? DashboardLoadSurface.recurring.loadingTitle)
    }

    private var offlineState: some View {
        ContentUnavailableView {
            Label("Recurring charges unavailable", systemImage: "wifi.slash")
        } description: {
            Text("VaultPeek can't reach the local server, so recurring charges aren't available yet. Reconnect to refresh.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("Recurring charges unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The last refresh didn't finish, so recurring charges aren't available yet. Refresh to try again.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }
}

private struct RecurringPaymentRow: View {
    let row: RecurringPaymentsSurfacePresentation.Row

    var body: some View {
        Group {
            // A ternary can't pick between `emphasizedDataSurface` and
            // `solidDataSurface` directly (different `ViewModifier` types behind
            // `some View`), so the attention state branches the surface call itself.
            if row.needsAttention {
                rowContent.emphasizedDataSurface(tint: SemanticColors.warning)
            } else {
                rowContent.solidDataSurface(
                    cornerRadius: Radius.panel,
                    fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.controlFillOpacity))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var rowContent: some View {
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

            // Cancel-help action (AND-497). Surfaced for every row, leading with
            // a chevron for known merchant pages so it never reads via color alone.
            Button {
                NSWorkspace.shared.open(row.cancelURL)
            } label: {
                Label(row.cancelLinkText, systemImage: "xmark.circle")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(row.cancelIsSpecific
                ? "Open \(row.merchantName)'s cancellation page"
                : "Search how to cancel \(row.merchantName)")
            .accessibilityLabel("How to cancel \(row.merchantName)")
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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
