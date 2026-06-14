import AppIntents
import PlaidBarCore
import SwiftUI
import WidgetKit

private struct GlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GlanceSnapshot
}

private struct GlanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let current = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: current.date) ?? current.date
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> GlanceEntry {
        let snapshot = (try? GlanceSnapshotStore.load()) ?? .placeholder()
        return GlanceEntry(date: snapshot.updatedAt, snapshot: snapshot)
    }
}

private struct PlaidBarGlanceWidget: Widget {
    let kind = "PlaidBarGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceTimelineProvider()) { entry in
            GlanceWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
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
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .imageScale(.small)
                Text(entry.snapshot.isDemo ? "VaultPeek Demo" : "VaultPeek")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(Formatters.currency(entry.snapshot.netWorth, format: .compact))
                .font(family == .systemSmall ? .system(size: 30, weight: .bold) : .system(size: 36, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .accessibilityLabel("Net worth \(Formatters.currency(entry.snapshot.netWorth, format: .full))")

            HStack(spacing: 5) {
                Text(entry.snapshot.changeDirection.glyph)
                    .font(.caption.weight(.bold))
                Text(entry.snapshot.signedChangeText)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityLabel("Today's change \(entry.snapshot.changeDirection.glyph) \(entry.snapshot.signedChangeText)")

            if family == .systemMedium {
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
        .accessibilityLabel(entry.snapshot.accessibilitySummary + " Updated \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened)).")
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

@available(macOS 15.0, *)
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

@available(macOS 26.0, *)
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

@main
struct PlaidBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaidBarGlanceWidget()
        if #available(macOS 26.0, *) {
            PlaidBarRefreshControl()
        }
    }
}
