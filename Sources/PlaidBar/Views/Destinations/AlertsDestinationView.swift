import PlaidBarCore
import SwiftUI

/// **Alerts** destination (3-column — `[⌘7]`) — Epic 7 / AND-585,
/// redesigned to the window-first desktop language (AND-624).
///
/// Content column = the alert **list**, re-hosted at window (desk-distance) scale:
/// a hero header carrying the unacknowledged count as a large tabular figure, then
/// the feed grouped into **Needs attention** and **Acknowledged** ``WindowSection``
/// cards (severity-sorted within each, ≤2 cards so the column reads calm). Detail
/// column = the selected alert's **detail** with its recovery action and
/// acknowledge toggle, also re-hosted in window-scale cards. The detail column is
/// **content-gated, not existence-gated**: with nothing selected it shows
/// the "Select an alert" prompt rather than collapsing.
///
/// This is a **layout re-host only** — the alert source, sort/acknowledge/count
/// policy, and recovery dispatch are unchanged:
/// - The alerts are the live ``AttentionQueue`` rows (``AppState/attentionQueue``)
///   — the same "do I need to act?" rollup the menu-bar glance and Dashboard key
///   off, so the feed stays truthful and consistent across surfaces.
/// - ``AlertsInbox`` / ``AlertsSummary`` (pure Core, unit-tested) reduce those rows
///   + the acknowledged-id set into the sorted feed, the unacknowledged count, and
///   the header wording. Acknowledgement is session-scoped per-window state on the
///   per-window ``NavigationModel`` (`alertSelection` + `acknowledgedAlertIDs`,
///   AND-621) — the rows and the queue are never mutated.
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
/// (ACCESSIBILITY.md). Cards back their figures with the quiet solid
/// ``WindowSection`` surface (data stays solid — glass is chrome-only).
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON); with the flag off this file is never instantiated
/// and the popover is byte-identical.
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

        ScrollView {
            VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                if inbox.isEmpty {
                    // All-clear: the empty state carries the message on its own; a
                    // hero tile of zeros would just repeat "all clear" three times
                    // and crowd a calm canvas, so it is suppressed here.
                    emptyState
                } else {
                    AlertsHeroHeader(
                        summary: summary,
                        inbox: inbox,
                        onAcknowledgeAll: { navigationModel.acknowledgeAllAlerts(in: inbox) }
                    )
                    feed(inbox)
                }
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(RouteDestination.alerts.title)
        // Keep the acknowledged set + selection bounded to the live rows so a
        // resolved condition never lingers acknowledged or selected.
        .onChange(of: rows.map(\.id)) { _, _ in
            navigationModel.pruneAlerts(toRowsIn: rows)
        }
        .onAppear { navigationModel.pruneAlerts(toRowsIn: rows) }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Feed (grouped sections)

    /// The feed, split into at most two ``WindowSection`` cards — **Needs
    /// attention** (unacknowledged) above **Acknowledged** — so the column reads as
    /// a calm work queue of two generous cards rather than one long undivided list.
    /// Each section is hidden when it has no rows, so a feed with nothing
    /// acknowledged shows a single card.
    @ViewBuilder
    private func feed(_ inbox: AlertsInbox) -> some View {
        let unacked = inbox.entries.filter { !$0.isAcknowledged }
        let acked = inbox.entries.filter(\.isAcknowledged)

        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            if !unacked.isEmpty {
                WindowSection(
                    "Needs attention",
                    systemImage: "exclamationmark.triangle"
                ) {
                    countAccessory(unacked.count)
                } content: {
                    alertRows(unacked, selectionEnabled: true)
                }
            }

            if !acked.isEmpty {
                WindowSection(
                    "Acknowledged",
                    systemImage: "bell.slash"
                ) {
                    countAccessory(acked.count)
                } content: {
                    alertRows(acked, selectionEnabled: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func countAccessory(_ count: Int) -> some View {
        Text("\(count)")
            .windowSupportingText()
            .monospacedDigit()
            .accessibilityLabel("\(count) alert\(count == 1 ? "" : "s")")
    }

    private func alertRows(_ entries: [AlertsInbox.Entry], selectionEnabled: Bool) -> some View {
        VStack(spacing: WindowMetrics.xs) {
            ForEach(entries) { entry in
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
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityLabel("Alerts. All clear, nothing needs attention.")
    }

    /// The detail-column (inspector) pane for Alerts — the selected alert's
    /// detail, recovery action, and acknowledge toggle, re-hosted in window-scale
    /// cards. Content-gated: shows the "Select an alert" prompt when nothing is
    /// selected.
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

        /// Dispatch the alert's recovery action through the shared
        /// ``RecoveryActionDispatcher`` — the same `AppState` paths
        /// ``AttentionQueueView`` runs, so an action means the same thing here as
        /// on the menu-bar glance.
        private func perform(_ row: AttentionQueueRow) {
            RecoveryActionDispatcher(appState: appState, openSettings: { openSettings() })
                .dispatch(row)
        }
    }
}

// MARK: - Hero header

/// The Alerts content column's hero header: the unacknowledged count as a large
/// tabular figure (the destination's headline number, ``WindowHeroMetric``) with a
/// glyph + summary line, and an "Acknowledge all" action when anything is pending.
/// Meaning rides the number, the glyph shape, and the text — never tint alone
/// (ACCESSIBILITY.md). It reuses the same quiet solid card surface as
/// ``WindowHeroMetricTile`` so it sits in the dashboard's visual system.
private struct AlertsHeroHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let summary: AlertsSummary
    let inbox: AlertsInbox
    let onAcknowledgeAll: () -> Void

    private var unacked: Int { inbox.unacknowledgedCount }
    private var hasPending: Bool { unacked > 0 }

    /// Lead glyph: a clean bell when nothing is pending, an escalating glyph keyed
    /// to the highest unacknowledged severity otherwise. Shape carries the state;
    /// the figure and summary carry it again in text.
    private var glyph: String {
        guard hasPending else { return "bell.badge.slash" }
        return inbox.highestUnacknowledgedSeverity?.statusSymbolName ?? "bell.badge"
    }

    private var accent: Color {
        guard hasPending else { return .secondary }
        switch inbox.highestUnacknowledgedSeverity {
        case .blocked: return SemanticColors.negative
        case .warning: return SemanticColors.warning
        default: return SemanticColors.brand
        }
    }

    private var figure: String { hasPending ? "\(unacked)" : "0" }

    private var caption: String {
        hasPending ? (unacked == 1 ? "needs attention" : "need attention") : "all clear"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            HStack(alignment: .top, spacing: WindowMetrics.md) {
                VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                    Label {
                        Text("Alerts")
                            .windowSupportingText()
                            .textCase(.uppercase)
                    } icon: {
                        Image(systemName: glyph)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .labelStyle(.titleAndIcon)

                    HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.xs) {
                        Text(figure)
                            .windowHeroMetric()
                            .rollingTabularNumber(figure, reduceMotion: reduceMotion)
                            .foregroundStyle(AppearanceTextColors.primary)
                            .lineLimit(1)
                        Text(caption)
                            .windowBodyText()
                            .foregroundStyle(.secondary)
                    }

                    Text(summary.title)
                        .windowSupportingText()
                        .accessibilityHidden(true)
                }

                Spacer(minLength: WindowMetrics.sm)

                if hasPending {
                    Button(action: onAcknowledgeAll) {
                        Label("Acknowledge all", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Acknowledge every listed alert")
                    .accessibilityHint("Marks all listed alerts acknowledged.")
                }
            }
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.accessibilityLabel)
    }
}

// MARK: - Row

/// A single alert row in a section card, at window scale. Severity is carried by a
/// status badge (glyph + label) and the acknowledged state by a strikethrough title
/// + a labeled toggle — never tint alone (ACCESSIBILITY.md).
private struct AlertsRowView: View {
    let entry: AlertsInbox.Entry
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleAcknowledged: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: WindowMetrics.sm) {
                Image(systemName: entry.severity.statusSymbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                    HStack(spacing: WindowMetrics.xs) {
                        AlertSeverityBadge(severity: entry.severity, tint: tint)
                        Text(entry.title)
                            .windowBodyText()
                            .fontWeight(.semibold)
                            .strikethrough(entry.isAcknowledged)
                            .foregroundStyle(entry.isAcknowledged ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Text(entry.detail)
                        .windowSupportingText()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WindowMetrics.sm)

                Button(action: onToggleAcknowledged) {
                    Image(systemName: entry.isAcknowledged ? "bell.slash.fill" : "bell.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(entry.isAcknowledged ? .secondary : tint)
                .help(entry.isAcknowledged ? "Un-acknowledge" : "Acknowledge")
                .accessibilityLabel(entry.isAcknowledged ? "Un-acknowledge alert" : "Acknowledge alert")
            }
            .padding(.horizontal, WindowMetrics.sm)
            .padding(.vertical, WindowMetrics.sm)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? SemanticColors.brand.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius - 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius - 4)
                .stroke(rowStroke, lineWidth: 1)
        }
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

    private var rowStroke: Color {
        if isSelected { return SemanticColors.brand.opacity(0.28) }
        return entry.isAcknowledged ? Color.primary.opacity(0.06) : tint.opacity(0.16)
    }
}

// MARK: - Detail (inspector)

/// The selected alert's detail pane at window scale: a header card (severity, full
/// message, acknowledge toggle) and a recovery card (when the alert carries an
/// action), both on the quiet solid window card surface.
private struct AlertDetailView: View {
    let entry: AlertsInbox.Entry
    let onToggleAcknowledged: () -> Void
    let onAction: () -> Void

    private var row: AttentionQueueRow { entry.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowMetrics.lg) {
                headerCard
                if row.action != nil || row.actionTitle != nil {
                    actionCard
                }
            }
            .padding(WindowMetrics.canvasMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alert detail. \(entry.accessibilityLabel)")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            HStack(spacing: WindowMetrics.sm) {
                AlertSeverityBadge(severity: entry.severity, tint: tint)
                if entry.isAcknowledged {
                    Label("Acknowledged", systemImage: "bell.slash")
                        .windowFigureCaption()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.chipVertical)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
            }

            Text(row.title)
                .windowCardTitle()
                .fixedSize(horizontal: false, vertical: true)

            Text(row.detail)
                .windowBodyText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(get: { entry.isAcknowledged }, set: { _ in onToggleAcknowledged() })) {
                Text(entry.isAcknowledged ? "Acknowledged" : "Acknowledge")
                    .windowBodyText()
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .accessibilityHint("Mutes this alert from the unacknowledged count without resolving the underlying condition.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WindowMetrics.md)
        .windowCardSurface()
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            Text("Resolve")
                .windowCardTitle()
            Text("Run the suggested step to clear this alert.")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAction) {
                Label(row.actionTitle ?? "Resolve", systemImage: row.actionIconName ?? "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(row.actionTitle ?? "Resolve")
            .accessibilityHint(row.accessibilityHint ?? row.detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WindowMetrics.md)
        .windowCardSurface()
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
/// (ACCESSIBILITY.md). At window scale uses the `.subheadline` supporting size so
/// it reads cleanly beside a `.body` row title.
private struct AlertSeverityBadge: View {
    let severity: AttentionQueueSeverity
    let tint: Color

    var body: some View {
        HStack(spacing: WindowMetrics.xs) {
            Image(systemName: severity.statusSymbolName)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(severity.statusLabel)
                .windowFigureCaption()
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
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
