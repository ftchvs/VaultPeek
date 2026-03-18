import SwiftUI
import PlaidBarCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
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
                Text("Credit warning threshold")
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

            Toggle("Launch at login", isOn: .constant(false))  // TODO: implement with SMAppService
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                Task { await appState.removeAccount(itemId: account.itemId) }
                            }
                            .foregroundStyle(.red)
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

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

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

            Link("View on GitHub", destination: URL(string: "https://github.com/ftchvs/PlaidBar")!)
                .font(.callout)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
