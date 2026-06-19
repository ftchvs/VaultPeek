import AppIntents
import PlaidBarCore
import SwiftUI
import WidgetKit

private struct GlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GlanceSnapshot
    /// True when no real snapshot exists yet (first install, post-reset, or a
    /// failed app-group read). The view shows a setup/unavailable state instead
    /// of a misleading "$0 · Updated now".
    var isUnavailable = false
    /// True when App Lock / Privacy Mask is active (read from the richer
    /// `FinanceSnapshot.isMasked` in the shared App Group). The widget then dots
    /// out every figure so balances never leak onto a shared/visible desktop
    /// while the user has explicitly masked the app (AND-513 / AND-462).
    var isMasked = false
}

private struct GlanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), snapshot: .placeholder(), isUnavailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        // Preview/gallery contexts (Add Widget) must not render the user's real
        // net worth before the widget is placed — use the redacted placeholder.
        if context.isPreview {
            completion(GlanceEntry(date: Date(), snapshot: .placeholder(), isUnavailable: true))
        } else {
            completion(entry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let current = entry()
        // Schedule the next reload relative to now, not the snapshot's
        // last-success time — otherwise a snapshot older than 15 minutes yields
        // an already-past refresh date and WidgetKit throttles/loops.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> GlanceEntry {
        // Distinguish "no snapshot yet" from a real zero balance so the widget
        // shows a setup state rather than a misleading "$0 · Updated now".
        guard let snapshot = try? GlanceSnapshotStore.load() else {
            return GlanceEntry(date: Date(), snapshot: .placeholder(), isUnavailable: true)
        }
        // The richer FinanceSnapshot (Epic D) carries the live privacy-mask flag
        // toggled by the Control Center control; honor it so the widget hides
        // figures the moment the user masks the app, without waiting for a glance
        // snapshot rewrite. The glance snapshot also carries its own `isRedacted`
        // flag (set when the app wrote it while masked/locked); honoring either
        // means the widget stays masked even if the sibling FinanceSnapshot is
        // missing or stale — and a redacted glance file already holds no figures
        // (AND-517).
        let financeMasked = AppGroupSnapshotStore.loadIfAvailable()?.isMasked ?? false
        let isMasked = financeMasked || snapshot.isRedacted
        return GlanceEntry(date: snapshot.updatedAt, snapshot: snapshot, isMasked: isMasked)
    }
}

