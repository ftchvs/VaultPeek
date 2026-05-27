import SwiftUI
import PlaidBarCore

struct MainPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var selectedFilter: DashboardAccountFilter = .all
    @State private var selectedAccountId: String?
    @State private var settingsCloseObserver: NSObjectProtocol?

    private var selectedAccount: AccountDTO? {
        let accounts = filteredAccounts
        if let selectedAccountId,
           let account = accounts.first(where: { $0.id == selectedAccountId }) {
            return account
        }
        return accounts.first ?? appState.accounts.first
    }

    private var filteredAccounts: [AccountDTO] {
        appState.accounts.filter { selectedFilter.includes($0, appState: appState) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isSetupComplete {
                SetupView()
                    .frame(width: 600)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DashboardHeader()
                            .environment(appState)

                        DashboardStatusStrip()
                            .environment(appState)

                        DashboardSummaryCards()
                            .environment(appState)

                        BalanceActivityHeatmap(transactions: appState.transactions)

                        DashboardFilterBar(selection: $selectedFilter)

                        AccountsSection(
                            accounts: filteredAccounts,
                            filter: selectedFilter,
                            selectedAccountId: selectedAccount?.id,
                            onSelect: { selectedAccountId = $0.id }
                        )
                        .environment(appState)

                        if let selectedAccount {
                            SelectedAccountPanel(account: selectedAccount)
                                .environment(appState)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 690, maxHeight: 820)

                Divider()

                DashboardFooter(
                    settingsCloseObserver: $settingsCloseObserver,
                    openSettings: openSettings
                )
                .environment(appState)
            }

            if let error = appState.error {
                ErrorBanner(error: error)
                    .environment(appState)
            }
        }
        .frame(width: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: appState.error != nil)
        .task {
            await appState.loadInitialData()
        }
        .onChange(of: appState.accounts) { _, accounts in
            guard selectedAccountId == nil || !accounts.contains(where: { $0.id == selectedAccountId }) else { return }
            selectedAccountId = accounts.first?.id
        }
        .onChange(of: selectedFilter) { _, _ in
            selectedAccountId = filteredAccounts.first?.id
        }
    }
}

// MARK: - Dashboard Header

private struct DashboardHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Net Worth")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Text(Formatters.currency(appState.netBalance, format: .full))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 24)

            VStack(alignment: .trailing, spacing: 4) {
                Text("PlaidBar")
                    .font(.headline.weight(.bold))
                Text(appState.statusSyncText)
                    .detailText()
                    .lineLimit(1)
            }
            .padding(.top, 3)
        }
    }
}

private struct DashboardStatusStrip: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            StatusStripItem(
                title: "Mode",
                value: appState.statusModeText,
                icon: appState.isDemoMode ? "play.circle.fill" : "server.rack",
                tint: appState.isDemoMode ? SemanticColors.brandSecondary : SemanticColors.brand
            )

            StatusDivider()

            StatusStripItem(
                title: "Server",
                value: appState.statusServerText,
                icon: serverIcon,
                tint: serverTint
            )

            StatusDivider()

            StatusStripItem(
                title: "Sync",
                value: appState.statusSyncText,
                icon: appState.isSyncStale ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill",
                tint: appState.isSyncStale ? SemanticColors.warning : SemanticColors.positive
            )

            StatusDivider()

            StatusStripItem(
                title: "Items",
                value: itemsText,
                icon: itemIcon,
                tint: itemTint
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var serverIcon: String {
        if appState.isLoading { return "arrow.triangle.2.circlepath" }
        if appState.error != nil { return "xmark.octagon.fill" }
        return appState.serverConnected ? "checkmark.circle.fill" : "server.rack"
    }

    private var serverTint: Color {
        if appState.isLoading { return SemanticColors.warning }
        if appState.error != nil { return SemanticColors.negative }
        return appState.serverConnected ? SemanticColors.positive : .secondary
    }

    private var itemsText: String {
        if appState.needsLoginItemCount > 0 {
            return "\(appState.needsLoginItemCount) login"
        }
        if appState.erroredItemCount > 0 {
            return "\(appState.erroredItemCount) error"
        }
        return "\(appState.statusItemCount) linked"
    }

    private var itemIcon: String {
        if appState.needsLoginItemCount > 0 { return "person.crop.circle.badge.exclamationmark.fill" }
        if appState.erroredItemCount > 0 { return "exclamationmark.triangle.fill" }
        return "link.circle.fill"
    }

    private var itemTint: Color {
        if appState.erroredItemCount > 0 { return SemanticColors.negative }
        if appState.needsLoginItemCount > 0 { return SemanticColors.warning }
        return appState.statusItemCount > 0 ? SemanticColors.positive : .secondary
    }
}

