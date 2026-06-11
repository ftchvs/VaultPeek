import AppKit
import PlaidBarCore
import SwiftUI

struct MainPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @AppStorage("dashboard.accountFilter") private var selectedFilterRawValue = DashboardAccountFilter.all.rawValue
    @AppStorage("dashboard.selectedAccountId") private var selectedAccountId = ""
    @State private var isShowingAccountSetup = false
    @State private var shouldShowSetupRecoveryDashboard = false

    private enum Layout {
        static let dashboardWidth: CGFloat = 480
        static let setupWidth: CGFloat = 560
        static let dashboardMinHeight: CGFloat = 460
        static let dashboardMaxHeight = CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
        static let contentHorizontalPadding: CGFloat = 12
        static let contentTopPadding: CGFloat = 8
        static let contentBottomPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 7
    }

    private var selectedFilter: DashboardAccountFilter {
        DashboardAccountFilter(rawValue: selectedFilterRawValue) ?? .all
    }

    private var selectedAccount: AccountDTO? {
        let accounts = filteredAccounts
        guard !selectedAccountId.isEmpty else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    private var filteredAccounts: [AccountDTO] {
        appState.accounts.filter { selectedFilter.includes($0, appState: appState) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowSetupScreen {
                SetupView()
                    .frame(width: Layout.setupWidth)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                        DashboardHeader()
                            .environment(appState)

                        DashboardStatusStrip()
                            .environment(appState)

                        if shouldElevateStatusReadinessPanel {
                            DashboardStatusReadinessPanel(
                                openSettings: { openSettings() },
                                onAddAccount: openAccountSetup
                            )
                            .environment(appState)
                        }

                        DashboardOverviewStack(
                            transactions: appState.transactions,
                            accounts: filteredAccounts,
                            filter: selectedFilter,
                            filterSelection: filterBinding,
                            selectedAccountId: selectedAccount?.id,
                            onSelectAccount: { selectedAccountId = $0.id },
                            onDeselectAccount: { selectedAccountId = "" },
                            onAddAccount: openAccountSetup
                        )
                        .environment(appState)

                        DashboardSummaryCards()
                            .environment(appState)

                        BalanceCompositionStrip()
                            .environment(appState)

                        LocalInsightsCard()
                            .environment(appState)

                        if shouldShowLowerStatusReadinessPanel {
                            DashboardStatusReadinessPanel(
                                openSettings: { openSettings() },
                                onAddAccount: openAccountSetup
                            )
                            .environment(appState)
                        }
                    }
                    .padding(.horizontal, Layout.contentHorizontalPadding)
                    .padding(.top, Layout.contentTopPadding)
                    .padding(.bottom, Layout.contentBottomPadding)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Layout.dashboardMinHeight, maxHeight: Layout.dashboardMaxHeight)

                Divider()

                DashboardFooter(
                    settingsActivation: .shared,
                    openSettings: openSettings,
                    onAddAccount: openAccountSetup
                )
                .environment(appState)
            }

            if let error = appState.error {
                ErrorBanner(error: error)
                    .environment(appState)
            }
        }
        .frame(width: shouldShowSetupScreen ? Layout.setupWidth : Layout.dashboardWidth)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: appState.error != nil)
        .sheet(
            isPresented: $isShowingAccountSetup,
            onDismiss: {
                if !appState.isSetupComplete {
                    shouldShowSetupRecoveryDashboard = true
                }
            }
        ) {
            SetupView {
                shouldShowSetupRecoveryDashboard = false
                isShowingAccountSetup = false
            }
            .environment(appState)
        }
        .task {
            await appState.loadInitialData()
        }
        .onChange(of: appState.accounts) { _, accounts in
            guard selectedAccountId.isEmpty || !accounts.contains(where: { $0.id == selectedAccountId }) else { return }
            selectedAccountId = ""
        }
        .onChange(of: selectedFilterRawValue) { _, _ in
            selectedAccountId = ""
        }
        .onChange(of: appState.isSetupComplete) { _, isComplete in
            if isComplete {
                shouldShowSetupRecoveryDashboard = false
            }
        }
    }

    private var shouldShowSetupScreen: Bool {
        !appState.isSetupComplete && !shouldShowSetupRecoveryDashboard
    }

    private var shouldShowStatusReadinessPanel: Bool {
        selectedFilter == .status || !appState.isSetupComplete || appState.dashboardStatusReadiness.level != .healthy
    }

    private var shouldElevateStatusReadinessPanel: Bool {
        !appState.isSetupComplete || appState.dashboardStatusReadiness.level != .healthy
    }

    private var shouldShowLowerStatusReadinessPanel: Bool {
        shouldShowStatusReadinessPanel && !shouldElevateStatusReadinessPanel
    }

    private var filterBinding: Binding<DashboardAccountFilter> {
        Binding(
            get: { selectedFilter },
            set: { selectedFilterRawValue = $0.rawValue }
        )
    }

    private func openAccountSetup() {
        isShowingAccountSetup = true
    }
}

// MARK: - Dashboard Header

private struct DashboardHeader: View {
    @Environment(AppState.self) private var appState

    private var trend: BalanceTrend? {
        BalanceTrend.evaluate(history: appState.balanceHistory)
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net Worth")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Text(Formatters.currency(appState.netBalance, format: .full))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            if let trend {
                VStack(alignment: .trailing, spacing: 3) {
                    BalanceTrendChart(trend: trend)
                        .frame(width: 92, height: 21)

                    Text("\(trend.deltaText) \(trend.spanText)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(deltaTint(for: trend.direction))
                        .lineLimit(1)
                }
                .padding(.top, 3)
                .padding(.trailing, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(trend.accessibilitySummary)
                .help(trend.accessibilitySummary)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text("PlaidBar")
                    .font(.headline.weight(.bold))
                Text(appState.statusSyncText)
                    .detailText()
                    .lineLimit(1)
            }
            .padding(.top, 3)
        }
    }

    private func deltaTint(for direction: BalanceTrend.Direction) -> Color {
        switch direction {
        case .up:
            SemanticColors.positive
        case .down:
            SemanticColors.negative
        case .flat:
            .secondary
        }
    }
}

