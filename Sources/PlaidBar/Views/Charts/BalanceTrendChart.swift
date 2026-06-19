import Charts
import PlaidBarCore
import SwiftUI

/// Quiet header sparkline for recorded net-worth history. The line draws in
/// left-to-right once per appearance; direction color is reinforced by the
/// signed delta text rendered next to it, so meaning never relies on color
/// alone. Axes, legend, and grid stay hidden: this is a glance, not a chart.
struct BalanceTrendChart: View {
    let trend: BalanceTrend

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealFraction: CGFloat = 0

    var body: some View {
        Chart(trend.points, id: \.date) { snapshot in
            AreaMark(
                x: .value("Date", snapshot.date),
                yStart: .value("Baseline", trend.chartBaseline),
                yEnd: .value("Net worth", snapshot.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(areaGradient)

            LineMark(
                x: .value("Date", snapshot.date),
                y: .value("Net worth", snapshot.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .mask(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .frame(width: proxy.size.width * revealFraction)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                revealFraction = 1
                return
            }
            revealFraction = 0
            withAnimation(MotionTokens.chartReveal.delay(0.1)) {
                revealFraction = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trend.accessibilitySummary)
        // VoiceOver audio graph: scrub the net-worth series tone-by-tone (AND-569).
        .audioGraph(ChartAudioGraph.trend(trend))
    }

    private var tint: Color {
        switch trend.direction {
        case .up:
            SemanticColors.positive
        case .down:
            SemanticColors.negative
        case .flat:
            .secondary
        }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.22),
                tint.opacity(0.035),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
