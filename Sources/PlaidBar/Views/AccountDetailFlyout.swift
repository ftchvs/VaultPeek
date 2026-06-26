import PlaidBarCore
import SwiftUI

// MARK: - Account Inspector

/// Presents `AccountDetailFlyout` as the three-column popover's trailing account
/// inspector (AND-371). The detail surface itself is position-agnostic; this
/// thin wrapper names the trailing-inspector role and scopes the close affordance
/// to dismissing only the inspector. The VoiceOver "opened" announcement is
/// driven from the selection change in `MainPopover` (not this view's mount), so
/// reopening the popover with a persisted selection does not re-announce (AND-373).
struct AccountInspector: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isStatusFilter: Bool
    let onClose: () -> Void

    var body: some View {
        AccountDetailFlyout(
            account: account,
            isStatusFilter: isStatusFilter,
            onClose: onClose
        )
        .environment(appState)
    }
}

// MARK: - Account Detail Fly-out

/// The contextual account panel shown in the three-column popover's trailing
/// inspector when an account row is selected (mounted via `AccountInspector`).
/// One `raised` surface, sections separated by spacing: metadata header, status,
/// balances, 30-day changes, transactions to review, top categories, recent
/// activity, and account actions. The panel is position-agnostic; its placement
/// and slide-in transition are owned by `MainPopover`.
struct AccountDetailFlyout: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: AccountDTO
    let isStatusFilter: Bool
    let onClose: () -> Void
    @State private var isConfirmingAccountRemoval = false

    var body: some View {
        // Derived once per body evaluation — the snapshot filters and sorts
        // the full transaction feed, so it must never live in computed
        // properties that re-run per access (same hoist-once rule as
        // BalanceActivityHeatmap.currentLayout()).
        let connection = connectionPresentation
        let snapshot = appState.accountActivitySnapshot(for: account.id)
        let insights = AccountDetailInsights.compute(transactions: snapshot.transactions)
        let summary = DashboardAccountDrillInSummary.presentation(
            for: account,
            activitySnapshot: snapshot,
            itemStatus: itemConnectionStatus,
            fallbackFreshnessLabel: connection.signalLabel,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
        let recent = Array(snapshot.transactions.prefix(6))

        VStack(spacing: 0) {
            header(summary: summary)
                .padding(Spacing.md)

            Divider()
                .opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    statusSection(connection: connection, summary: summary)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                    balancesSection(summary: summary)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                    if account.type == .investment,
                       !appState.shouldMaskFinancialValues,
                       !holdingRows.isEmpty {
                        holdingsSection()
                            .scrollEdgeDepth(reduceMotion: reduceMotion)
                    }
                    if appState.shouldMaskFinancialValues {
                        privateDetailsPlaceholder()
                            .scrollEdgeDepth(reduceMotion: reduceMotion)
                    } else {
                        changesSection(insights: insights)
                            .scrollEdgeDepth(reduceMotion: reduceMotion)
                        if !insights.reviewItems.isEmpty {
                            reviewSection(insights: insights)
                                .scrollEdgeDepth(reduceMotion: reduceMotion)
                        }
                        if !insights.topCategories.isEmpty {
                            categoriesSection(insights: insights)
                                .scrollEdgeDepth(reduceMotion: reduceMotion)
                        }
                        activitySection(
                            recent: recent,
                            fullFeed: snapshot.transactions,
                            emptyState: emptyState(snapshot: snapshot, connection: connection)
                        )
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                    }
                    actionsSection(summary: summary)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Group the inspector's coexisting glass surfaces (inset/
                // emphasized action chips) into one GlassEffectContainer sampling
                // region. Native Liquid Glass is the unconditional macOS-26
                // baseline (AND-511), so there is no version passthrough.
                // Merge radius = SurfaceTokens.glassMergeRadius.
                .glassGroup()
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.accessibilityLabel(privacyMaskEnabled: appState.shouldMaskFinancialValues))
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
            Text(
                "This disconnects the linked Plaid institution and removes \(institutionAccountCountText) plus \(institutionTransactionCountText) from VaultPeek. It does not close any bank account."
            )
        }
    }

    // MARK: Header (metadata)

    private func header(summary: DashboardAccountDrillInSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(summary.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(summary.subtitle)
                    .detailText()
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.sm)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(
                        minWidth: Sizing.hitTargetMin,
                        minHeight: Sizing.hitTargetMin
                    )
            }
            .buttonStyle(.borderless)
            .help("Close account details")
            .accessibilityLabel("Close account details")
        }
    }

    // MARK: Status

    private func statusSection(
        connection: AccountConnectionPresentation,
        summary: DashboardAccountDrillInSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlyoutSectionLabel("Status")

            HStack(spacing: Spacing.sm) {
                AccountConnectionBadge(
                    label: connection.detailLabel,
                    icon: connection.iconName,
                    tint: accountConnectionTint(for: connection.level)
                )

                Spacer(minLength: 0)

                Text(syncSignalText(connection: connection))
                    .detailText()
                    .lineLimit(1)
            }

            if let recoveryDetailLabel = connection.recoveryDetailLabel {
                Text(recoveryDetailLabel)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if connection.showsRecoveryActions {
                Button {
                    performConnectionRecoveryAction()
                } label: {
                    Label(connectionRecoveryActionTitle, systemImage: connectionRecoveryActionIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("\(connectionRecoveryActionTitle) for \(summary.displayName)")
                .accessibilityHint(
                    connection.recoveryDetailLabel
                        ?? "Refreshes this account's VaultPeek status."
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Balances

    private func balancesSection(summary: DashboardAccountDrillInSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            DetailValue(
                title: summary.availableTitle,
                value: PrivacyMaskPresentation.value(
                    Formatters.currency(summary.availableBalance, in: summary.currency, format: .compact),
                    isEnabled: appState.shouldMaskFinancialValues
                ),
                tint: AppearanceTextColors.primary,
                reduceMotion: reduceMotion
            )
            DetailValue(
                title: summary.currentTitle,
                value: PrivacyMaskPresentation.value(
                    Formatters.currency(summary.currentBalance, in: summary.currency, format: .compact),
                    isEnabled: appState.shouldMaskFinancialValues
                ),
                tint: AppearanceTextColors.primary,
                reduceMotion: reduceMotion
            )

            // Utilization stays neutral here — risk severity is carried by the
            // tinted icon ladder in the row and the Status section, not by
            // tinting small data text below contrast thresholds.
            if account.balances.utilizationPercent != nil,
               let utilizationText = AccountPresentation.dashboardUtilizationDetailText(
                   for: account,
                   threshold: appState.creditUtilizationThreshold,
                   privacyMaskEnabled: appState.shouldMaskFinancialValues
               )
            {
                DetailValue(
                    title: "Utilization",
                    value: utilizationText,
                    tint: AppearanceTextColors.primary,
                    reduceMotion: reduceMotion
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Balances for \(summary.displayName)")
    }

    private func privateDetailsPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FlyoutSectionLabel("Private")
            Text("Detailed balances, activity, and transaction history are hidden while Privacy Mask or App Lock is active.")
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private details hidden while VaultPeek is private")
    }

    // MARK: Holdings (Plaid Investments — AND-644)

    /// The display rows for this investment account's positions, joined to their
    /// securities and Privacy-Mask-aware, computed by the shared Core helper so
    /// the app never recomputes market values.
    private var holdingRows: [InvestmentHoldingsPresentation.HoldingRow] {
        InvestmentHoldingsPresentation.rows(
            forAccount: account.id,
            holdings: appState.investments.holdings,
            securities: appState.investments.securities,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
    }

    private func holdingsSection() -> some View {
        let summary = InvestmentHoldingsPresentation.summary(
            holdings: appState.investments.holdings,
            accountId: account.id,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                FlyoutSectionLabel("Holdings")
                Spacer(minLength: Spacing.xs)
                Text(summary.totalMarketValueText)
                    .dataText()
            }

            ForEach(holdingRows) { row in
                HoldingRowView(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Holdings. \(summary.accessibilityLabel)")
    }

    // MARK: Changes (30D vs prior 30D)

    private func changesSection(insights: AccountDetailInsights) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlyoutSectionLabel("Changes · 30 days")

            FlyoutChangeRow(
                title: "Spending",
                total: insights.spendTotal,
                delta: insights.spendDelta,
                increaseIsFavorable: false
            )
            FlyoutChangeRow(
                title: "Income",
                total: insights.incomeTotal,
                delta: insights.incomeDelta,
                increaseIsFavorable: true
            )
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Review

    private func reviewSection(insights: AccountDetailInsights) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlyoutSectionLabel("To review")

            ForEach(insights.reviewItems) { item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    TransactionMiniRow(transaction: item.transaction)
                    ReviewReasonChip(reason: item.reason)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(insights.reviewItems.count) transactions to review")
    }

    // MARK: Categories

    private func categoriesSection(insights: AccountDetailInsights) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlyoutSectionLabel("Top categories · 30 days")

            ForEach(insights.topCategories) { slice in
                CategorySliceRow(slice: slice)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Activity

    private func activitySection(
        recent: [TransactionDTO],
        fullFeed: [TransactionDTO],
        emptyState: AccountActivityEmptyState?
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlyoutSectionLabel("Recent activity")

            if fullFeed.isEmpty {
                if let emptyState {
                    AccountActivityEmptyStateView(presentation: emptyState)
                }
            } else if appState.readModelCacheEnabled, !appState.isDemoMode {
                // Large-history virtualization (AND-567): render the full per-account
                // feed through a lazy `LazyVStack` so a multi-thousand-row account
                // history never materializes all rows at once. In-memory source —
                // per-account scope, so it stays on the fallback (in-memory) path and
                // virtualizes today's rows without paging the global cache.
                PagedTransactionListView(source: .inMemory(fullFeed))
            } else {
                // Fallback path (kill-switch off / demo): byte-for-byte today's
                // rendering — the capped recent list in a plain VStack. No regression.
                VStack(alignment: .leading, spacing: Spacing.rowVertical) {
                    ForEach(recent) { transaction in
                        TransactionMiniRow(transaction: transaction)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func emptyState(
        snapshot: AccountTransactionFeed.AccountActivitySnapshot,
        connection: AccountConnectionPresentation
    ) -> AccountActivityEmptyState? {
        AccountActivityEmptyState.evaluate(
            transactionCount: snapshot.transactionCount,
            isDemoMode: appState.usesDemoConnectionPresentation,
            isInitialLoad: appState.loadState(for: .transactions).isInitialLoad,
            serverConnected: appState.serverConnected,
            connectionLevel: connection.level,
            accountDisplayName: AccountPresentation.displayName(for: account)
        )
    }

    // MARK: Actions

    private func actionsSection(summary: DashboardAccountDrillInSummary) -> some View {
        AccountDrillInActionBar(
            actions: DashboardDrillInAction.accountDrillInActions(isDemoMode: appState.isDemoMode),
            accountDisplayName: summary.displayName,
            onAction: performDrillInAction
        )
    }

    // MARK: Connection plumbing

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemConnectionStatus?.status,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }

    private func syncSignalText(connection: AccountConnectionPresentation) -> String {
        if isStatusFilter, let itemSyncLabel = connection.itemSyncLabel {
            return itemSyncLabel
        }
        return connection.signalLabel
    }

    private var connectionRecoveryActionTitle: String {
        switch connectionPresentation.level {
        case .loginRequired, .error:
            connectionPresentation.recoveryActionTitle ?? "Reconnect"
        case .stale, .demo, .offline, .healthy, .unknown:
            "Refresh"
        }
    }

    private var connectionRecoveryActionIcon: String {
        switch connectionPresentation.level {
        case .loginRequired, .error:
            "link.badge.plus"
        case .stale, .demo, .offline, .healthy, .unknown:
            "arrow.clockwise"
        }
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
            SettingsWindowActivationRestorer.shared.open(openSettings: openSettings)
        }
    }

    // MARK: Removal copy

    private var institutionRemovalName: String {
        itemConnectionStatus?.institutionName ?? AccountPresentation.displayName(for: account)
    }

    private var institutionAccountCountText: String {
        let count = max(appState.accounts.count { $0.itemId == account.itemId }, 1)
        return count == 1 ? "1 linked account" : "\(count) linked accounts"
    }

    private var institutionTransactionCountText: String {
        // The dialog message is evaluated as part of the panel body, so gate
        // the full transaction scan on the dialog actually being presented.
        guard isConfirmingAccountRemoval else { return "0 cached local transactions" }
        let institutionAccountIds = Set(
            appState.accounts.filter { $0.itemId == account.itemId }.map(\.id)
        )
        let count = appState.transactions.count { institutionAccountIds.contains($0.accountId) }
        return count == 1 ? "1 cached local transaction" : "\(count) cached local transactions"
    }
}

// MARK: - Section Label

private struct FlyoutSectionLabel: View {
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

// MARK: - Change Row

private struct FlyoutChangeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let total: Double
    let delta: Double
    let increaseIsFavorable: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(Formatters.currency(total, format: .compact))
                .dataText()
                .rollingTabularNumber(Formatters.currency(total, format: .compact), reduceMotion: reduceMotion)

            Spacer(minLength: Spacing.xs)

            if delta != 0 {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.medium))
                    Text("\(Formatters.signedCurrency(delta, format: .compact)) vs prior")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(deltaTint)
                .lineLimit(1)
            } else {
                Text("No change vs prior")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var deltaTint: Color {
        let isFavorable = (delta > 0) == increaseIsFavorable
        return isFavorable ? SemanticColors.positive : SemanticColors.negative
    }

    private var accessibilityText: String {
        if delta == 0 {
            return "\(title) \(Formatters.currency(total, format: .full)) in the last 30 days, unchanged versus the prior 30 days"
        }
        let direction = delta > 0 ? "up" : "down"
        return "\(title) \(Formatters.currency(total, format: .full)) in the last 30 days, \(direction) \(Formatters.currency(abs(delta), format: .full)) versus the prior 30 days"
    }
}

// MARK: - Holding Row (Plaid Investments — AND-644)

/// One investment holding rendered in the account inspector: security name +
/// ticker/type, quantity, market value, and an unrealized gain/loss cue.
///
/// Accessibility (ACCESSIBILITY.md): the gain/loss is never communicated by
/// color alone. The shared `InvestmentHoldingsPresentation` row supplies a
/// directional glyph (arrow up / down / dash — a *shape*) and a sign-prefixed
/// amount string; color is layered on top of those redundant cues, and the
/// whole row carries a spoken VoiceOver label. All currency strings are already
/// Privacy-Mask-aware (masked at the Core layer), so this view does no masking
/// of its own.
private struct HoldingRowView: View {
    let row: InvestmentHoldingsPresentation.HoldingRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(row.securityName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(subtitle)
                    .microText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(row.marketValueText)
                    .dataText()
                if let gainText = row.gainText, let direction = row.gainDirection {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: direction.glyphName)
                            .font(.caption2.weight(.medium))
                        Text(gainText)
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(tint(for: direction))
                    .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// Ticker (or type) + masked-aware quantity, e.g. "AAPL · 50 shares".
    private var subtitle: String {
        let lead = row.tickerSymbol ?? row.securityTypeLabel
        guard let lead, !lead.isEmpty else { return row.quantityText }
        return "\(lead) · \(row.quantityText)"
    }

    /// Color is *additive* on top of the glyph + sign cues, never the sole
    /// signal. `.flat` stays neutral.
    private func tint(for direction: InvestmentHoldingsPresentation.Direction) -> Color {
        switch direction {
        case .gain: return SemanticColors.positive
        case .loss: return SemanticColors.negative
        case .flat: return .secondary
        }
    }
}

// MARK: - Review Reason Chip

private struct ReviewReasonChip: View {
    let reason: AccountDetailInsights.ReviewItem.Reason

    var body: some View {
        Text(label)
            .microText()
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.chipVertical)
            .background(.quinary, in: Capsule())
            .accessibilityLabel("Marked for review: \(label)")
    }

    private var label: String {
        switch reason {
        case .pending: "Pending"
        case .largeAmount: "Large"
        }
    }
}

// MARK: - Category Slice Row

private struct CategorySliceRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let slice: AccountDetailInsights.CategorySlice

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: slice.category.iconName)
                    .font(.caption)
                    .foregroundStyle(tint)
                    .frame(width: Sizing.iconInline)

                Text(slice.category.displayName)
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                Text(Formatters.currency(slice.total, format: .compact))
                    .font(.caption.weight(.semibold))
                    .rollingTabularNumber(Formatters.currency(slice.total, format: .compact), reduceMotion: reduceMotion)

                Text(shareText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rollingTabularNumber(shareText, reduceMotion: reduceMotion)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(.quaternary.opacity(0.5))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.82))
                            .frame(width: max(proxy.size.width * slice.share, 2))
                    }
            }
            .frame(height: 3)
            .padding(.leading, Sizing.iconInline + Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(slice.category.displayName): \(Formatters.currency(slice.total, format: .full)), \(shareText) of 30 day spending, \(slice.transactionCount) transaction\(slice.transactionCount == 1 ? "" : "s")"
        )
    }

    private var shareText: String {
        "\(Int((slice.share * 100).rounded()))%"
    }

    private var tint: Color {
        CategoryAccentTokens.color(for: slice.category)
    }
}

// MARK: - Shared Detail Components

func accountConnectionTint(for level: AccountConnectionLevel) -> Color {
    switch level {
    case .demo, .offline, .healthy, .unknown:
        AppearanceTextColors.secondary
    case .stale, .loginRequired:
        SemanticColors.warning
    case .error:
        SemanticColors.negative
    }
}

struct AccountConnectionBadge: View {
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.chipVertical)
            .background(.quinary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Account status: \(label)")
    }
}

struct DetailValue: View {
    let title: String
    let value: String
    let tint: Color
    var reduceMotion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .dataText()
                .rollingTabularNumber(value, reduceMotion: reduceMotion)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct TransactionMiniRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            MerchantLogoView(
                logoURL: transaction.logoURL,
                fallbackTint: transaction.isIncome ? SemanticColors.positive : Color.secondary.opacity(0.55)
            )

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(transaction.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(Formatters.displayTransactionDate(transaction.date))
                    .microText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if transaction.pending {
                // Pending capsule (AND-499). Color is paired with an SF Symbol +
                // text so the state never reads via color alone (ACCESSIBILITY.md).
                Label("Pending", systemImage: "clock")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SemanticColors.pending)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule().fill(SemanticColors.pending.opacity(0.14))
                    )
                    .accessibilityHidden(true)
            }

            Text(amountText)
                .dataText()
                .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                .foregroundStyle(
                    transaction.isIncome ? SemanticColors.positive : AppearanceTextColors.primary
                )
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
        let pendingNote = transaction.pending ? ", pending" : ""
        return "\(transaction.displayName), \(direction)\(pendingNote), \(Formatters.currency(transaction.displayAmount, format: .full)), \(Formatters.displayTransactionDate(transaction.date))"
    }
}

struct AccountActivityEmptyStateView: View {
    let presentation: AccountActivityEmptyState

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.compactRowContentSpacing) {
            Image(systemName: presentation.iconName)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: Sizing.iconInline + 2, height: Sizing.iconInline + 2)
                .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(presentation.title)
                    .font(.caption.weight(.medium))
                Text(presentation.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.compactRowContentSpacing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var tint: Color {
        switch presentation.tone {
        case .brand:
            SemanticColors.brand
        case .healthy, .loading, .offline, .secondary:
            .secondary
        case .warning:
            SemanticColors.warning
        }
    }
}

struct AccountDrillInActionBar: View {
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(action == .remove ? SemanticColors.negative : AppearanceTextColors.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.chipVertical)
                        .glassSurface(
                            action == .remove ? .emphasized(SemanticColors.negative) : .inset,
                            cornerRadius: Radius.control
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.accessibilityLabel(accountDisplayName: accountDisplayName))
                .accessibilityHint(action.accessibilityHint)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected account actions")
    }
}