private struct DashboardSummaryCards: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(
                    title: "Cash",
                    value: Formatters.currency(appState.totalCash, format: .compact),
                    detail: "\(appState.depositoryAccounts.count) cash account\(appState.depositoryAccounts.count == 1 ? "" : "s")",
                    tint: .secondary
                )

                MetricCard(
                    title: "Credit",
                    value: creditValue,
                    detail: creditDetail,
                    tint: SemanticColors.creditDebt,
                    emphasizesTint: shouldEmphasizeCredit
                )

                MetricCard(
                    title: "7D Spend",
                    value: Formatters.currency(appState.recentSpend, format: .compact),
                    detail: recentSpendDetail,
                    tint: recentSpendTint,
                    emphasizesTint: appState.recentSpend > 0
                )
            }

            HStack(spacing: 8) {
                MetricCard(
                    title: "Sync",
                    value: appState.statusSyncText,
                    detail: appState.statusServerText,
                    tint: syncTint,
                    emphasizesTint: appState.isSyncStale || !appState.serverConnected
                )

                MetricCard(
                    title: "Action",
                    value: actionValue,
                    detail: actionDetail,
                    tint: actionTint,
                    emphasizesTint: appState.dashboardStatusReadiness.level != .healthy
                )
            }
        }
    }

    private var creditValue: String {
        if let utilization = appState.totalCreditUtilization {
            return Formatters.percent(utilization, decimals: 0)
        }
        guard !appState.creditAccounts.isEmpty else { return "No credit" }
        return Formatters.currency(MenuBarSummary.totalDebt(from: appState.creditAccounts), format: .compact)
    }

    private var creditDetail: String {
        let creditCount = appState.creditAccounts.count
        guard creditCount > 0 else { return "No credit linked" }

        if appState.totalCreditUtilization != nil {
            return "\(Formatters.currency(MenuBarSummary.totalDebt(from: appState.creditAccounts), format: .compact)) owed"
        }
        return "\(creditCount) credit account\(creditCount == 1 ? "" : "s")"
    }

    private var shouldEmphasizeCredit: Bool {
        guard let utilization = appState.totalCreditUtilization else {
            return MenuBarSummary.totalDebt(from: appState.creditAccounts) > 0
        }
        return utilization >= appState.creditUtilizationThreshold
    }

    private var recentSpendDetail: String {
        appState.recentSpend > 0 ? "Last 7 days" : "No 7D spend"
    }

    private var recentSpendTint: Color {
        appState.recentSpend > 0 ? SemanticColors.negative : .secondary
    }

    private var syncTint: Color {
        if !appState.serverConnected { return SemanticColors.negative }
        if appState.isSyncStale { return SemanticColors.warning }
        return .secondary
    }

    private var actionValue: String {
        switch appState.dashboardStatusReadiness.level {
        case .healthy:
            return "None"
        case .warning:
            return "Review"
        case .blocked:
            return "Blocked"
        }
    }

    private var actionDetail: String {
        appState.dashboardStatusReadiness.title
    }

    private var actionTint: Color {
        switch appState.dashboardStatusReadiness.level {
        case .healthy:
            return .secondary
        case .warning:
            return SemanticColors.warning
        case .blocked:
            return SemanticColors.negative
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var emphasizesTint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(emphasizesTint ? tint : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .nativePanelSurface(
            fill: AnyShapeStyle(cardFill),
            stroke: cardStroke
        )
        .overlay(alignment: .leading) {
            if emphasizesTint {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }

    private var cardFill: Color {
        SurfaceTokens.panelFill(emphasisTint: emphasizesTint ? tint : nil)
    }

    private var cardStroke: Color {
        SurfaceTokens.panelStroke(emphasisTint: emphasizesTint ? tint : nil)
    }
}

private struct BalanceCompositionStrip: View {
    @Environment(AppState.self) private var appState

    private let segmentSpacing: CGFloat = 2

    private var segments: [BalanceCompositionSegment] {
        [
            BalanceCompositionSegment(
                title: "Cash",
                value: AccountPresentation.positiveBalanceTotal(
                    from: appState.accounts,
                    type: .depository
                ),
                tint: Color.secondary.opacity(0.6)
            ),
            BalanceCompositionSegment(
                title: "Investments",
                value: AccountPresentation.positiveBalanceTotal(
                    from: appState.accounts,
                    type: .investment
                ),
                tint: Color.primary.opacity(0.36)
            ),
            BalanceCompositionSegment(
                title: "Credit",
                value: AccountPresentation.debtBalanceTotal(
                    from: appState.accounts,
                    type: .credit
                ),
                tint: SemanticColors.creditDebt
            ),
            BalanceCompositionSegment(
                title: "Loans",
                value: AccountPresentation.debtBalanceTotal(
                    from: appState.accounts,
                    type: .loan
                ),
                tint: SemanticColors.warning
            ),
        ]
    }

    private var activeSegments: [BalanceCompositionSegment] {
        segments.filter { $0.value > 0 }
    }

    private var total: Double {
        max(activeSegments.reduce(0) { $0 + $1.value }, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Balance Mix")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(appState.accountCount) accounts")
                    .microText()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                HStack(spacing: segmentSpacing) {
                    ForEach(activeSegments) { segment in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.fillColor)
                            .frame(width: segmentWidth(segment, totalWidth: proxy.size.width))
                            .accessibilityLabel(
                                "\(segment.title), \(Formatters.currency(segment.value, format: .compact))"
                            )
                    }
                }
            }
            .frame(height: 7)

            Divider()
                .opacity(0.55)

            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    BalanceCompositionLegend(segment: segment)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .nativePanelSurface(
            fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.panelFillOpacity)),
            stroke: Color.primary.opacity(0.065)
        )
        .accessibilityElement(children: .contain)
    }

    private func segmentWidth(_ segment: BalanceCompositionSegment, totalWidth: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(activeSegments.count - 1, 0)) * segmentSpacing
        let availableWidth = max(totalWidth - gaps, 0)
        return max(availableWidth * CGFloat(segment.value / total), 6)
    }
}