private struct StatusStripItem: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .microText()
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
    }
}

private struct DashboardSummaryCards: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "Cash",
                value: Formatters.currency(appState.totalCash, format: .compact),
                tint: SemanticColors.available
            )

            MetricCard(
                title: "Debt",
                value: Formatters.currency(totalDebt, format: .compact),
                tint: SemanticColors.creditDebt
            )

            MetricCard(
                title: "Runway",
                value: Formatters.currency(appState.netBalance, format: .compact),
                tint: SemanticColors.brand
            )
        }
    }

    private var totalDebt: Double {
        appState.creditAccounts.reduce(0) { total, account in
            total + abs(account.balances.current ?? 0)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

// MARK: - 365 Day Heatmap

private struct BalanceActivityHeatmap: View {
    let transactions: [TransactionDTO]

    private let calendar = Calendar.current
    private let spacing: CGFloat = 3
    private let monthLabelHeight: CGFloat = 12

    private var days: [SpendingHeatmapDay] {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmap.days(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: .spending,
            calendar: calendar
        )
    }

    private var peakValue: Double {
        max(days.map(\.value).max() ?? 0, 1)
    }

    private var activeDayCount: Int {
        days.filter { $0.transactionCount > 0 }.count
    }

    private var totalSpend: Double {
        days.reduce(0) { $0 + $1.value }
    }

    private var weekColumns: [[SpendingHeatmapDay?]] {
        guard let firstDay = days.first,
              let firstDate = Formatters.parseTransactionDate(firstDay.date) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let padded: [SpendingHeatmapDay?] = Array(repeating: nil, count: leadingEmptyDays) + days.map(Optional.some)
        return stride(from: 0, to: padded.count, by: 7).map { start in
            let week = Array(padded[start..<min(start + 7, padded.count)])
            return week + Array(repeating: nil, count: max(0, 7 - week.count))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("365D Spending Activity")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                Text(Formatters.currency(totalSpend, format: .compact))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                let weeks = max(weekColumns.count, 1)
                let cell = max(6, min(9, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks))))

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(weekColumns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            Text(monthLabel(for: week))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: cell, height: monthLabelHeight, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)

                            VStack(spacing: spacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    if let day {
                                        BalanceHeatmapCell(day: day, peakValue: peakValue, size: cell)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.clear)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: monthLabelHeight + 4 + 7 * 9 + 6 * spacing)

            HStack(spacing: 5) {
                Text("Less")
                    .microText()
                    .foregroundStyle(.secondary)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BalanceHeatmapCell.fillColor(intensity: intensity))
                        .frame(width: 9, height: 9)
                }

                Text("More")
                    .microText()
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(activeDayCount) days · Last 365D")
                    .microText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spending activity heatmap for the last 365 days with \(activeDayCount) active days.")
    }

    private func monthLabel(for week: [SpendingHeatmapDay?]) -> String {
        for day in week.compactMap(\.self) {
            guard let date = Formatters.parseTransactionDate(day.date) else { continue }
            guard calendar.component(.day, from: date) <= 7 else { continue }
            return date.formatted(.dateTime.month(.abbreviated))
        }
        return ""
    }
}

private struct BalanceHeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.fillColor(intensity: intensity))
            .frame(width: size, height: size)
            .help(helpText)
    }

    private var intensity: Double {
        guard day.transactionCount > 0 else { return 0 }
        return min(max(day.value / peakValue, 0), 1)
    }

    private var helpText: String {
        "\(Formatters.displayTransactionDate(day.date)): \(Formatters.currency(day.value, format: .full)) across \(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    static func fillColor(intensity: Double) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.08) }
        return SemanticColors.positive.opacity(0.18 + (0.72 * intensity))
    }
}

// MARK: - Account Filters

