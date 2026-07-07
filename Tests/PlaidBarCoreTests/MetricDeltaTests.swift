import Foundation
import Testing
@testable import PlaidBarCore

@Suite("MetricDelta classification")
struct MetricDeltaTests {
    // MARK: - Threshold matrix

    @Test("+$2 on an $800 baseline is flat via the relative gate")
    func smallRelativeChangeIsFlat() {
        let delta = MetricDelta.evaluate(current: 802, previous: 800, polarity: .lowerIsBetter)
        // Clears the $1 absolute gate but not the 1% relative gate (needs $8).
        #expect(delta.direction == .flat)
        #expect(delta.delta == 2)
        #expect(delta.sentiment == .neutral)
    }

    @Test("+$0.60 is flat via the absolute gate even when relatively large")
    func smallAbsoluteChangeIsFlat() {
        // On a $10 baseline, $0.60 is 6% (clears relative) but under the $1
        // absolute gate.
        let delta = MetricDelta.evaluate(current: 10.6, previous: 10, polarity: .lowerIsBetter)
        #expect(delta.direction == .flat)
    }

    @Test("+$420 on a $3,000 baseline clears both gates and reads up")
    func significantChangeIsUp() {
        let delta = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .lowerIsBetter)
        #expect(delta.direction == .up)
        #expect(delta.delta == 420)
        #expect(abs((delta.percentChange ?? 0) - 14) < 0.000_1)
    }

    @Test("Down movement clears the gates symmetrically")
    func significantDropIsDown() {
        let delta = MetricDelta.evaluate(current: 2_580, previous: 3_000, polarity: .lowerIsBetter)
        #expect(delta.direction == .down)
        #expect(delta.delta == -420)
        #expect(abs((delta.percentChange ?? 0) + 14) < 0.000_1)
    }

    @Test("Both thresholds must clear — stricter than BalanceTrend's ±0.005")
    func stricterThanBalanceTrend() {
        // A one-cent move would be `.up` under BalanceTrend's raw-movement
        // gate; MetricDelta calls it flat because it is not chip-worthy.
        let delta = MetricDelta.evaluate(current: 800.01, previous: 800, polarity: .neutral)
        #expect(delta.direction == .flat)
    }

    // MARK: - Percent honesty

    @Test("percentChange is nil when the previous magnitude is near zero")
    func percentNilOnTinyBaseline() {
        let delta = MetricDelta.evaluate(current: 480, previous: 0.4, polarity: .higherIsBetter)
        // No fake "+119,900%" — the baseline is below the absolute gate.
        #expect(delta.percentChange == nil)
        #expect(delta.percentText() == nil)
        // The movement itself still registers (relative gate is waived).
        #expect(delta.direction == .up)
    }

    @Test("percentChange is nil on an exactly-zero baseline")
    func percentNilOnZeroBaseline() {
        let delta = MetricDelta.evaluate(current: 100, previous: 0, polarity: .higherIsBetter)
        #expect(delta.percentChange == nil)
        #expect(delta.direction == .up)
    }

    @Test("percentText carries an explicit sign in both directions")
    func percentTextSigned() {
        let up = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .neutral)
        #expect(up.percentText() == "+14%")
        let down = MetricDelta.evaluate(current: 2_580, previous: 3_000, polarity: .neutral)
        #expect(down.percentText() == "-14%")
    }

    // MARK: - Sentiment = direction × polarity

    @Test("Spend rising is negative; spend falling is positive")
    func lowerIsBetterSentiment() {
        let up = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .lowerIsBetter)
        #expect(up.sentiment == .negative)
        let down = MetricDelta.evaluate(current: 2_580, previous: 3_000, polarity: .lowerIsBetter)
        #expect(down.sentiment == .positive)
    }

    @Test("Income rising is positive; income falling is negative")
    func higherIsBetterSentiment() {
        let up = MetricDelta.evaluate(current: 5_500, previous: 5_000, polarity: .higherIsBetter)
        #expect(up.sentiment == .positive)
        let down = MetricDelta.evaluate(current: 4_500, previous: 5_000, polarity: .higherIsBetter)
        #expect(down.sentiment == .negative)
    }

    @Test("Neutral polarity and flat direction are always neutral")
    func neutralSentiment() {
        let neutral = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .neutral)
        #expect(neutral.sentiment == .neutral)
        let flat = MetricDelta.evaluate(current: 3_000, previous: 3_000, polarity: .lowerIsBetter)
        #expect(flat.direction == .flat)
        #expect(flat.sentiment == .neutral)
    }

    // MARK: - Text delegation

    @Test("signedText byte-matches Formatters.signedCurrency")
    func signedTextMatchesFormatter() {
        let up = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .neutral)
        #expect(up.signedText(format: .compact) == Formatters.signedCurrency(420, format: .compact))
        #expect(up.signedText(format: .full) == Formatters.signedCurrency(420, format: .full))
        let down = MetricDelta.evaluate(current: 2_580, previous: 3_000, polarity: .neutral)
        #expect(down.signedText(format: .compact) == Formatters.signedCurrency(-420, format: .compact))
    }

    @Test("Glyphs match the GlanceSnapshot.ChangeDirection convention")
    func glyphConvention() {
        let up = MetricDelta.evaluate(current: 3_420, previous: 3_000, polarity: .neutral)
        #expect(up.glyph == GlanceSnapshot.ChangeDirection.up.glyph)
        let flat = MetricDelta.evaluate(current: 3_000, previous: 3_000, polarity: .neutral)
        #expect(flat.glyph == GlanceSnapshot.ChangeDirection.flat.glyph)
    }
}