private struct BalanceCompositionSegment: Identifiable {
    let title: String
    let value: Double
    let tint: Color

    var id: String {
        title
    }

    var fillColor: Color {
        value > 0 ? tint.opacity(0.82) : Color.primary.opacity(0.08)
    }
}

private struct BalanceCompositionLegend: View {
    let segment: BalanceCompositionSegment

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(segment.tint)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.title)
                    .microText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Formatters.currency(segment.value, format: .compact))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 365 Day Heatmap

private struct BalanceActivityHeatmap: View {
    let transactions: [TransactionDTO]

    @AppStorage("dashboard.heatmapMode") private var modeRawValue = SpendingHeatmapMode.spending.rawValue

    private let calendar = Calendar.current
    private let spacing: CGFloat = 2
    private let monthLabelHeight: CGFloat = 10
    private let monthLabelWidth: CGFloat = 22

    private var mode: SpendingHeatmapMode {
        SpendingHeatmapMode(rawValue: modeRawValue) ?? .spending
    }

    private func currentLayout() -> SpendingHeatmapLayout {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: mode,
            calendar: calendar
        )
    }

    var body: some View {
        // Derive the layout once per render. The previous computed-property form
        // re-aggregated every transaction on each property access (~8x per body).
        let layout = currentLayout()

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(layout.mode.summaryTitle)
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Heatmap metric", selection: modeBinding) {
                    Text(SpendingHeatmapMode.spending.shortLabel).tag(SpendingHeatmapMode.spending)
                    Text(SpendingHeatmapMode.netCashflow.shortLabel).tag(SpendingHeatmapMode.netCashflow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 116)

                Text(totalLabel(for: layout))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(totalTint(for: layout))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                let weeks = max(layout.weekColumns.count, 1)
                let cell = max(5, min(8, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks))))

                ZStack(alignment: .topLeading) {
                    ForEach(layout.monthMarkers) { marker in
                        Text(marker.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: monthLabelWidth, height: monthLabelHeight, alignment: .leading)
                            .offset(x: CGFloat(marker.weekIndex) * (cell + spacing), y: 0)
                    }

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: spacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        BalanceHeatmapCell(day: day, peakValue: layout.peakValue, mode: layout.mode, size: cell)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.clear)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                    .offset(y: monthLabelHeight + 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: monthLabelHeight + 3 + 7 * 8 + 6 * spacing)

            HStack(spacing: 5) {
                if layout.mode == .spending {
                    Text("Less")
                        .microText()
                        .foregroundStyle(.secondary)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BalanceHeatmapCell.fillColor(intensity: intensity, value: intensity, mode: layout.mode))
                            .frame(width: 8, height: 8)
                    }

                    Text("More")
                        .microText()
                        .foregroundStyle(.secondary)
                } else {
                    NetLegendKey(label: "Income", tint: SemanticColors.positive)
                    NetLegendKey(label: "Outflow", tint: SemanticColors.negative)
                }

                Spacer()

                Text("\(layout.activeDayCount) active days")
                    .microText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .nativePanelSurface(
            fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.panelFillOpacity)),
            stroke: Color.primary.opacity(0.065)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription).")
    }

    private var modeBinding: Binding<SpendingHeatmapMode> {
        Binding(
            get: { mode },
            set: { modeRawValue = $0.rawValue }
        )
    }

    private func totalLabel(for layout: SpendingHeatmapLayout) -> String {
        guard layout.mode == .netCashflow else {
            return Formatters.currency(layout.totalValue, format: .compact)
        }
        return cashflowText(for: layout.totalValue)
    }

    private func totalTint(for layout: SpendingHeatmapLayout) -> Color {
        guard layout.mode == .netCashflow else { return .secondary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(layout.totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return .secondary
    }

    private func cashflowText(for value: Double) -> String {
        let displayAmount = SpendingHeatmap.displayCashflowAmount(value)
        let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(displayAmount), format: .compact))"
    }
}

private struct NetLegendKey: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(0.72))
                .frame(width: 8, height: 8)
            Text(label)
                .microText()
                .foregroundStyle(.secondary)
        }
    }
}

private struct BalanceHeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let mode: SpendingHeatmapMode
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.fillColor(intensity: intensity, value: day.value, mode: mode))
            .frame(width: size, height: size)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var intensity: Double {
        SpendingHeatmap.cellIntensity(for: day, peakValue: peakValue)
    }

    private var helpText: String {
        let amount: String
        if mode == .netCashflow {
            let displayAmount = SpendingHeatmap.displayCashflowAmount(day.value)
            let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
            amount = "\(prefix)\(Formatters.currency(abs(displayAmount), format: .full))"
        } else {
            amount = Formatters.currency(day.value, format: .full)
        }
        return "\(Formatters.displayTransactionDate(day.date)): \(amount) across \(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    static func fillColor(intensity: Double, value: Double, mode: SpendingHeatmapMode) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.08) }

        let base: Color = if mode == .netCashflow, value < 0 {
            SemanticColors.positive
        } else {
            mode == .netCashflow ? SemanticColors.negative : SemanticColors.positive
        }
        return base.opacity(0.18 + (0.72 * intensity))
    }
}

// MARK: - Local Insights

private struct LocalInsightsCard: View {
    @Environment(AppState.self) private var appState

    private var summaries: [LocalAIActivitySummary] {
        appState.localAIActivitySummaries
    }

    private var availability: LocalAIAvailability {
        appState.localAIAvailability
    }

    private var primarySummary: LocalAIActivitySummary? {
        summaries.first { $0.window == .lastMonth } ?? summaries.first
    }

