import PlaidBarCore
import SwiftUI

/// **Accounts** destination (3-column — IA §3.1/§5.9, `[⌘8]`, AND-623 / AND-624,
/// ADR-001).
///
/// The full account ledger, re-hosted at **window (desk-distance) density** to
/// match the Dashboard reference (AND-624): a **headline metric row** over a
/// **type-grouped account list** in the content column, feeding the existing
/// ``AccountDetailFlyout`` in the inspector column. The shell renders this content
/// column plus ``Inspector`` in the detail column, which is content-gated and shows
/// "Select an account" when nothing is selected (IA §3.1).
///
/// ## Window-scale layout (AND-624)
/// This is a re-*host* of the same data the popover and Dashboard read — **no model
/// or chart logic lives here** — laid out for the window rather than the glance:
/// 1. a **hero metric row** (net worth, total assets, total debt) as large tabular
///    ``WindowHeroMetricTile`` figures, surfaced from `WealthSummaryPresentation`
///    (the same engine the rail and Dashboard use), so the content column leads with
///    the wealth context the inspector then drills into;
/// 2. the **type-grouped account list**: each ``AccountListGrouping`` section is a
///    ``WindowSection`` (a `title3` header + a count accessory) holding window-scale
///    account rows — larger rows, ≥`.body` tabular balances, sync/utilization shown
///    as glyph + text. The cards stack with the calm ``WindowMetrics`` rhythm, not
///    the popover's tight pack.
///
/// ## Reused engines (nothing rebuilt)
/// - **Selection** rides the existing per-window `NavigationState.selectedAccountID`
///   (the same `""`-sentinel slot the dashboard drill-in uses), so the list and the
///   inspector share one source of truth and two windows select independently
///   (R-10). No new navigation field is added.
/// - **Grouping** is the pure, unit-tested ``AccountListGrouping`` (PlaidBarCore):
///   accounts bucket by ``AccountType`` into ordered, labeled sections, preserving
///   input order within each section.
/// - **Row presentation** (icon, name, subtitle, amount, utilization cue) comes
///   from the shared ``AccountPresentation`` helpers — the same Core layer the
///   popover's `DashboardAccountRow` reads, so the two surfaces can't drift in what
///   a row says.
/// - **Headline figures** come from ``WealthSummaryPresentation`` — no new totals
///   are summed here.
/// - **Detail + actions** (balances, utilization, due dates, sync status, the
///   reconnect / remove / settings action bar) are the existing
///   ``AccountInspector`` → ``AccountDetailFlyout``, which already route reconnect
///   through `AppState.reconnectItem` and removal through `AppState.removeAccount`.
///   Nothing about those paths is re-implemented here.
///
/// ## Privacy & accessibility
/// Amounts route through ``AccountPresentation`` / ``PrivacyMaskPresentation``'s
/// privacy-mask-aware text, and the inspector withholds detail under Privacy Mask /
/// App Lock (the shell also gates the whole window). Selection is carried by a
/// filled vs. outline chevron (shape) and a tinted fill, never color alone
/// (ACCESSIBILITY.md). The hero figures name themselves in text.
///
/// Window-first surface only: built solely behind `WindowFirstFeatureFlag`
/// (default OFF), so with the flag off none of this is instantiated and the popover
/// is byte-identical.
struct AccountsDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var navigationModel: NavigationModel { appState.navigationModel }
    private var accounts: [AccountDTO] { appState.accounts }
    private var sections: [AccountListGrouping.Section] {
        AccountListGrouping.sections(for: accounts)
    }

    var body: some View {
        content
            .navigationTitle(RouteDestination.accounts.title)
            // The window-first Add Account entry point (AND-631): the destination
            // every add-account affordance (Dashboard attention chip, readiness
            // panel, recurring empty state) routes to. Invokes the shared
            // `AppState.addAccount()` flow — which opens Plaid Hosted Link in the
            // browser (no in-app sheet) — so those affordances resolve here instead
            // of dead-ending. In demo it no-ops (keeps demo); with no server it
            // surfaces the actionable error; with credentials it opens Link.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appState.addAccount() }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .help("Connect a bank with Plaid Link")
                    .disabled(appState.isLoading)
                }
            }
            // Self-heal: if the selected account falls out of the list (removed /
            // disconnected), clear it so the inspector returns to its prompt instead
            // of pointing at a vanished account. Mirrors the popover's reconcile.
            .onChange(of: accounts.map(\.id)) { _, ids in
                navigationModel.reconcileSelection(visibleAccountIDs: ids)
            }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if appState.loadState(for: .accounts).showsSkeleton, accounts.isEmpty {
            loadingState
        } else if accounts.isEmpty {
            emptyState
        } else {
            accountCanvas
        }
    }

    /// The window-scale content column: the hero metric row over the type-grouped
    /// account list, on the calm ``WindowMetrics`` rhythm. Scrolls as one canvas so
    /// the headline figures stay attached to the list they summarize.
    private var accountCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                heroMetricsRow

                VStack(alignment: .leading, spacing: WindowMetrics.lg) {
                    ForEach(sections) { section in
                        AccountsGroupSection(
                            section: section,
                            selectedID: selectedID,
                            onSelect: toggleSelection
                        )
                        .environment(appState)
                    }
                }
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Hero metrics row

    /// The headline figures across the top of the content column — net worth, total
    /// assets, total debt — surfaced from the same ``WealthSummaryPresentation`` the
    /// rail and Dashboard use (no new totals summed here). Reflows to wrap on a
    /// narrow window so each figure keeps its tabular legibility. Every value runs
    /// through `PrivacyMaskPresentation`; none rely on color for meaning (the label
    /// names the figure).
    private var heroMetricsRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: WindowMetrics.heroTileMinWidth), spacing: WindowMetrics.lg)],
            alignment: .leading,
            spacing: WindowMetrics.lg
        ) {
            ForEach(heroMetrics) { metric in
                WindowHeroMetricTile(
                    label: metric.label,
                    value: metric.value,
                    systemImage: metric.systemImage,
                    detail: metric.detail,
                    accent: metric.accent,
                    reduceMotion: reduceMotion
                )
            }
        }
        .loadingRedaction(appState.loadState(for: .summaryCards))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Account totals")
    }

    private struct HeroMetric: Identifiable {
        let id: String
        let label: String
        let value: String
        let systemImage: String
        let detail: String?
        let accent: Color
    }

    /// The wealth summary the rail/Dashboard also compute — the single source for net
    /// worth, total assets, total debt, and the account count used by the hero
    /// figures. Re-hosted, not recomputed.
    private var wealthSummary: WealthSummaryPresentation {
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

    private var heroMetrics: [HeroMetric] {
        let masked = appState.shouldMaskFinancialValues
        let summary = wealthSummary

        let netWorth = HeroMetric(
            id: "netWorth",
            label: "Net worth",
            value: PrivacyMaskPresentation.currency(summary.netWorth, format: .compact, isEnabled: masked),
            systemImage: "chart.line.uptrend.xyaxis",
            detail: accountCountDetail(summary.accountCount),
            accent: SemanticColors.brand
        )

        let assets = HeroMetric(
            id: "totalAssets",
            label: "Total assets",
            value: PrivacyMaskPresentation.currency(summary.totalAssets, format: .compact, isEnabled: masked),
            systemImage: "banknote",
            detail: "Cash and savings on hand",
            accent: SemanticColors.positive
        )

        let debt = HeroMetric(
            id: "totalDebt",
            label: "Total debt",
            value: PrivacyMaskPresentation.currency(summary.totalDebt, format: .compact, isEnabled: masked),
            systemImage: "creditcard",
            detail: "Credit and loan balances",
            accent: summary.totalDebt > 0 ? SemanticColors.warning : .secondary
        )

        return [netWorth, assets, debt]
    }

    private func accountCountDetail(_ count: Int) -> String {
        count == 1 ? "Across 1 account" : "Across \(count) accounts"
    }

    // MARK: - Selection (shared NavigationState.selectedAccountID)

    private var selectedID: String { navigationModel.selectedAccountID }

    private func toggleSelection(_ account: AccountDTO) {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            if selectedID == account.id {
                navigationModel.deselectAccount()
            } else {
                navigationModel.selectedAccountID = account.id
            }
        }
    }

    // MARK: - Empty / loading states

    private var loadingState: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading accounts")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: RouteDestination.accounts.systemImage)
        } description: {
            Text("Connect an institution to see its accounts here.")
        } actions: {
            // The primary recovery action for the no-accounts dead-end (AND-631):
            // start Plaid Link via the shared flow rather than leaving the user on
            // an explanation with no next step.
            Button {
                Task { await appState.addAccount() }
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The detail-column (inspector) pane for Accounts — the selected account's
    /// full detail and actions, re-hosting the existing ``AccountInspector`` /
    /// ``AccountDetailFlyout``. Content-gated: shows "Select an account" when
    /// nothing is selected (IA §3.1). A separate `View` because the shell mounts the
    /// content and inspector columns independently; both read the shared selection
    /// from `AppState.navigationModel`.
    struct Inspector: View {
        @Environment(AppState.self) private var appState

        private var navigationModel: NavigationModel { appState.navigationModel }

        /// The selected account resolved against the live (visible) accounts — `nil`
        /// when nothing is selected or the selection is no longer present, which
        /// content-gates the inspector to its prompt.
        private var selectedAccount: AccountDTO? {
            guard let id = navigationModel.resolvedSelectedID(
                visibleAccountIDs: appState.accounts.map(\.id)
            ) else { return nil }
            return appState.accounts.first { $0.id == id }
        }

        var body: some View {
            if let account = selectedAccount {
                AccountInspector(
                    account: account,
                    // Parity with the popover: the trailing inspector treats item-
                    // level sync as the status-filter detail does, surfacing the
                    // institution sync label.
                    isStatusFilter: navigationModel.dashboardFilter == .status,
                    onClose: { navigationModel.deselectAccount() }
                )
                .environment(appState)
            } else {
                DestinationInspectorPlaceholder(destination: .accounts)
            }
        }
    }
}

// MARK: - Account group section (window scale)

/// One type-group of accounts as a window-scale titled card: an
/// ``AccountListGrouping`` section rendered as a ``WindowSection`` (a `title3`
/// header + a count accessory) holding its account rows. This is the
/// list→inspector idiom at desk-distance density — a calm card per group rather
/// than the popover's pinned `.bar` headers over a tight stack.
private struct AccountsGroupSection: View {
    @Environment(AppState.self) private var appState
    let section: AccountListGrouping.Section
    let selectedID: String
    let onSelect: (AccountDTO) -> Void

    var body: some View {
        WindowSection(section.title, systemImage: Self.sectionSymbol(for: section.type)) {
            Text("\(section.accounts.count)")
                .windowSupportingText()
                .monospacedDigit()
                .accessibilityLabel("\(section.accounts.count) account\(section.accounts.count == 1 ? "" : "s")")
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(section.accounts.enumerated()), id: \.element.id) { index, account in
                    AccountListRow(
                        account: account,
                        isSelected: selectedID == account.id,
                        showsDivider: index < section.accounts.count - 1,
                        onSelect: { onSelect(account) }
                    )
                    .environment(appState)
                }
            }
        }
    }

    /// A group glyph for a section header, keyed by ``AccountType`` (shape, not
    /// color, carries meaning — ACCESSIBILITY.md). Namespaced here rather than in
    /// Core because it is purely this destination's section chrome; the per-row
    /// glyph still comes from the shared `AccountPresentation.iconName`.
    private static func sectionSymbol(for type: AccountType) -> String {
        switch type {
        case .depository: return "building.columns"
        case .credit: return "creditcard"
        case .loan: return "dollarsign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "square.grid.2x2"
        }
    }
}

