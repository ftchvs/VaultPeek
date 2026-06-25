import PlaidBarCore
import SwiftUI

/// The signature **Activity heatmap hero** of the window-first Dashboard
/// (AND-622/AND-624): the read-only 365-day year-scale activity grid, given a
/// prominent near-full-column-width card at the *top* of the Activity column so
/// it reads as the dashboard's headline instrument rather than a small lost
/// strip buried in a list of cards.
///
/// **Surface only — no model logic here.** It reads the *same*
/// ``SpendingHeatmapLayout`` Core engine the popover and the Insights destination
/// compute (`SpendingHeatmap.cellIntensity`, `ChartAudioGraph.heatmap`) — the
/// data is never recomputed or divergent. It renders that layout at a
/// **desk-distance scale** (``DashboardYearHeatmapGrid``: larger cells, month
/// markers, more height) rather than re-hosting the popover/Insights
/// ``InsightsActivityHeatmapGrid``, whose cells are capped at a glance-scale 9pt
/// and read small/lost on a desktop hero. Privacy Mask / Reduce Transparency swap
/// in a text alternative, since the grid leans on tinted, translucent cells
/// (ACCESSIBILITY.md — never color/translucency alone).
struct DashboardActivityHeatmapCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var layout: SpendingHeatmapLayout {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: appState.transactions,
            startDate: start,
            endDate: end,
            mode: appState.dashboardHeatmapMode,
            calendar: calendar
        )
    }

    var body: some View {
        let layout = layout
        WindowSection("Activity", systemImage: "square.grid.3x3.fill") {
            Text(layout.mode.summaryTitle)
                .windowSupportingText()
        } content: {
            if appState.shouldMaskFinancialValues || reduceTransparency {
                heatmapTextAlternative(layout: layout)
            } else {
                DashboardYearHeatmapGrid(layout: layout)
            }
        }
        .loadingRedaction(appState.loadState(for: .activityHeatmap))
    }

    private func heatmapTextAlternative(layout: SpendingHeatmapLayout) -> some View {
        let masked = appState.shouldMaskFinancialValues
        let total = masked
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(layout.totalValue, format: .compact)
        return VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            Label("\(layout.activeDayCount) active days in the last year", systemImage: "calendar")
                .windowBodyText()
            Text(masked
                ? "Activity totals are hidden while VaultPeek is private."
                : "\(total) across active days. \(layout.mode.semanticDescription)")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: WindowMetrics.heatmapHeroMinHeight, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The consolidated **Accounts** card of the window-first Dashboard
/// (AND-622/AND-624): the primary account filter, the account rows, and the
/// "what the bank said" bank-reported balances — merged into one card so the
/// Activity column reads as a few generous cards rather than a tight stack of
/// small ones. The filter segments live *inside* this card's header area (they
/// scope its rows) rather than as a separate strip above it.
///
/// **Surface only — no model logic here.** It composes existing reusable pieces
/// over `PlaidBarCore`:
/// - the **filter bar** is the existing ``DashboardFilterBar``, bound to the same
///   `AppState.dashboardFilter` the popover persists;
/// - the **account rows** render from the same ``AccountPresentation`` Core helpers
///   the popover row uses, honoring Privacy Mask, at window (desk-distance) type;
/// - the **"what the bank said" balances** re-host the same Core ledger the popover
///   strip reads (``BalanceTimeMachineView``), folded in as a footer detail.
///
/// **Drill-ins deep-link, not a third column**: selecting a row
/// calls `onSelectAccount`, which the destination routes to the **Accounts**
/// destination via `\.openRoute`.
///
/// Empty / loading states mirror the popover: a pre-setup install shows the Core
/// ``DashboardOverviewFallbackState`` banner instead of an empty grid; the
/// accounts section shows the skeleton while the first fetch is in flight and the
/// Core ``DashboardAccountEmptyState`` copy when a filter resolves to no rows.
struct DashboardOverviewColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The shell's unified `.searchable` query (AND-624). Empty ⇒ no filter, so the
    /// flag-OFF popover (which never injects it) is unchanged.
    @Environment(\.shellSearchQuery) private var searchQuery

    /// Routed by the destination to the Accounts destination (no local inspector
    /// on a 2-column canvas).
    let onSelectAccount: (AccountDTO) -> Void

    private var filter: DashboardAccountFilter { appState.dashboardFilter }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredAccounts: [AccountDTO] {
        let byFilter = appState.accounts.filter { filter.includes($0, appState: appState) }
        let query = trimmedQuery
        guard !query.isEmpty else { return byFilter }
        // Case-insensitive substring match on the displayed account name — the one
        // field the user reads in the row. Honors the active filter (search refines
        // within it) and never reveals masked values (it matches names, not amounts).
        return byFilter.filter {
            AccountPresentation.displayName(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    private var fallbackState: DashboardOverviewFallbackState? {
        DashboardOverviewFallbackState.evaluate(
            isSetupComplete: appState.isSetupComplete,
            isDemoMode: appState.isDemoMode,
            accountCount: appState.accounts.count,
            transactionCount: appState.transactions.count
        )
    }

    var body: some View {
        WindowSection("Accounts", systemImage: "building.columns") {
            Text("\(filteredAccounts.count)")
                .windowCardTitle()
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .opacity(accountsLoadState.showsSkeleton ? 0 : 1)
                .accessibilityLabel("\(filteredAccounts.count) accounts")
        } content: {
            if let fallbackState {
                DashboardOverviewFallback(presentation: fallbackState)
            } else {
                VStack(alignment: .leading, spacing: WindowMetrics.md) {
                    DashboardFilterBar(selection: filterBinding, hasSelectedAccount: false)
                    accountsSection
                    bankSaidFooter
                }
            }
        }
        .accessibilityLabel("Accounts with filters, account rows, and bank-reported balances.")
    }

    // MARK: - Accounts

    private var accountsLoadState: DashboardLoadState {
        appState.loadState(for: .accounts)
    }

    private var accountsSection: some View {
        Group {
            if filteredAccounts.isEmpty {
                if accountsLoadState.showsSkeleton {
                    DashboardAccountRowSkeletonList(loadState: accountsLoadState)
                } else if !trimmedQuery.isEmpty {
                    // A search that matched nothing reads differently from a filter
                    // that resolved to no accounts — name the query, not the filter.
                    ContentUnavailableView.search(text: trimmedQuery)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    DashboardAccountEmpty(filter: filter)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredAccounts) { account in
                        DashboardAccountRowButton(
                            account: account,
                            isStatusFilter: filter == .status,
                            onSelect: { onSelectAccount(account) }
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            }
        }
    }

    // MARK: - "What the bank said" (folded-in footer)

    /// The bank-reported balance ledger, folded into the Accounts card rather
    /// than carried as its own small card. ``BalanceTimeMachineView`` self-hides
    /// when there is nothing to show, so a divider only appears when there is a
    /// footer to separate.
    @ViewBuilder
    private var bankSaidFooter: some View {
        if appState.accountBalanceLedger.latestEntriesByAccount().contains(where: { entry in
            appState.accounts.contains { $0.id == entry.accountId }
        }) {
            Divider().opacity(0.4)
            BalanceTimeMachineView(scale: .window)
        }
    }

    private var filterBinding: Binding<DashboardAccountFilter> {
        Binding(
            get: { appState.dashboardFilter },
            set: { appState.dashboardFilter = $0 }
        )
    }
}

// MARK: - Account row

/// A single account row for the window-first dashboard overview. Drives off the
/// shared ``AccountPresentation`` Core helpers (the same source the popover row
/// uses), so name, subtitle, amount, and the VoiceOver label match. Rendered at
/// window (desk-distance) type — the account name and amount read at `.body`, the
/// subtitle at `.subheadline` — so the primary figures never drop to caption
/// scale on the larger surface. Selection deep-links to the Accounts destination
/// rather than opening a local inspector.
private struct DashboardAccountRowButton: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: AccountDTO
    let isStatusFilter: Bool
    let onSelect: () -> Void

    private var privacyMaskEnabled: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: WindowMetrics.sm) {
                Image(systemName: AccountPresentation.iconName(for: account))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Sizing.iconChip, height: Sizing.iconChip)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .windowBodyText()
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(subtitle)
                        .windowSupportingText()
                        .lineLimit(1)
                }

                Spacer(minLength: WindowMetrics.sm)

                Text(amountText)
                    .windowDataText()
                    .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)

                // The drill-in opens the Accounts destination; chevron.forward
                // flips correctly under RTL and carries the affordance by shape.
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, WindowMetrics.sm)
            .padding(.vertical, WindowMetrics.xs)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Divider().opacity(0.4)
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help("Open \(AccountPresentation.displayName(for: account)) in Accounts")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this account in the Accounts destination.")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: statusText,
            pendingCount: pendingCount,
            privacyMaskEnabled: privacyMaskEnabled
        )
    }

    private var amountText: String {
        AccountPresentation.rowAmountText(for: account, privacyMaskEnabled: privacyMaskEnabled)
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).count(where: \.pending)
    }

    private var accessibilityLabel: String {
        AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: amountText,
            connectionLabel: statusText,
            pendingCount: pendingCount,
            isSelected: false,
            utilizationThreshold: appState.creditUtilizationThreshold,
            privacyMaskEnabled: privacyMaskEnabled,
            liability: appState.liabilities.first { $0.accountId == account.id }
        )
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var statusText: String {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemConnectionStatus?.status,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        ).rowLabel
    }
}

