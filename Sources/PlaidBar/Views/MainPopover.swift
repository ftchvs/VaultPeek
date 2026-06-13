import AppKit
import PlaidBarCore
import SwiftUI

struct MainPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("dashboard.accountFilter") private var selectedFilterRawValue = DashboardAccountFilter.all.rawValue
    @AppStorage("dashboard.selectedAccountId") private var selectedAccountId = ""
    @AppStorage(PopoverTransparencySetting.storageKey) private var popoverTransparency = PopoverTransparencySetting.defaultValue
    @State private var isShowingAccountSetup = false
    @State private var shouldShowSetupRecoveryDashboard = false
    @State private var dashboardContentHeight: CGFloat = 0
    /// True after the first render. Gates the inspector's trailing slide-in so a
    /// popover opened with a persisted selection appears directly in three-column
    /// geometry (no slide on restore); in-session selections still slide (AND-405).
    @State private var hasAppeared = false

    private enum Layout {
        // Column widths and the screen-edge margin are owned by the shared,
        // unit-tested PopoverGeometry so the SwiftUI frames, the popover width
        // math, and the AppKit window anchor stay in lockstep (AND-375).
        static let dashboardWidth = PopoverGeometry.dashboardWidth
        static let flyoutWidth = PopoverGeometry.railWidth
        static let dashboardMinHeight: CGFloat = 460
        /// Vertical breathing room kept below the popover: menu bar,
        /// footer chrome, and a Dock-safe margin.
        static let screenHeightInset: CGFloat = 120
        /// Gap kept between the widened three-column popover and the screen's
        /// visible edges when it is clamped on-screen (AND-374 fallback).
        static let screenEdgeMargin = PopoverGeometry.screenEdgeMargin

        static let contentHorizontalPadding: CGFloat = 12
        static let contentTopPadding: CGFloat = 8
        static let contentBottomPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = Spacing.sm
        static let groupSpacing: CGFloat = Spacing.lg
    }

    /// RepoBar-style vertical sizing: the dashboard grows with its content
    /// up to the available screen height instead of stopping at a fixed
    /// budget. Short content hugs; long content fills the screen and
    /// scrolls. Falls back to the height-budget model when no screen is
    /// available (headless renders).
    private var dashboardScrollHeight: CGFloat {
        let fallback = CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
        let screenCap = NSScreen.main.map { $0.visibleFrame.height - Layout.screenHeightInset } ?? fallback
        let contentCap = dashboardContentHeight > 0 ? dashboardContentHeight : screenCap
        return max(Layout.dashboardMinHeight, min(screenCap, contentCap))
    }

    private var selectedFilter: DashboardAccountFilter {
        DashboardAccountFilter(rawValue: selectedFilterRawValue) ?? .all
    }

    private var selectedAccount: AccountDTO? {
        let accounts = filteredAccounts
        // A selection survives only while the account is still visible; a filter
        // change or a removed/synced-away account deselects it (AND-373/375).
        guard let id = DashboardAccountSelection.resolvedSelectedId(
            selectedAccountId,
            visibleAccountIds: accounts.map(\.id)
        ) else { return nil }
        return accounts.first { $0.id == id }
    }

    /// The trailing account inspector is reserved: a selection is persisted and
    /// we are past setup. Derived from the persisted `selectedAccountId`
    /// (`@AppStorage`) rather than the resolved `selectedAccount`, so a popover
    /// opened with a persisted selection reserves the three-column width and
    /// anchor immediately — before `loadInitialData()` populates accounts —
    /// instead of opening two-column and jumping to three-column once accounts
    /// arrive (AND-405). The inspector column shows a brief loading placeholder
    /// until `selectedAccount` resolves. Also drives the popover width, the
    /// leading-edge anchor, and Esc precedence.
    private var isAccountInspectorOpen: Bool {
        !selectedAccountId.isEmpty && !shouldShowSetupScreen
    }

    /// The width available for the popover on the active screen, or effectively
    /// unbounded when there is no screen (headless renders) so the full geometry
    /// is used.
    private var availableScreenWidth: CGFloat {
        NSScreen.main?.visibleFrame.width ?? .greatestFiniteMagnitude
    }

    /// Two-column base width: Wealth Summary rail + divider + dashboard. This is
    /// the popover's width with no account selected and the stable block whose
    /// leading edge the window anchor pins (AND-369/370).
    private var twoColumnWidth: CGFloat {
        PopoverGeometry.width(for: .twoColumn)
    }

    private func deselectAccount() {
        selectedAccountId = ""
    }

    private var filteredAccounts: [AccountDTO] {
        appState.accounts.filter { selectedFilter.includes($0, appState: appState) }
    }

    var body: some View {
        chromedPopover
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
            .onAppear { hasAppeared = true }
            // Also self-heals the first-open edge where a persisted selection
            // doesn't survive the active filter: at mount accounts are empty, so
            // this fires once when they first populate and clears a now-invalid
            // id, collapsing the reserved three-column back to two (AND-405).
            .onChange(of: filteredAccounts.map(\.id)) { _, ids in
                guard !selectedAccountId.isEmpty, !ids.contains(selectedAccountId) else { return }
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

    // The visual chrome is kept on its own opaque property so neither it nor the
    // lifecycle chain in `body` overflows the single-expression type-checker.
    private var chromedPopover: some View {
        popoverColumns
            .frame(width: popoverWidth)
            .foregroundStyle(AppearanceTextColors.primary)
            .environment(\.colorScheme, effectiveColorScheme)
            .background {
                PopoverMaterialBackground(transparencySetting: transparencySetting)
            }
            // Hold the two-column block's leading edge stable so opening the
            // trailing inspector grows the popover rightward instead of letting
            // AppKit re-center the widened window and slide the Wealth Summary
            // sideways (AND-370). The same anchor clamps the widened popover
            // inside the visible screen so it never renders off-screen near a
            // display edge (AND-374 primary fallback).
            .background {
                PopoverLeadingEdgeAnchor(
                    isInspectorOpen: isAccountInspectorOpen,
                    collapsedWidth: twoColumnWidth,
                    screenEdgeMargin: Layout.screenEdgeMargin
                )
            }
            .animation(
                MotionTokens.animation(MotionTokens.content, reduceMotion: reduceMotion),
                value: selectedAccount?.id
            )
            // Esc closes the trailing inspector first; with no inspector open the
            // handler is nil so the key event falls through and closes the
            // popover (AND-373).
            .onExitCommand(perform: exitCommandHandler)
            .animation(
                MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion),
                value: appState.error != nil
            )
    }

    /// Esc handler: dismiss the inspector when open, otherwise `nil` so the key
    /// event falls through and closes the popover (AND-373). Hoisted out of the
    /// view chain as an explicitly-typed value to keep the type-checker fast.
    private var exitCommandHandler: (() -> Void)? {
        guard isAccountInspectorOpen else { return nil }
        return { deselectAccount() }
    }

    // Split into per-column helpers so the type-checker can resolve the body in
    // reasonable time — the full three-column HStack plus modifiers overflows
    // the single-expression solver.
    private var popoverColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            if !shouldShowSetupScreen {
                wealthSummaryRail

                Divider()
                    .opacity(0.35)
            }

            // The center flexes: the rail and inspector keep their fixed widths,
            // so when the popover is capped on a narrow/scaled display the center
            // absorbs the difference (down to a floor) and the trailing inspector
            // + its close control stay on-screen (AND-405).
            dashboardColumn
                .frame(minWidth: PopoverGeometry.minDashboardWidth, maxWidth: .infinity)

            accountInspectorColumn
        }
    }

    // LEFT: the Wealth Summary rail is mounted unconditionally once setup is
    // complete and is never swapped out by account selection (three-column
    // contract, AND-367/369). A stable id keeps SwiftUI from remounting/flashing
    // it when the trailing inspector opens or closes.
    private var wealthSummaryRail: some View {
        WealthSummaryFlyout(onAddAccount: openAccountSetup)
            .environment(appState)
            .id("wealth-summary-rail")
            .frame(width: Layout.flyoutWidth)
            // Cap the rail to the same screen-bounded height as the dashboard
            // scroll column so tall content scrolls inside the rail instead of
            // growing the whole popover past the screen-bounded height.
            .frame(maxHeight: dashboardScrollHeight)
            .leftPanelSurface()
            .transition(.move(edge: .leading).combined(with: .opacity))
    }

    // RIGHT: the account inspector opens on the trailing side only when a row is
    // selected, leaving the left rail and center dashboard in place
    // (AND-369/371). It slides in from the trailing edge and is independently
    // dismissible.
    @ViewBuilder
    private var accountInspectorColumn: some View {
        if isAccountInspectorOpen {
            Divider()
                .opacity(0.35)

            Group {
                if let selectedAccount {
                    AccountInspector(
                        account: selectedAccount,
                        isStatusFilter: selectedFilter == .status,
                        onClose: deselectAccount
                    )
                    .environment(appState)
                } else {
                    // A persisted selection reserves the column before accounts
                    // load; show a brief placeholder so the width is correct
                    // immediately and fills in without a resize jump (AND-405).
                    inspectorLoadingPlaceholder
                }
            }
            .frame(width: Layout.flyoutWidth)
            .frame(maxHeight: dashboardScrollHeight)
            .leftPanelSurface()
            // Slide in only for an in-session selection; a popover opened with a
            // persisted selection appears directly in three-column (AND-405).
            .transition(.asymmetric(
                insertion: inspectorInsertionTransition,
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }

    private var inspectorInsertionTransition: AnyTransition {
        hasAppeared ? .move(edge: .trailing).combined(with: .opacity) : .identity
    }

    private var inspectorLoadingPlaceholder: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading account details")
    }

    private var popoverWidth: CGFloat {
        // Cap the content to the available screen width so the popover never
        // renders off-screen; the center dashboard flexes to absorb the cap so
        // the rail and the trailing inspector + close control stay visible on
        // narrow/scaled displays (AND-405). Setup renders at the dashboard width.
        guard !shouldShowSetupScreen else { return PopoverGeometry.width(for: .setup) }
        return PopoverGeometry.fittedWidth(
            for: isAccountInspectorOpen ? .threeColumn : .twoColumn,
            availableWidth: availableScreenWidth
        )
    }

    private var transparencySetting: PopoverTransparencySetting {
        PopoverTransparencySetting(value: popoverTransparency)
    }

    private var effectiveColorScheme: ColorScheme {
        guard let mode = CommandLineOptions.value(for: "--appearance") else { return colorScheme }
        switch mode.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return colorScheme
        }
    }

    private var dashboardColumn: some View {
        VStack(spacing: 0) {
            // The error banner outranks everything below it — including the
            // setup screen, which previously swallowed errors entirely.
            if let error = appState.error {
                ErrorBanner(error: error)
                    .environment(appState)
            }

            if shouldShowSetupScreen {
                SetupView()
            } else {
                ScrollView {
                    // 16pt between concept groups, 8pt between siblings
                    // within a group — spacing is the hierarchy.
                    VStack(alignment: .leading, spacing: Layout.groupSpacing) {
                        // The rail owns the net-worth hero and its trend, so the
                        // center leads with the latest-changes receipt instead of
                        // repeating either (AND-372).
                        DashboardChangeReceiptStrip()
                            .environment(appState)

                        if shouldElevateStatusReadinessPanel {
                            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                                AttentionQueueView(title: "Attention", onAddAccount: openAccountSetup)
                                    .environment(appState)

                                DashboardStatusReadinessPanel(
                                    openSettings: { openSettings() },
                                    onAddAccount: openAccountSetup
                                )
                                .environment(appState)
                            }
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

                        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                            // The left rail owns the portfolio totals (assets,
                            // debt, balance mix, 30-day cashflow), so the center
                            // drops those duplicates (AND-372) and keeps only what
                            // the rail does NOT show: the 7-day spend velocity and
                            // the local-only insight receipt.
                            RecentSpendChip()
                                .environment(appState)

                            LocalInsightsCard()
                                .environment(appState)
                        }
                        .loadingRedaction(appState.loadState(for: .summaryCards))

                        if shouldShowLowerStatusReadinessPanel {
                            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                                AttentionQueueView(title: "Attention", onAddAccount: openAccountSetup)
                                    .environment(appState)

                                DashboardStatusReadinessPanel(
                                    openSettings: { openSettings() },
                                    onAddAccount: openAccountSetup
                                )
                                .environment(appState)
                            }
                        }
                    }
                    .padding(.horizontal, Layout.contentHorizontalPadding)
                    .padding(.top, Layout.contentTopPadding)
                    .padding(.bottom, Layout.contentBottomPadding)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        dashboardContentHeight = height
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: dashboardScrollHeight)

                Divider()

                DashboardFooter(
                    settingsActivation: .shared,
                    openSettings: openSettings,
                    onAddAccount: openAccountSetup
                )
                .environment(appState)
            }
        }
    }

    private var shouldShowSetupScreen: Bool {
        !appState.isSetupComplete && !shouldShowSetupRecoveryDashboard
    }

    private var shouldShowStatusReadinessPanel: Bool {
        selectedFilter == .status || shouldElevateStatusReadinessPanel
    }

    private var shouldElevateStatusReadinessPanel: Bool {
        // `.loading` stays quiet like `.healthy`: the boot handshake must not
        // hoist an attention panel over the dashboard before any verdict.
        let level = appState.dashboardStatusReadiness.level
        return !appState.isSetupComplete || level == .warning || level == .blocked
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

private struct DashboardChangeReceiptStrip: View {
    @Environment(AppState.self) private var appState

    private var receipt: DashboardChangeReceipt? {
        DashboardChangeReceipt.evaluate(
            history: appState.balanceHistory,
            transactions: appState.transactions,
            itemStatuses: appState.itemStatuses
        )
    }

    var body: some View {
        if let receipt {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(receipt.title.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(receipt.summary)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    ForEach(receipt.rows) { row in
                        Text(row.value)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .help(row.accessibilityText)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(receipt.accessibilitySummary)
            .help(receipt.accessibilitySummary)
        }
    }
}

private struct RecentSpendChip: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // 7-day spend velocity — the one summary metric the left rail does not
        // show (its cashflow section is 30-day). The rail owns cash, credit, and
        // the balance mix, so the center keeps only this short-window signal.
        // Renders nothing when there is no recent spend, so the center has no
        // empty stub.
        if appState.recentSpend > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("7-DAY SPEND")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                Text(Formatters.currency(appState.recentSpend, format: .compact))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("7 day spend: \(Formatters.currency(appState.recentSpend, format: .full))")
        }
    }
}

