import AppKit
import PlaidBarCore
import SwiftUI

// MARK: - Status Strip

struct DashboardStatusStrip: View {
    @Environment(AppState.self) private var appState
    let openSettings: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            StatusStripItem(
                title: "Mode",
                value: appState.statusModeText,
                icon: appState.isDemoMode ? "play.circle.fill" : "server.rack",
                tint: .secondary
            )

            StatusDivider()

            StatusStripItem(
                title: "Server",
                value: appState.statusServerText,
                icon: serverIcon,
                tint: serverTint
            )

            StatusDivider()

            StatusStripItem(
                title: "Sync",
                value: appState.statusSyncText,
                icon: appState.isSyncStale ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill",
                tint: appState.isSyncStale ? SemanticColors.warning : .secondary
            )

            StatusDivider()

            StatusStripItem(
                title: "Items",
                value: itemsText,
                icon: itemIcon,
                tint: itemTint
            )

            StatusDivider()

            StatusStripActions(
                actions: statusActions,
                labelForAction: actionLabel,
                isDisabled: appState.isLoading,
                perform: perform
            )
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        .nativeInsetSurface(cornerRadius: SurfaceTokens.panelCornerRadius)
        .accessibilityElement(children: .contain)
    }

    private var readiness: DashboardStatusReadiness {
        appState.dashboardStatusReadiness
    }

    private var statusActions: [DashboardStatusReadinessAction] {
        var actions: [DashboardStatusReadinessAction] = []
        if let primaryAction = readiness.primaryAction {
            actions.append(primaryAction)
        }
        actions.append(contentsOf: readiness.secondaryActions)
        let uniqueActions = actions.reduce(into: [DashboardStatusReadinessAction]()) { uniqueActions, action in
            if !uniqueActions.contains(action) {
                uniqueActions.append(action)
            }
        }
        return Array(uniqueActions.prefix(2))
    }

    private var serverIcon: String {
        if appState.isDemoMode { return "play.circle.fill" }
        if appState.isLoading { return "arrow.triangle.2.circlepath" }
        if appState.error != nil { return "xmark.octagon.fill" }
        return appState.serverConnected ? "checkmark.circle.fill" : "server.rack"
    }

    private var serverTint: Color {
        if appState.isDemoMode { return .secondary }
        if appState.isLoading { return SemanticColors.warning }
        if appState.error != nil { return SemanticColors.negative }
        return .secondary
    }

    private var itemsText: String {
        if appState.erroredItemCount > 0 {
            return "\(appState.erroredItemCount) error"
        }
        if appState.needsLoginItemCount > 0 {
            return "\(appState.needsLoginItemCount) login"
        }
        return "\(appState.statusItemCount) linked"
    }

    private var itemIcon: String {
        if appState.erroredItemCount > 0 { return "exclamationmark.triangle.fill" }
        if appState.needsLoginItemCount > 0 { return "person.crop.circle.badge.exclamationmark.fill" }
        return "link.circle.fill"
    }

    private var itemTint: Color {
        if appState.erroredItemCount > 0 { return SemanticColors.negative }
        if appState.needsLoginItemCount > 0 { return SemanticColors.warning }
        return .secondary
    }

    private func actionLabel(for action: DashboardStatusReadinessAction) -> String {
        if action == .reconnect,
           let title = ItemRecoveryTarget.actionTitle(from: appState.itemStatuses) {
            return title
        }
        if readiness.primaryAction == action {
            return readiness.primaryActionTitle ?? action.defaultTitle
        }
        if action == .addAccount {
            return "Connect Bank"
        }
        return action.defaultTitle
    }

    private func perform(_ action: DashboardStatusReadinessAction) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            onAddAccount()
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            guard let itemId = ItemRecoveryTarget.itemId(from: appState.itemStatuses) else {
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

private struct StatusStripItem: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 13)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .microText()
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusStripActions: View {
    let actions: [DashboardStatusReadinessAction]
    let labelForAction: (DashboardStatusReadinessAction) -> String
    let isDisabled: Bool
    let perform: (DashboardStatusReadinessAction) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(actions, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Label(labelForAction(action), systemImage: action.defaultIconName)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(labelForAction(action))
                .accessibilityLabel(labelForAction(action))
                .disabled(isDisabled)
            }
        }
        .frame(minWidth: 46, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status actions")
    }
}

private struct StatusDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, Spacing.xxs)
            .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Account Filters

