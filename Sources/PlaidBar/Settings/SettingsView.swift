import SwiftUI
import PlaidBarCore
import Sparkle
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.selectedTab") private var selectedTab = SettingsTab.general.rawValue
    let updater: SPUUpdater

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general.rawValue)

            AccountSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Accounts", systemImage: "building.columns")
                }
                .tag(SettingsTab.accounts.rawValue)

            NotificationSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(SettingsTab.notifications.rawValue)

            AboutView(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
        }
        .frame(width: 620, height: 560)
    }
}

private enum SettingsTab: String {
    case general
    case accounts
    case notifications
    case about
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingResetConfirmation = false
    @State private var resetResultMessage: String?
    @State private var resetErrorMessage: String?

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SettingsCard {
                    settingsRow("Menu bar shows") {
                        Picker("Menu bar shows", selection: $state.menuBarSummaryMode) {
                            ForEach(MenuBarSummaryMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }

                    settingsRow("Balance format") {
                        Picker("Balance format", selection: $state.balanceFormat) {
                            Text("$12,450.32").tag(CurrencyFormat.full)
                            Text("$12.4K").tag(CurrencyFormat.abbreviated)
                            Text("$12,450").tag(CurrencyFormat.compact)
                        }
                        .labelsHidden()
                        .frame(width: 230)
                        .disabled(appState.menuBarSummaryMode == .creditUtilization || appState.menuBarSummaryMode == .iconOnly)
                    }

                    settingsRow("Refresh interval") {
                        Picker("Refresh interval", selection: $state.refreshInterval) {
                            Text("5 minutes").tag(TimeInterval(5 * 60))
                            Text("15 minutes").tag(TimeInterval(15 * 60))
                            Text("30 minutes").tag(TimeInterval(30 * 60))
                            Text("1 hour").tag(TimeInterval(60 * 60))
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }

                    settingsRow("Credit warning") {
                        HStack(spacing: Spacing.sm) {
                            TextField(
                                "",
                                value: $state.creditUtilizationThreshold,
                                format: .number.precision(.fractionLength(0))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help("Credit cards above this utilization threshold show warning colors")

                    Toggle("Launch at login", isOn: $state.launchAtLogin)
                        .padding(.top, Spacing.xs)
                }

                SettingsCard(title: "Local AI") {
                    settingsRow("Availability") {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: localAIAvailabilityIcon)
                                .foregroundStyle(localAIAvailabilityTint)
                            Text(appState.localAIAvailability.state.displayName)
                                .font(.body.weight(.medium))
                        }
                    }

                    settingsRow("Runtime") {
                        Text(appState.localAIAvailability.runtimeName ?? "None configured")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text(appState.localAIAvailability.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)

                    Text("VaultPeek does not send transaction data to cloud AI services. Local insight summaries are derived from local accounts, transactions, and recurring detections; raw Plaid transaction categories remain unchanged.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: "Local Data") {
                    settingsRow("Storage path", alignment: .top) {
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text(appState.activeStorageDirectoryDisplayText)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)

                            Text(storageDetailText)
                                .detailText()
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }

                    LocalTrustReceiptView(receipt: localTrustReceipt)

                    HStack(alignment: .center, spacing: Spacing.sm) {
                        Button {
                            revealStorageDirectory()
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }
                        .controlSize(.small)

                        Button {
                            copyStoragePath()
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)

                        Button {
                            isShowingResetConfirmation = true
                        } label: {
                            Label("Reset Local Data", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .alert("Reset Local Data?", isPresented: $isShowingResetConfirmation) {
            Button("Reset Local Data", role: .destructive) {
                resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the SQLite database, account and transaction caches, stored Plaid access tokens, sync cursors, and loaded account data under \(appState.activeStorageDirectoryDisplayText). Keeps server.conf, app/server auth, Plaid dashboard Items, shell credentials, and app preferences. Restart the VaultPeek companion server after resetting.")
        }
        .alert("Local Data Reset", isPresented: Binding(
            get: { resetResultMessage != nil },
            set: { if !$0 { resetResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetResultMessage ?? "")
        }
        .alert("Reset Failed", isPresented: Binding(
            get: { resetErrorMessage != nil },
            set: { if !$0 { resetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetErrorMessage ?? "")
        }
    }

    private func revealStorageDirectory() {
        let url = appState.activeStorageDirectoryURL
        try? LocalDataStore.prepareStorageDirectory(at: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyStoragePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.activeStorageDirectoryURL.path, forType: .string)
    }

    private func resetLocalData() {
        do {
            let result = try appState.resetLocalData()
            let preservationText = preservedEntriesText(for: result)
            if result.removedEntryCount == 0 {
                resetResultMessage = "No local data found. \(LocalDataStore.displayPath(for: URL(fileURLWithPath: result.directoryPath, isDirectory: true))) is ready. \(keychainResetText(for: result))\(preservationText)"
            } else {
                resetResultMessage = "Removed \(result.removedEntryCount) VaultPeek data item\(result.removedEntryCount == 1 ? "" : "s") from \(LocalDataStore.displayPath(for: URL(fileURLWithPath: result.directoryPath, isDirectory: true))). \(keychainResetText(for: result))\(preservationText) Restart the VaultPeek companion server."
            }
        } catch {
            resetErrorMessage = error.localizedDescription
        }
    }

    private var storageDetailText: String {
        if let serverStoragePath = appState.serverStoragePath {
            return "Server: \(LocalDataStore.displayPath(for: URL(fileURLWithPath: NSString(string: serverStoragePath).expandingTildeInPath)))"
        }

        return "Default: \(appState.localStorageResolvedDisplayPathText)"
    }

    private var localTrustReceipt: LocalTrustReceipt {
        LocalTrustReceipt.settingsReceipt(storagePath: appState.activeStorageDirectoryDisplayText)
    }

    private var localAIAvailabilityIcon: String {
        switch appState.localAIAvailability.state {
        case .available: "cpu.fill"
        case .disabled: "pause.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var localAIAvailabilityTint: Color {
        switch appState.localAIAvailability.state {
        case .available: SemanticColors.positive
        case .disabled: .secondary
        case .unavailable: SemanticColors.warning
        }
    }

    private func keychainResetText(for result: LocalDataResetResult) -> String {
        result.keychainTokensCleared
            ? "Keychain token entries were cleared when present."
            : "Keychain token entries were not cleared."
    }

    private func preservedEntriesText(for result: LocalDataResetResult) -> String {
        guard result.preservedEntryCount > 0 else { return "" }
        return " Left \(result.preservedEntryCount) config or unrelated item\(result.preservedEntryCount == 1 ? "" : "s") untouched."
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                Text(title)
                    .sectionTitle()
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LocalTrustReceiptView: View {
    let receipt: LocalTrustReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(receipt.title)
                    .font(.headline)

                Text(receipt.subtitle)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(receipt.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                            Text(row.detail)
                                .detailText()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title). \(row.detail)")
                }
            }

            Text(receipt.footer)
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@ViewBuilder
@MainActor
private func settingsRow<Content: View>(
    _ title: String,
    alignment: VerticalAlignment = .center,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: alignment, spacing: Spacing.md) {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .leading)

        Spacer(minLength: Spacing.md)

        content()
            .frame(maxWidth: 330, alignment: .trailing)
    }
}

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingAccountSetup = false
    @State private var pendingRemoval: PendingAccountRemoval?

    private var emptyPresentation: SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.accounts(
            isDemoMode: appState.isDemoMode,
            serverConnected: appState.serverConnected,
            linkedItemCount: appState.statusItemCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AttentionQueueView(
                title: "ATTENTION",
                showsHealthyRow: false,
                onAddAccount: handleAddAccount
            )
            .environment(appState)
            .padding([.horizontal, .top], Spacing.md)

            if appState.accounts.isEmpty {
                SecondaryUnavailableView(presentation: emptyPresentation) {
                    performEmptyAction(emptyPresentation.action)
                }
            } else {
                List {
                    ForEach(accountGroups) { group in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(group.institutionName)
                                        .font(.headline)

                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: group.connection.iconName)
                                            .foregroundStyle(color(for: group.connection.level))
                                        Text(group.connection.signalLabel)
                                            .foregroundStyle(color(for: group.connection.level))
                                        Text("\u{00B7}")
                                            .foregroundStyle(.tertiary)
                                        Text("\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")")
                                            .foregroundStyle(.secondary)
                                        if let itemSyncLabel = group.connection.itemSyncLabel {
                                            Text("\u{00B7}")
                                                .foregroundStyle(.tertiary)
                                            Text(itemSyncLabel)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .detailText()

                                    if let recoveryDetailLabel = group.connection.recoveryDetailLabel {
                                        Text(recoveryDetailLabel)
                                            .detailText()
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                Spacer()

                                if group.connection.showsRecoveryActions,
                                   let recoveryActionTitle = group.connection.recoveryActionTitle {
                                    Button {
                                        performRecoveryAction(for: group)
                                    } label: {
                                        Label(recoveryActionTitle, systemImage: group.connection.level == .stale ? "arrow.clockwise" : "link.badge.plus")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button(role: .destructive) {
                                    pendingRemoval = PendingAccountRemoval(
                                        itemId: group.id,
                                        institutionName: group.institutionName,
                                        accountCount: group.accounts.count
                                    )
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }

                            ForEach(group.accounts) { account in
                                HStack {
                                    Image(systemName: AccountPresentation.iconName(for: account))
                                        .foregroundStyle(accountIconTint(for: account))
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        Text(account.name)
                                        Text(account.type.rawValue.capitalized)
                                            .detailText()
                                    }

                                    Spacer()

                                    Text(balanceText(for: account))
                                        .monospacedDigit()
                                        .foregroundStyle(balanceTint(for: account))
                                }
                                .padding(.leading, Spacing.md)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(accountAccessibilityLabel(for: account))
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(groupAccessibilityLabel(for: group))
                    }
                }
            }

            if !appState.accounts.isEmpty {
                HStack {
                    Spacer()
                    Button("Add Account") {
                        handleAddAccount()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .sheet(isPresented: $isShowingAccountSetup) {
            SetupView {
                isShowingAccountSetup = false
            }
                .environment(appState)
        }
        .onChange(of: appState.isSetupComplete) { _, isComplete in
            if isComplete {
                isShowingAccountSetup = false
            }
        }
        .alert(item: $pendingRemoval) { removal in
            Alert(
                title: Text("Remove \(removal.institutionName)?"),
                message: Text("This removes \(removal.accountCount) linked account\(removal.accountCount == 1 ? "" : "s") from VaultPeek and clears matching cached transactions from this Mac. It does not delete the institution from Plaid's dashboard."),
                primaryButton: .destructive(Text("Remove")) {
                    Task { await appState.removeAccount(itemId: removal.itemId) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func handleAddAccount() {
        isShowingAccountSetup = true
    }

    private func performEmptyAction(_ action: SecondaryContentUnavailableAction) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            handleAddAccount()
        case .refreshAccounts:
            Task { await appState.refreshAccounts() }
        case .syncTransactions:
            Task { await appState.syncTransactions() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .clearFilters, .showWiderPeriod:
            break
        }
    }

    private var accountGroups: [AccountItemGroup] {
        Dictionary(grouping: appState.accounts, by: \.itemId)
            .map { itemId, accounts in
                let status = appState.itemStatuses.first(where: { $0.id == itemId })
                let institutionName = accounts.compactMap(\.institutionName).first
                    ?? status?.institutionName
                    ?? "Plaid item"
                return AccountItemGroup(
                    id: itemId,
                    institutionName: institutionName,
                    connection: AccountConnectionPresentation.evaluate(
                        isDemoMode: appState.usesDemoConnectionPresentation,
                        serverConnected: appState.serverConnected,
                        isSyncStale: appState.isSyncStale,
                        statusSyncText: appState.statusSyncText,
                        itemStatus: status?.status ?? .connected,
                        institutionName: institutionName,
                        itemLastSyncRelative: status?.lastSync.map(Formatters.relativeDate)
                    ),
                    accounts: accounts.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.institutionName < $1.institutionName }
    }

    private func performRecoveryAction(for group: AccountItemGroup) {
        switch group.connection.level {
        case .stale:
            Task { await appState.refreshDashboard() }
        case .loginRequired, .error:
            Task { await appState.reconnectItem(itemId: group.id) }
        case .demo, .offline, .healthy, .unknown:
            break
        }
    }

    private func color(for level: AccountConnectionLevel) -> Color {
        switch level {
        case .healthy, .demo:
            SemanticColors.positive
        case .stale, .loginRequired, .unknown:
            SemanticColors.warning
        case .error, .offline:
            SemanticColors.negative
        }
    }

    private func accountIconTint(for account: AccountDTO) -> Color {
        switch account.type {
        case .credit, .loan:
            SemanticColors.creditDebt
        case .investment:
            SemanticColors.sparkline
        case .depository:
            SemanticColors.available
        case .other:
            .secondary
        }
    }

    private func balanceText(for account: AccountDTO) -> String {
        Formatters.currency(AccountPresentation.displayBalance(for: account), format: .compact)
    }

    private func balanceTint(for account: AccountDTO) -> Color {
        AccountPresentation.isDebt(account) ? SemanticColors.creditDebt : .secondary
    }

    private func groupAccessibilityLabel(for group: AccountItemGroup) -> String {
        var parts = [
            group.institutionName,
            group.connection.signalLabel,
            "\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")",
        ]
        if let itemSyncLabel = group.connection.itemSyncLabel {
            parts.append(itemSyncLabel)
        }
        if let recoveryDetailLabel = group.connection.recoveryDetailLabel {
            parts.append(recoveryDetailLabel)
        }
        return parts.joined(separator: ", ")
    }

    private func accountAccessibilityLabel(for account: AccountDTO) -> String {
        "\(account.name), \(account.type.rawValue.capitalized), \(balanceText(for: account))"
    }

}

private struct AccountItemGroup: Identifiable {
    let id: String
    let institutionName: String
    let connection: AccountConnectionPresentation
    let accounts: [AccountDTO]
}

private struct PendingAccountRemoval: Identifiable {
    let itemId: String
    let institutionName: String
    let accountCount: Int

    var id: String { itemId }
}

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    private var permissionPresentation: NotificationPermissionPresentation {
        appState.notificationPermissionPresentation
    }

    private var areNotificationControlsDisabled: Bool {
        !appState.notificationsEnabled || permissionPresentation.shouldDisableNotifications
    }

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SettingsCard {
                    permissionStatusRow

                    Toggle("Enable notifications", isOn: $state.notificationsEnabled)
                        .onChange(of: appState.notificationsEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await appState.requestNotificationPermission()
                                    await refreshPermissionStatus()
                                    guard granted else {
                                        return
                                    }
                                }
                            } else {
                                Task { await refreshPermissionStatus() }
                            }
                        }
                        .disabled(permissionPresentation.isNotificationToggleDisabled)
                }

                SettingsCard(title: "Transaction Alerts") {
                    Toggle("Large transactions", isOn: $state.notifyLargeTransaction)
                        .disabled(areNotificationControlsDisabled)

                    settingsRow("Threshold") {
                        HStack(spacing: Spacing.sm) {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField(
                                "",
                                value: $state.largeTransactionThreshold,
                                format: .number.precision(.fractionLength(0))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .disabled(areNotificationControlsDisabled || !appState.notifyLargeTransaction)

                    if !areNotificationControlsDisabled,
                       appState.notifyLargeTransaction,
                       appState.largeTransactionThreshold <= 0 {
                        InlineSettingsNotice(
                            text: "A $0 threshold sends an alert for every outgoing transaction.",
                            icon: "bell.badge",
                            tint: SemanticColors.warning
                        )
                    }

                    Toggle("Low balance warning", isOn: $state.notifyLowBalance)
                        .disabled(areNotificationControlsDisabled)

                    settingsRow("Threshold") {
                        HStack(spacing: Spacing.sm) {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField(
                                "",
                                value: $state.lowBalanceThreshold,
                                format: .number.precision(.fractionLength(0))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .disabled(areNotificationControlsDisabled || !appState.notifyLowBalance)
                }

                SettingsCard(title: "Credit Alerts") {
                    Toggle("High utilization", isOn: $state.notifyHighUtilization)
                        .disabled(areNotificationControlsDisabled)
                    Text("Uses credit warning threshold (\(Formatters.percent(appState.creditUtilizationThreshold, decimals: 0)))")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.lg)
        }
        .task {
            await refreshPermissionStatus()
        }
    }

    private var permissionStatusRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: permissionIcon)
                .foregroundStyle(permissionTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text("macOS permission")
                    Spacer()
                    Text(permissionLabel)
                        .foregroundStyle(permissionTint)
                        .font(.callout.weight(.semibold))
                }

                Text(permissionDetail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                if let action = permissionPresentation.recoveryAction {
                    permissionRecoveryAction(action)
                        .padding(.top, Spacing.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("macOS notification permission: \(permissionLabel)")
        .accessibilityHint(permissionDetail)
    }

    private func refreshPermissionStatus() async {
        _ = await appState.notificationPermissionStatus()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private var permissionLabel: String {
        permissionPresentation.label
    }

    private var permissionDetail: String {
        permissionPresentation.detail
    }

    private var permissionIcon: String {
        permissionPresentation.iconName
    }

    private var permissionTint: Color {
        switch permissionPresentation.tone {
        case .positive:
            SemanticColors.positive
        case .warning:
            SemanticColors.warning
        case .secondary:
            .secondary
        }
    }

    @ViewBuilder
    private func permissionRecoveryAction(_ action: NotificationPermissionRecoveryAction) -> some View {
        if permissionPresentation.isRecoveryActionInteractive {
            Button {
                performPermissionRecoveryAction(action)
            } label: {
                Label(
                    permissionPresentation.recoveryActionTitle ?? "Recover Notifications",
                    systemImage: permissionPresentation.recoveryActionIconName ?? "bell.badge"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(permissionActionAccessibilityHint(for: action))
        } else {
            Label(
                permissionPresentation.recoveryActionTitle ?? "Recover Notifications",
                systemImage: permissionPresentation.recoveryActionIconName ?? "bell.badge"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(permissionTint)
            .accessibilityLabel(permissionPresentation.recoveryActionTitle ?? "Recover Notifications")
            .accessibilityHint(permissionPresentation.detail)
        }
    }

    private func performPermissionRecoveryAction(_ action: NotificationPermissionRecoveryAction) {
        switch action {
        case .requestPermission:
            Task {
                let granted = await appState.requestNotificationPermission()
                appState.notificationsEnabled = granted
                await refreshPermissionStatus()
            }
        case .openSystemSettings:
            openNotificationSettings()
        case .checkAgain:
            Task { await refreshPermissionStatus() }
        case .runBundledApp:
            break
        }
    }

    private func permissionActionAccessibilityHint(for action: NotificationPermissionRecoveryAction) -> Text {
        switch action {
        case .requestPermission:
            Text("Requests macOS notification permission for VaultPeek.")
        case .openSystemSettings:
            Text("Opens macOS Notification settings for VaultPeek.")
        case .checkAgain:
            Text("Checks the current macOS notification permission again.")
        case .runBundledApp:
            Text(permissionPresentation.detail)
        }
    }
}

private struct InlineSettingsNotice: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(text)
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutView: View {
    let updater: SPUUpdater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(SemanticColors.brand)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(PlaidBarConstants.appName)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Version \(PlaidBarConstants.appVersion)")
                            .foregroundStyle(.secondary)

                        Text("Your bank accounts, credit cards, and spending -- always one click away.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                SettingsCard(title: "Support") {
                    supportLink(
                        "Troubleshooting",
                        systemImage: "wrench.and.screwdriver",
                        url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/troubleshooting.md",
                        detail: "Setup, server, Plaid Link, notifications, and screenshot fixes."
                    )

                    supportLink(
                        "Privacy",
                        systemImage: "lock.shield",
                        url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/privacy.md",
                        detail: "What stays local, what calls Plaid, and what not to share."
                    )

                    supportLink(
                        "Security",
                        systemImage: "exclamationmark.shield",
                        url: "https://github.com/ftchvs/PlaidBar/blob/main/SECURITY.md",
                        detail: "Private reporting path for token, credential, or data exposure."
                    )
                }

                SettingsCard(title: "Project") {
                    supportLink(
                        "GitHub Repository",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        url: "https://github.com/ftchvs/PlaidBar",
                        detail: "Source, issues, and releases (private repository)."
                    )

                    supportLink(
                        "1.0 Roadmap",
                        systemImage: "map",
                        url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/v1.0-roadmap.md",
                        detail: "Product, design, system, security, and release plan."
                    )

                    supportLink(
                        "Release Notes",
                        systemImage: "doc.text",
                        url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/release-notes.md",
                        detail: "Curated release summary for current and upcoming versions."
                    )
                }

                HStack {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Spacer()

                    Text("© 2026 Felipe Tavares Chaves · Proprietary")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Spacing.lg)
        }
    }

    @ViewBuilder
    private func supportLink(
        _ title: String,
        systemImage: String,
        url: String,
        detail: String
    ) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: systemImage)
                        .foregroundStyle(SemanticColors.brand)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .foregroundStyle(.primary)
                        Text(detail)
                            .detailText()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
