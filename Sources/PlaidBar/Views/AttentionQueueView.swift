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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: row.severity.statusSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                // One-shot, non-repeating feedback when a row enters warning or
                // blocked severity. The bounce fires only when `motionTrigger`
                // changes (a transition into a non-healthy state); it never loops.
                // `motionTrigger` is held stable — and thus silent — under Reduce
                // Motion or while healthy. The discrete SF Symbol effect plays in
                // place inside the fixed 24x24 frame, so the row never resizes.
                // SeverityStatusBadge stays the primary, color-independent meaning
                // carrier; this motion is decorative reinforcement only.
                .symbolEffect(.bounce, options: .nonRepeating, value: motionTrigger)
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

    /// Drives the leading status glyph's one-shot bounce. Stable (and therefore
    /// non-animating) under Reduce Motion or when the row is healthy; otherwise
    /// distinct per non-healthy severity so a transition into `.warning` or
    /// `.blocked` changes the value exactly once and fires a single bounce.
    private var motionTrigger: Int {
        guard !reduceMotion else { return 0 }
        switch row.severity {
        case .healthy: return 0
        case .warning: return 1
        case .blocked: return 2
        }
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

// Synthetic rows only — no Plaid data. Exercises the warning and blocked status
// glyphs that drive the one-shot bounce (AND-360). To verify the transition
// animation manually, run `swift run PlaidBar --demo` and toggle a row into a
// non-healthy state; with Reduce Motion on, the glyph must stay still while the
// badge text/icon still distinguishes severity without color.
#Preview("Attention rows") {
    VStack(spacing: Spacing.xs) {
        AttentionQueueRowView(
            row: AttentionQueueRow(
                id: "preview-warning",
                severity: .warning,
                title: "Sync is stale",
                detail: "Last update was a while ago. Refresh to pull the latest balances.",
                action: .refresh,
                accessibilityHint: "Refreshes the dashboard."
            ),
            isDisabled: false
        ) {}

        AttentionQueueRowView(
            row: AttentionQueueRow(
                id: "preview-blocked",
                severity: .blocked,
                title: "Server offline",
                detail: "Start the VaultPeek companion server, then check the connection.",
                action: .checkServer,
                accessibilityHint: "Checks the local VaultPeek companion server connection."
            ),
            isDisabled: false
        ) {}
    }
    .padding()
    .frame(width: 360)
}
