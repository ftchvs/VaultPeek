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
        // Built once per view identity. `update` re-derives from the same model.
        AXChartDescriptor(
            title: descriptor.title,
            summary: descriptor.summary,
            xAxis: makeXAxis(from: descriptor),
            yAxis: makeYAxis(from: descriptor),
            additionalAxes: [],
            series: [makeSeries(from: descriptor)]
        )
    }

    func updateChartDescriptor(_ axDescriptor: AXChartDescriptor) {
        // CRITICAL (AND-569 follow-up): `make` runs only once per view identity,
        // so when inputs change WITHOUT a new identity — most importantly when
        // Privacy Mask / App Lock toggles ON while a chart is on screen, or when
        // data refreshes — VoiceOver keeps reading the descriptor built here. If
        // this stayed a no-op, a descriptor built while UNMASKED would keep
        // announcing exact amounts (point labels, summary, value axis) after
        // masking engaged. `self.descriptor` is the current, masked-or-not value
        // model (the representable is reconstructed each render), so re-derive
        // every field from it — through the SAME builders `make` uses, so
        // build-time and update-time masking cannot diverge.
        axDescriptor.title = descriptor.title
        axDescriptor.summary = descriptor.summary
        axDescriptor.xAxis = makeXAxis(from: descriptor)
        axDescriptor.yAxis = makeYAxis(from: descriptor)
        axDescriptor.series = [makeSeries(from: descriptor)]
    }

    // MARK: - Translation (single path shared by make + update)

    private func makeXAxis(from model: ChartAudioGraph.Descriptor) -> AXNumericDataAxisDescriptor {
        AXNumericDataAxisDescriptor(
            title: model.xAxis.title,
            range: model.xAxis.lowerBound ... model.xAxis.upperBound,
            gridlinePositions: []
        ) { value in
            // X is an opaque index (day / rank); the per-point label carries the
            // human-readable position, so the axis value reads as a plain number.
            String(Int(value.rounded()))
        }
    }

    private func makeYAxis(from model: ChartAudioGraph.Descriptor) -> AXNumericDataAxisDescriptor {
        let isMasked = model.isPrivacyMasked
        return AXNumericDataAxisDescriptor(
            title: model.yAxis.title,
            range: model.yAxis.lowerBound ... model.yAxis.upperBound,
            gridlinePositions: []
        ) { value in
            // VoiceOver speaks this while scrubbing the value axis — a third place an
            // exact amount can leak past Privacy Mask, alongside the (already-masked)
            // point labels and summary. Redact here too; pitch still conveys relative
            // magnitude (AND-569). `isMasked` is captured from the CURRENT model, so a
            // post-toggle `update` installs a closure that redacts.
            ChartAudioGraph.yAxisValueDescription(value, isMasked: isMasked)
        }
    }

    private func makeSeries(from model: ChartAudioGraph.Descriptor) -> AXDataSeriesDescriptor {
        let dataPoints = model.points.map { point in
            AXDataPoint(x: point.xValue, y: point.yValue, additionalValues: [], label: point.label)
        }
        return AXDataSeriesDescriptor(
            name: model.seriesName,
            isContinuous: model.isContinuous,
            dataPoints: dataPoints
        )
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
