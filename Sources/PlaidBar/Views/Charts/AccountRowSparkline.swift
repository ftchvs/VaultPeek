import Charts
import PlaidBarCore
import SwiftUI

/// Inline glance sparkline for a dashboard account row (AND-379). Renders a
/// normalized `AccountSparkline.Series` as a hidden-axis line tinted by trend
/// direction, sized to fit the row's trailing cluster ahead of the chevron
/// without changing row height.
///
/// It renders **complete**, with no reveal animation. Unlike the always-present
/// net-worth header chart (`BalanceTrendChart`), this view is one-per-row inside
/// a scrollable, filterable account list, so a per-appearance mask reveal would
/// replay every time a row is re-realized on scroll or a filter toggle — visual
/// noise that works against the "calm glance" intent. Rendering complete also
/// makes it trivially correct under Reduce Motion (there is simply no motion).
///
/// The sparkline is decorative: the row already announces the balance and the
/// trailing delta carries direction in text, so it is hidden from VoiceOver by
/// its caller; the color is a supplementary cue, never the sole one.
struct AccountRowSparkline: View {
    let series: AccountSparkline.Series

    /// Tuned to the account-row density: wide enough to read a shape, short
    /// enough to keep the row at its existing height.
    static let width: CGFloat = 54
    static let height: CGFloat = 16

    var body: some View {
        Chart(series.indexedPoints, id: \.x) { point in
            LineMark(
                x: .value("Point", point.x),
                y: .value("Balance", point.y)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Normalized data lives in 0...1; pad the domain slightly so a flat
        // mid-line and the rounded line caps are not clipped at the edges.
        .chartYScale(domain: -0.15 ... 1.15)
        .frame(width: Self.width, height: Self.height)
    }

    private var tint: Color {
        switch series.direction {
        case .up:
            SemanticColors.positive
        case .down:
            SemanticColors.negative
        case .flat:
            .secondary
        }
    }
}
