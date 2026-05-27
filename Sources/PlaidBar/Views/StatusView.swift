import SwiftUI
import PlaidBarCore

struct StatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            statusHeader

            diagnosticsGrid

            if !appState.itemStatuses.isEmpty {
                itemSection
            }

            recoveryActions
        }
        .padding(Spacing.lg)
    }

    private var statusHeader: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: statusIcon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(appState.diagnosticsSummary)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Mode: \(appState.statusModeText)")
                    .detailText()
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var diagnosticsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
            ],
            spacing: Spacing.sm
        ) {
            DiagnosticTile(
                title: "Server",
                value: appState.statusServerText,
                icon: "server.rack",
                color: appState.serverConnected ? SemanticColors.positive : SemanticColors.negative
            )
            DiagnosticTile(
                title: "Sync",
                value: appState.statusSyncText,
                icon: "arrow.triangle.2.circlepath",
                color: appState.isSyncStale ? SemanticColors.warning : SemanticColors.positive
            )
            DiagnosticTile(
                title: "Accounts",
                value: "\(appState.accountCount)",
                icon: "creditcard",
                color: SemanticColors.brand
            )
            DiagnosticTile(
                title: "Transactions",
                value: "\(appState.transactionCount)",
                icon: "list.bullet.rectangle",
                color: SemanticColors.brandSecondary
            )
            DiagnosticTile(
                title: "Plaid items",
                value: "\(appState.connectedItemCount)/\(appState.statusItemCount)",
                icon: "link",
                color: itemHealthColor
            )
            DiagnosticTile(
                title: "Credentials",
                value: appState.serverCredentialsText,
                icon: "key",
                color: credentialsColor
            )
            DiagnosticTile(
                title: "Sync ready",
                value: appState.serverSyncReadinessText,
                icon: "checklist.checked",
                color: syncReadinessColor
            )
            DiagnosticTile(
                title: "Version",
                value: appState.serverVersion ?? PlaidBarConstants.appVersion,
                icon: "number",
                color: .secondary
            )
            DiagnosticTile(
                title: "Endpoint",
                value: appState.localServerURLText.replacingOccurrences(of: "http://", with: ""),
                icon: "network",
                color: .secondary
            )
            DiagnosticTile(
                title: "Storage",
                value: appState.serverStorageDisplayText,
                icon: "internaldrive",
                color: .secondary
            )
            DiagnosticTile(
                title: "Refresh",
                value: appState.refreshCadenceText,
                icon: "timer",
                color: .secondary
            )
        }
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PLAID ITEMS")
                .sectionTitle()
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.xs) {
                ForEach(appState.itemStatuses) { item in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: icon(for: item.status))
                            .foregroundStyle(color(for: item.status))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(item.institutionName ?? "Plaid item")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)

                            Text(statusDetail(for: item))
                                .detailText()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Text(label(for: item.status))
                                .microText()
                                .foregroundStyle(color(for: item.status))

                            if item.status != .connected {
                                Button {
                                    Task { await appState.reconnectItem(itemId: item.id) }
                                } label: {
                                    Label("Reconnect", systemImage: "link.badge.plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
    }

    private var recoveryActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "lock.doc")
                Text("Local data path: \(appState.serverStorageDisplayText)")
            }
            .detailText()

            Text("RECOVERY")
                .sectionTitle()
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm) {
                Button {
                    Task {
                        await appState.checkServerConnection()
                        if appState.serverConnected {
                            await appState.refreshAccounts()
                            await appState.syncTransactions()
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await appState.addAccount() }
                } label: {
                    Label("Connect", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusIcon: String {
        if appState.isDemoMode { return "play.circle.fill" }
        if !appState.serverConnected { return "xmark.octagon.fill" }
        if appState.erroredItemCount > 0 || appState.needsLoginItemCount > 0 { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if appState.isDemoMode { return SemanticColors.brandSecondary }
        if !appState.serverConnected { return SemanticColors.negative }
        if appState.erroredItemCount > 0 || appState.needsLoginItemCount > 0 { return SemanticColors.warning }
        return SemanticColors.positive
    }

    private var itemHealthColor: Color {
        if appState.statusItemCount == 0 { return .secondary }
        if appState.connectedItemCount < appState.statusItemCount { return SemanticColors.warning }
        if appState.erroredItemCount > 0 || appState.needsLoginItemCount > 0 { return SemanticColors.warning }
        return SemanticColors.positive
    }

    private var credentialsColor: Color {
        guard appState.serverConnected else { return .secondary }
        return appState.serverCredentialsConfigured == true ? SemanticColors.positive : SemanticColors.negative
    }

    private var syncReadinessColor: Color {
        guard appState.serverConnected else { return .secondary }
        return appState.serverSyncReady == true ? SemanticColors.positive : .secondary
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
        case .loginRequired: "Login"
        case .error: "Error"
        }
    }

    private func statusDetail(for item: ItemStatus) -> String {
        switch item.status {
        case .connected:
            item.lastSync.map { "Updated \(Formatters.relativeDate($0))" } ?? "No sync recorded"
        case .loginRequired:
            "Plaid requires a fresh bank login. Reconnect this item."
        case .error:
            "The last Plaid request failed. Reconnect or try refreshing again."
        }
    }
}

private struct DiagnosticTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .detailText()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(Spacing.sm)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
