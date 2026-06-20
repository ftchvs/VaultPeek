import AppKit
import PlaidBarCore
import SwiftUI

/// **Alerts** destination (3-column — IA §3.1/§5.8, `[⌘7]`) — Epic 7 / AND-585
/// (ADR-001 window-first workspace).
///
/// Content column = the alert **list** (severity-sorted, with inline acknowledge +
/// "Acknowledge all"); detail column = the selected alert's **detail** with its
/// recovery action and acknowledge toggle. The detail column is **content-gated,
/// not existence-gated** (IA §3.1): with nothing selected it shows the "Select an
/// alert" prompt rather than collapsing.
///
/// **Surfaces existing engines, adds no alert source:**
/// - The alerts are the live ``AttentionQueue`` rows (``AppState/attentionQueue``)
///   — the same "do I need to act?" rollup the menu-bar glance and Dashboard key
///   off (IA §1.3), so the feed stays truthful and consistent across surfaces.
/// - ``AlertsInbox`` (new pure Core, unit-tested) reduces those rows + the
///   acknowledged-id set into a sorted feed and the unacknowledged count. The rows
///   are stateless (recomputed each render), so acknowledgement is layered on top
///   as session-scoped per-window state on the per-window ``NavigationModel``
///   (`alertSelection` + `acknowledgedAlertIDs`, AND-621/R-10) — the rows and the
///   queue are never mutated.
/// - Each alert's recovery action runs through the same dispatch the existing
///   ``AttentionQueueView`` uses, so an action means the same thing on every
///   surface.
///
/// The sidebar's unacked badge (`AppState.sidebarUnacknowledgedAlertCount`) already
/// exists; it counts live non-healthy rows. Acknowledging mutes an alert from
/// *this destination's* unacknowledged count (session state) without resolving the
/// underlying condition — the badge keeps reflecting the live rows.
///
/// Severity is always carried by text + SF Symbol, never color alone
/// (ACCESSIBILITY.md). **Flag-OFF inert:** reached only when the window-first
/// `Window` opens (`WindowFirstFeatureFlag` ON); with the flag off this file is
/// never instantiated and the popover is byte-identical.
struct AlertsDestinationView: View {
    @Environment(AppState.self) private var appState

    private var navigationModel: NavigationModel { appState.navigationModel }

    private var rows: [AttentionQueueRow] {
        appState.attentionQueue.rows
    }

    private var inbox: AlertsInbox {
        AlertsInbox.make(rows: rows, acknowledgedIDs: navigationModel.acknowledgedAlertIDs)
    }

    private var summary: AlertsSummary {
        AlertsSummary.make(from: inbox)
    }