    private var bullets: [String] {
        Array(primarySummary?.generatedBullets.prefix(3) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text("Local Insights")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                LocalAIStatusPill(availability: availability)
            }

            Text(primarySummary?.generatedSummary ?? "Local summaries are ready when transaction history is available.")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            HStack(spacing: 6) {
                ForEach(summaries) { summary in
                    LocalInsightWindowMetric(summary: summary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.secondary.opacity(0.58))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(bullet)
                            .microText()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(footerText)
                    .microText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .nativePanelSurface(
            fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.panelFillOpacity)),
            stroke: Color.primary.opacity(0.065)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local insights. \(availability.state.displayName). \(availability.detail)")
    }

    private var footerText: String {
        let suggestionCount = primarySummary?.input.categorySuggestions.count ?? 0
        guard suggestionCount > 0 else {
            return "Local-only. No cloud model calls. Plaid categories remain the auditable fallback."
        }
        return "\(suggestionCount) deterministic category hint\(suggestionCount == 1 ? "" : "s"). Plaid categories remain fallback evidence."
    }
}

private struct LocalAIStatusPill: View {
    let availability: LocalAIAvailability

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
            Text("Local - \(availability.state.displayName)")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .nativeInsetSurface(cornerRadius: 7)
        .help(availability.detail)
    }

    private var iconName: String {
        switch availability.state {
        case .available: "cpu.fill"
        case .disabled: "pause.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch availability.state {
        case .available: SemanticColors.positive
        case .disabled: .secondary
        case .unavailable: SemanticColors.warning
        }
    }
}

private struct LocalInsightWindowMetric: View {
    let summary: LocalAIActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.window.displayName)
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(Formatters.currency(summary.input.current.expenseTotal, format: .compact))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(netText)
                .microText()
                .foregroundStyle(netTint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .nativeInsetSurface(cornerRadius: 7)
        .help("\(summary.window.displayName): \(summary.input.current.transactionCount) transaction source rows.")
    }

    private var netText: String {
        let amount = summary.input.current.netCashflow
        let prefix = amount > 0 ? "+" : amount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(amount), format: .compact)) net"
    }

    private var netTint: Color {
        let amount = summary.input.current.netCashflow
        if amount > 0 { return SemanticColors.positive }
        if amount < 0 { return SemanticColors.negative }
        return .secondary
    }
}

private struct DashboardStatusReadinessPanel: View {
    @Environment(AppState.self) private var appState
    let openSettings: () -> Void
    let onAddAccount: () -> Void

    private var readiness: DashboardStatusReadiness {
        appState.dashboardStatusReadiness
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness.title)
                        .font(.callout.weight(.semibold))
                    Text(readiness.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            if !appState.isSetupComplete {
                SetupRecoverySummary(state: appState.firstRunCompletionState)
            }

            StatusMetricGrid()
                .environment(appState)

            if let primaryAction = readiness.primaryAction {
                HStack(spacing: 8) {
                    if readinessNeedsAttention {
                        Button {
                            perform(primaryAction)
                        } label: {
                            Label(
                                primaryActionLabel(for: primaryAction),
                                systemImage: readiness.primaryActionIconName ?? primaryAction.defaultIconName
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(tint)
                        .disabled(appState.isLoading)
                    } else {
                        Button {
                            perform(primaryAction)
                        } label: {
                            Label(
                                primaryActionLabel(for: primaryAction),
                                systemImage: readiness.primaryActionIconName ?? primaryAction.defaultIconName
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appState.isLoading)
                    }
                }
            }
        }
        .padding(12)
        .nativePanelSurface(
            fill: AnyShapeStyle(SurfaceTokens.panelFill(emphasisTint: readinessNeedsAttention ? tint : nil)),
            stroke: panelStroke
        )
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch readiness.level {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch readiness.level {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private var readinessNeedsAttention: Bool {
        readiness.level != .healthy
    }

    private var panelStroke: Color {
        readinessNeedsAttention ? tint.opacity(0.18) : Color.primary.opacity(0.07)
    }

    private func perform(_ action: DashboardStatusReadinessAction) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            onAddAccount()
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            guard let itemId = reconnectItemId else {
                Task { await appState.refreshAccounts() }
                return
            }
            Task { await appState.reconnectItem(itemId: itemId) }
        case .openSettings:
            openSettings()
        case .requestNotificationPermission:
            Task { _ = await appState.requestNotificationPermission() }
        case .openNotificationSettings:
            openNotificationSettings()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            openSettings()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func primaryActionLabel(for action: DashboardStatusReadinessAction) -> String {
        if action == .reconnect,
           let title = ItemRecoveryTarget.actionTitle(from: appState.itemStatuses) {
            return title
        }
        return readiness.primaryActionTitle ?? action.defaultTitle
    }

    private var reconnectItemId: String? {
        ItemRecoveryTarget.itemId(from: appState.itemStatuses)
    }
}

private struct SetupRecoverySummary: View {
    let state: FirstRunCompletionState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("Setup recovery")
                    .microText()
                    .foregroundStyle(.secondary)
                Text(state.title)
                    .font(.caption.weight(.semibold))
                Text(state.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch state.step {
        case .ready:
            "checkmark.circle.fill"
        case .blocked:
            "exclamationmark.triangle.fill"
        case .openPlaidLink:
            "link.circle"
        case .loadAccounts:
            "building.columns"
        case .syncTransactions:
            "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch state.step {
        case .ready:
            .secondary
        case .blocked:
            SemanticColors.negative
        case .openPlaidLink, .loadAccounts, .syncTransactions:
            SemanticColors.brand
        }
    }
}

private struct StatusMetricGrid: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            StatusMetricPill(title: "Mode", value: appState.statusModeText)
            StatusMetricPill(title: "Server", value: appState.statusServerText)
            StatusMetricPill(title: "Items", value: "\(appState.statusItemCount) linked")
            StatusMetricPill(title: "Synced", value: syncedItemsText)
            StatusMetricPill(title: "Credentials", value: appState.serverCredentialsText)
            StatusMetricPill(title: "Last Sync", value: appState.lastSyncRelative ?? "Never")
            StatusMetricPill(title: "Data Path", value: appState.activeStorageDirectoryDisplayText)
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 112), spacing: 6),
            GridItem(.flexible(minimum: 112), spacing: 6),
            GridItem(.flexible(minimum: 112), spacing: 6),
        ]
    }

