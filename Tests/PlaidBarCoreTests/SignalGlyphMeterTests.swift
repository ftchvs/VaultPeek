import Foundation
import Testing
@testable import PlaidBarCore

@Suite("SignalGlyphMeter (AND-485)")
struct SignalGlyphMeterTests {

    @Test("Magnitude maps proportionally to fill, clamped at the ends")
    func magnitudeMapsToFill() {
        #expect(SignalGlyphMeter.bar(magnitude: 0).fillFraction == 0)
        #expect(SignalGlyphMeter.bar(magnitude: 1).fillFraction == 1)
        #expect(abs(SignalGlyphMeter.bar(magnitude: 0.5).fillFraction - 0.5) < 0.0001)
        // Over-range (e.g. over-limit card) clamps to full fill.
        #expect(SignalGlyphMeter.bar(magnitude: 1.4).fillFraction == 1)
        // Negative clamps to empty.
        #expect(SignalGlyphMeter.bar(magnitude: -0.3).fillFraction == 0)
    }

    @Test("Severity band changes by value, not color")
    func severityBandByValue() {
        let calm = SignalGlyphMeter.bar(magnitude: 0.4, threshold: 0.6)
        #expect(calm.severity == .calm)
        let over = SignalGlyphMeter.bar(magnitude: 0.7, threshold: 0.6)
        #expect(over.severity == .overThreshold)
        // Exactly at threshold counts as over.
        let atThreshold = SignalGlyphMeter.bar(magnitude: 0.6, threshold: 0.6)
        #expect(atThreshold.severity == .overThreshold)
        // No threshold provided stays calm.
        #expect(SignalGlyphMeter.bar(magnitude: 0.99).severity == .calm)
    }

    @Test("isStale flips the staleness hint regardless of magnitude")
    func staleFlipsHint() {
        #expect(SignalGlyphMeter.bar(magnitude: 0.1, isStale: true).staleness == .stale)
        #expect(SignalGlyphMeter.bar(magnitude: 0.9, isStale: true).staleness == .stale)
        #expect(SignalGlyphMeter.bar(magnitude: 0.5, isStale: false).staleness == .fresh)
    }

    @Test("Flat or empty balance history yields a defined mid-line, never NaN")
    func flatSeriesIsDefined() {
        let flat = SignalGlyphMeter.sparkline(balances: [100, 100, 100, 100])
        #expect(!flat.isEmpty)
        #expect(flat.fillFraction.isFinite)
        // Flat series collapses to the mid-line.
        #expect(flat.polyline.allSatisfy { $0 == 0.5 })

        let empty = SignalGlyphMeter.sparkline(balances: [])
        #expect(empty.isEmpty)
    }

    @Test("Sparkline downsamples while keeping endpoints and stays in 0...1")
    func sparklineDownsamples() {
        let rising = (0 ..< 50).map { Double($0) }
        let model = SignalGlyphMeter.sparkline(balances: rising, maxPoints: 8)
        #expect(model.polyline.count <= 8)
        #expect(model.polyline.first == 0) // lowest normalizes to 0
        #expect(model.polyline.last == 1)  // highest normalizes to 1
        #expect(model.polyline.allSatisfy { $0 >= 0 && $0 <= 1 })
        // The trailing point doubles as the bar fill.
        #expect(model.fillFraction == 1)
    }

    @Test("Utilization path tracks the worst single card, not the pooled aggregate")
    func utilizationMatchesSummary() {
        // Amex: 1000/10000 = 10%; Visa: 2000/5000 = 40%. Pooled aggregate is
        // 3000/15000 = 20% (calm), but the meter must surface the worst card
        // (40%, over the 30% threshold) — otherwise a near-maxed card hides
        // behind a large-limit one (Codex #499, AND-485).
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -1_000, limit: 10_000)),
            AccountDTO(id: "3", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -2_000, limit: 5_000)),
        ]
        let pooledPercent = MenuBarSummary.creditUtilization(from: accounts) ?? 0 // 20%
        let highestPercent = MenuBarSummary.highestUtilization(from: accounts) ?? 0 // 40%
        let model = SignalGlyphMeter.utilization(from: accounts, thresholdPercent: 30)
        // The meter follows the highest card, not the calmer pooled aggregate.
        #expect(abs(model.fillFraction - highestPercent / 100) < 0.0001)
        #expect(abs(model.fillFraction - pooledPercent / 100) > 0.0001)
        #expect(model.severity == .overThreshold) // 40% >= 30% threshold

        // Over-limit single card clamps to a full bar.
        let overLimit = [
            AccountDTO(id: "4", itemId: "i", name: "Maxed", type: .credit, balances: BalanceDTO(current: -12_000, limit: 10_000)),
        ]
        let overModel = SignalGlyphMeter.utilization(from: overLimit, thresholdPercent: 30)
        #expect(overModel.fillFraction == 1)
        #expect(overModel.severity == .overThreshold)
    }

    @Test("Accessibility description conveys value, threshold, and staleness in words")
    func accessibilityDescriptionIsWordOnly() {
        // Empty model announces nothing.
        #expect(SignalGlyphMeter.SignalGlyphRenderModel.empty.accessibilityDescription == nil)

        // Calm, fresh: just the rounded percent.
        let calm = SignalGlyphMeter.bar(magnitude: 0.4, threshold: 0.6)
        #expect(calm.accessibilityDescription == "Signal meter 40 percent")

        // Over-threshold and stale both surface as words, never color.
        let over = SignalGlyphMeter.bar(magnitude: 0.75, threshold: 0.6, isStale: true)
        #expect(over.accessibilityDescription == "Signal meter 75 percent, over threshold, stale")
    }

    @Test("No-credit input degrades to the empty no-meter model, never crashes")
    func noCreditDegradesToEmpty() {
        let cashOnly = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
        ]
        let model = SignalGlyphMeter.utilization(from: cashOnly, thresholdPercent: 30)
        #expect(model.isEmpty)
        #expect(model == SignalGlyphMeter.SignalGlyphRenderModel.empty)
    }
}
