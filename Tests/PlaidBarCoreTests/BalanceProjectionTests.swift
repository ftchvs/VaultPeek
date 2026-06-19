import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Balance projection value type (AND-498)")
struct BalanceProjectionTests {
    private func snap(_ day: Int, _ balance: Double) -> BalanceSnapshot {
        BalanceSnapshot(date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), balance: balance)
    }

    @Test("anchorBalance is the first snapshot; endBalance is the last")
    func anchorAndEndFromSeries() {
        let projection = BalanceProjection(
            series: [snap(0, 1_000), snap(1, 800), snap(2, 600)],
            projectedLow: snap(2, 600),
            confidence: .lowConfidence,
            accessibilitySummary: "summary"
        )
        #expect(projection.anchorBalance == 1_000)
        #expect(projection.endBalance == 600)
    }

    @Test("Empty series falls back to the projected low for both anchor and end")
    func emptySeriesFallsBackToLow() {
        let low = snap(5, 42)
        let projection = BalanceProjection(
            series: [],
            projectedLow: low,
            confidence: .insufficientData,
            accessibilitySummary: "summary"
        )
        #expect(projection.anchorBalance == 42)
        #expect(projection.endBalance == 42)
    }

    @Test("Single-element series uses it for both anchor and end")
    func singleElementSeries() {
        let only = snap(0, 250)
        let projection = BalanceProjection(
            series: [only],
            projectedLow: only,
            confidence: .ok,
            accessibilitySummary: "summary"
        )
        #expect(projection.anchorBalance == 250)
        #expect(projection.endBalance == 250)
    }
}
