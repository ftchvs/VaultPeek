import SwiftUI
import Charts
import PlaidBarCore

struct MainPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var settingsCloseObserver: NSObjectProtocol?

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            if !appState.isSetupComplete {
                SetupView()
            } else {
                // Header — balance as hero with sparkline
                VStack(spacing: Spacing.xxs) {
                    Text(Formatters.currency(appState.netBalance, format: .full))
                        .heroBalance()
                        .contentTransition(.numericText())
                        .animation(.default, value: appState.netBalance)

                    // Balance sparkline
                    if appState.balanceHistory.count >= 2 {
                        BalanceSparkline(history: appState.balanceHistory)
                            .frame(height: 24)
                            .padding(.horizontal, Spacing.xl * 2)
                            .padding(.top, Spacing.xs)
                    }

                    HStack(spacing: Spacing.rowVertical) {
                        Text("PlaidBar")
                            .detailText()
                        if let syncText = appState.lastSyncRelative {
                            Text("\u{00B7}")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Text("Synced \(syncText)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.md)

                // Tab picker
                Picker("View", selection: $state.selectedTab) {
                    ForEach(PopoverTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)

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
                HStack(spacing: Spacing.md) {
                    Button {
                        Task { await appState.addAccount() }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Account (Cmd+N)")
                    .keyboardShortcut("n", modifiers: .command)

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
                    .help("Refresh (Cmd+R)")
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        openSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.setActivationPolicy(.regular)
                            NSApp.activate(ignoringOtherApps: true)
                            if let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first(where: {
                                $0.canBecomeKey && $0.isVisible && $0.level == .normal
                            }) {
                                settingsWindow.orderFrontRegardless()
                                // Remove previous observer to prevent stacking
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
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
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
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.rowVertical)
                .background(.red.opacity(0.1))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.25), value: appState.error != nil)
        // Keyboard shortcuts for tab switching
        .background {
            Group {
                Button("") { appState.selectedTab = .accounts }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { appState.selectedTab = .transactions }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { appState.selectedTab = .spending }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { appState.selectedTab = .credit }
                    .keyboardShortcut("4", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .task {
            await appState.loadInitialData()
        }
    }
}

// MARK: - Balance Sparkline

private struct BalanceSparkline: View {
    let history: [BalanceSnapshot]

    var body: some View {
        Chart(history, id: \.date) { snapshot in
            LineMark(
                x: .value("Date", snapshot.date),
                y: .value("Balance", snapshot.balance)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(SemanticColors.sparkline.opacity(0.6))

            AreaMark(
                x: .value("Date", snapshot.date),
                y: .value("Balance", snapshot.balance)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(SemanticColors.sparkline.opacity(0.08))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
