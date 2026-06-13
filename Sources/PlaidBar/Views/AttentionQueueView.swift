import AppKit
import PlaidBarCore
import SwiftUI

struct AttentionQueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    let title: String
    var showsHealthyRow = true
    var onAddAccount: (() -> Void)?

    private var rows: [AttentionQueueRow] {
        let rows = appState.attentionQueue.rows
        guard showsHealthyRow else {
            return rows.filter { $0.severity != .healthy }
        }
        return rows
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .sectionTitle()
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(rows.count)/\(AttentionQueue.maximumRowCount)")
                        .microText()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                VStack(spacing: Spacing.xs) {
                    ForEach(rows) { row in
                        AttentionQueueRowView(row: row, isDisabled: appState.isLoading) {
                            perform(row)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title), \(rows.count) item\(rows.count == 1 ? "" : "s")")
        }
    }

    private func perform(_ row: AttentionQueueRow) {
        guard let action = row.action else { return }
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            if let onAddAccount {
                onAddAccount()
            } else {
                Task { await appState.addAccount() }
            }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            guard let itemId = row.targetItemId ?? ItemRecoveryTarget.itemId(from: appState.itemStatuses) else {
                Task { await appState.refreshDashboard() }
                return
            }
            Task { await appState.reconnectItem(itemId: itemId) }
        case .openSettings:
            openSettings()
        case .requestNotificationPermission:
            Task { _ = await appState.requestNotificationPermission() }
        case .openNotificationSettings:
            openNotificationSettings()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            openSettings()
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct AttentionQueueRowView: View {
    let row: AttentionQueueRow
    let isDisabled: Bool
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: row.severity.statusSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    SeverityStatusBadge(severity: row.severity, tint: tint)

                    Text(row.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(row.detail)
                    .microText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(row.accessibilityHint ?? "")

            Spacer(minLength: Spacing.xs)

            if let actionTitle = row.actionTitle {
                Button {
                    perform()
                } label: {
                    Label(actionTitle, systemImage: row.actionIconName ?? "arrow.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(actionTitle)
                .accessibilityLabel(actionTitle)
                .accessibilityHint(row.accessibilityHint ?? row.detail)
                .disabled(isDisabled)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        .nativePanelSurface(
            fill: AnyShapeStyle(SurfaceTokens.panelFill(emphasisTint: emphasizedTint)),
            stroke: panelStroke
        )
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch row.severity {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private var emphasizedTint: Color? {
        row.severity == .healthy ? nil : tint
    }

    private var panelStroke: Color {
        row.severity == .healthy ? Color.primary.opacity(0.07) : tint.opacity(0.18)
    }
}

private struct SeverityStatusBadge: View {
    let severity: AttentionQueueSeverity
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: severity.statusSymbolName)
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)

            Text(severity.statusLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
