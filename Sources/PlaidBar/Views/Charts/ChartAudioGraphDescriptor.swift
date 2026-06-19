import Accessibility
import PlaidBarCore
import SwiftUI

/// Bridges a pure ``ChartAudioGraph/Descriptor`` (built + unit-tested in
/// PlaidBarCore) into the `Accessibility` framework's `AXChartDescriptor`, so
/// VoiceOver exposes the *audio graph* rotor action ("Describe Chart" → "Play
/// Audio Graph") on VaultPeek's charts (AND-569).
///
/// The descriptor is the scrubbable, tone-by-tone counterpart to each chart's
/// existing spoken `accessibilityLabel`: the same series, but the user can walk
/// it point-by-point or hear it played as pitch. Meaning never relies on color
/// (ACCESSIBILITY.md) — the audio graph conveys the series purely through pitch
/// plus the labeled numeric axes carried here.
///
/// `AX*` descriptor types are reference types and aren't `Sendable`; this struct
/// holds only the `Sendable` value model and constructs the `AX*` graph lazily
/// inside `makeChartDescriptor()`, on demand, when VoiceOver requests it.
struct ChartAudioGraphRepresentable: AXChartDescriptorRepresentable {
    let descriptor: ChartAudioGraph.Descriptor

    func makeChartDescriptor() -> AXChartDescriptor {
        let model = descriptor

        let xAxis = AXNumericDataAxisDescriptor(
            title: model.xAxis.title,
            range: model.xAxis.lowerBound ... model.xAxis.upperBound,
            gridlinePositions: []
        ) { value in
            // X is an opaque index (day / rank); the per-point label carries the
            // human-readable position, so the axis value reads as a plain number.
            String(Int(value.rounded()))
        }

        let isMasked = model.isPrivacyMasked
        let yAxis = AXNumericDataAxisDescriptor(
            title: model.yAxis.title,
            range: model.yAxis.lowerBound ... model.yAxis.upperBound,
            gridlinePositions: []
        ) { value in
            // VoiceOver speaks this while scrubbing the value axis — a third place an
            // exact amount can leak past Privacy Mask, alongside the (already-masked)
            // point labels and summary. Redact here too; pitch still conveys relative
            // magnitude (AND-569).
            ChartAudioGraph.yAxisValueDescription(value, isMasked: isMasked)
        }

        let dataPoints = model.points.map { point in
            AXDataPoint(x: point.xValue, y: point.yValue, additionalValues: [], label: point.label)
        }

        let series = AXDataSeriesDescriptor(
            name: model.seriesName,
            isContinuous: model.isContinuous,
            dataPoints: dataPoints
        )

        return AXChartDescriptor(
            title: model.title,
            summary: model.summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // The representable is rebuilt whenever the underlying value model
        // changes, so there is no incremental state to reconcile here.
    }
}

extension View {
    /// Attach a VoiceOver audio graph built from a pure
    /// ``ChartAudioGraph/Descriptor``. No-op when the descriptor has no points
    /// (nothing to sonify) so empty/loading charts don't advertise an empty
    /// audio graph (AND-569).
    @ViewBuilder
    func audioGraph(_ descriptor: ChartAudioGraph.Descriptor) -> some View {
        if descriptor.isEmpty {
            self
        } else {
            accessibilityChartDescriptor(ChartAudioGraphRepresentable(descriptor: descriptor))
        }
    }
}
