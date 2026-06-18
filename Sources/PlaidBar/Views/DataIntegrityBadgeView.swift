import PlaidBarCore
import SwiftUI

/// Lightweight presentation-only badge for the stale/partial data verdict
/// (AND-489). Pairs an SF Symbol with text so meaning is never carried by color
/// alone. All decision logic lives in `DataIntegrityBadge` (Core).
struct DataIntegrityBadgeView: View {
    let result: DataIntegrityBadge.Result

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: result.iconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(result.title)
                .microText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(result.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.accessibilityLabel)
    }
}