// MARK: - 365 Day Heatmap

private struct BalanceActivityHeatmap: View {
    let transactions: [TransactionDTO]
    var loadState: DashboardLoadState?

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

                Text(isInitialLoad ? "—" : totalLabel(for: layout))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isInitialLoad ? AppearanceTextColors.secondary : totalTint(for: layout))
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
                                        BalanceHeatmapCell(
                                            day: day,
                                            peakValue: layout.peakValue,
                                            mode: layout.mode,
                                            size: cell
                                        )
                                    } else {
                                        RoundedRectangle(cornerRadius: Radius.cell)
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
            // First sync in flight: the empty grid dims so it reads as a
            // placeholder, not as a year of zero activity.
            .opacity(isInitialLoad ? 0.45 : 1)

            HStack(spacing: 5) {
                if layout.mode == .spending {
                    Text("Less")
                        .microText()
                        .foregroundStyle(.secondary)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: Radius.cell)
                            .fill(BalanceHeatmapCell.fillColor(
                                intensity: intensity,
                                value: intensity,
                                mode: layout.mode
                            ))
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

                Text(isInitialLoad ? "Loading activity" : "\(layout.activeDayCount) active days")
                    .microText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isInitialLoad
                ? (loadState?.loadingAccessibilityLabel ?? "Loading activity heatmap.")
                : "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription)."
        )
    }

    private var isInitialLoad: Bool {
        loadState?.isInitialLoad ?? false
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
        guard layout.mode == .netCashflow else { return AppearanceTextColors.primary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(layout.totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return AppearanceTextColors.secondary
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
            RoundedRectangle(cornerRadius: Radius.cell)
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
        RoundedRectangle(cornerRadius: Radius.cell)
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
        guard intensity > 0 else { return Color.primary.opacity(0.06) }

        // Spend mode uses a neutral intensity ramp: green means money-in
        // everywhere else in the app, so green-for-heavy-spending would
        // invert the token semantics. Net mode keeps the green/red pairing
        // with its explicit Income/Outflow legend.
        guard mode == .netCashflow else {
            return Color.primary.opacity(0.14 + (0.6 * intensity))
        }

        let base: Color = value < 0 ? SemanticColors.positive : SemanticColors.negative
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
        primarySummary?.availability ?? appState.localAIAvailability
    }

    private var primarySummary: LocalAIActivitySummary? {
        summaries.first { $0.window == .lastMonth } ?? summaries.first
    }

    private var bullets: [String] {
        Array(primarySummary?.generatedBullets.prefix(3) ?? [])
    }

    private var receipt: LocalAIInsightReceipt {
        LocalAIInsightReceipt.make(summary: primarySummary, availability: availability)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(receipt.title)
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                LocalAIStatusPill(availability: availability)
            }

            Text(receipt.headline)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            HStack(spacing: 6) {
                ForEach(receipt.evidenceChips) { chip in
                    LocalInsightEvidenceChip(chip: chip)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(receiptDetailLines.enumerated()), id: \.offset) { _, detail in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.secondary.opacity(0.58))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(detail)
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
        .padding(Spacing.sm)
        .glassSurface(.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(receipt.accessibilitySummary)
    }

    private var receiptDetailLines: [String] {
        var lines = [receipt.confidence]
        if let unavailableState = receipt.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: receipt.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    private var footerText: String {
        "\(receipt.localOnlyBadge). \(receipt.reversibleActionCopy)"
    }
}

private struct LocalAIStatusPill: View {
    let availability: LocalAIAvailability

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(.caption2.weight(.medium))
            Text("Local - \(availability.state.displayName)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .help(availability.detail)
    }

    private var iconName: String {
        switch availability.state {
        case .available: "cpu.fill"
        case .disabled: "pause.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .checking: "hourglass"
        }
    }

    private var tint: Color {
        switch availability.state {
        case .available: SemanticColors.positive
        case .disabled: AppearanceTextColors.secondary
        case .unavailable: SemanticColors.warning
        case .checking: AppearanceTextColors.secondary
        }
    }
}

private struct LocalInsightEvidenceChip: View {
    let chip: LocalAIInsightReceipt.EvidenceChip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: chip.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentTint)
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
        .glassSurface(.inset, cornerRadius: Radius.control)
        .help("\(chip.label): \(chip.value)")
    }

    private var accentTint: Color {
        guard let category = chip.accentCategory else { return AppearanceTextColors.secondary }
        return CategoryAccentTokens.color(for: category)
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
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

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
        .padding(Spacing.md)
        .glassSurface(readinessNeedsAttention ? .emphasized(tint) : .raised)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch readiness.level {
        case .healthy: "checkmark.circle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        // Warning/negative tints are reserved for actionable verdicts —
        // an in-flight first load renders neutral.
        switch readiness.level {
        case .healthy, .loading: AppearanceTextColors.secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private var readinessNeedsAttention: Bool {
        readiness.level == .warning || readiness.level == .blocked
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
           let title = ItemRecoveryTarget.actionTitle(from: appState.itemStatuses)
        {
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
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control))

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
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
                BalanceActivityHeatmap(
                    transactions: transactions,
                    loadState: appState.loadState(for: .activityHeatmap)
                )
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
        .accessibilityLabel(
            "Overview with activity heatmap, account filters, account rows, and selected account details."
        )
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
                    .background(
                        SemanticColors.brandSecondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Radius.panel)
                    )

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
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.emphasized(SemanticColors.brandSecondary))
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
    /// Tracks which account row holds keyboard focus so opening and closing the
    /// trailing inspector keeps the user's place in the list (AND-373).
    @FocusState private var focusedAccountId: String?

    private var accountsLoadState: DashboardLoadState {
        appState.loadState(for: .accounts)
    }

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
                    .opacity(accountsLoadState.showsSkeleton ? 0 : 1)
            }
            .padding(.horizontal, Spacing.compactRowHorizontalPadding)
            .padding(.bottom, Spacing.xs)

            if accounts.isEmpty {
                if accountsLoadState.showsSkeleton {
                    // First fetch in flight: redacted placeholder rows
                    // instead of offline/empty copy.
                    DashboardAccountRowSkeletonList(loadState: accountsLoadState)
                } else {
                    DashboardEmptyAccountState(filter: filter, onAddAccount: onAddAccount)
                        .environment(appState)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        AccountRowWithDrilldown(
                            account: account,
                            isStatusFilter: filter == .status,
                            isSelected: selectedAccountId == account.id,
                            focusBinding: $focusedAccountId,
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            }
        }
        // Keep focus on the selected row while the inspector is open and return
        // it to that row when the inspector closes, so keyboard users do not
        // lose context on Esc/close (AND-373). onChange does not fire on mount,
        // so a popover reopened with a persisted selection neither re-announces
        // nor re-homes focus.
        .onChange(of: selectedAccountId) { previous, current in
            if let current, let account = accounts.first(where: { $0.id == current }) {
                focusedAccountId = current
                // Announce only on a genuine selection change (not on mount/
                // restore), so VoiceOver hears the inspector open exactly once.
                AccessibilityNotification.Announcement(
                    "\(AccountPresentation.displayName(for: account)) details opened in account inspector"
                ).post()
            } else if let previous, accounts.contains(where: { $0.id == previous }) {
                // Return focus only when the row still exists (Esc/✕/re-click).
                // If the selection was cleared because the row left the list
                // (filter change or account removed), leave focus alone rather
                // than pointing @FocusState at a vanished id (AND-373).
                focusedAccountId = previous
            }
        }
    }
}

private struct AccountRowWithDrilldown: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isStatusFilter: Bool
    let isSelected: Bool
    let focusBinding: FocusState<String?>.Binding
    let onSelect: () -> Void

    var body: some View {
        // Selection opens the AccountInspector on the trailing side of the
        // dashboard (mounted by MainPopover), not an inline panel below. The
        // left rail stays in place; only the right inspector toggles.
        Button(action: onSelect) {
            DashboardAccountRow(account: account, isStatusFilter: isStatusFilter, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .focused(focusBinding, equals: account.id)
        .hoverHighlight()
        .help(drillInPath.pointerHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accountAccessibilityLabel)
        .accessibilityHint(drillInPath.accessibilityHint)
        .accessibilityAction(named: drillInPath.accessibilityActionName, onSelect)
    }

    private var accountAccessibilityLabel: String {
        let label = AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: AccountPresentation.rowAmountText(for: account),
            connectionLabel: connectionPresentation.rowLabel,
            pendingCount: pendingCount,
            isSelected: isSelected,
            utilizationThreshold: appState.creditUtilizationThreshold
        )
        guard let demoTrend else { return label }
        return "\(label). \(accountTrendAccessibility(demoTrend))"
    }

    private var demoTrend: BalanceTrend? {
        demoAccountTrend(for: account, appState: appState)
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
            isInitialLoad: appState.loadState(for: .accounts).isInitialLoad,
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
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(message)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Loading is passive: no recovery actions until the first fetch
            // delivers a verdict the user can act on.
            if !presentation.isLoading {
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
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(emphasizedTint.map { SurfaceRank.emphasized($0) } ?? .raised)
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
            SemanticColors.brand
        case .healthy, .loading:
            .secondary
        case .offline, .secondary:
            .secondary
        case .warning:
            SemanticColors.warning
        }
    }

    private var emphasizedTint: Color? {
        switch presentation.tone {
        case .brand, .warning:
            tint
        case .healthy, .loading, .offline, .secondary:
            nil
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Sizing.iconChip, height: Sizing.iconChip)
                .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(alignment: .bottomTrailing) {
                    // Decorative reinforcement only: the row subtitle carries
                    // the connection state in text, so the tinted dot is
                    // hidden from VoiceOver instead of being color-only.
                    Circle()
                        .fill(statusTint)
                        .frame(width: Sizing.statusDot, height: Sizing.statusDot)
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(account.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .detailText()
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.compactRowContentSpacing)

            if let demoTrend {
                BalanceTrendChart(trend: demoTrend)
                    .frame(width: 54, height: 16)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                // Amounts are data, not verdicts: keep them neutral. Risk is
                // carried by the utilization line below — icon + tint + text,
                // and only once the user's own threshold is crossed.
                Text(amountText)
                    .dataText()
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)

                if let utilization = account.balances.utilizationPercent {
                    // Mirrors the filter-bar rule: tint the icon, never the
                    // text — orange caption text fails 4.5:1 contrast.
                    HStack(spacing: Spacing.xxs) {
                        if utilizationNeedsAttention {
                            Image(systemName: SemanticColors.utilizationIcon(
                                for: utilization,
                                threshold: appState.creditUtilizationThreshold
                            ))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SemanticColors.utilization(
                                for: utilization,
                                threshold: appState.creditUtilizationThreshold
                            ))
                        }
                        Text(trailingDetailText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(utilizationNeedsAttention ? AnyShapeStyle(AppearanceTextColors.primary) :
                                AnyShapeStyle(.secondary))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text(trailingDetailText)
                        .microText()
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            // The account inspector opens on the trailing side of the
            // dashboard; chevron.forward flips correctly under RTL. The selected
            // row swaps in a filled chevron so selection is carried by shape,
            // not color alone (AND-373).
            Image(systemName: isSelected ? "chevron.forward.circle.fill" : "chevron.forward")
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowVerticalPadding)
        .background(
            isSelected ? Color.accentColor.opacity(SurfaceTokens.selectedFillOpacity) : .clear,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .overlay(alignment: .bottom) {
            if !isSelected {
                Divider()
                    .opacity(0.4)
            }
        }
        .contentShape(Rectangle())
    }

    private var utilizationNeedsAttention: Bool {
        guard let utilization = account.balances.utilizationPercent else { return false }
        return utilization >= appState.creditUtilizationThreshold
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

    private var demoTrend: BalanceTrend? {
        demoAccountTrend(for: account, appState: appState)
    }
}

@MainActor
private func demoAccountTrend(for account: AccountDTO, appState: AppState) -> BalanceTrend? {
    guard appState.usesDemoConnectionPresentation else { return nil }
    return BalanceTrend.evaluate(history: DemoFixtures.accountBalanceHistory(forAccountId: account.id))
}

private func accountTrendAccessibility(_ trend: BalanceTrend) -> String {
    let change: String
    switch trend.direction {
    case .up:
        change = "up \(Formatters.currency(abs(trend.delta), format: .full))"
    case .down:
        change = "down \(Formatters.currency(abs(trend.delta), format: .full))"
    case .flat:
        change = "unchanged"
    }
    return "Demo account balance trend \(change) over the last \(trend.spanDays) day\(trend.spanDays == 1 ? "" : "s")"
}

// MARK: - Footer

private struct DashboardFooter: View {
    @Environment(AppState.self) private var appState
    let settingsActivation: SettingsWindowActivationRestorer
    let openSettings: OpenSettingsAction
    let onAddAccount: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onAddAccount) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Add Account")
            .accessibilityLabel("Add Account")
            .keyboardShortcut("n", modifiers: .command)

            // The one place sync/mode status lives on a healthy dashboard.
            Text(statusLineText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Status: \(statusLineText)")

            Spacer()

            Button {
                Task { await appState.refreshDashboard() }
            } label: {
                RefreshIcon(isLoading: appState.isLoading)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
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
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    private var statusLineText: String {
        var parts = [appState.statusModeText]
        parts.append(appState.statusSyncText)
        if appState.statusItemCount > 0 {
            parts.append("\(appState.statusItemCount) linked")
        }
        return parts.joined(separator: " · ")
    }

    private func openSettingsWindow() {
        settingsActivation.open(openSettings: openSettings)
    }
}

@MainActor
final class SettingsWindowActivationRestorer {
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
            guard let self, discoveryObserver != nil else { return }
            _ = focusCurrentSettingsWindow()
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
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticColors.negative)
                .accessibilityHidden(true)
            // Sanitized errors are capped at 220 characters upstream, so an
            // uncapped line count stays bounded while never truncating the
            // actionable part of the message.
            Text(error)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(SemanticColors.negative.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(error)")
        .task(id: error) {
            // Keyed by the error text so each distinct error is announced,
            // not just the first one mounted; the task also yields once so
            // the banner is in the hierarchy before VoiceOver speaks.
            await Task.yield()
            AccessibilityNotification.Announcement("Error: \(error)").post()
        }
    }
}
