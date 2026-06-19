import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard read-model mapper (AND-566)")
struct DashboardReadModelMapperTests {

    private func sampleAccounts() -> [AccountDTO] {
        [
            AccountDTO(id: "chk", itemId: "i1", name: "Checking", type: .depository, balances: BalanceDTO(available: 8200)),
            AccountDTO(id: "sav", itemId: "i1", name: "Savings", type: .depository, balances: BalanceDTO(available: 5100)),
            AccountDTO(id: "amex", itemId: "i2", name: "Amex", type: .credit, balances: BalanceDTO(current: -850, limit: 10000)),
        ]
    }

    private func sampleTransactions(count: Int) -> [TransactionDTO] {
        (0..<count).map { i in
            TransactionDTO(
                id: "tx_\(i)",
                accountId: "chk",
                amount: Double(i + 1),
                date: "2026-01-\(String(format: "%02d", (i % 28) + 1))",
                name: "Merchant \(i)"
            )
        }
    }

    @Test("cacheKey scopes by environment and normalized storage path")
    func cacheKeyScoping() {
        let sandbox = DashboardReadModelMapper.cacheKey(environment: .sandbox, storagePath: "/Users/x/.vaultpeek/")
        let production = DashboardReadModelMapper.cacheKey(environment: .production, storagePath: "/Users/x/.vaultpeek/")
        #expect(sandbox != production, "different Plaid environments must never share a cached row")

        let trailingSlash = DashboardReadModelMapper.cacheKey(environment: .sandbox, storagePath: "/Users/x/.vaultpeek")
        #expect(sandbox == trailingSlash, "path normalization should ignore a trailing slash")
    }

    @Test("makeReadModel caps recent transactions newest-first")
    func makeReadModelCaps() {
        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: "k",
            accounts: sampleAccounts(),
            transactions: sampleTransactions(count: 120),
            maxRecentTransactions: 50,
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(model.recentTransactions.count == 50)
        // Newest-first: the highest day-of-month within the window leads.
        let dates = model.recentTransactions.map(\.date)
        #expect(dates == dates.sorted(by: >))
        #expect(model.schemaVersion == DashboardReadModel.currentSchemaVersion)
    }

    @Test("makeReadModel summary reuses authoritative aggregators")
    func makeReadModelSummary() {
        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: "k",
            accounts: sampleAccounts(),
            transactions: [],
            generatedAt: Date()
        )

        // netCash = 8200 + 5100 - 850 = 12450
        #expect(abs(model.summary.netCash - 12450) < 0.01)
        // totalDebt across credit accounts = 850
        #expect(abs(model.summary.totalDebt - 850) < 0.01)
        #expect(model.summary.accountCount == 3)
    }

    @Test("hydrate returns DTOs when key matches and row is current")
    func hydrateHappyPath() {
        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: "match",
            accounts: sampleAccounts(),
            transactions: sampleTransactions(count: 3),
            generatedAt: Date()
        )

        let hydration = DashboardReadModelMapper.hydrate(from: model, expectedCacheKey: "match")
        #expect(hydration != nil)
        #expect(hydration?.accounts.count == 3)
        #expect(hydration?.recentTransactions.count == 3)
    }

    @Test("hydrate refuses a mismatched cache key (environment guard)")
    func hydrateRejectsMismatchedKey() {
        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: "sandbox|/a",
            accounts: sampleAccounts(),
            transactions: sampleTransactions(count: 3),
            generatedAt: Date()
        )

        #expect(DashboardReadModelMapper.hydrate(from: model, expectedCacheKey: "production|/a") == nil)
    }

    @Test("hydrate refuses an older schema row (disposable across upgrades)")
    func hydrateRejectsOlderSchema() {
        let stale = DashboardReadModel(
            cacheKey: "k",
            schemaVersion: DashboardReadModel.currentSchemaVersion - 1,
            accounts: sampleAccounts(),
            recentTransactions: sampleTransactions(count: 2),
            summary: .init(netCash: 0, totalDebt: 0, accountCount: 3),
            generatedAt: Date()
        )

        #expect(DashboardReadModelMapper.hydrate(from: stale, expectedCacheKey: "k") == nil)
    }

    @Test("hydrate refuses an empty row so cold path stays on loading/empty")
    func hydrateRejectsEmpty() {
        let empty = DashboardReadModelMapper.makeReadModel(
            cacheKey: "k",
            accounts: [],
            transactions: [],
            generatedAt: Date()
        )

        #expect(empty.isEmpty)
        #expect(DashboardReadModelMapper.hydrate(from: empty, expectedCacheKey: "k") == nil)
    }

    @Test("read-model round-trips through Codable unchanged")
    func codableRoundTrip() throws {
        let model = DashboardReadModelMapper.makeReadModel(
            cacheKey: "k",
            accounts: sampleAccounts(),
            transactions: sampleTransactions(count: 10),
            generatedAt: Date(timeIntervalSince1970: 12345)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(model)
        let decoded = try decoder.decode(DashboardReadModel.self, from: data)
        #expect(decoded == model)
    }
}
