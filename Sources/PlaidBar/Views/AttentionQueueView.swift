import PlaidBarCore
import SwiftUI

struct AttentionQueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    /// Deep-links a glance chip into the window-first window (AND-597).
    /// No-op by default — installed with a real handler only when the window-first
    /// flag is ON (`PlaidBarApp`), so flag-OFF chip behavior is unchanged.
    @Environment(\.openRoute) private var openRoute

    let title: String
    var showsHealthyRow = true
    var onAddAccount: (() -> Void)?
    /// Opt-in richer inline treatment (Gate-0, AND-979 — the Alerts fold,
    /// 2026-07-02): each non-healthy row gets an "Acknowledge" affordance
    /// alongside its existing resolve action, and an acknowledged row drops out
    /// of the visible glance list (it stays tracked in `NavigationModel.
    /// acknowledgedAlertIDs`, so it can come back if the underlying condition
    /// recurs with a fresh row). Acknowledging only hides — the queue is capped
    /// upstream in `AttentionQueue.init`, so a hidden row does not backfill a
    /// truncated one. Defaults to `false` so every existing call site
    /// (`MainPopover`'s two glance uses and Settings' two) is byte-for-byte
    /// unchanged — only Dashboard's status-readiness card opts in, since that is
    /// the folded-in home for what used to be the standalone Alerts
    /// destination's detail+acknowledge workflow. Row detail was already always
    /// visible inline here; the only genuinely new capability is "acknowledge
    /// without resolving."
    var supportsAcknowledge = false

    /// Window-first hybrid opt-in, resolved once per render. Gates whether an
    /// attention chip routes into the window vs. runs its existing in-place
    /// action. OFF (the shipping default) ⇒ today's behavior exactly.
    private var isWindowFirstEnabled: Bool { WindowFirstFeatureFlag.resolved() }

    private var navigationModel: NavigationModel { appState.navigationModel }

    private var rows: [AttentionQueueRow] {
        var rows = appState.attentionQueue.rows
        if !showsHealthyRow {
            rows = rows.filter { $0.severity != .healthy }
        }
        if supportsAcknowledge {
            rows = rows.filter { !navigationModel.acknowledgedAlertIDs.contains($0.id) }
        }
        return rows
    }

    var body: some View {
        // A `Group` (always present, even when `rows` is momentarily empty —
        // e.g. everything visible got acknowledged) so the self-heal below
        // keeps running rather than dropping out with the hidden content, the
        // same way it always ran on `AlertsDestinationView`'s always-present
        // ScrollView before the fold.
        Group {
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
                            // The healthy row is a status readout, not an alert —
                            // acknowledging it would only blank the whole card for
                            // the session, so it never gets the affordance.
                            let canAcknowledge = supportsAcknowledge && row.severity != .healthy
                            AttentionQueueRowView(
                                row: row,
                                isDisabled: appState.isLoading,
                                supportsAcknowledge: canAcknowledge,
                                onAcknowledge: canAcknowledge ? { navigationModel.acknowledgeAlert(row.id) } : nil
                            ) {
                                perform(row)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(title), \(rows.count) item\(rows.count == 1 ? "" : "s")")
            }
        }
        // Self-heal: an acknowledged id whose row is no longer live (the
        // underlying condition resolved on its own) never lingers in
        // NavigationModel's session-scoped set — the same self-heal
        // `AlertsDestinationView` ran before the fold.
        .onChange(of: appState.attentionQueue.rows.map(\.id)) { _, _ in
            guard supportsAcknowledge else { return }
            navigationModel.pruneAlerts(toRowsIn: appState.attentionQueue.rows)
        }
    }

    private func perform(_ row: AttentionQueueRow) {
        // Window-first: a glance chip is a launcher. When the flag
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

        // In-place dispatch through the shared dispatcher (no `openRoute`, so the
        // route-mapped fallback never fires here — this path is reached only when
        // the row has no window destination or the flag is OFF, matching the prior
        // behavior exactly).
        RecoveryActionDispatcher(
            appState: appState,
            openSettings: { openSettings() },
            onAddAccount: onAddAccount
        )
        .dispatch(row)
    }
}

private struct AttentionQueueRowView: View {
    let row: AttentionQueueRow
    let isDisabled: Bool
    /// Whether this row shows the "Acknowledge" affordance alongside its
    /// resolve action (Gate-0, AND-979 — the Alerts fold). `false` for every
    /// pre-existing call site (`MainPopover`'s two uses and Settings' two) —
    /// byte-for-byte unchanged there.
    var supportsAcknowledge = false
    /// Acknowledges this row (removes it from the visible queue without
    /// resolving the underlying condition). `nil` when `supportsAcknowledge`
    /// is `false`.
    var onAcknowledge: (() -> Void)?
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

            if supportsAcknowledge, let onAcknowledge {
                // Acknowledge without resolving — the capability the folded-in
                // Alerts destination's detail pane carried, now inline. A
                // distinct affordance from the resolve action below: this one
                // never dispatches a recovery step, it only clears the row from
                // the glance queue.
                Button(action: onAcknowledge) {
                    Label("Acknowledge", systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Acknowledge — dismiss from the queue without resolving")
                .accessibilityLabel("Acknowledge")
                .accessibilityHint("Dismisses this item from the attention queue without resolving it.")
            }

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
        // Attention rows are *data* surfaces — solid, never glass (R-08).
        // A ternary can't pick between the two modifiers (different types), so
        // the severity branches the surface call, matching every sibling
        // attention surface (DashboardReadinessPanel, MainPopover readiness).
        .modifier(AttentionRowSurface(emphasizedTint: emphasizedTint, quietStroke: panelStroke))
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

/// The attention row's surface: solid emphasized tint for warning/blocked rows,
/// quiet solid fill for the healthy row — never glass, since these rows are
/// data (severity, institution, recovery detail), not chrome (R-08 / AND-980).
private struct AttentionRowSurface: ViewModifier {
    let emphasizedTint: Color?
    let quietStroke: Color

    func body(content: Content) -> some View {
        if let emphasizedTint {
            content.emphasizedDataSurface(tint: emphasizedTint)
        } else {
            content.solidDataSurface(
                cornerRadius: Radius.panel,
                fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.controlFillOpacity)),
                stroke: quietStroke
            )
        }
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
#if canImport(PreviewsMacros)
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
#endif
