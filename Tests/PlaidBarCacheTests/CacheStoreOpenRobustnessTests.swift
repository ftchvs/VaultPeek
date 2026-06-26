import Foundation
import Testing
@testable import PlaidBarCache
@testable import PlaidBarCore

/// Robustness coverage for the disposable cache *open* path (AND-656 findings 2 & 3).
///
/// Two invariants are pinned here:
///   1. **Incompatible/corrupt store = disposable miss.** A backing file that
///      cannot decode as the current JSON `Snapshot` (e.g. a leftover pre-JSON
///      SwiftData `.store`) must read as a clean cache miss, be discarded, and let
///      the next write rebuild it — never permanently disable the cache and never
///      lose authoritative (live in-memory) data.
///   2. **Opening does no synchronous full decode.** Constructing the store must
///      perform zero disk I/O; the read+decode is deferred to the first
///      actor-isolated operation, so a MainActor caller never blocks on a
///      full-history decode at open time.
@Suite("Disposable cache open robustness (AND-656)", .serialized)
struct CacheStoreOpenRobustnessTests {

    // MARK: - Helpers

    /// A `FileManager` that counts `fileExists(atPath:)` calls so a test can prove
    /// the store touched disk lazily (zero probes at construction, exactly the
    /// expected probes once an operation runs).
    private final class CountingFileManager: FileManager, @unchecked Sendable {
        private(set) var fileExistsCallCount = 0

        override func fileExists(atPath path: String) -> Bool {
            fileExistsCallCount += 1
            return super.fileExists(atPath: path)
        }
    }

