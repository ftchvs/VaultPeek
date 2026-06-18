import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Account Balance Ledger Tests")
struct AccountBalanceLedgerTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func account(_ id: String, current: Double, available: Double? = nil, limit: Double? = nil) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: "item-\(id)",
            name: id.capitalized,
            type: .depository,
            balances: BalanceDTO(available: available, current: current, limit: limit, isoCurrencyCode: "USD")
        )
    }

    @Test("Appending the same account twice on the same day replaces (no duplicate per account/day)")
    func sameDayReplaces() {
        let first = AccountBalanceLedger().appending(
            accounts: [account("a", current: 100)], now: now, calendar: calendar
        )
        let second = first.appending(
            accounts: [account("a", current: 150)], now: now, calendar: calendar
        )
        let aEntries = second.entries.filter { $0.accountId == "a" }
        #expect(aEntries.count == 1)
        #expect(aEntries.first?.current == 150)
    }

    @Test("Entries older than the retention window are pruned")
    func retentionPrune() {
        let oldDate = calendar.date(byAdding: .day, value: -120, to: now)!
        let seeded = AccountBalanceLedger(entries: [
            AccountBalanceLedger.LedgerEntry(accountId: "a", date: oldDate, current: 50, available: nil, limit: nil, recordedAt: oldDate),
        ])
        let updated = seeded.appending(
            accounts: [account("a", current: 100)], now: now, retentionDays: 90, calendar: calendar
        )
        #expect(updated.entries.allSatisfy { $0.date >= calendar.date(byAdding: .day, value: -90, to: now)! })
        #expect(updated.entries.contains { $0.current == 100 })
        #expect(!updated.entries.contains { $0.current == 50 })
    }

    @Test("Output is stably sorted by (date, accountId)")
    func stableSort() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let ledger = AccountBalanceLedger()
            .appending(accounts: [account("b", current: 1), account("a", current: 2)], now: yesterday, calendar: calendar)
            .appending(accounts: [account("b", current: 3), account("a", current: 4)], now: now, calendar: calendar)
        // Same-day entries sorted by accountId; earlier date first.
        let keys = ledger.entries.map { "\(AccountBalanceLedger.dayKey($0.date))|\($0.accountId)" }
        #expect(keys == keys.sorted())
    }

    @Test("Multi-account days keep one row per account")
    func multiAccountOneRowEach() {
        let ledger = AccountBalanceLedger().appending(
            accounts: [account("a", current: 1), account("b", current: 2), account("c", current: 3)],
            now: now, calendar: calendar
        )
        #expect(ledger.entries.count == 3)
        #expect(Set(ledger.entries.map(\.accountId)) == ["a", "b", "c"])
    }

    @Test("latestEntriesByAccount returns the most recent entry per account")
    func latestPerAccount() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let ledger = AccountBalanceLedger()
            .appending(accounts: [account("a", current: 10)], now: yesterday, calendar: calendar)
            .appending(accounts: [account("a", current: 20)], now: now, calendar: calendar)
        let latest = ledger.latestEntriesByAccount()
        #expect(latest.count == 1)
        #expect(latest.first?.current == 20)
    }
}
