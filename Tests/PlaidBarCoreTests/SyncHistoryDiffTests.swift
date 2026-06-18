import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Sync History Diff Tests")
struct SyncHistoryDiffTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ accountId: String, daysAgo: Int, current: Double) -> AccountBalanceLedger.LedgerEntry {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return AccountBalanceLedger.LedgerEntry(
            accountId: accountId, date: date, current: current, available: nil, limit: nil, recordedAt: date
        )
    }

    private let names: [String: String] = ["a": "Chase Checking", "b": "Amex Platinum"]
    private func displayName(_ id: String) -> String? { names[id] }

    @Test("Identical previous/next ledgers yield no diff rows")
    func identicalYieldsNoRows() {
        let ledger = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 1, current: 100),
            entry("a", daysAgo: 0, current: 110),
        ])
        let rows = SyncHistoryDiff.evaluate(previousLedger: ledger, nextLedger: ledger, displayName: displayName)
        #expect(rows.isEmpty)
    }

    @Test("A rewrite of a prior-day current balance yields one row with correct signed delta and accessibility text")
    func rewriteYieldsRow() {
        let previous = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 2, current: 100),
            entry("a", daysAgo: 1, current: 105),
        ])
        let next = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 2, current: 130), // restated +30
            entry("a", daysAgo: 1, current: 105),
        ])
        let rows = SyncHistoryDiff.evaluate(previousLedger: previous, nextLedger: next, displayName: displayName)
        #expect(rows.count == 1)
        #expect(rows.first?.changedDayCount == 1)
        #expect(rows.first?.netDelta == 30)
        #expect(rows.first?.summary.contains("+") == true)
        #expect(rows.first?.accessibilityText.isEmpty == false)
    }

    @Test("A purely-additive newer day (no prior-day rewrite) yields no history-changed rows")
    func additiveDayYieldsNoRows() {
        let previous = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 1, current: 100),
        ])
        let next = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 1, current: 100), // unchanged
            entry("a", daysAgo: 0, current: 120), // brand-new day, additive
        ])
        let rows = SyncHistoryDiff.evaluate(previousLedger: previous, nextLedger: next, displayName: displayName)
        #expect(rows.isEmpty)
    }

    @Test("User-facing strings carry the account display name and never the accountId")
    func stringsUseDisplayNameNotId() {
        let previous = AccountBalanceLedger(entries: [entry("a", daysAgo: 2, current: 100)])
        let next = AccountBalanceLedger(entries: [entry("a", daysAgo: 2, current: 80)])
        let rows = SyncHistoryDiff.evaluate(previousLedger: previous, nextLedger: next, displayName: displayName)
        #expect(rows.first?.summary.contains("Chase Checking") == true)
        #expect(rows.first?.summary.contains("\"a\"") == false)
        #expect(rows.first?.accessibilityText.contains("Chase Checking") == true)
        // accountId never appears in user text.
        #expect(rows.first?.summary.contains("a|") == false)
        #expect(rows.first?.accessibilityText.lowercased().contains("accountid") == false)
    }

    @Test("Multiple rewritten days for one account accumulate into a single row")
    func multipleDaysAccumulate() {
        let previous = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 3, current: 100),
            entry("a", daysAgo: 2, current: 100),
        ])
        let next = AccountBalanceLedger(entries: [
            entry("a", daysAgo: 3, current: 110), // +10
            entry("a", daysAgo: 2, current: 95),  // -5
        ])
        let rows = SyncHistoryDiff.evaluate(previousLedger: previous, nextLedger: next, displayName: displayName)
        #expect(rows.count == 1)
        #expect(rows.first?.changedDayCount == 2)
        #expect(rows.first?.netDelta == 5) // +10 - 5
    }
}
