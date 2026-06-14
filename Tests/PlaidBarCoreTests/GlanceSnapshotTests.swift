import Testing
@testable import PlaidBarCore

@Suite("Glance snapshot")
struct GlanceSnapshotTests {
    @Test("Builds display-safe aggregate snapshot")
    func buildsDisplaySafeAggregateSnapshot() throws {
        let now = try #require(Formatters.parseTransactionDate("2026-06-14"))
        let previous = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let snapshot = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: [
                BalanceSnapshot(date: previous, balance: 1_000),
                BalanceSnapshot(date: now, balance: 1_250),
            ],
            updatedAt: now,
            isDemo: false
        )

        #expect(snapshot.netWorth == 1_250)
        #expect(snapshot.todayChange == 250)
        #expect(snapshot.changeDirection == .up)
        #expect(snapshot.signedChangeText == "+$250")
        #expect(snapshot.sparkline.count >= 2)
        #expect(!snapshot.accessibilitySummary.contains("account"))
        #expect(!snapshot.accessibilitySummary.contains("item"))
        #expect(!snapshot.accessibilitySummary.contains("transaction"))
        #expect(!snapshot.accessibilitySummary.contains("token"))
    }

    @Test("Snapshot JSON excludes Plaid identifiers and raw payload fields")
    func snapshotJSONExcludesPrivateFields() throws {
        let directory = temporaryDirectory()
        let snapshot = GlanceSnapshot(
            netWorth: 17_604.24,
            todayChange: -42,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sparkline: [0, 0.5, 1],
            isDemo: true
        )

        try GlanceSnapshotStore.save(snapshot, directory: directory)
        let json = try String(
            contentsOf: GlanceSnapshotStore.snapshotURL(directory: directory),
            encoding: .utf8
        )

        #expect(json.contains("\"netWorth\""))
        #expect(json.contains("\"todayChange\""))
        #expect(json.contains("\"sparkline\""))
        #expect(!json.contains("access_token"))
        #expect(!json.contains("client_secret"))
        #expect(!json.contains("public_token"))
        #expect(!json.contains("account_id"))
        #expect(!json.contains("item_id"))
        #expect(!json.contains("transaction_id"))
        #expect(!json.contains("transactions"))
        #expect(!json.contains("accounts"))
    }

    @Test("Command request is consumed once")
    func commandRequestIsConsumedOnce() throws {
        let directory = temporaryDirectory()
        let requestedAt = Date(timeIntervalSince1970: 1_780_000_000)
        try GlanceSnapshotStore.saveCommand(
            GlanceCommandRequest(command: .refreshBalances, requestedAt: requestedAt),
            directory: directory
        )

        let request = try #require(try GlanceSnapshotStore.consumeCommand(directory: directory))
        #expect(request.command == .refreshBalances)
        #expect(request.requestedAt == requestedAt)
        #expect(try GlanceSnapshotStore.consumeCommand(directory: directory) == nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceSnapshotTests-\(UUID().uuidString)", isDirectory: true)
    }
}
