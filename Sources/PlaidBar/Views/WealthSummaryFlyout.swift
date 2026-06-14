import PlaidBarCore
import SwiftUI

struct WealthSummaryFlyout: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onAddAccount: () -> Void
    var onOpenSubscriptions: (() -> Void)?

    private var presentation: WealthSummaryPresentation {
        WealthSummaryPresentation.evaluate(
            accounts: appState.accounts,
            transactions: appState.transactions,
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            credentialsConfigured: appState.serverCredentialsConfigured,
            linkedItemCount: appState.statusItemCount,
            syncedItemCount: appState.serverSyncedItemCount ?? 0,
            itemStatuses: appState.itemStatuses,
            isSyncStale: appState.isSyncStale,
            lastSyncRelative: appState.lastSyncRelative,
            statusSyncText: appState.statusSyncText,
            errorMessage: appState.error,
            creditUtilizationThreshold: appState.creditUtilizationThreshold,
            balanceHistory: appState.balanceHistory
        )
    }

    var body: some View {
        let presentation = presentation

        VStack(spacing: 0) {
            header(presentation)
                .padding(Spacing.md)

            Divider()
                .opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    WealthMetricGrid(presentation: presentation)
                        .loadingRedaction(appState.loadState(for: .summaryCards))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthBalanceMixSection(presentation: presentation)
                        .loadingRedaction(appState.loadState(for: .summaryCards))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthCashflowSection(cashflow: presentation.cashflow)
                        .loadingRedaction(appState.loadState(for: .transactions))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    SafeToSpendCard(
                        result: SafeToSpendCalculator.compute(
                            accounts: appState.accounts,
                            recurringTransactions: appState.recurringTransactions,
                            cashflow: presentation.cashflow,
                            asOf: Date()
                        ),
                        lastUpdatedRelative: appState.lastSyncRelative
                    )
                    .loadingRedaction(appState.loadState(for: .summaryCards))
                    .scrollEdgeDepth(reduceMotion: reduceMotion)

                    // Read-only recurring obligations (AND-400). Built inline
                    // from the already-cached detector output, mirroring how the
                    // safe-to-spend card is composed above; self-hides when no
                    // recurring series are detected.
                    RecurringObligationsSection(
                        presentation: RecurringObligationsPresentation.make(
                            from: appState.recurringTransactions,
                            asOf: Date()
                        ),
                        onOpenSubscriptions: onOpenSubscriptions
                    )
                    .loadingRedaction(appState.loadState(for: .transactions))
                    .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthCreditSection(
                        summary: presentation.creditUtilization,
                        threshold: appState.creditUtilizationThreshold
                    )
                        .loadingRedaction(appState.loadState(for: .credit))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthAttentionSection(summary: presentation.attention)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    if presentation.accountCount == 0 {
                        Button(action: onAddAccount) {
                            Label("Connect Bank", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Group the flyout's coexisting glass panels (metric tiles) into
                // one GlassEffectContainer sampling region on macOS 26; passthrough
                // on macOS 15 (AND-381). Merge radius = SurfaceTokens.glassMergeRadius.
                .glassGroup()
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(presentation))
    }

    private func header(_ presentation: WealthSummaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wealth Summary")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                WealthSyncPill(summary: presentation.syncHealth)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Net worth")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Text(Formatters.currency(presentation.netWorth, format: .full))
                    .displayBalance()
                    .rollingTabularNumber(Formatters.currency(presentation.netWorth, format: .full), reduceMotion: reduceMotion)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                WealthNetWorthTrendBlock(trend: presentation.netWorthTrend)
            }
            .padding(Spacing.sm)
            .heroAccentSurface()
        }
    }

    private func accessibilitySummary(_ presentation: WealthSummaryPresentation) -> String {
        let netWorth = Formatters.currency(presentation.netWorth, format: .full)
        let netCashflow = cashflowText(presentation.cashflow.net, format: .full)
        return "Wealth summary. Net worth \(netWorth). 30 day net cashflow \(netCashflow). \(presentation.syncHealth.title). \(presentation.attention.detail)"
    }
}

private struct WealthNetWorthTrendBlock: View {
    let trend: NetWorthTrendPresentation

