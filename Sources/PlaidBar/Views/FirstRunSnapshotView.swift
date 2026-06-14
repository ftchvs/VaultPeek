import PlaidBarCore
import SwiftUI

struct FirstRunSnapshotView: View {
    let presentation: FirstRunSnapshotPresentation
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
                    value: Formatters.currency(snapshot.cashAvailable, format: .compact),
                    detail: "\(snapshot.cashAccountCount) cash account\(snapshot.cashAccountCount == 1 ? "" : "s")",
                    icon: "banknote",
                    accessibilityLabel: "Cash available \(Formatters.currency(snapshot.cashAvailable, format: .full)) across \(snapshot.cashAccountCount) cash account\(snapshot.cashAccountCount == 1 ? "" : "s")."
                )

                SnapshotMetricTile(
                    title: "Net Worth",
                    value: Formatters.currency(snapshot.netWorth, format: .compact),
                    detail: "Local estimate",
                    icon: "sum",
                    accessibilityLabel: "Net worth estimate \(Formatters.currency(snapshot.netWorth, format: .full))."
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
        .glassSurface(.hero(SemanticColors.brand))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.primaryAccessibilityLabel)
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
                        SnapshotTransactionRow(transaction: transaction)
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
        return Formatters.currency(spend, format: .compact)
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
        return "Month-to-date spend \(Formatters.currency(spend, format: .full))."
    }

    private var creditValue: String {
        guard snapshot.hasCreditAccounts else { return "No Credit" }
        guard let utilization = snapshot.creditUtilization else { return "No Limit" }
        return Formatters.percent(utilization, decimals: 0)
    }

    private var creditDetail: String {
        if snapshot.hasCreditAccounts, let utilization = snapshot.creditUtilization {
            return "Utilization, \(creditUtilizationStatus(for: utilization))"
        }
        if snapshot.hasDebtAccounts {
            return "\(Formatters.currency(snapshot.debtTotal, format: .compact)) balance"
        }
        return "No credit balance"
    }

    private var creditIcon: String {
        guard let utilization = snapshot.creditUtilization else { return "creditcard" }
        return SemanticColors.utilizationIcon(for: utilization)
    }

    private var creditAccessibilityLabel: String {
        if snapshot.hasCreditAccounts, let utilization = snapshot.creditUtilization {
            return "Credit utilization \(Formatters.percent(utilization, decimals: 0)), \(creditUtilizationStatus(for: utilization)). Debt balance \(Formatters.currency(snapshot.debtTotal, format: .full))."
        }
        if snapshot.hasDebtAccounts {
            return "Credit utilization unavailable. Debt balance \(Formatters.currency(snapshot.debtTotal, format: .full))."
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
        .glassSurface(.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SnapshotTransactionRow: View {
    let transaction: FirstRunSnapshot.LargeTransaction

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

            Text(Formatters.currency(transaction.amount, format: .compact))
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
        .accessibilityLabel("\(transaction.displayName), \(Formatters.currency(transaction.amount, format: .full)), \(Formatters.displayTransactionDate(transaction.date)).")
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
