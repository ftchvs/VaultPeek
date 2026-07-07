import Foundation
import Testing
@testable import PlaidBarCore

@Suite("MetricDeltaChip composition")
struct MetricDeltaChipTests {
    private static var spendUp: MetricDelta {
        MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .lowerIsBetter)
    }

    private static var incomeDown: MetricDelta {
        MetricDelta.evaluate(current: 4_500, previous: 5_000, polarity: .higherIsBetter)
    }

    private static var flat: MetricDelta {
        MetricDelta.evaluate(current: 3_000, previous: 3_000, polarity: .lowerIsBetter)
    }

    // MARK: - Privacy Mask contract

    @Test("isMasked suppresses the chip entirely — never a bare arrow")
    func maskedReturnsNil() {
        #expect(MetricDeltaChip.make(
            delta: Self.spendUp, comparisonLabel: "vs last month", isMasked: true
        ) == nil)
        // Masking wins over every other knob, including showsFlat.
        #expect(MetricDeltaChip.make(
            delta: Self.flat, comparisonLabel: "vs last month", showsFlat: true, isMasked: true
        ) == nil)
    }

    // MARK: - Flat handling

    @Test("Flat deltas are hidden by default and shown only on request")
    func flatHiddenUnlessRequested() {
        #expect(MetricDeltaChip.make(
            delta: Self.flat, comparisonLabel: "vs last month", isMasked: false
        ) == nil)

        let chip = MetricDeltaChip.make(
            delta: Self.flat, comparisonLabel: "vs last month", showsFlat: true, isMasked: false
        )!
        #expect(chip.glyph == "■")
        #expect(chip.text == "Unchanged vs last month")
        #expect(chip.sentiment == .neutral)
        #expect(chip.accessibilityLabel == "Unchanged versus last month")
    }

    // MARK: - Composition

    @Test("Currency chip composes glyph, signed text, and comparison label")
    func currencyComposition() {
        let chip = MetricDeltaChip.make(
            delta: Self.spendUp, comparisonLabel: "vs last month", isMasked: false
        )!
        #expect(chip.glyph == "▲")
        #expect(chip.text == "+$420 vs last month")
        // Spend rising reads negative even though the arrow points up.
        #expect(chip.sentiment == .negative)
        #expect(chip.accessibilityLabel == "Up 420 dollars versus last month")
    }

    @Test("Downward chip carries the minus sign and Down wording")
    func downComposition() {
        let chip = MetricDeltaChip.make(
            delta: Self.incomeDown, comparisonLabel: "vs last month to date", isMasked: false
        )!
        #expect(chip.glyph == "▼")
        #expect(chip.text == "-$500 vs last month to date")
        #expect(chip.sentiment == .negative)
        #expect(chip.accessibilityLabel == "Down 500 dollars versus last month to date")
    }

    @Test("Percent and combined styles render the honest percent")
    func percentStyles() {
        let percent = MetricDeltaChip.make(
            delta: Self.spendUp, comparisonLabel: "vs last month", style: .percent, isMasked: false
        )!
        #expect(percent.text == "+14% vs last month")
        #expect(percent.accessibilityLabel == "Up 14 percent versus last month")

        let both = MetricDeltaChip.make(
            delta: Self.spendUp, comparisonLabel: "vs last month", style: .currencyAndPercent, isMasked: false
        )!
        #expect(both.text == "+$420 (+14%) vs last month")
        #expect(both.accessibilityLabel == "Up 420 dollars, 14 percent versus last month")
    }

    @Test("Percent styles fall back to currency when no honest percent exists")
    func percentFallback() {
        // Near-zero baseline: percentChange is nil, so no fake percent is shown.
        let delta = MetricDelta.evaluate(current: 480, previous: 0, polarity: .higherIsBetter)
        let chip = MetricDeltaChip.make(
            delta: delta, comparisonLabel: "vs last month", style: .currencyAndPercent, isMasked: false
        )!
        #expect(chip.text == "+$480 vs last month")
        #expect(chip.accessibilityLabel == "Up 480 dollars versus last month")
    }

    @Test("Chip text uses the requested currency format byte-for-byte")
    func formatDelegation() {
        let chip = MetricDeltaChip.make(
            delta: Self.spendUp, comparisonLabel: "vs last month", format: .full, isMasked: false
        )!
        #expect(chip.text == "\(Formatters.signedCurrency(420, format: .full)) vs last month")
    }
}
