import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Recurring detector helpers")
struct RecurringDetectorHelpersTests {
    private func tx(_ id: String, date: String) -> TransactionDTO {
        TransactionDTO(
            id: id, accountId: "x", amount: 10, date: date,
            name: id, merchantName: id, category: .subscriptions, pending: false
        )
    }

    @Test("computeIntervals derives day gaps from a transaction sequence")
    func computeIntervalsFromTransactions() {
        let intervals = RecurringDetector.computeIntervals([
            tx("a", date: "2026-01-01"),
            tx("b", date: "2026-01-08"),
            tx("c", date: "2026-01-15"),
        ])
        #expect(intervals.count == 2)
        // Tolerance keeps the assertion robust across DST/timezone boundaries.
        #expect(intervals.allSatisfy { abs($0 - 7) < 0.1 })
    }

    @Test("computeNextDate steps forward by the detected frequency")
    func computeNextDate() {
        #expect(RecurringDetector.computeNextDate(from: "2026-01-15", frequency: .weekly) == "2026-01-22")
        #expect(RecurringDetector.computeNextDate(from: "2026-01-15", frequency: .biweekly) == "2026-01-29")
        #expect(RecurringDetector.computeNextDate(from: "2026-01-15", frequency: .monthly) == "2026-02-15")
        #expect(RecurringDetector.computeNextDate(from: "2026-01-15", frequency: .quarterly) == "2026-04-15")
        #expect(RecurringDetector.computeNextDate(from: "2026-01-15", frequency: .annual) == "2027-01-15")
    }

    @Test("computeNextDate returns the input verbatim when the date is unparseable")
    func computeNextDateUnparseable() {
        #expect(RecurringDetector.computeNextDate(from: "not-a-date", frequency: .monthly) == "not-a-date")
    }

    @Test("classifyFrequency maps median day intervals to a cadence")
    func classifyFrequency() {
        #expect(RecurringDetector.classifyFrequency(medianInterval: 7) == .weekly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 14) == .biweekly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 30) == .monthly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 90) == .quarterly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 365) == .annual)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 3) == nil)
    }

    @Test("median handles odd, even, and empty inputs")
    func median() {
        #expect(RecurringDetector.median([3, 1, 2]) == 2)
        #expect(RecurringDetector.median([1, 2, 3, 4]) == 2.5)
        #expect(RecurringDetector.median([]) == 0)
    }
}
