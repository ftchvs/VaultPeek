import AppKit
import PlaidBarCore
import SwiftUI

struct AttentionQueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    /// Deep-links a glance chip into the window-first window (ADR-001 / AND-597).
    /// No-op by default — installed with a real handler only when the window-first
    /// flag is ON (`PlaidBarApp`), so flag-OFF chip behavior is unchanged.
    @Environment(\.openRoute) private var openRoute

    let title: String
    var showsHealthyRow = true
    var onAddAccount: (() -> Void)?

    /// Window-first hybrid opt-in, resolved once per render. Gates whether an
    /// attention chip routes into the window vs. runs its existing in-place
    /// action. OFF (the shipping default) ⇒ today's behavior exactly.
    private var isWindowFirstEnabled: Bool { WindowFirstFeatureFlag.resolved() }

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
        // Window-first: a glance chip is a launcher (IA §3.6 / §6). When the flag
        // is ON and the chip maps to an in-window destination, open the window
        // there instead of running the in-place action — e.g. "Card over 75%"
        // opens Accounts at that card, "Recent spending changed" opens
        // Transactions. The pure `Route.from(attentionRow:)` decides the target.
        // When the flag is OFF this branch is skipped entirely, so the chip runs
        // exactly today's action (`openRoute` would also be a no-op, but the flag
        // guard keeps flag-OFF behavior byte-identical without relying on that).
        if isWindowFirstEnabled, let route = Route.from(attentionRow: row) {
            openRoute(route)
            return
        }

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
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: row.severity.statusSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: Sizing.glyphMedium, height: Sizing.glyphMedium)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: SurfaceTokens.panelCornerRadius))
                // One-shot, non-repeating feedback when a warning or blocked row
                // appears. The attention queue keys rows by id, so a real
                // healthy→warning/blocked transition *inserts* a new row view
                // rather than mutating one; `isActive` flips false→true on appear
                // and fires the bounce exactly once for that insertion. It never
                // loops. The effect is gated on `bouncesOnAppear`, which is false
                // under Reduce Motion or while healthy — so it stays silent there,
                // and toggling Reduce Motion on (true→false) never bounces. The
                // discrete effect plays in place inside the fixed 24x24 frame, so
                // the row never resizes. SeverityStatusBadge stays the primary,
                // color-independent meaning carrier; this motion is decorative
                // reinforcement only.
                .symbolMotion(.bounceOnce, isActive: hasAppeared && bouncesOnAppear, reduceMotion: reduceMotion)
                .onAppear { hasAppeared = true }
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

    /// Whether this row's severity warrants the one-shot bounce when it appears
    /// (warning/blocked, not healthy). The Reduce Motion gate is applied centrally
    /// by `symbolMotion(.bounceOnce:reduceMotion:)` (AND-358), so this expresses
    /// severity intent only.
    private var bouncesOnAppear: Bool {
        row.severity != .healthy
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
//
// Gated behind `!SWIFT_PACKAGE`: the `#Preview` macro is supplied by Xcode's
// `PreviewsMacros` plugin, which is absent in plain SwiftPM (`swift build`/
// `swift test`). Without this guard the whole package fails to compile, taking
// the test suite down with it (#314).
#if !SWIFT_PACKAGE
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
#endif