// MARK: - Empty / fallback

/// The dashboard accounts empty state, surfaced from the same Core
/// ``DashboardAccountEmptyState`` engine the popover uses. The "Add account"
/// affordance deep-links to the Accounts destination via the parent's route.
private struct DashboardAccountEmpty: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openRoute) private var openRoute
    let filter: DashboardAccountFilter

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
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            HStack(spacing: WindowMetrics.sm) {
                Image(systemName: presentation.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .windowBodyText()
                        .fontWeight(.semibold)
                    Text(presentation.detail)
                        .windowSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !presentation.isLoading, presentation.showsAddAccount {
                Button { openRoute(.accounts()) } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.title). \(presentation.detail)")
    }

    private var tint: Color {
        switch presentation.tone {
        case .brand: SemanticColors.brand
        case .warning: SemanticColors.warning
        case .healthy, .loading, .offline, .secondary: .secondary
        }
    }
}

/// The pre-setup overview fallback banner, surfaced from the Core
/// ``DashboardOverviewFallbackState`` (shown when no demo or synced data can yet
/// provide a meaningful first glance). The action deep-links to Accounts.
private struct DashboardOverviewFallback: View {
    @Environment(\.openRoute) private var openRoute
    let presentation: DashboardOverviewFallbackState

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            HStack(alignment: .top, spacing: WindowMetrics.sm) {
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
                        .windowBodyText()
                        .fontWeight(.semibold)
                    Text(presentation.detail)
                        .windowSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.title). \(presentation.detail)")