private enum DashboardAccountFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case cash = "Cash"
    case credit = "Credit"
    case savings = "Savings"
    case debt = "Debt"
    case status = "Status"

    var id: String { rawValue }

    @MainActor
    func includes(_ account: AccountDTO, appState: AppState) -> Bool {
        switch self {
        case .all:
            return true
        case .cash:
            return account.type == .depository
        case .credit:
            return account.type == .credit
        case .savings:
            return account.subtype?.localizedCaseInsensitiveContains("saving") == true
        case .debt:
            return account.type == .credit || account.type == .loan
        case .status:
            guard appState.needsLoginItemCount > 0 || appState.erroredItemCount > 0 else { return true }
            let degradedItemIds = Set(
                appState.itemStatuses
                    .filter { $0.status == .loginRequired || $0.status == .error }
                    .map(\.id)
            )
            return degradedItemIds.contains(account.itemId)
        }
    }
}

private struct DashboardFilterBar: View {
    @Binding var selection: DashboardAccountFilter

    var body: some View {
        HStack(spacing: 1) {
            ForEach(DashboardAccountFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection == filter ? .white : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == filter ? SemanticColors.brand : Color.clear)

                if filter != DashboardAccountFilter.allCases.last {
                    Divider()
                        .padding(.vertical, 8)
                }
            }
        }
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Account List

private struct AccountsSection: View {
    @Environment(AppState.self) private var appState
    let accounts: [AccountDTO]
    let filter: DashboardAccountFilter
    let selectedAccountId: String?
    let onSelect: (AccountDTO) -> Void

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
            .padding(.horizontal, 2)
            .padding(.bottom, 7)

            if accounts.isEmpty {
                DashboardEmptyAccountState(filter: filter)
                    .environment(appState)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        Button {
                            onSelect(account)
                        } label: {
                            DashboardAccountRow(
                                account: account,
                                isSelected: selectedAccountId == account.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct DashboardEmptyAccountState: View {
    @Environment(AppState.self) private var appState
    let filter: DashboardAccountFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
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
                    Button {
                        Task { await appState.addAccount() }
                    } label: {
                        Label("Add Account", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    Task {
                        if !appState.serverConnected {
                            await appState.checkServerConnection()
                        } else {
                            await appState.refreshAccounts()
                            await appState.syncTransactions()
                        }
                    }
                } label: {
                    Label(actionTitle, systemImage: actionIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private var title: String {
        if !appState.isDemoMode && !appState.serverConnected { return "Server offline" }
        if appState.statusItemCount == 0 { return "No bank linked" }
        if appState.accounts.isEmpty { return "No account data" }
        if filter == .status { return "No accounts need attention" }
        return "No \(filter.rawValue.lowercased()) accounts"
    }

    private var message: String {
        if !appState.isDemoMode && !appState.serverConnected {
            return "Start PlaidBarServer, then check the connection again."
        }
        if appState.statusItemCount == 0 {
            return "Connect a Plaid institution to show balances in this menu bar dashboard."
        }
        if appState.accounts.isEmpty {
            return "The server has linked items, but balances have not loaded yet."
        }
        if filter == .status {
            return "Every linked item looks healthy. Switch filters to inspect balances."
        }
        return "This filter has no matching linked accounts. Switch filters or add another institution."
    }

    private var icon: String {
        if !appState.isDemoMode && !appState.serverConnected { return "server.rack" }
        if appState.statusItemCount == 0 { return "building.columns" }
        if appState.accounts.isEmpty { return "tray" }
        if filter == .status { return "checkmark.circle.fill" }
        return "line.3.horizontal.decrease.circle"
    }

    private var tint: Color {
        if !appState.isDemoMode && !appState.serverConnected { return .secondary }
        if appState.statusItemCount == 0 { return SemanticColors.brand }
        if appState.accounts.isEmpty { return SemanticColors.warning }
        if filter == .status { return SemanticColors.positive }
        return .secondary
    }

    private var showsAddAccount: Bool {
        appState.serverConnected && appState.statusItemCount == 0
    }

    private var actionTitle: String {
        !appState.serverConnected ? "Check Server" : "Refresh"
    }

    private var actionIcon: String {
        "arrow.clockwise"
    }
}

private struct DashboardAccountRow: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: account.type == .credit ? "creditcard.fill" : "building.columns.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(account.type == .credit ? SemanticColors.creditDebt : SemanticColors.available)
                .frame(width: 34, height: 34)
                .background((account.type == .credit ? SemanticColors.creditDebt : SemanticColors.available).opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .detailText()
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(account.type == .credit ? SemanticColors.creditDebt : .primary)
                    .lineLimit(1)

                if let utilization = account.balances.utilizationPercent {
                    Text(Formatters.percent(utilization, decimals: 0))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SemanticColors.utilization(for: utilization))
                } else {
                    Text(statusText)
                        .microText()
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? SemanticColors.brand.opacity(0.14) : Color.primary.opacity(0.018))
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.55)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let mask = account.mask.map { " •••• \($0)" } ?? ""
        let pending = pendingCount > 0 ? " • \(pendingCount) pending" : ""
        return "\(account.institutionName ?? account.type.rawValue.capitalized)\(mask) • \(statusText)\(pending)"
    }

    private var amountText: String {
        let amount = account.balances.current ?? account.balances.effectiveBalance
        return Formatters.currency(account.type == .credit ? abs(amount) : amount, format: .full)
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).filter(\.pending).count
    }

    private var itemStatus: ItemConnectionStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }?.status
    }

    private var statusText: String {
        if appState.isDemoMode { return "Demo" }
        if !appState.serverConnected { return "Server offline" }

        switch itemStatus {
        case .connected:
            return appState.statusSyncText
        case .loginRequired:
            return "Reconnect"
        case .error:
            return "Item error"
        case nil:
            return appState.statusSyncText
        }
    }

    private var statusTint: Color {
        if appState.isDemoMode { return SemanticColors.brandSecondary }
        if !appState.serverConnected { return .secondary }

        switch itemStatus {
        case .connected:
            return appState.isSyncStale ? SemanticColors.warning : SemanticColors.positive
        case .loginRequired:
            return SemanticColors.warning
        case .error:
            return SemanticColors.negative
        case nil:
            return appState.isSyncStale ? SemanticColors.warning : .secondary
        }
    }
}

// MARK: - Selected Account

private struct SelectedAccountPanel: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO

