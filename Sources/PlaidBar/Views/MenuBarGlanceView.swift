import AppKit
import PlaidBarCore
import SwiftUI

/// The reduced menu-bar **glance** that replaces the full dashboard popover once
/// window-first is the default (ADR-001 §6, AND-616 / AND-587).
///
/// The glance is **read + route only**. It shows the sync line, two-to-four
/// high-signal numbers (net worth · safe-to-spend · to-review), up to three
/// attention chips that **deep-link into window destinations**, and an
/// "Open VaultPeek" button that opens the primary `Window`. The full dashboard
/// now lives only in the window's Dashboard destination — this view never hosts
/// it and never mutates finance data.
///
/// All assembly lives in the pure `MenuBarGlanceModel` (PlaidBarCore): this is a
/// thin renderer over `appState.menuBarGlanceModel`. Color is never the sole
/// carrier of meaning — every metric and chip pairs a label with an SF Symbol,
/// and severity is shown by glyph *shape* plus text, not tint alone (ACCESSIBILITY.md).
/// Privacy Mask / App Lock is honored upstream: the model redacts currency
/// metrics when `shouldMaskFinancialValues` is set.
struct MenuBarGlanceView: View {
    @Environment(AppState.self) private var appState
    /// Deep-links a chip's ``Route`` into the primary window (AND-597). When the
    /// scene wires a real handler this opens the window at the destination; the
    /// no-op default is never reached here (the glance is only mounted when
    /// window-first is enabled), but keeping the environment seam means the view
    /// stays headless-safe for previews/snapshots.
    @Environment(\.openRoute) private var openRoute
    /// Opens the primary window for the "Open VaultPeek" button — supplied by the
    /// scene (it owns `openWindow(id:)`). No-op default keeps previews safe.
    @Environment(\.openPrimaryWindow) private var openPrimaryWindow
    @Environment(\.openSettings) private var openSettings

    /// Compact glance width — narrower than the old 3-column dashboard popover,
    /// matching a launcher rather than a workspace (ADR-001 §6).
    private static let width: CGFloat = 300

    private var model: MenuBarGlanceModel { appState.menuBarGlanceModel }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            syncStatusRow
            metricsRow
            if !model.chips.isEmpty {
                Divider()
                chips
            }
            Divider()
            footer
        }
        .padding(Spacing.md)
        .frame(width: Self.width)
    }

    // MARK: - Sync status

    private var syncStatusRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: model.syncStatusGlyph)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.syncStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status. \(model.syncStatusText)")
    }

    // MARK: - Glance metrics

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(model.metrics) { metric in
                GlanceMetricCell(metric: metric)
                if metric.id != model.metrics.last?.id {
                    Divider().frame(height: 32)
                }
            }
        }
    }

    // MARK: - Attention chips

    private var chips: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(model.chips) { chip in
                GlanceChipRow(chip: chip) {
                    activate(chip)
                }
            }
        }
    }

    /// A chip routes into the window when it carries a ``Route``; otherwise it
    /// runs its in-place infrastructure action (check server, open Settings,
    /// refresh) — exactly the `MenuBarGlanceModel.Chip` contract. The local-infra
    /// action set mirrors `AttentionQueueView.perform`.
    private func activate(_ chip: MenuBarGlanceModel.Chip) {
        if let route = chip.route {
            openRoute(route)
            return
        }
        guard let action = chip.fallbackAction else { return }
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            Task { await appState.addAccount() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            // Degraded-item chips carry a `Route` (`Route.from(attentionRow:)`
            // maps `item-error-/item-repair-/item-outage-` rows to Accounts), so
            // a reconnect action never reaches this fallback. Refresh defensively.
            Task { await appState.refreshDashboard() }
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

    // MARK: - Footer quick-actions

    /// The reduced glance footer: the popover's one-click Privacy Mask and
    /// Refresh affordances kept reachable here (AND-616), then the primary
    /// "Open VaultPeek" CTA which fills the remaining width. The glance stays a
    /// launcher — only these two icon buttons plus the CTA; Add-Account,
    /// Recurring, Detach, Settings, and the status line live in the window.
    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            privacyMaskButton
            refreshButton
            openButton
        }
    }

    private var privacyMaskButton: some View {
        let isMasked = appState.appLockPreferences.privacyMaskEnabled
        let label = PrivacyMaskPresentation.toggleActionLabel(isMasked: isMasked)
        return Button {
            appState.togglePrivacyMask()
        } label: {
            // State is shape-borne (eye vs. eye.slash), never color alone.
            Image(systemName: PrivacyMaskPresentation.toggleSymbolName(isMasked: isMasked))
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
        .help(label)
        .accessibilityLabel(label)
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }

    private var refreshButton: some View {
        Button {
            Task { await appState.refreshDashboard() }
        } label: {
            // RefreshIcon carries loading state by glyph/motion, not color alone.
            RefreshIcon(isLoading: appState.isLoading)
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
        .help("Refresh")
        .accessibilityLabel("Refresh")
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Open window

    private var openButton: some View {
        Button {
            openPrimaryWindow()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "macwindow")
                    .accessibilityHidden(true)
                Text("Open VaultPeek")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Opens the VaultPeek window.")
    }
}

/// One glance metric — label + value, with an SF Symbol so meaning is never tint
/// alone.
private struct GlanceMetricCell: View {
    let metric: MenuBarGlanceModel.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label(metric.label, systemImage: metric.glyph)
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(metric.value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label). \(metric.value)")
    }
}

/// One attention chip row. The leading glyph's *shape* carries severity (never
/// color alone); the whole row is a button that routes into the window or runs
/// the chip's in-place action.
private struct GlanceChipRow: View {
    let chip: MenuBarGlanceModel.Chip
    let action: () -> Void

    private var tint: Color {
        switch chip.severity {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: chip.glyph)
                    .font(.callout)
                    .foregroundStyle(tint)
                    .frame(width: Sizing.glyphSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(chip.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(chip.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(chip.severity == .healthy ? 0.0 : 0.10), in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityHint(chip.accessibilityHint ?? (chip.deepLinks ? "Opens this in the VaultPeek window." : ""))
    }
}