private struct PlaidBarGlanceWidget: Widget {
    let kind = "PlaidBarGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceTimelineProvider()) { entry in
            GlanceWidgetView(entry: entry)
                // macOS 26 renders widget container backgrounds with the system
                // glass material; a faint tinted gradient over `.background` gives
                // depth under that glass without competing with the headline number
                // or relying on color to convey meaning (AND-513).
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(.windowBackgroundColor).opacity(0.92),
                            Color(.controlBackgroundColor).opacity(0.96),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .widgetURL(URL(string: GlanceSnapshot.deepLinkURL))
        }
        .configurationDisplayName("VaultPeek")
        .description("Glance at net worth and today's change from local VaultPeek data.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GlanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    var body: some View {
        if entry.isUnavailable {
            unavailableState
        } else {
            dataState
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .imageScale(.small)
                Text("VaultPeek")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text("Open VaultPeek")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text("Connect an account to see your net worth here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VaultPeek. Open the app and connect an account to see your net worth.")
    }

    private var dataState: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 6) {
                Image(systemName: entry.isMasked ? "eye.slash" : "lock.shield")
                    .imageScale(.small)
                Text(entry.snapshot.isDemo ? "VaultPeek Demo" : "VaultPeek")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(PrivacyMaskPresentation.currency(entry.snapshot.netWorth, format: .compact, isEnabled: entry.isMasked))
                .font(family == .systemSmall ? .system(size: 30, weight: .bold) : .system(size: 36, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .accessibilityLabel(netWorthAccessibilityLabel)

            HStack(spacing: 5) {
                if !entry.isMasked {
                    Text(entry.snapshot.changeDirection.glyph)
                        .font(.caption.weight(.bold))
                }
                Text(entry.isMasked ? PrivacyMaskPresentation.compactValue : entry.snapshot.signedChangeText)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityLabel(changeAccessibilityLabel)

            if family == .systemMedium, !entry.isMasked {
                SparklineView(values: entry.snapshot.sparkline)
                    .frame(height: 38)
                    .accessibilityLabel("Net worth sparkline")
            }

            Spacer(minLength: 0)

            Text("Updated \(entry.snapshot.updatedAt, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var netWorthAccessibilityLabel: String {
        entry.isMasked
            ? "Net worth hidden while Privacy Mask is on"
            : "Net worth \(Formatters.currency(entry.snapshot.netWorth, format: .full))"
    }

    private var changeAccessibilityLabel: String {
        entry.isMasked
            ? "Today's change hidden while Privacy Mask is on"
            : "Today's change \(entry.snapshot.changeDirection.glyph) \(entry.snapshot.signedChangeText)"
    }

    private var summaryAccessibilityLabel: String {
        let updated = " Updated \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))."
        if entry.isMasked {
            let source = entry.snapshot.isDemo ? "Demo data. " : ""
            return "\(source)Figures hidden while Privacy Mask is on." + updated
        }
        return entry.snapshot.accessibilitySummary + updated
    }
}

private struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let points = makePoints(size: proxy.size)
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func makePoints(size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        return values.enumerated().map { index, value in
            let x = width * CGFloat(index) / CGFloat(values.count - 1)
            let y = height - (height * CGFloat(min(max(value, 0), 1)))
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Control Center controls (AND-513, Epic E)
//
// macOS 26 lets users pin app controls to Control Center / the menu bar. A
// control runs in this extension, *not* the app, so it cannot mutate app state
// directly — it drops a command file in the shared App Group container and nudges
// the app, which consumes the command on activation (see `WidgetControlCommandStore`
// and the app's `consumePending*Command`). Two controls ship:
//   1. Refresh balances — a button (existing scaffold, retained).
//   2. Privacy Mask — a toggle that hides/reveals figures across the app.

struct RefreshBalancesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh balances"
    static let description = IntentDescription("Ask VaultPeek to refresh local balances.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try GlanceSnapshotStore.saveCommand(
            GlanceCommandRequest(command: .refreshBalances, requestedAt: Date())
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private struct PlaidBarRefreshControl: ControlWidget {
    let kind = "PlaidBarRefreshControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: RefreshBalancesIntent()) {
                Label("Refresh balances", systemImage: "arrow.clockwise")
            }
        }
        .displayName("Refresh balances")
        .description("Ask VaultPeek to refresh balances through the local app.")
    }
}

// MARK: - Privacy Mask toggle control

/// Sets the privacy-mask state from a Control Center toggle. Receives the desired
/// `value` (on = masked) from the system and records it as a command for the app
/// to apply. `openAppWhenRun` is intentionally **false**: hiding figures should be
/// silent and not yank the app to the foreground; the app applies the pending
/// command the next time it activates or refreshes.
struct SetPrivacyMaskIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Privacy Mask"
    static let description = IntentDescription("Hide or reveal VaultPeek figures.")

    @Parameter(title: "Privacy Mask")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        try WidgetControlCommandStore.savePrivacyCommand(
            PrivacyMaskCommandRequest(maskEnabled: value, requestedAt: Date())
        )
        // Reload the controls so the toggle reflects its new state even before the
        // app has applied the command and rewritten the snapshot.
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// Supplies the toggle's current on/off state. Reads `FinanceSnapshot.isMasked`
/// from the shared App Group snapshot (Epic D) so the control mirrors whatever
/// the app last persisted — no balances are read, only the boolean mask flag.
struct PrivacyMaskValueProvider: ControlValueProvider {
    let previewValue = false

    func currentValue() async throws -> Bool {
        AppGroupSnapshotStore.loadIfAvailable()?.isMasked ?? false
    }
}

private struct PlaidBarPrivacyMaskControl: ControlWidget {
    let kind = "PlaidBarPrivacyMaskControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: kind,
            provider: PrivacyMaskValueProvider()
        ) { isMasked in
            ControlWidgetToggle(
                "Privacy Mask",
                isOn: isMasked,
                action: SetPrivacyMaskIntent()
            ) { isOn in
                Label(
                    isOn ? "Figures hidden" : "Figures visible",
                    systemImage: isOn ? "eye.slash" : "eye"
                )
            }
            .tint(.indigo)
        }
        .displayName("Privacy Mask")
        .description("Hide or reveal VaultPeek balances from Control Center.")
    }
}

@main
struct PlaidBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaidBarGlanceWidget()
        PlaidBarRefreshControl()
        PlaidBarPrivacyMaskControl()
    }
}
