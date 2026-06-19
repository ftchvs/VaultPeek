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

    @Test("Row id uses the zero-padded stable-hash format (call-site regression guard)")
    func rowIdUsesPaddedStableHash() {
        // "k0" hashes to a value with a leading-zero nibble, so the padded form
        // (08be…) differs from the unpadded form (8be…). This pins the row id to
        // StableHash.hexPadded so a future swap to .hex — which would orphan
        // existing identifiers — is caught here, at the call site.
        let previous = AccountBalanceLedger(entries: [
            entry("k0", daysAgo: 2, current: 100),
            entry("k0", daysAgo: 1, current: 105),
        ])
        let next = AccountBalanceLedger(entries: [
            entry("k0", daysAgo: 2, current: 130),
            entry("k0", daysAgo: 1, current: 105),
        ])
        let rows = SyncHistoryDiff.evaluate(previousLedger: previous, nextLedger: next, displayName: displayName)
        #expect(rows.first?.id == "08be0e07b562230e")
        #expect(rows.first?.id == StableHash.hexPadded("k0"))
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

    @Test("A same-day balance change (today's in-place replacement) is not flagged as a prior-day restatement")
    func currentDayMovementYieldsNoRows() {
        // Both ledgers carry an entry for `now` (the current sync day) with a
        // different balance — an ordinary intraday refresh, not history rewrite.
        let previous = AccountBalanceLedger(entries: [entry("a", daysAgo: 0, current: 100)])
        let next = AccountBalanceLedger(entries: [entry("a", daysAgo: 0, current: 140)])
        let rows = SyncHistoryDiff.evaluate(
            previousLedger: previous, nextLedger: next, now: now, displayName: displayName
        )
        #expect(rows.isEmpty)
    }

    @Test("A prior nil balance later restated to a value still produces a history-changed row")
    func nilPriorBalanceRestatementYieldsRow() {
        let priorNil = AccountBalanceLedger.LedgerEntry(
            accountId: "a",
            date: calendar.date(byAdding: .day, value: -2, to: now)!,
            current: nil, available: nil, limit: nil,
            recordedAt: calendar.date(byAdding: .day, value: -2, to: now)!
        )
        let previous = AccountBalanceLedger(entries: [priorNil])
        let next = AccountBalanceLedger(entries: [entry("a", daysAgo: 2, current: 50)])
        let rows = SyncHistoryDiff.evaluate(
            previousLedger: previous, nextLedger: next, now: now, displayName: displayName
        )
        // nil -> 50 is a restatement of an already-recorded prior day, not a new day.
        #expect(rows.count == 1)
        #expect(rows.first?.changedDayCount == 1)
        #expect(rows.first?.netDelta == 50)
    }

    @Test("maskCurrencyTokens replaces signed currency tokens in prose when enabled, no-op when disabled")
    func maskCurrencyTokensMasksDeltas() {
        let summary = "Chase Checking: 2 prior days restated (-$1,234.56)"
        let masked = SyncHistoryDiff.maskCurrencyTokens(in: summary, isEnabled: true)
        #expect(masked == "Chase Checking: 2 prior days restated (\(PrivacyMaskPresentation.compactValue))")
        #expect(!masked.contains("1,234"))
        // Disabled is a pure pass-through.
        #expect(SyncHistoryDiff.maskCurrencyTokens(in: summary, isEnabled: false) == summary)
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