            Button { openRoute(.accounts()) } label: {
                Label(presentation.actionTitle, systemImage: presentation.actionIconName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Year heatmap (desk-distance scale)

/// The 365-day activity heatmap rendered at **desk-distance scale** for the
/// Dashboard hero (AND-624). It reads the exact same ``SpendingHeatmapLayout``
/// the popover/Insights compute and the exact same `SpendingHeatmap.cellIntensity`
/// mapping — only the *render size* differs from the glance-scale
/// ``InsightsActivityHeatmapGrid`` (whose cells cap at 9pt): cells here grow to
/// fill the hero card's width (clamped to a comfortable desk range) and the grid
/// carries month markers, so the signature year view reads as a prominent hero
/// rather than a small lost strip.
///
/// Meaning never rides on cell color alone (ACCESSIBILITY.md): the card's title +
/// the legend + the active-day count + the VoiceOver label and audio graph carry
/// the same information in text and sound. Callers swap in a text alternative
/// under Privacy Mask / Reduce Transparency before reaching this view.
struct DashboardYearHeatmapGrid: View {
    let layout: SpendingHeatmapLayout

    /// Gap between cells. A touch wider than the glance grid's 2pt so the larger
    /// cells read as a clean lattice at desk distance.
    private let cellSpacing: CGFloat = 3
    /// Desk-distance cell-size clamp. `maxCell` keeps the grid from blowing the
    /// column out when there is room; `deskMinCell` is the *preferred* desk floor,
    /// but the grid is allowed to shrink below it (down to ``hardMinCell``) rather
    /// than overflow when the 53-week year can't fit a narrow column — see
    /// ``clampedCell(forWidth:)``. The popover/Insights grid floors hard at 9pt,
    /// but it lives in a wider surface; the Dashboard hero shares a 2-column canvas
    /// and must fit a ~368pt column, so a clean shrink beats a horizontal bleed.
    private let deskMinCell: CGFloat = 9
    private let hardMinCell: CGFloat = 4
    private let maxCell: CGFloat = 15

    private var weekCount: Int { max(layout.weekColumns.count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let metrics = resolvedMetrics(forWidth: width)
                VStack(alignment: .leading, spacing: metrics.spacing) {
                    monthMarkers(cell: metrics.cell, spacing: metrics.spacing)
                    grid(cell: metrics.cell, spacing: metrics.spacing)
                }
            }
            .frame(height: gridHeight)
            // Belt-and-braces bound only: the resolved metrics already fit the full
            // 53-week year (cell + gap) inside the column, so this never hides data
            // — it just guarantees no sub-pixel paint escapes the card (AQ-1).
            .clipped()

            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription)."
        )
        // VoiceOver audio graph over the active days (AND-569) — same Core source.
        .audioGraph(ChartAudioGraph.heatmap(layout, isPrivacyMasked: false))
    }

    /// Resolve the cell size **and** inter-cell gap so the full 53-week year fits the
    /// available width — the whole year stays glanceable (never clipped or hidden)
    /// at any column width.
    ///
    /// When there is room, the cell grows toward `maxCell` at the comfortable desk
    /// gap (`cellSpacing`). When the year can't fit the desk scale (e.g. the
    /// ~330–368pt two-column column, where 53 cells at the 9pt desk floor + 3pt gaps
    /// would need ~636pt), BOTH the cell and the gap shrink together — the gap
    /// tightening toward 1pt so the lattice stays legible rather than gappy — so all
    /// 53 weeks fit inside the card (Apple Health "Year"-style fit-to-width, not a
    /// horizontal bleed). The `.clipped()` in `body` is then only a safety bound,
    /// never the thing that hides weeks (AQ-1, codex review).
    private func resolvedMetrics(forWidth width: CGFloat) -> (cell: CGFloat, spacing: CGFloat) {
        guard width > 0 else { return (deskMinCell, cellSpacing) }
        let n = CGFloat(weekCount)
        let deskFit = floor((width - (n - 1) * cellSpacing) / n)
        if deskFit >= deskMinCell {
            // Room for the comfortable desk scale (or larger); grow up to maxCell.
            return (min(maxCell, deskFit), cellSpacing)
        }
        // Too narrow for the desk scale: shrink cell + gap together so the whole
        // year still fits. Size the cell assuming a tight 1pt gap, derive a
        // proportional gap (≈ cell/3, capped at the desk gap), then re-fit the cell.
        let tightCell = max(hardMinCell, floor((width - (n - 1)) / n))
        let spacing = max(1, min(cellSpacing, floor(tightCell / 3)))
        let cell = max(hardMinCell, floor((width - (n - 1) * spacing) / n))
        return (cell, spacing)
    }

    /// Reserve height for seven day-rows at the max cell size plus the month-marker
    /// row, so the card lays out at a stable, prominent height regardless of the
    /// resolved cell size.
    private var gridHeight: CGFloat {
        let markerRow: CGFloat = 16
        return markerRow + 7 * maxCell + 6 * cellSpacing
    }

    private func grid(cell: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cellView(for: day, size: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(for day: SpendingHeatmapDay?, size: CGFloat) -> some View {
        if let day {
            let intensity = SpendingHeatmap.cellIntensity(for: day, peakValue: layout.peakValue)
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.primary.opacity(0.10 + 0.62 * intensity))
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(.clear)
                .frame(width: size, height: size)
        }
    }

    /// Month labels above the grid, positioned by their week index. `step` is
    /// derived from the *resolved* cell + gap so the labels track the grid columns
    /// exactly; because the resolved metrics fit the whole year inside the column,
    /// the last label lands within the grid (no width guard needed). Hidden from
    /// accessibility (the VoiceOver label already names the span).
    private func monthMarkers(cell: CGFloat, spacing: CGFloat) -> some View {
        let step = cell + spacing
        return ZStack(alignment: .topLeading) {
            ForEach(layout.monthMarkers) { marker in
                Text(marker.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(marker.weekIndex) * step)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: WindowMetrics.xs) {
            Text("Less")
                .windowSupportingText()
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.primary.opacity(0.10 + 0.62 * intensity))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .windowSupportingText()

            Spacer()

            Text("\(layout.activeDayCount) active days")
                .windowSupportingText()
        }
        .accessibilityHidden(true)
    }
}