    private var syncedItemsText: String {
        "\(appState.serverSyncedItemCount ?? 0) of \(appState.statusItemCount)"
    }
}

private struct StatusMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .microText()
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .nativeInsetSurface(cornerRadius: SurfaceTokens.panelCornerRadius)
    }
}

// MARK: - Overview Flow

private struct DashboardOverviewStack: View {
    @Environment(AppState.self) private var appState
    let transactions: [TransactionDTO]
    let accounts: [AccountDTO]
    let filter: DashboardAccountFilter
    @Binding var filterSelection: DashboardAccountFilter
    let selectedAccountId: String?
    let onSelectAccount: (AccountDTO) -> Void
    let onDeselectAccount: () -> Void
    let onAddAccount: () -> Void

    private var fallbackState: DashboardOverviewFallbackState? {
        DashboardOverviewFallbackState.evaluate(
            isSetupComplete: appState.isSetupComplete,
            isDemoMode: appState.isDemoMode,
            accountCount: appState.accounts.count,
            transactionCount: appState.transactions.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.stack) {
            if let fallbackState {
                DashboardOverviewFallbackBanner(presentation: fallbackState, onAction: onAddAccount)
            } else {
                BalanceActivityHeatmap(transactions: transactions)
            }

            VStack(alignment: .leading, spacing: LayoutSpacing.controls) {
                DashboardFilterBar(
                    selection: $filterSelection,
                    hasSelectedAccount: selectedAccountId != nil
                )

                AccountsSection(
                    accounts: accounts,
                    filter: filter,
                    selectedAccountId: selectedAccountId,
                    onSelect: onSelectAccount,
                    onDeselect: onDeselectAccount,
                    onAddAccount: onAddAccount
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview with activity heatmap, account filters, account rows, and selected account details.")
    }

    private enum LayoutSpacing {
        static let stack: CGFloat = 6
        static let controls: CGFloat = 5
    }
}

private struct DashboardOverviewFallbackBanner: View {
    let presentation: DashboardOverviewFallbackState
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SemanticColors.brandSecondary)
                    .frame(width: 30, height: 30)
                    .background(SemanticColors.brandSecondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.callout.weight(.semibold))
                    Text(presentation.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.title). \(presentation.detail)")

            Button(action: onAction) {
                Label(presentation.actionTitle, systemImage: presentation.actionIconName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativePanelSurface(
            fill: AnyShapeStyle(SurfaceTokens.panelFill(emphasisTint: SemanticColors.brandSecondary.opacity(0.18))),
            stroke: SemanticColors.brandSecondary.opacity(0.22)
        )
    }
}

// MARK: - Account List

private struct AccountsSection: View {
    @Environment(AppState.self) private var appState
    let accounts: [AccountDTO]
    let filter: DashboardAccountFilter
    let selectedAccountId: String?
    let onSelect: (AccountDTO) -> Void
    let onDeselect: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Accounts")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(accounts.count)")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.compactRowTextSpacing)
            .padding(.bottom, Spacing.xs)

            if accounts.isEmpty {
                DashboardEmptyAccountState(filter: filter, onAddAccount: onAddAccount)
                    .environment(appState)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        AccountRowWithDrilldown(
                            account: account,
                            isStatusFilter: filter == .status,
                            isSelected: selectedAccountId == account.id,
                            onSelect: {
                                if selectedAccountId == account.id {
                                    onDeselect()
                                } else {
                                    onSelect(account)
                                }
                            }
                        )
                        .environment(appState)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct AccountRowWithDrilldown: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isStatusFilter: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                DashboardAccountRow(account: account, isStatusFilter: isStatusFilter, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .focusable(true)
            .help(drillInPath.pointerHelp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accountAccessibilityLabel)
            .accessibilityHint(drillInPath.accessibilityHint)
            .accessibilityAction(named: drillInPath.accessibilityActionName, onSelect)

            if isSelected {
                SelectedAccountPanel(
                    account: account,
                    isStatusFilter: isStatusFilter,
                    activitySnapshot: appState.accountActivitySnapshot(for: account.id)
                )
                    .environment(appState)
                    .padding(.top, Spacing.compactRowVerticalPadding)
                    .padding(.bottom, Spacing.compactRowContentSpacing)
            }
        }
    }

    private var accountAccessibilityLabel: String {
        AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: AccountPresentation.rowAmountText(for: account),
            connectionLabel: connectionPresentation.rowLabel,
            pendingCount: pendingCount,
            isSelected: isSelected,
            utilizationThreshold: appState.creditUtilizationThreshold
        )
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).count(where: \.pending)
    }

    private var drillInPath: DashboardAccountDrillInPath {
        DashboardAccountDrillInPath.presentation(for: account, isSelected: isSelected)
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }
}

private struct DashboardEmptyAccountState: View {
    @Environment(AppState.self) private var appState
    let filter: DashboardAccountFilter
    let onAddAccount: () -> Void