    var body: some View {
        switch trend {
        case let .available(balanceTrend):
            HStack(alignment: .center, spacing: Spacing.sm) {
                BalanceTrendChart(trend: balanceTrend)
                    .frame(height: 38)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(balanceTrend.deltaText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(balanceTrend.spanText)
                        .microText()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(balanceTrend.accessibilitySummary)
            .help(balanceTrend.accessibilitySummary)
        case let .insufficientHistory(pointCount, requiredPointCount):
            Label(
                "Trend pending · \(max(requiredPointCount - pointCount, 0)) more snapshot\(max(requiredPointCount - pointCount, 0) == 1 ? "" : "s")",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .detailText()
            .accessibilityLabel(trend.accessibilitySummary)
        }
    }
}

private struct WealthSyncPill: View {
    let summary: WealthSummaryPresentation.SyncHealthSummary

    var body: some View {
        Label {
            Text(shortTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: summary.iconName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .help("\(summary.title). \(summary.detail)")
        .accessibilityLabel("\(summary.title). \(summary.detail)")
    }

    private var shortTitle: String {
        switch summary.severity {
        case .healthy:
            summary.title
        case .warning:
            "Attention"
        case .blocked:
            "Blocked"
        }
    }

    private var tint: Color {
        switch summary.severity {
        case .healthy:
            .secondary
        case .warning:
            SemanticColors.warning
        case .blocked:
            SemanticColors.negative
        }
    }
}

private struct WealthMetricGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: WealthSummaryPresentation

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 108), spacing: Spacing.sm),
            GridItem(.flexible(minimum: 108), spacing: Spacing.sm),
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.sm) {
            WealthMetricTile(
                title: "Assets",
                value: Formatters.currency(presentation.totalAssets, format: .compact),
                detail: "\(presentation.accountCount) accounts",
                systemImage: "building.columns.fill",
                reduceMotion: reduceMotion
            )

            WealthMetricTile(
                title: "Debt",
                value: Formatters.currency(presentation.totalDebt, format: .compact),
                detail: presentation.totalDebt > 0 ? "Credit and loans" : "No debt synced",
                systemImage: "creditcard.fill",
                tint: presentation.totalDebt > 0 ? SemanticColors.creditDebt : AppearanceTextColors.secondary,
                reduceMotion: reduceMotion
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WealthMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = .secondary
    var reduceMotion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .microText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .dataText()
                .rollingTabularNumber(value, reduceMotion: reduceMotion)
                .foregroundStyle(AppearanceTextColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .glassSurface(.inset, cornerRadius: Radius.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

private struct WealthBalanceMixSection: View {
    let presentation: WealthSummaryPresentation

    private var barSegments: [BalanceCompositionBarSegment] {
        presentation.balanceMix.segments.map { segment in
            BalanceCompositionBarSegment(
                id: segment.id,
                title: segment.title,
                value: segment.value,
                share: segment.share,
                tint: tint(for: segment.id)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            WealthFlyoutSectionLabel("Balance mix")

            if presentation.balanceMix.segments.isEmpty {
                Label("No balances loaded", systemImage: "chart.pie")
                    .detailText()
                    .foregroundStyle(.secondary)
            } else {
                AnimatedBalanceCompositionBar(segments: barSegments)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(presentation.balanceMix.segments) { segment in
                        WealthMixLegendRow(segment: segment, tint: tint(for: segment.id))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tint(for id: String) -> Color {
        switch id {
        case "cash":
            Color.secondary.opacity(0.6)
        case "investments":
            Color.primary.opacity(0.36)
        case "credit":
            SemanticColors.creditDebt
        case "loans":
            SemanticColors.warning
        default:
            Color.secondary.opacity(0.6)
        }
    }
}

private struct WealthMixLegendRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let segment: BalanceCompositionPresentation.Segment
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(segment.title)
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Text(Formatters.currency(segment.value, format: .compact))
                .font(.caption.weight(.semibold))
                .rollingTabularNumber(Formatters.currency(segment.value, format: .compact), reduceMotion: reduceMotion)
                .lineLimit(1)

            Text(percentText(segment.share))
                .microText()
                .foregroundStyle(.secondary)
                .rollingTabularNumber(percentText(segment.share), reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(segment.title): \(Formatters.currency(segment.value, format: .full)), \(percentText(segment.share))"
        )
    }
}

private struct WealthCashflowSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cashflow: WealthSummaryPresentation.CashflowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                WealthFlyoutSectionLabel("\(cashflow.windowDays)D cashflow")
                Spacer()
                Text("\(cashflow.transactionCount) tx")
                    .microText()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Spacing.xs) {
                WealthCashflowRow(title: "Income", amount: cashflow.income, role: .income, reduceMotion: reduceMotion)
                WealthCashflowRow(title: "Spending", amount: cashflow.spending, role: .spending, reduceMotion: reduceMotion)
                WealthCashflowRow(title: "Net", amount: cashflow.net, role: .net, reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private enum WealthCashflowRole {
    case income
    case spending
    case net
}

private struct WealthCashflowRow: View {
    let title: String
    let amount: Double
    let role: WealthCashflowRole
    var reduceMotion: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label(title, systemImage: iconName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            Text(amountText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(accessibilityAmountText)")
    }

    private var iconName: String {
        switch role {
        case .income:
            "arrow.down.circle.fill"
        case .spending:
            "arrow.up.circle.fill"
        case .net:
            amount >= 0 ? "plus.circle.fill" : "minus.circle.fill"
        }
    }

    private var amountText: String {
        switch role {
        case .income, .net:
            cashflowText(amount, format: .compact)
        case .spending:
            Formatters.currency(amount, format: .compact)
        }
    }

    private var accessibilityAmountText: String {
        switch role {
        case .income, .net:
            cashflowText(amount, format: .full)
        case .spending:
            Formatters.currency(amount, format: .full)
        }
    }

    private var tint: Color {
        switch role {
        case .income:
            return SemanticColors.positive
        case .spending:
            return AppearanceTextColors.primary
        case .net:
            if amount > 0 { return SemanticColors.positive }
            if amount < 0 { return SemanticColors.negative }
            return AppearanceTextColors.secondary
        }
    }
}

private struct WealthCreditSection: View {
    let summary: WealthSummaryPresentation.CreditUtilizationSummary?
    let threshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            WealthFlyoutSectionLabel("Credit")

            if let summary {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: SemanticColors.utilizationIcon(for: summary.percent, threshold: threshold))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint(summary))
                        .frame(width: Sizing.iconInline, height: Sizing.iconInline)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("\(Formatters.percent(summary.percent, decimals: 0)) utilization, \(summary.statusLabel.lowercased())")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("\(Formatters.currency(summary.usedCredit, format: .compact)) used of \(Formatters.currency(summary.totalLimit, format: .compact)) limit")
                            .detailText()
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Credit utilization \(Formatters.percent(summary.percent, decimals: 0)), \(summary.statusLabel). \(Formatters.currency(summary.usedCredit, format: .full)) used of \(Formatters.currency(summary.totalLimit, format: .full)) limit."
                )
            } else {
                Label("No credit utilization available", systemImage: "creditcard")
                    .detailText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tint(_ summary: WealthSummaryPresentation.CreditUtilizationSummary) -> Color {
        guard summary.exceedsThreshold else { return AppearanceTextColors.secondary }
        return SemanticColors.utilization(for: summary.percent, threshold: threshold)
    }
}

private struct WealthAttentionSection: View {
    let summary: WealthSummaryPresentation.AttentionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            WealthFlyoutSectionLabel("Attention")

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: Sizing.iconInline, height: Sizing.iconInline)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(summary.title)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailText)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(summary.title). \(detailText)")
        }
    }

    private var detailText: String {
        guard summary.visibleRowCount > 1 else { return summary.detail }
        return "\(summary.detail) \(summary.visibleRowCount - 1) more item\(summary.visibleRowCount == 2 ? "" : "s") in Attention."
    }

    private var iconName: String {
        switch summary.severity {
        case .healthy:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .blocked:
            "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch summary.severity {
        case .healthy:
            .secondary
        case .warning:
            SemanticColors.warning
        case .blocked:
            SemanticColors.negative
        }
    }
}

private struct WealthFlyoutSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .sectionTitle()
            .foregroundStyle(.secondary)
    }
}

private func cashflowText(_ amount: Double, format: CurrencyFormat) -> String {
    if amount > 0 {
        return "+\(Formatters.currency(amount, format: format))"
    }
    if amount < 0 {
        return "-\(Formatters.currency(abs(amount), format: format))"
    }
    return Formatters.currency(0, format: format)
}

private func percentText(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
}
