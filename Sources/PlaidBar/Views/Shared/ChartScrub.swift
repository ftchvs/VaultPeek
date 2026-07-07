import Charts
import PlaidBarCore
import SwiftUI

// MARK: - Chart scrub (design-elevation shared kit)
//
// Hover/drag interactivity for Date-x Swift Charts: a thin vertical indicator
// plus a small solid callout (date + value) that follows the pointer. The
// chart supplies its own resolver closure — the modifier never touches series
// data, so any chart (balance trend, spend trend, projections) can adopt it by
// mapping a scrubbed `Date` to its preformatted, mask-aware value string.
//
// VoiceOver: the scrub is a pointer affordance, so it is a deliberate NO-OP
// while VoiceOver runs — audio graphs (`ChartAudioGraphDescriptor`) remain the
// accessibility path for series exploration, and the selection overlay would
// only add noise. Reduce Motion: the indicator tracks the pointer with no
// animated snapping (position updates are applied without animation).

/// Wraps `chartXSelection(value:)` and renders the shared scrub indicator +
/// callout. Apply to a `Chart` whose x dimension is `Date`.
struct ChartScrub: ViewModifier {
    /// Resolves a scrubbed date to its preformatted, mask-aware value string
    /// ("$4,820.14" or "••••"); `nil` hides the callout (gap in the series).
    let valueText: (Date) -> String?
    /// Formats the callout's date line (defaults to an abbreviated date).
    var dateText: (Date) -> String = { date in
        date.formatted(date: .abbreviated, time: .omitted)
    }

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var selectedDate: Date?

    func body(content: Content) -> some View {
        if voiceOverEnabled {
            // NO-OP under VoiceOver: audio graphs are the accessibility path.
            content
        } else {
            content
                .chartXSelection(value: $selectedDate)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let selectedDate,
                           let plotAnchor = proxy.plotFrame,
                           let xPosition = proxy.position(forX: selectedDate) {
                            let plotFrame = geometry[plotAnchor]
                            let x = plotFrame.minX + xPosition
                            if plotFrame.minX ... plotFrame.maxX ~= x {
                                indicator(x: x, plotFrame: plotFrame)
                                callout(for: selectedDate, x: x, plotFrame: plotFrame)
                            }
                        }
                    }
                    // Presentation-only mirror of the pointer; the values are
                    // already on-screen in the chart itself.
                    .accessibilityHidden(true)
                    // No animated snapping — the rule tracks the pointer 1:1
                    // (also the Reduce Motion-correct behavior).
                    .animation(nil, value: selectedDate)
                }
        }
    }

    /// The thin vertical rule at the scrubbed x position.
    private func indicator(x: CGFloat, plotFrame: CGRect) -> some View {
        Rectangle()
            .fill(.secondary.opacity(0.55))
            .frame(width: 1, height: plotFrame.height)
            .position(x: x, y: plotFrame.midY)
    }

    /// The small solid callout (date + value) above the rule, clamped to stay
    /// inside the plot horizontally. Solid background, never glass — a
    /// financial figure must not sample translucency (R-08).
    @ViewBuilder
    private func callout(for date: Date, x: CGFloat, plotFrame: CGRect) -> some View {
        if let value = valueText(date) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dateText(date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.background, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Color.primary.opacity(SurfaceTokens.panelStrokeOpacity), lineWidth: 1)
            }
            .fixedSize()
            .modifier(CalloutPlacement(x: x, plotFrame: plotFrame))
        }
    }
}

/// Positions the callout above the scrub rule, clamped inside the plot frame.
private struct CalloutPlacement: ViewModifier {
    let x: CGFloat
    let plotFrame: CGRect

    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .position(
                x: min(max(x, plotFrame.minX + size.width / 2), plotFrame.maxX - size.width / 2),
                y: plotFrame.minY + size.height / 2
            )
    }
}

extension View {
    /// Shared Date-x chart scrub: vertical rule + solid callout, resolver
    /// supplied by the chart. No-op while VoiceOver runs (audio graphs are the
    /// accessibility path); no animated snapping. See ``ChartScrub``.
    func chartScrub(
        valueText: @escaping (Date) -> String?,
        dateText: @escaping (Date) -> String = { date in
            date.formatted(date: .abbreviated, time: .omitted)
        }
    ) -> some View {
        modifier(ChartScrub(valueText: valueText, dateText: dateText))
    }
}

#if canImport(PreviewsMacros)
private struct ChartScrubPreviewHost: View {
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
    }

    let points: [Point] = {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let balances: [Double] = [4820, 4770, 5010, 4950, 5240, 5180, 5420]
        return balances.enumerated().map { index, balance in
            Point(date: start.addingTimeInterval(Double(index) * 86_400), balance: balance)
        }
    }()

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Balance", point.balance)
            )
            .foregroundStyle(SemanticColors.sparkline)
        }
        .chartScrub { date in
            points
                .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                .map { $0.balance.formatted(.currency(code: "USD")) }
        }
        .frame(width: 480, height: 200)
        .padding(Spacing.lg)
    }
}

#Preview("Chart scrub") {
    ChartScrubPreviewHost()
}

#Preview("Chart scrub — dark") {
    ChartScrubPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
