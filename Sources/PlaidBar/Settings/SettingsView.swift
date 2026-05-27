import SwiftUI
import PlaidBarCore
import Sparkle
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AccountSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Accounts", systemImage: "building.columns")
                }

            NotificationSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AboutView(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 620, height: 560)
    }
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

                SettingsCard(title: "Local Data") {
                    settingsRow("Storage path", alignment: .top) {
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text(appState.localStoragePathText)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)

                            Text(appState.localStorageResolvedPathText)
                                .detailText()
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        Button {
                            revealStorageDirectory()
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }

                        Button {
                            copyStoragePath()
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }

                        Spacer()

                        Button(role: .destructive) {
                            isShowingResetConfirmation = true
                        } label: {
                            Label("Reset", systemImage: "trash")
                        }
                    }

                    Text("Stores the local server database, Plaid item tokens, sync cursors, and app/server auth token. App preferences stay in macOS preferences.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.lg)
        }
        .alert("Reset Local PlaidBar Data?", isPresented: $isShowingResetConfirmation) {
            Button("Reset Local Data", role: .destructive) {
                resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes files under \(appState.localStoragePathText), including the SQLite database, stored Plaid access tokens, sync cursors, and the app/server auth token. It also clears currently loaded accounts, transactions, and balance history from this app. It does not revoke bank permissions, remove Plaid dashboard Items, delete Plaid credentials from your shell environment, or change app preferences. Stop and restart PlaidBarServer after resetting.")
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
        let url = appState.localStorageDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyStoragePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.localStorageResolvedPathText, forType: .string)
    }

    private func resetLocalData() {
        do {
            let result = try appState.resetLocalData()
            if result.removedEntryCount == 0 {
                resetResultMessage = "No existing files were found. \(appState.localStoragePathText) is ready for a fresh local server start."
            } else {
                resetResultMessage = "Removed \(result.removedEntryCount) item\(result.removedEntryCount == 1 ? "" : "s") from \(appState.localStoragePathText). Restart PlaidBarServer before reconnecting accounts."
            }
        } catch {
            resetErrorMessage = error.localizedDescription
        }
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
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

@ViewBuilder
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

    var body: some View {
        VStack(alignment: .leading) {
            if appState.accounts.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptyIcon)
                } description: {
                    Text(emptyMessage)
                } actions: {
                    Button {
                        Task { await appState.addAccount() }
                    } label: {
                        Label("Add Account", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                List {
                    ForEach(accountGroups) { group in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(group.institutionName)
                                        .font(.headline)

                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: icon(for: group.status))
                                            .foregroundStyle(color(for: group.status))
                                        Text(label(for: group.status))
                                            .foregroundStyle(color(for: group.status))
                                        Text("\u{00B7}")
                                            .foregroundStyle(.tertiary)
                                        Text("\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")")
                                            .foregroundStyle(.secondary)
                                    }
                                    .detailText()
                                }

                                Spacer()

                                if group.status != .connected {
                                    Button {
                                        Task { await appState.reconnectItem(itemId: group.id) }
                                    } label: {
                                        Label("Reconnect", systemImage: "link.badge.plus")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button(role: .destructive) {
                                    Task { await appState.removeAccount(itemId: group.id) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }

                            ForEach(group.accounts) { account in
                                HStack {
                                    Image(systemName: account.type == .credit ? "creditcard" : "building.columns")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        Text(account.name)
                                        Text(account.type.rawValue.capitalized)
                                            .detailText()
                                    }

                                    Spacer()

                                    Text(Formatters.currency(account.balances.effectiveBalance, format: .compact))
                                        .monospacedDigit()
                                        .foregroundStyle(account.type == .credit ? SemanticColors.creditDebt : .secondary)
                                }
                                .padding(.leading, Spacing.md)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Add Account") {
                    Task { await appState.addAccount() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
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
                    status: status?.status ?? .connected,
                    accounts: accounts.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.institutionName < $1.institutionName }
    }

    private var emptyTitle: String {
        if !appState.isDemoMode && !appState.serverConnected { return "Server Offline" }
        if appState.statusItemCount == 0 { return "No Bank Linked" }
        return "No Account Data"
    }

    private var emptyIcon: String {
        if !appState.isDemoMode && !appState.serverConnected { return "server.rack" }
        return "building.columns"
    }

    private var emptyMessage: String {
        if !appState.isDemoMode && !appState.serverConnected {
            return "Start PlaidBarServer before managing linked accounts."
        }
        if appState.statusItemCount == 0 {
            return "Connect a Plaid institution to manage linked accounts here."
        }
        return "The server has a linked item, but account details are not loaded yet."
    }

    private func icon(for status: ItemConnectionStatus) -> String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .loginRequired: "person.crop.circle.badge.exclamationmark"
        case .error: "xmark.octagon.fill"
        }
    }

    private func color(for status: ItemConnectionStatus) -> Color {
        switch status {
        case .connected: SemanticColors.positive
        case .loginRequired: SemanticColors.warning
        case .error: SemanticColors.negative
        }
    }

    private func label(for status: ItemConnectionStatus) -> String {
        switch status {
        case .connected: "Connected"
        case .loginRequired: "Login required"
        case .error: "Error"
        }
    }
}

private struct AccountItemGroup: Identifiable {
    let id: String
    let institutionName: String
    let status: ItemConnectionStatus
    let accounts: [AccountDTO]
}

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var permissionDenied = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Toggle("Enable notifications", isOn: $state.notificationsEnabled)
                .onChange(of: appState.notificationsEnabled) { _, enabled in
                    if enabled {
                        Task {
                            let granted = await appState.requestNotificationPermission()
                            if !granted {
                                permissionDenied = true
                                appState.notificationsEnabled = false
                            }
                        }
                    }
                }

            if permissionDenied {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(SemanticColors.warning)
                    Text("Notifications denied. Enable in System Settings > Notifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transaction Alerts") {
                Toggle("Large transactions", isOn: $state.notifyLargeTransaction)
                    .disabled(!appState.notificationsEnabled)

                HStack {
                    Text("Threshold")
                    Spacer()
                    Text("$")
                    TextField(
                        "",
                        value: $state.largeTransactionThreshold,
                        format: .number.precision(.fractionLength(0))
                    )
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                }
                .disabled(!appState.notificationsEnabled || !appState.notifyLargeTransaction)

                Toggle("Low balance warning", isOn: $state.notifyLowBalance)
                    .disabled(!appState.notificationsEnabled)

                HStack {
                    Text("Threshold")
                    Spacer()
                    Text("$")
                    TextField(
                        "",
                        value: $state.lowBalanceThreshold,
                        format: .number.precision(.fractionLength(0))
                    )
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                }
                .disabled(!appState.notificationsEnabled || !appState.notifyLowBalance)
            }

            Section("Credit Alerts") {
                Toggle("High utilization", isOn: $state.notifyHighUtilization)
                    .disabled(!appState.notificationsEnabled)
                Text("Uses credit warning threshold (\(Formatters.percent(appState.creditUtilizationThreshold, decimals: 0)))")
                    .detailText()
            }
        }
        .padding()
    }
}

struct AboutView: View {
    let updater: SPUUpdater

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(SemanticColors.brand)

            Text("PlaidBar")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(PlaidBarConstants.appVersion)")
                .foregroundStyle(.secondary)

            Text("Your bank accounts, credit cards, and spending -- always one click away.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Divider()

            HStack(spacing: Spacing.lg) {
                Button("Check for Updates\u{2026}") {
                    updater.checkForUpdates()
                }

                if let repoURL = URL(string: "https://github.com/ftchvs/PlaidBar") {
                    Link("View on GitHub", destination: repoURL)
                        .font(.callout)
                }
            }

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
