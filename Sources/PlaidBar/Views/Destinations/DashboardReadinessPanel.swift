import PlaidBarCore
import SwiftUI

/// The dashboard's status-readiness panel for the window-first **Dashboard**
/// destination (AND-622), surfaced from the same Core ``DashboardStatusReadiness``
/// verdict the menu-bar popover renders. It carries the readiness title/detail,
/// the status metric grid, and the primary recovery action — dispatched through
/// the same `AppState` methods the popover uses, so the two surfaces drive
/// identical recovery behavior.
///
/// **Surface only — no verdict logic here.** The verdict, its tone, and the
/// action set all come from `AppState.dashboardStatusReadiness` (Core). Meaning is
/// carried by glyph + text, never color alone (ACCESSIBILITY.md).
struct DashboardReadinessPanel: View {
    @Environment(AppState.self) private var appState
    let openSettings: () -> Void
    let onAddAccount: () -> Void

    private var readiness: DashboardStatusReadiness {
        appState.dashboardStatusReadiness
    }

    private var needsAttention: Bool {
        readiness.level == .warning || readiness.level == .blocked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness.title)
                        .font(.callout.weight(.semibold))
                    Text(readiness.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            DashboardStatusMetricGrid()

            if let primaryAction = readiness.primaryAction {
                Button {
                    perform(primaryAction)
                } label: {
                    Label(
                        primaryActionLabel(for: primaryAction),
                        systemImage: readiness.primaryActionIconName ?? primaryAction.canonicalIconName
                    )
                }
                .buttonStyle(needsAttention ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                .controlSize(.small)
                .tint(tint)
                .disabled(appState.isLoading)
            }
        }
        .padding(Spacing.md)
        .glassSurface(needsAttention ? .emphasized(tint) : .raised)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch readiness.level {
        case .healthy: "checkmark.circle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch readiness.level {
        case .healthy, .loading: AppearanceTextColors.secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private func primaryActionLabel(for action: RecoveryAction) -> String {
        if action == .reconnect,
           let title = ItemRecoveryTarget.actionTitle(from: appState.itemStatuses) {
            return title
        }
        return readiness.primaryActionTitle ?? action.canonicalTitle
    }

    /// Dispatches a readiness action through the shared ``RecoveryActionDispatcher``
    /// — the same `AppState` entry points every other attention surface uses, so
    /// recovery means the same thing everywhere.
    private func perform(_ action: RecoveryAction) {
        RecoveryActionDispatcher(
            appState: appState,
            openSettings: openSettings,
            onAddAccount: onAddAccount
        )
        .perform(action)
    }
}

/// The readiness status metric grid (Mode / Server / Items / Synced / Credentials
/// / Last Sync / Data Path), reading the same `AppState` status accessors the
/// popover grid reads. Surface only.
private struct DashboardStatusMetricGrid: View {
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.flexible(minimum: 112), spacing: 6),
        GridItem(.flexible(minimum: 112), spacing: 6),
        GridItem(.flexible(minimum: 112), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            metric("Mode", appState.statusModeText)
            metric("Server", appState.statusServerText)
            metric("Items", "\(appState.statusItemCount) linked")
            metric("Synced", "\(appState.serverSyncedItemCount ?? 0) of \(appState.statusItemCount)")
            metric("Credentials", appState.serverCredentialsText)
            metric("Last Sync", appState.lastSyncRelative ?? "Never")
            metric("Data Path", appState.activeStorageDirectoryDisplayText)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .microText()
                .foregroundStyle(.secondary)
            Text(value)
                .windowFigureCaption()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// An inline error banner for the window-first dashboard overview, mirroring the
/// popover's `ErrorBanner` (which is private to `MainPopover`). Same shape +
/// dismiss + VoiceOver announcement so a sync error reads the same on both
/// surfaces. Meaning is carried by glyph + text, never color alone.
struct DashboardErrorBanner: View {
    let error: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticColors.negative)
                .accessibilityHidden(true)
            Text(error)
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(SemanticColors.negative.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(error)")
        .task(id: error) {
            await Task.yield()
            AccessibilityNotification.Announcement("Error: \(error)").post()
        }
    }
}

/// Type-erased button style so the readiness primary action can pick prominent vs
/// bordered without the two branches producing different `some View` body types.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let makeBody: (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration)
    }
}
