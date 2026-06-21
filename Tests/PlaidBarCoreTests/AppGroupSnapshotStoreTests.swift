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

    // MARK: - Privacy-command re-redaction (bug-hunt R2)
    //
    // When Privacy Mask is enabled from the Control Center control / Focus filter
    // (or applied on app activation), the privacy-command path re-redacts the
    // already-persisted snapshot in place with `AppGroupSnapshotStore.save(s.masked())`
    // — so the widget + Safe-to-Spend / Credit-Utilization value controls stop
    // reading real balances immediately, without waiting for the app to foreground.
    // These tests lock in that the persisted snapshot is value-free and `isMasked`.

    @Test("masked() zeroes every figure and empties every list, keeping isMasked true")
    func maskedIsValueFree() {
        let masked = sampleSnapshot().masked()

        #expect(masked.isMasked)
        #expect(masked.safeToSpend == 0)
        #expect(masked.totalBalance == 0)
        #expect(masked.creditUtilization == nil)
        #expect(masked.periodSpending == 0)
        #expect(masked.accountBalances.isEmpty)
        #expect(masked.nextRecurringBills.isEmpty)
        #expect(masked.topSpendingCategories.isEmpty)
        // Non-value metadata is preserved so the masked surface still timestamps.
        #expect(masked.isoCurrencyCode == sampleSnapshot().isoCurrencyCode)
        #expect(masked.generatedAt == sampleSnapshot().generatedAt)
    }

    @Test("masked() is idempotent on an already-masked snapshot")
    func maskedIsIdempotent() {
        let once = sampleSnapshot().masked()
        let twice = once.masked()
        #expect(twice == once)
        #expect(twice.isMasked)
    }

    @Test("Privacy-command path leaves the persisted FinanceSnapshot value-free and masked")
    func privacyCommandPathPersistsMaskedSnapshot() throws {
        let directory = temporaryDirectory()
        // A real, value-bearing snapshot is already on disk (last app write).
        let real = sampleSnapshot()
        try AppGroupSnapshotStore.save(real, directory: directory)

        // Enabling Privacy Mask re-redacts in place — mirrors
        // SetPrivacyMaskIntent.perform() / FocusPrivacyFilterIntent.perform() /
        // AppState.applyPendingPrivacyMaskControlCommand().
        let onDisk = try #require(AppGroupSnapshotStore.loadIfAvailable(directory: directory))
        #expect(!onDisk.isMasked)
        try AppGroupSnapshotStore.save(onDisk.masked(), directory: directory)

        // The reader surfaces (widget, value controls) now see no real figures.
        let reread = try AppGroupSnapshotStore.load(directory: directory)
        #expect(reread.isMasked)
        #expect(reread.safeToSpend == 0)
        #expect(reread.totalBalance == 0)
        #expect(reread.creditUtilization == nil)
        #expect(reread.accountBalances.isEmpty)
        #expect(reread.nextRecurringBills.isEmpty)

        // And the bytes on disk carry none of the real figures either.
        let json = try String(
            contentsOf: AppGroupSnapshotStore.snapshotURL(directory: directory),
            encoding: .utf8
        )
        #expect(!json.contains("1234.56"))
        #expect(!json.contains("9876.54"))
        #expect(!json.contains("Everyday Checking"))
        #expect(!json.contains("Vacation Savings"))
        #expect(!json.contains("Rent"))
        #expect(!json.contains("27.5"))
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
