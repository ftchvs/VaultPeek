import PlaidBarCore
import SwiftUI

/// The overview block of the window-first **Dashboard** destination (AND-622): the
/// activity heatmap + the primary account filter + the account rows — the same
/// instrument the menu-bar popover renders via its private `DashboardOverviewStack`.
///
/// **Surface only — no model logic here.** It composes existing reusable pieces
/// over `PlaidBarCore`:
/// - the **filter bar** is the existing ``DashboardFilterBar``, bound to the same
///   `AppState.dashboardFilter` the popover persists;
/// - the **activity heatmap** is the existing read-only ``InsightsActivityHeatmapGrid``
///   (already factored out for the Insights destination, AND-585) over the same
///   ``SpendingHeatmapLayout`` Core engine — *the heatmap is not rebuilt here*;
/// - the **account rows** render from the same ``AccountPresentation`` Core helpers
///   the popover row uses, honoring Privacy Mask.
///
/// **Drill-ins deep-link, not a third column** (IA §3.1, §5.1): the 2-column
/// dashboard has no inspector, so selecting a row calls `onSelectAccount`, which
/// the destination routes to the **Accounts** destination via `\.openRoute`.
///
/// Empty / loading states mirror the popover: a pre-setup install shows the Core
/// ``DashboardOverviewFallbackState`` banner instead of an empty grid; the
/// accounts section shows the skeleton while the first fetch is in flight and the
/// Core ``DashboardAccountEmptyState`` copy when a filter resolves to no rows.
struct DashboardOverviewColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Routed by the destination to the Accounts destination (no local inspector
    /// on a 2-column canvas).
    let onSelectAccount: (AccountDTO) -> Void

    private var filter: DashboardAccountFilter { appState.dashboardFilter }

    private var filteredAccounts: [AccountDTO] {
        appState.accounts.filter { filter.includes($0, appState: appState) }
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let fallbackState {
                DashboardOverviewFallback(presentation: fallbackState)
            } else {
                activityHeatmap
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                DashboardFilterBar(selection: filterBinding, hasSelectedAccount: false)
                accountsSection
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview with activity heatmap, account filters, and account rows.")
    }

    // MARK: - Heatmap

    /// The read-only year heatmap, reusing the existing ``InsightsActivityHeatmapGrid``
    /// over the same Core layout the popover computes. Privacy Mask / Reduce
    /// Transparency swap in a text alternative, since the grid leans on tinted,
    /// translucent cells (ACCESSIBILITY.md — never color/translucency alone).
    @ViewBuilder
    private var activityHeatmap: some View {
        let layout = heatmapLayout()
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(layout.mode.summaryTitle, systemImage: "square.grid.3x3.fill")
                .sectionTitle()
                .foregroundStyle(.secondary)

            if appState.shouldMaskFinancialValues || reduceTransparency {
                heatmapTextAlternative(layout: layout)
            } else {
                InsightsActivityHeatmapGrid(layout: layout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
        .loadingRedaction(appState.loadState(for: .activityHeatmap))
        .accessibilityElement(children: .contain)
    }

    private func heatmapLayout() -> SpendingHeatmapLayout {
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

    private func heatmapTextAlternative(layout: SpendingHeatmapLayout) -> some View {
        let masked = appState.shouldMaskFinancialValues
        let total = masked
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(layout.totalValue, format: .compact)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("\(layout.activeDayCount) active days in the last year", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
            Text(masked
                ? "Activity totals are hidden while VaultPeek is private."
                : "\(total) across active days. \(layout.mode.semanticDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Accounts

    private var accountsLoadState: DashboardLoadState {
        appState.loadState(for: .accounts)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Accounts")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filteredAccounts.count)")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                    .opacity(accountsLoadState.showsSkeleton ? 0 : 1)
            }
            .padding(.horizontal, Spacing.compactRowHorizontalPadding)
            .padding(.bottom, Spacing.xs)

            if filteredAccounts.isEmpty {
                if accountsLoadState.showsSkeleton {
                    DashboardAccountRowSkeletonList(loadState: accountsLoadState)
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
/// uses), so name, subtitle, amount, and the VoiceOver label match. Selection
/// deep-links to the Accounts destination rather than opening a local inspector.
private struct DashboardAccountRowButton: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: AccountDTO
    let isStatusFilter: Bool
    let onSelect: () -> Void

    private var privacyMaskEnabled: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.compactRowContentSpacing) {
                Image(systemName: AccountPresentation.iconName(for: account))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Sizing.iconChip, height: Sizing.iconChip)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))

                VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                    Text(account.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .detailText()
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.compactRowContentSpacing)

                Text(amountText)
                    .dataText()
                    .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)

                // The drill-in opens the Accounts destination; chevron.forward
                // flips correctly under RTL and carries the affordance by shape.
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.compactRowHorizontalPadding)
            .padding(.vertical, Spacing.compactRowVerticalPadding)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: presentation.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.callout.weight(.semibold))
                    Text(presentation.detail)
                        .detailText()
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
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(emphasizedTint.map { SurfaceRank.emphasized($0) } ?? .raised)
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

    private var emphasizedTint: Color? {
        switch presentation.tone {
        case .brand, .warning: tint
        case .healthy, .loading, .offline, .secondary: nil
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

            Button { openRoute(.accounts()) } label: {
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