/// The dashboard account filter is the core `DashboardAccountFilterKind`
/// reused directly. The persisted `@AppStorage("dashboard.accountFilter")`
/// raw values ("All", "Cash", "Credit", "Savings", "Debt", "Status") are the
/// core enum's raw values, so stored selections decode exactly as before.
typealias DashboardAccountFilter = DashboardAccountFilterKind

extension DashboardAccountFilterKind {
    /// View-layer convenience that resolves degraded item ids from app state.
    @MainActor
    func includes(_ account: AccountDTO, appState: AppState) -> Bool {
        includes(account, degradedItemIds: appState.degradedItemIds)
    }
}

// MARK: - Filter Bar

struct DashboardFilterBar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: DashboardAccountFilter
    /// Whether an account row is drilled in, so the container's VoiceOver
    /// label keeps the row-selection state the old caption used to announce.
    let hasSelectedAccount: Bool

    var body: some View {
        let items = DashboardNavBarModel.items(
            accounts: appState.accounts,
            degradedItemIds: appState.degradedItemIds
        )

        // No container clipShape here: segments round their own outer
        // corners (see `DashboardFilterSegment.backgroundShape`) so the
        // keyboard focus ring on the first/last segment is never cropped.
        HStack(spacing: 1) {
            ForEach(items) { item in
                DashboardFilterSegment(
                    item: item,
                    isSelected: selection == item.kind,
                    isFirst: item.kind == DashboardAccountFilterKind.allCases.first,
                    isLast: item.kind == DashboardAccountFilterKind.allCases.last
                ) {
                    selection = item.kind
                }

                if item.kind != DashboardAccountFilterKind.allCases.last {
                    Divider()
                        .padding(.vertical, Spacing.rowVertical)
                }
            }
        }
        .nativeInsetSurface(cornerRadius: SurfaceTokens.panelCornerRadius)
        .accessibilityElement(children: .contain)
        // The selected-filter rollup lives in the container *label*, not the
        // container value: macOS VoiceOver announces a group's label when
        // entering it but does not reliably read a group's AXValue.
        .accessibilityLabel(DashboardNavBarModel.containerAccessibilityLabel(
            selected: selection,
            items: items,
            hasSelectedAccount: hasSelectedAccount
        ))
    }
}

private struct DashboardFilterSegment: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: DashboardNavBarItem
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.xs) {
                if let statusIconName = item.statusIconName {
                    Image(systemName: statusIconName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusIconTint)
                }

                Text(item.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text("\(item.count)")
                    .microText()
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Plain-styled buttons in this popover do not receive Tab focus by
        // default; opt in explicitly so the segments stay keyboard-reachable
        // (same pattern as AccountRowWithDrilldown in MainPopover).
        .focusable(true)
        .background(backgroundFill, in: backgroundShape)
        .overlay(alignment: .bottom) {
            selectionIndicator
        }
        .onHover { isHovered = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(item.shortcutOrdinal)")), modifiers: .command)
        .help(item.helpText)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .accessibilityHint("Filters the dashboard account list.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Warning tint is reserved for the status icon: orange digits at micro
    /// size fall far below the 4.5:1 contrast small text needs in light
    /// mode, so the count always stays `.secondary` and the triangle-vs-
    /// checkmark shape carries the attention state — never color alone.
    /// This mirrors the status strip, which tints icons but never text.
    private var statusIconTint: Color {
        item.showsAttentionBadge ? SemanticColors.warning : .secondary
    }

    private var backgroundFill: Color {
        if isSelected {
            return SemanticColors.brand.opacity(SurfaceTokens.selectedFillOpacity)
        }
        if isHovered {
            return Color.primary.opacity(SurfaceTokens.insetFillOpacity)
        }
        return .clear
    }

    /// Rounds only the bar's outer corners on the first/last segment so the
    /// hover/selection fill matches the inset surface without a container
    /// `clipShape` — which would crop the keyboard focus ring at the ends.
    private var backgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? SurfaceTokens.panelCornerRadius : 0,
            bottomLeadingRadius: isFirst ? SurfaceTokens.panelCornerRadius : 0,
            bottomTrailingRadius: isLast ? SurfaceTokens.panelCornerRadius : 0,
            topTrailingRadius: isLast ? SurfaceTokens.panelCornerRadius : 0
        )
    }

    private var selectionIndicator: some View {
        Rectangle()
            .fill(SemanticColors.brand)
            .frame(height: Spacing.xxs)
            .padding(.horizontal, Spacing.sm)
            .opacity(isSelected ? 1 : 0)
            .scaleEffect(x: isSelected ? 1 : 0.4, y: 1, anchor: .center)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isSelected)
    }
}
