import Charts
import PlaidBarCore
import SwiftUI

/// Forward cash-flow forecast (AND-498): the projected balance over the next
/// 30–90 days drawn as a dashed line (distinct from the solid recorded trend),
/// with a "today" rule, a projected-low marker, and a confidence cue. Uncertainty
/// is shown through the dash + text + marker, never color alone (ACCESSIBILITY.md).
struct ProjectedBalanceChart: View {
    let projection: BalanceProjection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealFraction: CGFloat = 0

    private var anchorDate: Date { projection.series.first?.date ?? projection.projectedLow.date }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Chart {
                ForEach(projection.series, id: \.date) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Projected balance", snapshot.balance),
                        series: .value("Series", "projected")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.secondary)
                    // Dashed = forecast, distinguishing it from the solid recorded
                    // trend without relying on color.
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                }

                // "Today" anchor rule.
                RuleMark(x: .value("Today", anchorDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Today")
                            .microText()
                            .foregroundStyle(.secondary)
                    }

                // Projected-low marker + labeled annotation.
                PointMark(
                    x: .value("Low date", projection.projectedLow.date),
                    y: .value("Low balance", projection.projectedLow.balance)
                )
                .symbol(.circle)
                .symbolSize(40)
                .foregroundStyle(lowTint)
                .annotation(position: .bottom, alignment: .center) {
                    Label(
                        Formatters.currency(projection.projectedLow.balance, format: .compact),
                        systemImage: "arrow.down.to.line"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(lowTint)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 88)
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
            // Scrubbable audio graph (AND-569/AND-588): the analogue of the spoken
            // `accessibilitySummary` below — VoiceOver's "Play Audio Graph" rotor
            // plays the projected balance tone-by-tone, with the projected-low day
            // called out. No-op when the series has too few points to sonify.
            .audioGraph(ChartAudioGraph.projection(projection))

            // Confidence cue: text + icon, never color alone.
            Label(confidenceText, systemImage: projection.confidence.iconName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(projection.accessibilitySummary)
    }

    private var lowTint: Color {
        // The projected low dipping below the anchor is the cautionary case.
        projection.projectedLow.balance < projection.anchorBalance
            ? SemanticColors.warning
            : .secondary
    }

    private var confidenceText: String {
        switch projection.confidence {
        case .insufficientData: "Indicative only — no recurring signal yet"
        case .lowConfidence: "Forecast from recurring patterns"
        case .ok: "Forecast"
        }
    }
}
