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
            lowCashThreshold: appState.lowBalanceThreshold,
            largeTransactionThreshold: appState.largeTransactionThreshold,
            balanceHistory: appState.balanceHistory
        )
    }

    var body: some View {
        let presentation = presentation
        let privacyMaskEnabled = appState.shouldMaskFinancialValues

        VStack(spacing: 0) {
            header(presentation, privacyMaskEnabled: privacyMaskEnabled)
                .padding(Spacing.md)

            Divider()
                .opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    WealthMetricGrid(presentation: presentation, privacyMaskEnabled: privacyMaskEnabled)
                        .loadingRedaction(appState.loadState(for: .summaryCards))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthBalanceMixSection(presentation: presentation, privacyMaskEnabled: privacyMaskEnabled)
                        .loadingRedaction(appState.loadState(for: .summaryCards))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthCashflowSection(cashflow: presentation.cashflow, privacyMaskEnabled: privacyMaskEnabled)
                        .loadingRedaction(appState.loadState(for: .transactions))
                        .scrollEdgeDepth(reduceMotion: reduceMotion)

                    SafeToSpendCard(
                        result: SafeToSpendCalculator.compute(
                            accounts: appState.accounts,
                            recurringTransactions: appState.recurringTransactions,
                            cashflow: presentation.cashflow,
                            asOf: Date()
                        ),
                        lastUpdatedRelative: appState.lastSyncRelative,
                        privacyMaskEnabled: privacyMaskEnabled
                    )
                    .loadingRedaction(appState.loadState(for: .summaryCards))
                    .scrollEdgeDepth(reduceMotion: reduceMotion)

                    // Forward cash-flow forecast (AND-498). Self-hides until
                    // there is enough recorded balance history to anchor a line.
                    ProjectedBalanceSection(
                        presentation: ProjectedBalancePresentation.evaluate(
                            history: appState.balanceHistory,
                            recurring: appState.recurringTransactions,
                            now: Date()
                        ),
                        privacyMaskEnabled: privacyMaskEnabled
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
                        onOpenSubscriptions: onOpenSubscriptions,
                        privacyMaskEnabled: privacyMaskEnabled
                    )
                    .loadingRedaction(appState.loadState(for: .transactions))
                    .scrollEdgeDepth(reduceMotion: reduceMotion)

                    WealthCreditSection(
                        summary: presentation.creditUtilization,
                        threshold: appState.creditUtilizationThreshold,
                        privacyMaskEnabled: privacyMaskEnabled
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
        .accessibilityLabel(accessibilitySummary(presentation, privacyMaskEnabled: privacyMaskEnabled))
    }

    private func header(
        _ presentation: WealthSummaryPresentation,
        privacyMaskEnabled: Bool
    ) -> some View {
        let netWorthText = PrivacyMaskPresentation.currency(
            presentation.netWorth,
            format: .full,
            isEnabled: privacyMaskEnabled,
            style: .hero
        )
        return VStack(alignment: .leading, spacing: Spacing.sm) {
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

                Text(netWorthText)
                    .displayBalance()
                    .rollingTabularNumber(netWorthText, reduceMotion: reduceMotion)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !privacyMaskEnabled {
                    WealthNetWorthTrendBlock(trend: presentation.netWorthTrend)
                }
            }
            .padding(Spacing.sm)
            .heroAccentSurface()
        }
    }

    private func accessibilitySummary(
        _ presentation: WealthSummaryPresentation,
        privacyMaskEnabled: Bool
    ) -> String {
        let netWorth = PrivacyMaskPresentation.currency(
            presentation.netWorth,
            format: .full,
            isEnabled: privacyMaskEnabled,
            style: .hero
        )
        let netCashflow = privacyMaskEnabled
            ? PrivacyMaskPresentation.compactValue
            : cashflowText(presentation.cashflow.net, format: .full)
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
    let privacyMaskEnabled: Bool

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
                value: PrivacyMaskPresentation.currency(presentation.totalAssets, format: .compact, isEnabled: privacyMaskEnabled),
                detail: "\(presentation.accountCount) accounts",
                systemImage: "building.columns.fill",
                reduceMotion: reduceMotion
            )

            WealthMetricTile(
                title: "Debt",
                value: PrivacyMaskPresentation.currency(presentation.totalDebt, format: .compact, isEnabled: privacyMaskEnabled),
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
    let privacyMaskEnabled: Bool

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
                        WealthMixLegendRow(
                            segment: segment,
                            tint: tint(for: segment.id),
                            privacyMaskEnabled: privacyMaskEnabled
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tint(for id: String) -> Color {
        switch id {
        case "cash":
            SemanticColors.positive
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
    let privacyMaskEnabled: Bool

    private var compactValue: String {
        PrivacyMaskPresentation.currency(segment.value, format: .compact, isEnabled: privacyMaskEnabled)
    }

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

            Text(compactValue)
                .font(.caption.weight(.semibold))
                .rollingTabularNumber(compactValue, reduceMotion: reduceMotion)
                .lineLimit(1)

            Text(percentText(segment.share))
                .microText()
                .foregroundStyle(.secondary)
                .rollingTabularNumber(percentText(segment.share), reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(segment.title): \(PrivacyMaskPresentation.currency(segment.value, format: .full, isEnabled: privacyMaskEnabled)), \(percentText(segment.share))"
        )
    }
}

private struct WealthCashflowSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cashflow: WealthSummaryPresentation.CashflowSummary
    let privacyMaskEnabled: Bool

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
                WealthCashflowRow(title: "Income", amount: cashflow.income, role: .income, privacyMaskEnabled: privacyMaskEnabled, reduceMotion: reduceMotion)
                WealthCashflowRow(title: "Spending", amount: cashflow.spending, role: .spending, privacyMaskEnabled: privacyMaskEnabled, reduceMotion: reduceMotion)
                WealthCashflowRow(title: "Net", amount: cashflow.net, role: .net, privacyMaskEnabled: privacyMaskEnabled, reduceMotion: reduceMotion)
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
    var privacyMaskEnabled: Bool = false
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
        guard !privacyMaskEnabled else { return PrivacyMaskPresentation.compactValue }
        switch role {
        case .income, .net:
            return cashflowText(amount, format: .compact)
        case .spending:
            return Formatters.currency(amount, format: .compact)
        }
    }

    private var accessibilityAmountText: String {
        guard !privacyMaskEnabled else { return PrivacyMaskPresentation.compactValue }
        switch role {
        case .income, .net:
            return cashflowText(amount, format: .full)
        case .spending:
            return Formatters.currency(amount, format: .full)
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

/// Forward cash-flow forecast block (AND-498). Self-hides when there isn't
/// enough recorded balance history to anchor a line; masks the chart (which
/// shows balance amounts) when privacy mode is on.
private struct ProjectedBalanceSection: View {
    let presentation: ProjectedBalancePresentation
    let privacyMaskEnabled: Bool

    var body: some View {
        switch presentation {
        case let .available(projection):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    WealthFlyoutSectionLabel("Projected balance")
                    Spacer()
                    Text("\(projection.series.count - 1)D")
                        .microText()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if privacyMaskEnabled {
                    Label("Forecast hidden while VaultPeek is private", systemImage: "eye.slash")
                        .detailText()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                } else {
                    ProjectedBalanceChart(projection: projection)
                }
            }
            .accessibilityElement(children: .contain)
        case .insufficientHistory:
            // Stay quiet until there is enough history — no empty placeholder.
            EmptyView()
        }
    }
}

private struct WealthCreditSection: View {
    let summary: WealthSummaryPresentation.CreditUtilizationSummary?
    let threshold: Double
    let privacyMaskEnabled: Bool

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
                        Text("\(percentValue(summary)) utilization, \(summary.statusLabel.lowercased())")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("\(usedValue(summary, format: .compact)) used of \(limitValue(summary, format: .compact)) limit")
                            .detailText()
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Credit utilization \(percentValue(summary)), \(summary.statusLabel). \(usedValue(summary, format: .full)) used of \(limitValue(summary, format: .full)) limit."
                )
            } else {
                Label("No credit utilization available", systemImage: "creditcard")
                    .detailText()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentValue(_ summary: WealthSummaryPresentation.CreditUtilizationSummary) -> String {
        PrivacyMaskPresentation.percent(summary.percent, decimals: 0, isEnabled: privacyMaskEnabled)
    }

    private func usedValue(
        _ summary: WealthSummaryPresentation.CreditUtilizationSummary,
        format: CurrencyFormat
    ) -> String {
        PrivacyMaskPresentation.currency(summary.usedCredit, format: format, isEnabled: privacyMaskEnabled)
    }

    private func limitValue(
        _ summary: WealthSummaryPresentation.CreditUtilizationSummary,
        format: CurrencyFormat
    ) -> String {
        PrivacyMaskPresentation.currency(summary.totalLimit, format: format, isEnabled: privacyMaskEnabled)
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
