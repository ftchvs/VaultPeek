import PlaidBarCore
import SwiftUI

struct FirstRunSnapshotView: View {
    let presentation: FirstRunSnapshotPresentation
    let isMasked: Bool
    let onDismiss: () -> Void

    private var snapshot: FirstRunSnapshot {
        presentation.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: Spacing.sm) {
                SnapshotMetricTile(
                    title: "Cash Available",
                    value: PrivacyMaskPresentation.currency(snapshot.cashAvailable, format: .compact, isEnabled: isMasked),
                    detail: "\(snapshot.cashAccountCount) cash account\(snapshot.cashAccountCount == 1 ? "" : "s")",
                    icon: "banknote",
                    accessibilityLabel: "Cash available \(PrivacyMaskPresentation.currency(snapshot.cashAvailable, format: .full, isEnabled: isMasked)) across \(snapshot.cashAccountCount) cash account\(snapshot.cashAccountCount == 1 ? "" : "s")."
                )

                SnapshotMetricTile(
                    title: "Net Worth",
                    value: PrivacyMaskPresentation.currency(snapshot.netWorth, format: .compact, isEnabled: isMasked),
                    detail: "Local estimate",
                    icon: "sum",
                    accessibilityLabel: "Net worth estimate \(PrivacyMaskPresentation.currency(snapshot.netWorth, format: .full, isEnabled: isMasked))."
                )

                SnapshotMetricTile(
                    title: "Month To Date",
                    value: monthToDateValue,
                    detail: monthToDateDetail,
                    icon: "calendar",
                    accessibilityLabel: monthToDateAccessibilityLabel
                )

                SnapshotMetricTile(
                    title: "Credit",
                    value: creditValue,
                    detail: creditDetail,
                    icon: creditIcon,
                    accessibilityLabel: creditAccessibilityLabel
                )
            }

            largeTransactionsSection
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroAccentSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.maskedAccessibilitySummary(isMasked: isMasked))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3.weight(.medium))
                .foregroundStyle(SemanticColors.brand)
                .frame(width: Sizing.iconChip)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(presentation.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(presentation.subtitle)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: Sizing.hitTargetMin, height: Sizing.hitTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss first snapshot")
            .accessibilityHint(presentation.dismissalAccessibilityHint)
            .help("Dismiss")
        }
    }

    private var largeTransactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label("Large Recent Transactions", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(largeTransactionSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if snapshot.largeTransactions.isEmpty {
                SnapshotEmptyRow(
                    icon: "checkmark.circle",
                    text: largeTransactionEmptyText,
                    accessibilityLabel: largeTransactionEmptyText
                )
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(snapshot.largeTransactions) { transaction in
                        SnapshotTransactionRow(transaction: transaction, isMasked: isMasked)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 118), spacing: Spacing.sm),
            GridItem(.flexible(minimum: 118), spacing: Spacing.sm),
        ]
    }

    private var monthToDateValue: String {
        guard let spend = snapshot.monthToDateSpend else { return "Not Available" }
        return PrivacyMaskPresentation.currency(spend, format: .compact, isEnabled: isMasked)
    }

    private var monthToDateDetail: String {
        switch snapshot.transactionState {
        case .ready:
            "Synced spend"
        case .syncing:
            "Transactions syncing"
        case .empty:
            "No transaction rows"
        }
    }

    private var monthToDateAccessibilityLabel: String {
        guard let spend = snapshot.monthToDateSpend else {
            return "\(monthToDateDetail). Month-to-date spend is not available."
        }
        return "Month-to-date spend \(PrivacyMaskPresentation.currency(spend, format: .full, isEnabled: isMasked))."
    }

    private var creditValue: String {
        guard snapshot.hasCreditAccounts else { return "No Credit" }
        guard let utilization = snapshot.creditUtilization else { return "No Limit" }
        return PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: isMasked)
    }

    private var creditDetail: String {
        if snapshot.hasCreditAccounts, let utilization = snapshot.creditUtilization {
            // Masked: drop the derived low/elevated/high status so the magnitude
            // of utilization is not leaked through the qualitative band.
            if isMasked { return "Utilization" }
            return "Utilization, \(creditUtilizationStatus(for: utilization))"
        }
        if snapshot.hasDebtAccounts {
            return "\(PrivacyMaskPresentation.currency(snapshot.debtTotal, format: .compact, isEnabled: isMasked)) balance"
        }
        return "No credit balance"
    }

    private var creditIcon: String {
        // Masked: the utilization-derived icon encodes the magnitude band, so
        // fall back to the neutral creditcard glyph rather than a status icon.
        guard !isMasked, let utilization = snapshot.creditUtilization else { return "creditcard" }
        return SemanticColors.utilizationIcon(for: utilization)
    }

    private var creditAccessibilityLabel: String {
        if snapshot.hasCreditAccounts, let utilization = snapshot.creditUtilization {
            if isMasked {
                return "Credit utilization \(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: true)). Debt balance \(PrivacyMaskPresentation.currency(snapshot.debtTotal, format: .full, isEnabled: true))."
            }
            return "Credit utilization \(Formatters.percent(utilization, decimals: 0)), \(creditUtilizationStatus(for: utilization)). Debt balance \(Formatters.currency(snapshot.debtTotal, format: .full))."
        }
        if snapshot.hasDebtAccounts {
            return "Credit utilization unavailable. Debt balance \(PrivacyMaskPresentation.currency(snapshot.debtTotal, format: .full, isEnabled: isMasked))."
        }
        return "No credit utilization or debt balance available."
    }

    private var largeTransactionSummary: String {
        if snapshot.largeTransactions.isEmpty { return "None found" }
        return "\(snapshot.largeTransactions.count) found"
    }

    private var largeTransactionEmptyText: String {
        switch snapshot.transactionState {
        case .ready:
            "No recent transactions above your alert threshold."
        case .syncing:
            "Transaction history is still syncing."
        case .empty:
            "No transaction rows are available yet."
        }
    }

    private func creditUtilizationStatus(for utilization: Double) -> String {
        if utilization < 30 { return "low" }
        if utilization < 75 { return "elevated" }
        return "high"
    }
}

private struct SnapshotMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Sizing.iconInline)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidDataSurface(cornerRadius: Radius.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SnapshotTransactionRow: View {
    let transaction: FirstRunSnapshot.LargeTransaction
    let isMasked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "arrow.up.right.circle")
                .foregroundStyle(.secondary)
                .frame(width: Sizing.iconInline)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(transaction.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(Formatters.displayTransactionDate(transaction.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(PrivacyMaskPresentation.currency(transaction.amount, format: .compact, isEnabled: isMasked))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transaction.displayName), \(PrivacyMaskPresentation.currency(transaction.amount, format: .full, isEnabled: isMasked)), \(Formatters.displayTransactionDate(transaction.date)).")
    }
}

private struct SnapshotEmptyRow: View {
    let icon: String
    let text: String
    let accessibilityLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: Sizing.iconInline)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