    var body: some View {
        let inbox = inbox

        VStack(alignment: .leading, spacing: Spacing.md) {
            header(inbox)

            if inbox.isEmpty {
                emptyState
            } else {
                alertsList(inbox)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(RouteDestination.alerts.title)
        // Keep the acknowledged set + selection bounded to the live rows so a
        // resolved condition never lingers acknowledged or selected.
        .onChange(of: rows.map(\.id)) { _, _ in
            navigationModel.pruneAlerts(toRowsIn: rows)
        }
        .onAppear { navigationModel.pruneAlerts(toRowsIn: rows) }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private func header(_ inbox: AlertsInbox) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("Alerts")
                        .font(.title2.weight(.bold))

                    // Unacked-count chip. Meaning rides the number + the VoiceOver
                    // label, never color alone (ACCESSIBILITY.md). Hidden at zero.
                    if let badge = summary.unacknowledgedBadge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SemanticColors.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(SemanticColors.warning.opacity(0.12), in: Capsule())
                            .overlay { Capsule().stroke(SemanticColors.warning.opacity(0.20), lineWidth: 1) }
                            .accessibilityLabel("\(inbox.unacknowledgedCount) unacknowledged")
                    }
                }

                Text(summary.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(summary.accessibilityLabel)
            }

            Spacer(minLength: Spacing.sm)

            if inbox.unacknowledgedCount > 0 {
                Button {
                    navigationModel.acknowledgeAllAlerts(in: inbox)
                } label: {
                    Label("Acknowledge all", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Acknowledge every listed alert")
                .accessibilityHint("Marks all listed alerts acknowledged.")
            }
        }
    }

    // MARK: - List

    private func alertsList(_ inbox: AlertsInbox) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(inbox.entries) { entry in
                    AlertsRowView(
                        entry: entry,
                        isSelected: navigationModel.alertSelection == entry.id,
                        onSelect: { navigationModel.alertSelection = entry.id },
                        onToggleAcknowledged: { toggleAcknowledged(entry) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Alerts list, \(inbox.totalCount) item\(inbox.totalCount == 1 ? "" : "s")")
    }

    private func toggleAcknowledged(_ entry: AlertsInbox.Entry) {
        if entry.isAcknowledged {
            navigationModel.unacknowledgeAlert(entry.id)
        } else {
            navigationModel.acknowledgeAlert(entry.id)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("All clear", systemImage: "checkmark.circle")
        } description: {
            Text("Nothing needs your attention right now. Connection, sync, and spending alerts show up here when something changes.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Alerts. All clear, nothing needs attention.")
    }

    /// The detail-column (inspector) pane for Alerts — the selected alert's
    /// detail, recovery action, and acknowledge toggle. Content-gated: shows the
    /// "Select an alert" prompt when nothing is selected (IA §3.1).
    struct Inspector: View {
        @Environment(AppState.self) private var appState
        @Environment(\.openSettings) private var openSettings

        private var navigationModel: NavigationModel { appState.navigationModel }

        private var inbox: AlertsInbox {
            AlertsInbox.make(
                rows: appState.attentionQueue.rows,
                acknowledgedIDs: navigationModel.acknowledgedAlertIDs
            )
        }

        private var selectedEntry: AlertsInbox.Entry? {
            inbox.entry(id: navigationModel.alertSelection)
        }

        var body: some View {
            if let entry = selectedEntry {
                AlertDetailView(
                    entry: entry,
                    onToggleAcknowledged: { toggleAcknowledged(entry) },
                    onAction: { perform(entry.row) }
                )
            } else {
                emptyPrompt
            }
        }

        private var emptyPrompt: some View {
            ContentUnavailableView {
                Label(RouteDestination.alerts.detailColumnEmptyPrompt ?? "Select an alert", systemImage: "bell")
            } description: {
                Text("Pick an alert to see what changed and how to resolve it.")
            }
            .accessibilityLabel("Select an alert to see its detail.")
        }

        private func toggleAcknowledged(_ entry: AlertsInbox.Entry) {
            if entry.isAcknowledged {
                navigationModel.unacknowledgeAlert(entry.id)
            } else {
                navigationModel.acknowledgeAlert(entry.id)
            }
        }

        /// Dispatch the alert's recovery action — the same paths
        /// ``AttentionQueueView`` runs, so an action means the same thing here as
        /// on the menu-bar glance.
        private func perform(_ row: AttentionQueueRow) {
            guard let action = row.action else { return }
            switch action {
            case .checkServer:
                Task { await appState.checkServerConnection() }
            case .addAccount:
                Task { await appState.addAccount() }
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
}

// MARK: - Row

/// A single alert row in the list. Severity is carried by a status badge (glyph +
/// label) and the acknowledged state by a strikethrough title + a labeled toggle —
/// never tint alone.
private struct AlertsRowView: View {
    let entry: AlertsInbox.Entry
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleAcknowledged: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: entry.severity.statusSymbolName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: Sizing.glyphSmall, height: Sizing.glyphSmall)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        AlertSeverityBadge(severity: entry.severity, tint: tint)
                        Text(entry.title)
                            .font(.caption.weight(.semibold))
                            .strikethrough(entry.isAcknowledged)
                            .foregroundStyle(entry.isAcknowledged ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Text(entry.detail)
                        .microText()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.xs)

                Button(action: onToggleAcknowledged) {
                    Image(systemName: entry.isAcknowledged ? "bell.slash.fill" : "bell.fill")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(entry.isAcknowledged ? .secondary : tint)
                .help(entry.isAcknowledged ? "Un-acknowledge" : "Acknowledge")
                .accessibilityLabel(entry.isAcknowledged ? "Un-acknowledge alert" : "Acknowledge alert")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.rowVertical)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? SemanticColors.brand.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .nativeInsetSurface(stroke: panelStroke)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityHint("Opens the alert detail.")
    }

    private var tint: Color {
        switch entry.severity {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private var panelStroke: Color {
        if isSelected { return SemanticColors.brand.opacity(0.28) }
        return entry.isAcknowledged ? Color.primary.opacity(0.06) : tint.opacity(0.16)
    }
}

// MARK: - Detail (inspector)

/// The selected alert's detail pane: title, severity, full message, an acknowledge
/// toggle, and the recovery action (when the alert carries one).
private struct AlertDetailView: View {
    let entry: AlertsInbox.Entry
    let onToggleAcknowledged: () -> Void
    let onAction: () -> Void

    private var row: AttentionQueueRow { entry.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerCard
                if row.action != nil || row.actionTitle != nil {
                    actionCard
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alert detail. \(entry.accessibilityLabel)")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                AlertSeverityBadge(severity: entry.severity, tint: tint)
                if entry.isAcknowledged {
                    Label("Acknowledged", systemImage: "bell.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
            }

            Text(row.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(row.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(get: { entry.isAcknowledged }, set: { _ in onToggleAcknowledged() })) {
                Text(entry.isAcknowledged ? "Acknowledged" : "Acknowledge")
                    .font(.caption.weight(.medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint("Mutes this alert from the unacknowledged count without resolving the underlying condition.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Resolve")
                .font(.headline)
            Text("Run the suggested step to clear this alert.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAction) {
                Label(row.actionTitle ?? "Resolve", systemImage: row.actionIconName ?? "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel(row.actionTitle ?? "Resolve")
            .accessibilityHint(row.accessibilityHint ?? row.detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(.raised)
    }

    private var tint: Color {
        switch entry.severity {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }
}

// MARK: - Severity badge

/// Severity badge — glyph + label, color-independent meaning carrier
/// (ACCESSIBILITY.md). Mirrors the popover's attention badge without depending on
/// its private view.
private struct AlertSeverityBadge: View {
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
        .overlay { Capsule().stroke(tint.opacity(0.22), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

#Preview("Content") {
    AlertsDestinationView()
        .environment(AppState())
}

#Preview("Inspector") {
    AlertsDestinationView.Inspector()
        .environment(AppState())
}