    private var transactions: [TransactionDTO] {
        Array(accountTransactions.prefix(5))
    }

    private var accountTransactions: [TransactionDTO] {
        appState.transactionsForAccount(account.id)
    }

    private var pendingTransactions: [TransactionDTO] {
        accountTransactions.filter(\.pending)
    }

    private var outflowTotal: Double {
        accountTransactions
            .filter { !$0.isIncome && $0.category != .transfer && $0.category != .transferOut }
            .reduce(0) { $0 + $1.displayAmount }
    }

    private var inflowTotal: Double {
        accountTransactions
            .filter(\.isIncome)
            .reduce(0) { $0 + $1.displayAmount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected")
                        .sectionTitle()
                        .foregroundStyle(.secondary)
                    Text(account.officialName ?? account.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text(selectedSubtitle)
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

            HStack(spacing: 10) {
                DetailValue(title: "Available", value: availableText, tint: SemanticColors.available)
                DetailValue(title: "Current", value: currentText, tint: .primary)

                if let utilization = account.balances.utilizationPercent {
                    DetailValue(
                        title: "Utilization",
                        value: Formatters.percent(utilization, decimals: 0),
                        tint: SemanticColors.utilization(for: utilization)
                    )
                } else {
                    DetailValue(title: "Activity", value: activityText, tint: connectionTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                AccountSignalPill(
                    title: "Pending",
                    value: "\(pendingTransactions.count)",
                    icon: "clock.fill",
                    tint: pendingTransactions.isEmpty ? .secondary : SemanticColors.pending
                )
                AccountSignalPill(
                    title: "Out",
                    value: Formatters.currency(outflowTotal, format: .compact),
                    icon: "arrow.up.right.circle.fill",
                    tint: outflowTotal > 0 ? SemanticColors.negative : .secondary
                )
                AccountSignalPill(
                    title: "In",
                    value: Formatters.currency(inflowTotal, format: .compact),
                    icon: "arrow.down.left.circle.fill",
                    tint: inflowTotal > 0 ? SemanticColors.positive : .secondary
                )
                AccountSignalPill(
                    title: "Sync",
                    value: syncSignalText,
                    icon: connectionIcon,
                    tint: connectionTint
                )
            }

            if shouldShowRecoveryActions {
                HStack(spacing: 8) {
                    if itemStatus == .loginRequired || itemStatus == .error {
                        Button {
                            Task { await appState.reconnectItem(itemId: account.itemId) }
                        } label: {
                            Label("Reconnect", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        Task {
                            await appState.refreshBalances()
                            await appState.syncTransactions()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Activity")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                if transactions.isEmpty {
                    Text("No recent activity for this account.")
                        .detailText()
                        .padding(.vertical, 10)
                } else {
                    ForEach(transactions) { transaction in
                        TransactionMiniRow(transaction: transaction)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(connectionTint.opacity(0.18), lineWidth: 1)
        }
    }

    private var selectedSubtitle: String {
        let subtype = account.subtype?.capitalized ?? account.type.rawValue.capitalized
        let mask = account.mask.map { " •••• \($0)" } ?? ""
        return "\(account.type.rawValue.capitalized) • \(subtype)\(mask)"
    }

    private var availableText: String {
        Formatters.currency(account.balances.available ?? account.balances.effectiveBalance, format: .compact)
    }

    private var currentText: String {
        let amount = account.balances.current ?? account.balances.effectiveBalance
        return Formatters.currency(account.type == .credit ? abs(amount) : amount, format: .compact)
    }

    private var itemStatus: ItemConnectionStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }?.status
    }

    private var connectionLabel: String {
        if appState.isDemoMode { return "Demo data" }
        if !appState.serverConnected { return "Server offline" }

        switch itemStatus {
        case .connected:
            return appState.statusSyncText
        case .loginRequired:
            return "Login required"
        case .error:
            return "Item error"
        case nil:
            return appState.statusSyncText
        }
    }

    private var connectionIcon: String {
        if appState.isDemoMode { return "play.circle.fill" }
        if !appState.serverConnected { return "server.rack" }

        switch itemStatus {
        case .connected:
            return appState.isSyncStale ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill"
        case .loginRequired:
            return "person.crop.circle.badge.exclamationmark.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case nil:
            return appState.isSyncStale ? "clock.badge.exclamationmark.fill" : "link.circle.fill"
        }
    }

    private var connectionTint: Color {
        if appState.isDemoMode { return SemanticColors.brandSecondary }
        if !appState.serverConnected { return .secondary }

        switch itemStatus {
        case .connected:
            return appState.isSyncStale ? SemanticColors.warning : SemanticColors.positive
        case .loginRequired:
            return SemanticColors.warning
        case .error:
            return SemanticColors.negative
        case nil:
            return appState.isSyncStale ? SemanticColors.warning : .secondary
        }
    }

    private var activityText: String {
        "\(accountTransactions.count) tx"
    }

    private var syncSignalText: String {
        if itemStatus == .loginRequired { return "Login" }
        if itemStatus == .error { return "Error" }
        if appState.isSyncStale { return "Stale" }
        return "Fresh"
    }

    private var shouldShowRecoveryActions: Bool {
        !appState.isDemoMode && (appState.isSyncStale || itemStatus == .loginRequired || itemStatus == .error)
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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct AccountSignalPill: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DetailValue: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}

private struct TransactionMiniRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(transaction.isIncome ? SemanticColors.positive : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
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
    }

    private var amountText: String {
        let prefix = transaction.isIncome ? "+" : ""
        return "\(prefix)\(Formatters.currency(transaction.displayAmount, format: .compact))"
    }
}

// MARK: - Footer

private struct DashboardFooter: View {
    @Environment(AppState.self) private var appState
    @Binding var settingsCloseObserver: NSObjectProtocol?
    let openSettings: OpenSettingsAction

    var body: some View {
        HStack(spacing: 18) {
            Button {
                Task { await appState.addAccount() }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Add Account")
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Button {
                Task {
                    await appState.refreshBalances()
                    await appState.syncTransactions()
                }
            } label: {
                RefreshIcon(isLoading: appState.isLoading)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func openSettingsWindow() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first(where: {
                $0.canBecomeKey && $0.isVisible && $0.level == .normal
            }) {
                settingsWindow.orderFrontRegardless()
                if let existing = settingsCloseObserver {
                    NotificationCenter.default.removeObserver(existing)
                }
                settingsCloseObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: settingsWindow,
                    queue: .main
                ) { _ in
                    NSApp.setActivationPolicy(.accessory)
                    if let observer = settingsCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    settingsCloseObserver = nil
                }
            }
        }
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(.red.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