    private var presentation: DashboardAccountEmptyState {
        DashboardAccountEmptyState.evaluate(
            filter: filter,
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            credentialsConfigured: appState.serverCredentialsConfigured,
            linkedItemCount: appState.statusItemCount,
            accountCount: appState.accounts.count,
            degradedItemCount: appState.needsLoginItemCount + appState.erroredItemCount,
            degradedItemRecoveryTitle: ItemRecoveryTarget.actionTitle(from: appState.itemStatuses),
            degradedItemRecoveryDetail: ItemRecoveryTarget.recoveryDetail(from: appState.itemStatuses)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(message)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                if showsAddAccount {
                    Button(action: onAddAccount) {
                        Label("Add Account", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    performRecoveryAction()
                } label: {
                    Label(actionTitle, systemImage: actionIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativePanelSurface(
            fill: AnyShapeStyle(SurfaceTokens.panelFill(emphasisTint: emphasizedTint)),
            stroke: panelStroke
        )
    }

    private var title: String {
        presentation.title
    }

    private var message: String {
        presentation.detail
    }

    private var icon: String {
        presentation.iconName
    }

    private var tint: Color {
        switch presentation.tone {
        case .brand:
            return SemanticColors.brand
        case .healthy:
            return .secondary
        case .offline, .secondary:
            return .secondary
        case .warning:
            return SemanticColors.warning
        }
    }

    private var panelStroke: Color {
        switch presentation.tone {
        case .brand, .warning:
            return tint.opacity(0.18)
        case .healthy, .offline, .secondary:
            return Color.primary.opacity(0.07)
        }
    }

    private var emphasizedTint: Color? {
        switch presentation.tone {
        case .brand, .warning:
            return tint
        case .healthy, .offline, .secondary:
            return nil
        }
    }

    private var showsAddAccount: Bool {
        presentation.showsAddAccount
    }

    private var actionTitle: String {
        presentation.actionTitle
    }

    private var actionIcon: String {
        presentation.actionIconName
    }

    private func performRecoveryAction() {
        switch presentation.action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            guard let itemId = ItemRecoveryTarget.itemId(from: appState.itemStatuses) else {
                Task { await appState.refreshDashboard() }
                return
            }
            Task { await appState.reconnectItem(itemId: itemId) }
        case .sync:
            Task { await appState.refreshDashboard() }
        }
    }
}

private struct DashboardAccountRow: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isStatusFilter: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            Image(systemName: AccountPresentation.iconName(for: account))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accountTint)
                .frame(width: 28, height: 28)
                .background(accountTint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                }

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(account.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .detailText()
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.compactRowContentSpacing)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(amountText)
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AccountPresentation.isDebt(account) ? SemanticColors.creditDebt : .primary)
                    .lineLimit(1)

                if let utilization = account.balances.utilizationPercent {
                    Text(trailingDetailText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SemanticColors.utilization(
                            for: utilization,
                            threshold: appState.creditUtilizationThreshold
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                } else {
                    Text(trailingDetailText)
                        .microText()
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowVerticalPadding)
        .background(isSelected ? SemanticColors.brand.opacity(SurfaceTokens.selectedFillOpacity) : Color.primary.opacity(0.012))
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(SemanticColors.brand)
                    .frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.55)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: isStatusFilter ? connectionPresentation.statusFilterSubtitle : statusText,
            pendingCount: pendingCount
        )
    }

    private var amountText: String {
        AccountPresentation.rowAmountText(for: account)
    }

    private var accountTint: Color {
        switch account.type {
        case .credit, .loan:
            SemanticColors.creditDebt
        case .investment:
            .secondary
        case .depository:
            .secondary
        case .other:
            .secondary
        }
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).filter(\.pending).count
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }

    private var statusText: String {
        connectionPresentation.rowLabel
    }

    private var trailingDetailText: String {
        AccountPresentation.dashboardTrailingDetailText(
            for: account,
            connectionLabel: statusText
        )
    }

    private var statusTint: Color {
        accountConnectionTint(for: connectionPresentation.level)
    }
}

// MARK: - Selected Account

