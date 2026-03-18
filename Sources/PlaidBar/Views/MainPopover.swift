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
                // Header — balance as hero
                VStack(spacing: 2) {
                    Text(Formatters.currency(appState.netBalance, format: .full))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: appState.netBalance)

                    HStack(spacing: 6) {
                        Text("PlaidBar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let syncText = appState.lastSyncRelative {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Text("Synced \(syncText)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Tab picker
                Picker("View", selection: $state.selectedTab) {
                    ForEach(PopoverTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                // Content with tab animation
                ScrollView {
                    Group {
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
                    .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300, maxHeight: 480)

                Divider()

                // Footer
                HStack(spacing: 12) {
                    Button {
                        Task { await appState.addAccount() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Account")

                    Spacer()

                    Button {
                        Task {
                            await appState.refreshBalances()
                            await appState.syncTransactions()
                        }
                    } label: {
                        RefreshIcon(isLoading: appState.isLoading)
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.25), value: appState.error != nil)
        .task {
            await appState.loadInitialData()
        }
    }
}