// MARK: - Account Row (window scale)

/// A single account row in the Accounts destination's content column, at window
/// (desk-distance) density. Re-hosts the popover row's visual idiom (leading type
/// icon, name + subtitle, trailing amount + utilization cue, selection chevron) on
/// the shared ``AccountPresentation`` helpers so the two surfaces can't drift, but
/// scaled up for the window: a larger icon chip, `.body` name, `.subheadline`
/// subtitle, and a `.body`-tabular balance figure. Selection is carried by a filled
/// vs. outline chevron (shape) and a tinted fill, never color alone (ACCESSIBILITY.md).
private struct AccountListRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: AccountDTO
    let isSelected: Bool
    let showsDivider: Bool
    let onSelect: () -> Void

    private var privacyMaskEnabled: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: WindowMetrics.sm) {
                Image(systemName: AccountPresentation.iconName(for: account))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
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

                VStack(alignment: .trailing, spacing: 2) {
                    Text(amountText)
                        .windowDataText()
                        .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                        .foregroundStyle(AppearanceTextColors.primary)
                        .lineLimit(1)

                    if let utilization = account.balances.utilizationPercent,
                       let utilizationText = AccountPresentation.dashboardUtilizationDetailText(
                           for: account,
                           threshold: appState.creditUtilizationThreshold,
                           privacyMaskEnabled: privacyMaskEnabled
                       ) {
                        HStack(spacing: WindowMetrics.xs / 2) {
                            if utilization >= appState.creditUtilizationThreshold {
                                // Tint the icon, never the small text — orange caption
                                // text fails 4.5:1 contrast (ACCESSIBILITY.md).
                                Image(systemName: SemanticColors.utilizationIcon(
                                    for: utilization,
                                    threshold: appState.creditUtilizationThreshold
                                ))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SemanticColors.utilization(
                                    for: utilization,
                                    threshold: appState.creditUtilizationThreshold
                                ))
                            }
                            Text(utilizationText)
                                .windowSupportingText()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }

                Image(systemName: isSelected ? "chevron.forward.circle.fill" : "chevron.forward")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, WindowMetrics.sm)
            .padding(.vertical, WindowMetrics.sm)
            .background(
                isSelected ? Color.accentColor.opacity(SurfaceTokens.selectedFillOpacity) : .clear,
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .overlay(alignment: .bottom) {
                if showsDivider, !isSelected {
                    Divider().opacity(0.4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Shows this account's details in the inspector.")
    }

    private var subtitle: String {
        AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: AccountPresentation.subtitle(for: account, privacyMaskEnabled: privacyMaskEnabled),
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
            connectionLabel: AccountPresentation.subtitle(for: account, privacyMaskEnabled: privacyMaskEnabled),
            pendingCount: pendingCount,
            isSelected: isSelected,
            utilizationThreshold: appState.creditUtilizationThreshold,
            privacyMaskEnabled: privacyMaskEnabled,
            liability: appState.liabilities.first { $0.accountId == account.id }
        )
    }
}

#Preview("Content") {
    AccountsDestinationView()
        .environment(AppState())
        .frame(width: 640, height: 480)
}

#Preview("Inspector") {
    AccountsDestinationView.Inspector()
        .environment(AppState())
        .frame(width: 320, height: 480)
}