    private func makeTempDirectory(_ tag: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultpeek-open-robustness-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes bytes that are NOT a valid `Snapshot` JSON at the store's filename,
    /// standing in for a leftover incompatible (e.g. SwiftData) `.store` file.
    private func writeIncompatibleFile(at url: URL) throws {
        // Arbitrary non-JSON bytes — decoding as our `Snapshot` must fail.
        let garbage = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x53, 0x51, 0x4C, 0x69, 0x74, 0x65])
        try garbage.write(to: url)
    }

    private func sampleReadModel(cacheKey: String) -> DashboardReadModel {
        DashboardReadModelMapper.makeReadModel(
            cacheKey: cacheKey,
            accounts: [
                AccountDTO(id: "chk", itemId: "i1", name: "Checking", type: .depository, balances: BalanceDTO(available: 4200)),
            ],
            transactions: [
                TransactionDTO(id: "t1", accountId: "chk", amount: 9.99, date: "2026-03-01", name: "Coffee"),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000)
        )
    }

    private func sampleTransactions(count: Int) -> [TransactionDTO] {
        (0..<count).map { i in
            TransactionDTO(
                id: "tx_\(String(format: "%04d", i))",
                accountId: "chk",
                amount: Double(i + 1),
                date: "2026-03-\(String(format: "%02d", (i % 28) + 1))",
                name: "Merchant \(i)"
            )
        }
    }

    // MARK: - Finding 2: incompatible store is a disposable miss

    @Test("read-model: an incompatible store file reads as a miss and self-heals on write")
    func readModelIncompatibleFileIsDisposableMiss() async throws {
        let directory = makeTempDirectory("rm-incompat")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(ReadModelCacheStore.storeFilename)
        try writeIncompatibleFile(at: storeURL)

        let key = "sandbox|/x"
        let store = ReadModelCacheStore(onDiskIn: directory)

        // The undecodable file is a clean miss, not a hard error: load returns nil
        // (caller's `try?` would see a value, not a thrown failure).
        #expect(try await store.load(cacheKey: key) == nil)

        // ...and the incompatible file was discarded so the cache is NOT permanently
        // disabled. A subsequent write rebuilds a fresh, decodable store.
        let model = sampleReadModel(cacheKey: key)
        try await store.save(model)
        #expect(try await store.load(cacheKey: key) == model)

        // A brand-new store actor over the same directory now reads the rebuilt row,
        // proving the file on disk is valid JSON again (real-data round-trips, no loss).
        let reopened = ReadModelCacheStore(onDiskIn: directory)
        #expect(try await reopened.load(cacheKey: key) == model)
    }

    @Test("transaction: an incompatible store file reads as a miss and self-heals on write")
    func transactionIncompatibleFileIsDisposableMiss() async throws {
        let directory = makeTempDirectory("tx-incompat")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(TransactionCacheStore.storeFilename)
        try writeIncompatibleFile(at: storeURL)

        let key = "sandbox|/x"
        let store = TransactionCacheStore(onDiskIn: directory)

        // Incompatible file → clean miss: count is zero, no thrown failure.
        #expect(try await store.count(cacheKey: key) == 0)

        // The cache rebuilds from the next refresh rather than staying disabled.
        let all = sampleTransactions(count: 6)
        try await store.upsert(cacheKey: key, transactions: all)
        #expect(try await store.count(cacheKey: key) == 6)

        // Re-opening over the same directory reads the rebuilt rows back.
        let reopened = TransactionCacheStore(onDiskIn: directory)
        #expect(try await reopened.count(cacheKey: key) == 6)
    }

    @Test("read-model: a clearAll on an incompatible file wins without decoding it")
    func readModelClearAllOverIncompatibleFile() async throws {
        let directory = makeTempDirectory("rm-clear")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(ReadModelCacheStore.storeFilename)
        try writeIncompatibleFile(at: storeURL)

        // A clear/reset path (e.g. last institution removed) over an incompatible
        // file must still succeed and leave a clean, empty, decodable store.
        let store = ReadModelCacheStore(onDiskIn: directory)
        try await store.clearAll()

        let reopened = ReadModelCacheStore(onDiskIn: directory)
        #expect(try await reopened.load(cacheKey: "sandbox|/x") == nil)
    }

    // MARK: - Finding 3: opening does no synchronous full decode

    @Test("read-model: constructing the store performs no disk I/O (lazy open)")
    func readModelOpenIsLazy() async throws {
        let directory = makeTempDirectory("rm-lazy")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed a real, valid, non-trivial store so an *eager* open would have to
        // decode it. The lazy contract means construction must not read it.
        let seeded = ReadModelCacheStore(onDiskIn: directory)
        try await seeded.save(sampleReadModel(cacheKey: "sandbox|/x"))

        let counter = CountingFileManager()
        let store = ReadModelCacheStore(onDiskIn: directory, fileManager: counter)

        // Opening touched disk zero times — no `fileExists`, no read, no decode.
        #expect(counter.fileExistsCallCount == 0, "open must not probe or read the backing file")

        // The first operation hydrates lazily (now disk is touched) and still reads
        // the seeded row correctly.
        let loaded = try await store.load(cacheKey: "sandbox|/x")
        #expect(loaded?.cacheKey == "sandbox|/x")
        #expect(counter.fileExistsCallCount >= 1, "the first operation triggers the deferred load")
    }

    @Test("transaction: constructing the store performs no disk I/O (lazy open)")
    func transactionOpenIsLazy() async throws {
        let directory = makeTempDirectory("tx-lazy")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed a large-ish history so an eager open would decode the whole file.
        let seeded = TransactionCacheStore(onDiskIn: directory)
        try await seeded.upsert(cacheKey: "sandbox|/x", transactions: sampleTransactions(count: 50))

        let counter = CountingFileManager()
        let store = TransactionCacheStore(onDiskIn: directory, fileManager: counter)

        // Opening the (potentially large) store decodes nothing and touches no disk.
        #expect(counter.fileExistsCallCount == 0, "open must not probe or read the full history")

        // The first read faults in the history lazily, off the open path.
        #expect(try await store.count(cacheKey: "sandbox|/x") == 50)
        #expect(counter.fileExistsCallCount >= 1, "the first read triggers the deferred load")
    }

    // MARK: - AND-670: a corrupt *row payload* is a disposable miss, not a throw

    /// Corrupts only the inner `payload` blob of a stored read-model row while
    /// leaving the surrounding `Snapshot` JSON (and the queryable `schemaVersion`
    /// scalar) intact, so the whole-store decode in `loadedRows()` still succeeds
    /// and the failure surfaces at the per-row `DashboardReadModel` decode in
    /// `load(cacheKey:)`.
    private func corruptRowPayload(at storeURL: URL) throws {
        let raw = try Data(contentsOf: storeURL)
        var json = try #require(
            try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        )
        var rows = try #require(json["rows"] as? [String: Any])
        for key in rows.keys {
            var row = try #require(rows[key] as? [String: Any])
            // Replace the base64 payload with bytes that are valid base64 but do
            // NOT decode as a `DashboardReadModel`.
            row["payload"] = Data([0x7B, 0x6E, 0x6F, 0x70, 0x65]).base64EncodedString()
            rows[key] = row
        }
        json["rows"] = rows
        let mutated = try JSONSerialization.data(withJSONObject: json)
        try mutated.write(to: storeURL)
    }

    @Test("read-model: a corrupt row payload reads as a miss (not a throw) and self-heals")
    func readModelCorruptRowPayloadIsDisposableMiss() async throws {
        let directory = makeTempDirectory("rm-corrupt-payload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(ReadModelCacheStore.storeFilename)
        let key = "sandbox|/x"

        // Seed a valid row, then corrupt ONLY its inner payload blob on disk.
        do {
            let seed = ReadModelCacheStore(onDiskIn: directory)
            try await seed.save(sampleReadModel(cacheKey: key))
        }
        try corruptRowPayload(at: storeURL)

        // The corrupt per-row payload is a clean miss — `load` returns nil rather
        // than throwing, so the caller's `try?` sees a value, not a failure.
        let store = ReadModelCacheStore(onDiskIn: directory)
        #expect(try await store.load(cacheKey: key) == nil)

        // ...and the bad row was purged, so the cache is not permanently broken: a
        // subsequent write rebuilds a clean, decodable row.
        let model = sampleReadModel(cacheKey: key)
        try await store.save(model)
        #expect(try await store.load(cacheKey: key) == model)

        // A fresh actor over the same directory reads the rebuilt row back.
        let reopened = ReadModelCacheStore(onDiskIn: directory)
        #expect(try await reopened.load(cacheKey: key) == model)
    }

    // MARK: - AND-670: BudgetingV2Store opens lazily (no work before needed)

    @Test("budgeting-v2: constructing the store performs no disk I/O (lazy open)")
    func budgetingV2OpenIsLazy() async throws {
        let directory = makeTempDirectory("bv2-lazy")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed a real on-disk snapshot so an *eager* open would have to read + decode
        // it. The lazy contract means construction must not touch disk.
        let seeded = try BudgetingV2Store(onDiskIn: directory)
        try await seeded.seedV2(cacheKey: "sandbox|/x")

        let counter = CountingFileManager()
        let store = try BudgetingV2Store(onDiskIn: directory, fileManager: counter)

        // Opening touched disk zero times — no `fileExists`, no read, no decode.
        #expect(counter.fileExistsCallCount == 0, "open must not probe or read the backing file")

        // The first operation hydrates lazily (now disk is touched) and still reads
        // the seeded snapshot correctly.
        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == true)
        #expect(counter.fileExistsCallCount >= 1, "the first operation triggers the deferred load")
    }

    @Test("budgeting-v2: opening over an incompatible file does no work and reads as not-opted-in")
    func budgetingV2IncompatibleFileIsDisposableMiss() async throws {
        let directory = makeTempDirectory("bv2-incompat")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(BudgetingV2Store.storeFilename)
        try writeIncompatibleFile(at: storeURL)

        let counter = CountingFileManager()
        // Construction never throws or reads, even over a corrupt file (lazy open).
        let store = try BudgetingV2Store(onDiskIn: directory, fileManager: counter)
        #expect(counter.fileExistsCallCount == 0, "a cold/missing/corrupt store does no work at open")

        // The incompatible file self-heals into a clean miss: not opted in → v1.
        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == false)

        // ...and the store is not permanently broken — a seed rebuilds it.
        try await store.seedV2(cacheKey: "sandbox|/x")
        #expect(try await store.isOptedIn(cacheKey: "sandbox|/x") == true)
        let reopened = try BudgetingV2Store(onDiskIn: directory)
        #expect(try await reopened.isOptedIn(cacheKey: "sandbox|/x") == true)
    }

    @Test("transaction: replaceAll never decodes a pre-existing incompatible file")
    func transactionReplaceAllOverIncompatibleFile() async throws {
        let directory = makeTempDirectory("tx-replace")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(TransactionCacheStore.storeFilename)
        try writeIncompatibleFile(at: storeURL)

        // A full refresh (`replaceAll`) starts from empty, so it must rebuild the
        // store over the incompatible file without a decode failure surfacing.
        let store = TransactionCacheStore(onDiskIn: directory)
        try await store.replaceAll(cacheKey: "sandbox|/x", transactions: sampleTransactions(count: 4))
        #expect(try await store.count(cacheKey: "sandbox|/x") == 4)

        let reopened = TransactionCacheStore(onDiskIn: directory)
        #expect(try await reopened.count(cacheKey: "sandbox|/x") == 4)
    }
}