private struct SelectedAccountPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    let account: AccountDTO
    let isStatusFilter: Bool
    let activitySnapshot: AccountTransactionFeed.AccountActivitySnapshot
    @State private var isConfirmingAccountRemoval = false

    private var drillInSummary: DashboardAccountDrillInSummary {
        DashboardAccountDrillInSummary.presentation(
            for: account,
            activitySnapshot: activitySnapshot,
            itemStatus: itemConnectionStatus,
            fallbackFreshnessLabel: connectionPresentation.signalLabel
        )
    }

    private var transactions: [TransactionDTO] {
        Array(activitySnapshot.transactions.prefix(5))
    }

    private var accountTransactions: [TransactionDTO] {
        activitySnapshot.transactions
    }

    private var pendingTransactions: [TransactionDTO] {
        activitySnapshot.pendingTransactions
    }

    private var activitySummary: AccountActivitySummary {
        activitySnapshot.recentSummary
    }

    private var emptyState: AccountActivityEmptyState? {
        AccountActivityEmptyState.evaluate(
            transactionCount: activitySnapshot.transactionCount,
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            connectionLevel: connectionPresentation.level,
            accountDisplayName: AccountPresentation.displayName(for: account)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compactRowContentSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                    Text("Drill-in")
                        .sectionTitle()
                        .foregroundStyle(.secondary)
                    Text(drillInSummary.displayName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text(drillInSummary.subtitle)
                        .detailText()
                        .lineLimit(1)
                }

                Spacer()

                AccountConnectionBadge(
                    label: connectionLabel,
                    icon: connectionIcon,
                    tint: connectionTint
                )
            }

            DrillInSurfaceRail(surfaces: DashboardDrillInSurface.surfaces(for: account))

            HStack(spacing: Spacing.compactRowContentSpacing) {
                DetailValue(title: drillInSummary.availableTitle, value: availableText, tint: .primary)
                DetailValue(title: drillInSummary.currentTitle, value: currentText, tint: currentTint)

                if let utilization = account.balances.utilizationPercent,
                   let utilizationText = AccountPresentation.dashboardUtilizationDetailText(
                       for: account,
                       threshold: appState.creditUtilizationThreshold
                   ) {
                    DetailValue(
                        title: "Utilization",
                        value: utilizationText,
                        tint: SemanticColors.utilization(
                            for: utilization,
                            threshold: appState.creditUtilizationThreshold
                        )
                    )
                } else {
                    DetailValue(title: "Activity", value: activityText, tint: connectionTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.compactRowContentSpacing) {
                AccountSignalPill(
                    title: "Pending",
                    value: "\(pendingTransactions.count)",
                    icon: "clock.fill",
                    tint: pendingTransactions.isEmpty ? .secondary : SemanticColors.pending
                )
                AccountSignalPill(
                    title: "30D Out",
                    value: Formatters.currency(activitySummary.outflowTotal, format: .compact),
                    icon: "arrow.up.right.circle.fill",
                    tint: .secondary
                )
                AccountSignalPill(
                    title: "30D In",
                    value: Formatters.currency(activitySummary.inflowTotal, format: .compact),
                    icon: "arrow.down.left.circle.fill",
                    tint: .secondary
                )
                AccountSignalPill(
                    title: "Sync",
                    value: syncSignalText,
                    icon: connectionIcon,
                    tint: connectionTint
                )
            }

            if isStatusFilter, let recoveryDetailLabel = connectionPresentation.recoveryDetailLabel {
                HStack(alignment: .top, spacing: Spacing.compactRowContentSpacing) {
                    Image(systemName: connectionIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(connectionTint)
                        .frame(width: 16)
                    Text(recoveryDetailLabel)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.compactRowHorizontalPadding)
                .padding(.vertical, Spacing.compactRowVerticalPadding)
                .nativePanelSurface(
                    cornerRadius: SurfaceTokens.panelCornerRadius,
                    fill: AnyShapeStyle(recoveryFill),
                    stroke: connectionTint.opacity(shouldEmphasizeConnection ? 0.14 : 0.06),
                    useLiquidGlass: false
                )
                .accessibilityElement(children: .combine)
            }

            if shouldShowRecoveryActions {
                HStack(spacing: Spacing.compactRowContentSpacing) {
                    Button {
                        performConnectionRecoveryAction()
                    } label: {
                        Label(connectionRecoveryActionTitle, systemImage: connectionRecoveryActionIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(connectionRecoveryAccessibilityLabel)
                    .accessibilityHint(connectionRecoveryAccessibilityHint)
                }
            }

            AccountDrillInActionBar(
                actions: drillInActions,
                accountDisplayName: drillInSummary.displayName,
                onAction: performDrillInAction
            )

            VStack(alignment: .leading, spacing: Spacing.rowVertical) {
                Text("Recent Activity")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                if transactions.isEmpty {
                    if let emptyState {
                        AccountActivityEmptyStateView(presentation: emptyState)
                    }
                } else {
                    ForEach(transactions) { transaction in
                        TransactionMiniRow(transaction: transaction)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .nativePanelSurface(
            fill: AnyShapeStyle(SurfaceTokens.panelFill(emphasisTint: shouldEmphasizeConnection ? connectionTint : nil)),
            stroke: panelStroke
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(drillInSummary.accessibilityLabel)
        .confirmationDialog(
            "Remove \(institutionRemovalName)?",
            isPresented: $isConfirmingAccountRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Institution", role: .destructive) {
                Task { await appState.removeAccount(itemId: account.itemId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects the linked Plaid institution and removes \(institutionAccountCountText) plus cached local transactions from PlaidBar. It does not close any bank account.")
        }
    }

    private var availableText: String {
        Formatters.currency(drillInSummary.availableBalance, format: .compact)
    }

    private var currentText: String {
        Formatters.currency(drillInSummary.currentBalance, format: .compact)
    }

    private var currentTint: Color {
        AccountPresentation.isDebt(account) ? SemanticColors.creditDebt : .primary
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var institutionRemovalName: String {
        itemConnectionStatus?.institutionName ?? AccountPresentation.displayName(for: account)
    }

    private var institutionAccountCount: Int {
        appState.accounts.count { $0.itemId == account.itemId }
    }

    private var institutionAccountCountText: String {
        let count = max(institutionAccountCount, 1)
        return count == 1 ? "1 linked account" : "\(count) linked accounts"
    }

    private var drillInActions: [DashboardDrillInAction] {
        DashboardDrillInAction.accountDrillInActions(
            isDemoMode: appState.isDemoMode
        )
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }

    private var connectionLabel: String {
        connectionPresentation.detailLabel
    }

    private var connectionIcon: String {
        connectionPresentation.iconName
    }

    private var connectionTint: Color {
        accountConnectionTint(for: connectionPresentation.level)
    }

    private var activityText: String {
        "\(drillInSummary.transactionCount) tx"
    }

    private var syncSignalText: String {
        if isStatusFilter, let itemSyncLabel = connectionPresentation.itemSyncLabel {
            return itemSyncLabel
        }
        return connectionPresentation.signalLabel
    }

    private var shouldShowRecoveryActions: Bool {
        connectionPresentation.showsRecoveryActions
    }

    private var recoveryActionTitle: String {
        connectionPresentation.recoveryActionTitle ?? "Reconnect"
    }

    private var connectionRecoveryActionTitle: String {
        switch connectionPresentation.level {
        case .loginRequired, .error:
            return recoveryActionTitle
        case .stale:
            return "Refresh"
        case .demo, .offline, .healthy, .unknown:
            return "Refresh"
        }
    }

    private var connectionRecoveryActionIcon: String {
        switch connectionPresentation.level {
        case .loginRequired, .error:
            return "link.badge.plus"
        case .stale:
            return "arrow.clockwise"
        case .demo, .offline, .healthy, .unknown:
            return "arrow.clockwise"
        }
    }

    private var connectionRecoveryAccessibilityLabel: String {
        "\(connectionRecoveryActionTitle) for \(drillInSummary.displayName)"
    }

    private var connectionRecoveryAccessibilityHint: String {
        connectionPresentation.recoveryDetailLabel ?? "Refreshes this selected account's PlaidBar status."
    }

    private func performConnectionRecoveryAction() {
        switch connectionPresentation.level {
        case .loginRequired, .error:
            Task { await appState.reconnectItem(itemId: account.itemId) }
        case .stale:
            Task { await appState.refreshDashboard() }
        case .demo, .offline, .healthy, .unknown:
            break
        }
    }

    private func performDrillInAction(_ action: DashboardDrillInAction) {
        switch action {
        case .reconnect:
            Task { await appState.reconnectItem(itemId: account.itemId) }
        case .remove:
            isConfirmingAccountRemoval = true
        case .settings:
            openSettingsWindow()
        }
    }

    private func openSettingsWindow() {
        SettingsWindowActivationRestorer.shared.open(openSettings: openSettings)
    }

    private var panelStroke: Color {
        shouldEmphasizeConnection ? connectionTint.opacity(0.18) : Color.primary.opacity(0.07)
    }

    private var recoveryFill: Color {
        shouldEmphasizeConnection ? connectionTint.opacity(0.08) : Color.primary.opacity(0.035)
    }

    private var shouldEmphasizeConnection: Bool {
        switch connectionPresentation.level {
        case .stale, .loginRequired, .error:
            return true
        case .demo, .offline, .healthy, .unknown:
            return false
        }
    }
}

private struct AccountDrillInActionBar: View {
    let actions: [DashboardDrillInAction]
    let accountDisplayName: String
    let onAction: (DashboardDrillInAction) -> Void

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            ForEach(actions, id: \.self) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.iconName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(action == .remove ? SemanticColors.negative : nil)
                .accessibilityLabel(action.accessibilityLabel(accountDisplayName: accountDisplayName))
                .accessibilityHint(action.accessibilityHint)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected account actions")
    }
}

private func accountConnectionTint(for level: AccountConnectionLevel) -> Color {
    switch level {
    case .demo:
        return .secondary
    case .offline:
        return .secondary
    case .healthy:
        return .secondary
    case .stale, .loginRequired:
        return SemanticColors.warning
    case .error:
        return SemanticColors.negative
    case .unknown:
        return .secondary
    }
}

private struct DrillInSurfaceRail: View {
    let surfaces: [DashboardDrillInSurface]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(surfaces, id: \.self) { surface in
                Label(surface.title, systemImage: surface.iconName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                    .accessibilityLabel("\(surface.title) drill-in")
                    .accessibilityHint(surface.accessibilitySummary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected account drill-in surfaces")
    }
}

private struct AccountConnectionBadge: View {
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.compactRowHorizontalPadding)
            .padding(.vertical, Spacing.compactRowVerticalPadding)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Selected account status: \(label)")
    }
}

private struct AccountSignalPill: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(title)
                    .microText()
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeInsetSurface(cornerRadius: SurfaceTokens.panelCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct DetailValue: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct TransactionMiniRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            Circle()
                .fill(transaction.isIncome ? SemanticColors.positive : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(transaction.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(Formatters.displayTransactionDate(transaction.date))
                    .microText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountText)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(transaction.isIncome ? SemanticColors.positive : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var amountText: String {
        let prefix = transaction.isIncome ? "+" : ""
        return "\(prefix)\(Formatters.currency(transaction.displayAmount, format: .compact))"
    }

    private var accessibilityLabel: String {
        let direction = transaction.isIncome ? "income" : "outflow"
        return "\(transaction.displayName), \(direction), \(Formatters.currency(transaction.displayAmount, format: .full)), \(Formatters.displayTransactionDate(transaction.date))"
    }
}

private struct AccountActivityEmptyStateView: View {
    let presentation: AccountActivityEmptyState

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.compactRowContentSpacing) {
            Image(systemName: presentation.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Text(presentation.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.compactRowContentSpacing)
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowContentSpacing)
        .nativePanelSurface(
            cornerRadius: SurfaceTokens.panelCornerRadius,
            fill: AnyShapeStyle(tint.opacity(0.055)),
            stroke: tint.opacity(0.11),
            useLiquidGlass: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var tint: Color {
        switch presentation.tone {
        case .brand:
            SemanticColors.brand
        case .healthy:
            .secondary
        case .offline, .secondary:
            .secondary
        case .warning:
            SemanticColors.warning
        }
    }
}

// MARK: - Footer

private struct DashboardFooter: View {
    @Environment(AppState.self) private var appState
    let settingsActivation: SettingsWindowActivationRestorer
    let openSettings: OpenSettingsAction
    let onAddAccount: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onAddAccount) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Add Account")
            .accessibilityLabel("Add Account")
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Button {
                Task { await appState.refreshDashboard() }
            } label: {
                RefreshIcon(isLoading: appState.isLoading)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func openSettingsWindow() {
        settingsActivation.open(openSettings: openSettings)
    }
}

@MainActor
private final class SettingsWindowActivationRestorer {
    static let shared = SettingsWindowActivationRestorer()

    private var closeObserver: NSObjectProtocol?
    private var discoveryObserver: NSObjectProtocol?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func open(openSettings: OpenSettingsAction) {
        let app = NSApplication.shared
        if previousActivationPolicy == nil {
            previousActivationPolicy = app.activationPolicy()
        }

        removeDiscoveryObserver()
        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }

        openSettings()
        app.activate(ignoringOtherApps: true)

        if focusCurrentSettingsWindow() { return }

        discoveryObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let observedWindow = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard
                    let self,
                    let settingsWindow = observedWindow,
                    Self.isSettingsWindowCandidate(settingsWindow)
                else { return }

                self.focus(settingsWindow)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.discoveryObserver != nil else { return }
            _ = self.focusCurrentSettingsWindow()
        }
    }

    private func focusCurrentSettingsWindow() -> Bool {
        guard let settingsWindow = NSApplication.shared.windows.first(where: Self.isSettingsWindowCandidate) else {
            return false
        }

        focus(settingsWindow)
        return true
    }

    private func focus(_ settingsWindow: NSWindow) {
        removeDiscoveryObserver()
        removeCloseObserver()

        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreActivationPolicy()
            }
        }
    }

    private func restoreActivationPolicy() {
        let app = NSApplication.shared
        app.setActivationPolicy(previousActivationPolicy ?? .accessory)
        previousActivationPolicy = nil
        removeCloseObserver()
        removeDiscoveryObserver()
    }

    private static func isSettingsWindowCandidate(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.canBecomeKey, !window.isMiniaturized, window.level == .normal else {
            return false
        }

        if window.title.localizedCaseInsensitiveContains("settings") {
            return true
        }

        return window.styleMask.contains(.titled)
            && window.sheetParent == nil
            && window.frame.width >= 580
            && window.frame.height >= 500
    }

    private func removeCloseObserver() {
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
    }

    private func removeDiscoveryObserver() {
        guard let discoveryObserver else { return }
        NotificationCenter.default.removeObserver(discoveryObserver)
        self.discoveryObserver = nil
    }
}

private struct ErrorBanner: View {
    @Environment(AppState.self) private var appState
    let error: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button {
                appState.error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.red.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
