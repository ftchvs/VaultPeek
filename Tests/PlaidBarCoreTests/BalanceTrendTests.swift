import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Balance trend display values")
struct BalanceTrendTests {
    private func snap(_ balance: Double) -> BalanceSnapshot {
        BalanceSnapshot(date: Date(timeIntervalSince1970: 0), balance: balance)
    }

    @Test("Chart baseline is the minimum point balance, or zero when empty")
    func chartBaseline() {
        let trend = BalanceTrend(direction: .up, delta: 50, spanDays: 5, points: [snap(100), snap(50), snap(120)])
        #expect(trend.chartBaseline == 50)
        #expect(BalanceTrend(direction: .flat, delta: 0, spanDays: 1, points: []).chartBaseline == 0)
    }

    @Test("Delta text signs the magnitude by direction")
    func deltaText() {
        #expect(BalanceTrend(direction: .up, delta: 1_200, spanDays: 5, points: []).deltaText.hasPrefix("+"))
        #expect(BalanceTrend(direction: .down, delta: -300, spanDays: 5, points: []).deltaText.hasPrefix("-"))
        let flat = BalanceTrend(direction: .flat, delta: 0, spanDays: 5, points: []).deltaText
        #expect(!flat.hasPrefix("+"))
        #expect(!flat.hasPrefix("-"))
    }

    @Test("Span text is a compact day count")
    func spanText() {
        #expect(BalanceTrend(direction: .up, delta: 1, spanDays: 30, points: []).spanText == "30D")
    }

    @Test("Accessibility summary states direction and pluralizes the span")
    func accessibilitySummary() {
        #expect(BalanceTrend(direction: .up, delta: 100, spanDays: 5, points: []).accessibilitySummary.contains("up"))
        #expect(BalanceTrend(direction: .down, delta: -100, spanDays: 5, points: []).accessibilitySummary.contains("down"))
        let flat = BalanceTrend(direction: .flat, delta: 0, spanDays: 5, points: [])
        #expect(flat.accessibilitySummary.contains("unchanged"))
        #expect(flat.accessibilitySummary.contains("5 days"))
        #expect(BalanceTrend(direction: .up, delta: 100, spanDays: 1, points: []).accessibilitySummary.contains("1 day."))
    }
}
