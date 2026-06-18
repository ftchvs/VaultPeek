import PlaidBarCore
import SwiftUI

/// Per-item connection health strip (AND-488): Connected / Reconnect-needed /
/// Provider-outage buckets. Presentation-only — all classification lives in the
/// `ConnectionHealthStrip` Core presenter. Each bucket pairs an SF Symbol with
/// text so meaning is never carried by color alone. Self-hides when there are no
/// linked items to report on.
struct ConnectionHealthStripView: View {
    @Environment(AppState.self) private var appState

    private var result: ConnectionHealthStrip.Result {
        ConnectionHealthStrip.evaluate(appState.itemStatuses)
    }

    var body: some View {
        let result = result
        if !result.buckets.isEmpty {
            HStack(spacing: Spacing.sm) {
                ForEach(result.buckets) { bucket in
                    HStack(spacing: 5) {
                        Image(systemName: bucket.iconName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(bucket.label)
                            .microText()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .help(bucket.detail)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bucket.label). \(bucket.detail)")
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .glassSurface(.inset)
        }
    }
}
