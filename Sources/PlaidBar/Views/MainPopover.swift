import SwiftUI
import PlaidBarCore

struct MainPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            if !appState.isSetupComplete {
                SetupView()
            } else {
                // Header
                HStack {
                    Text("PlaidBar")
                        .font(.headline)
                    Spacer()
                    Text(Formatters.currency(appState.netBalance, format: .full))
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Tab picker
                Picker("View", selection: $state.selectedTab) {
                    ForEach(PopoverTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                // Content
                ScrollView {
                    switch appState.selectedTab {
                    case .accounts:
                        AccountsView()
                    case .transactions:
                        TransactionsView()
                    case .spending:
                        SpendingView()
                    case .credit:
                        CreditView()
                    }
                }
                .frame(maxHeight: 400)

                Divider()

                // Footer
                HStack {
                    Button("Add Account") {
                        Task { await appState.addAccount() }
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if appState.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button {
                        Task {
                            await appState.refreshBalances()
                            await appState.syncTransactions()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")

                    SettingsLink {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Error banner
            if let error = appState.error {
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
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.red.opacity(0.1))
            }
        }
        .frame(width: 360)
        .task {
            await appState.loadInitialData()
        }
    }
}
