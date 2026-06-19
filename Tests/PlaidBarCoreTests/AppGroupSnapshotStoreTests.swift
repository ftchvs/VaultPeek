import Foundation
import Testing
@testable import PlaidBarCore

@Suite("App Group finance snapshot store")
struct AppGroupSnapshotStoreTests {
    // MARK: - Round trip

    @Test("Snapshot round-trips through the store unchanged")
    func snapshotRoundTrips() throws {
        let directory = temporaryDirectory()
        let snapshot = sampleSnapshot()

        try AppGroupSnapshotStore.save(snapshot, directory: directory)
        let loaded = try AppGroupSnapshotStore.load(directory: directory)

        #expect(loaded == snapshot)
    }

    @Test("loadIfAvailable returns nil when no snapshot has been written")
    func loadIfAvailableReturnsNilWhenMissing() {
        let directory = temporaryDirectory()
        #expect(AppGroupSnapshotStore.loadIfAvailable(directory: directory) == nil)
    }

    @Test("Clearing removes the snapshot file")
    func clearRemovesSnapshot() throws {
        let directory = temporaryDirectory()
        try AppGroupSnapshotStore.save(sampleSnapshot(), directory: directory)
        #expect(AppGroupSnapshotStore.loadIfAvailable(directory: directory) != nil)

        try AppGroupSnapshotStore.clear(directory: directory)
        #expect(AppGroupSnapshotStore.loadIfAvailable(directory: directory) == nil)
    }

    @Test("Snapshot JSON carries values only — no Plaid identifiers or secrets")
    func snapshotJSONExcludesPrivateFields() throws {
        let directory = temporaryDirectory()
        try AppGroupSnapshotStore.save(sampleSnapshot(), directory: directory)

        let json = try String(
            contentsOf: AppGroupSnapshotStore.snapshotURL(directory: directory),
            encoding: .utf8
        )

        #expect(json.contains("\"safeToSpend\""))
        #expect(json.contains("\"totalBalance\""))
        #expect(json.contains("\"isMasked\""))
        #expect(!json.contains("access_token"))
        #expect(!json.contains("accessToken"))
        #expect(!json.contains("client_secret"))
        #expect(!json.contains("public_token"))
        #expect(!json.contains("account_id"))
        #expect(!json.contains("accountId"))
        #expect(!json.contains("item_id"))
        #expect(!json.contains("itemId"))
        #expect(!json.contains("transaction_id"))
    }

    @Test("Shares the glance snapshot App Group identifier")
    func sharesAppGroupIdentifier() {
        #expect(FinanceSnapshot.appGroupIdentifier == GlanceSnapshot.appGroupIdentifier)
        #expect(FinanceSnapshot.filename != GlanceSnapshot.filename)
    }

    // MARK: - Helpers

    private func sampleSnapshot(isMasked: Bool = false) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 1_234.56,
            totalBalance: 9_876.54,
            accountBalances: [
                FinanceSnapshot.AccountBalance(displayName: "Everyday Checking", balance: 4_200.10),
                FinanceSnapshot.AccountBalance(displayName: "Vacation Savings", balance: 5_676.44),
            ],
            nextRecurringBills: [
                FinanceSnapshot.UpcomingBill(merchantName: "Rent", amount: 1_800, nextExpectedDate: "2026-07-01"),
            ],
            creditUtilization: 27.5,
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            isMasked: isMasked
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGroupSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
