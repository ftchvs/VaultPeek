import SwiftUI
import PlaidBarCore
import Sparkle

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
        .frame(width: 480, height: 380)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Toggle("Show balance in menu bar", isOn: $state.showBalanceInMenuBar)

            Picker("Balance format", selection: $state.balanceFormat) {
                Text("$12,450.32").tag(CurrencyFormat.full)
                Text("$12.4K").tag(CurrencyFormat.abbreviated)
                Text("$12,450").tag(CurrencyFormat.compact)
            }
            .disabled(!appState.showBalanceInMenuBar)

            Picker("Refresh interval", selection: $state.refreshInterval) {
                Text("5 minutes").tag(TimeInterval(5 * 60))
                Text("15 minutes").tag(TimeInterval(15 * 60))
                Text("30 minutes").tag(TimeInterval(30 * 60))
                Text("1 hour").tag(TimeInterval(60 * 60))
            }

            HStack {
                Text("Credit warning")
                Spacer()
                TextField(
                    "",
                    value: $state.creditUtilizationThreshold,
                    format: .number.precision(.fractionLength(0))
                )
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                Text("%")
            }
            .help("Credit cards above this utilization threshold show warning colors")

            Toggle("Launch at login", isOn: $state.launchAtLogin)
        }
        .padding()
    }
}

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading) {
            if appState.accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "building.columns")
            } else {
                List {
                    ForEach(appState.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                Text(account.type.rawValue.capitalized)
                                    .detailText()
                            }
                            Spacer()
                            Button("Remove") {
                                Task { await appState.removeAccount(itemId: account.itemId) }
                            }
                            .foregroundStyle(SemanticColors.negative)
                        }
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
                            let granted = await NotificationService.shared.requestPermission()
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
