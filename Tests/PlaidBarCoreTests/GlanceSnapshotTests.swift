import Foundation
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

    // MARK: - Privacy Mask / App Lock redaction (AND-517)

    @Test("Masked build zeroes every financial value")
    func maskedBuildZeroesEveryFinancialValue() throws {
        let now = try #require(Formatters.parseTransactionDate("2026-06-14"))
        let previous = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let history = [
            BalanceSnapshot(date: previous, balance: 1_000),
            BalanceSnapshot(date: now, balance: 1_250),
        ]

        let masked = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: history,
            updatedAt: now,
            isDemo: false,
            isMasked: true
        )

        #expect(masked.isRedacted)
        #expect(masked.netWorth == 0)
        #expect(masked.todayChange == 0)
        #expect(masked.changeDirection == .flat)
        #expect(masked.sparkline.isEmpty)
        // Non-sensitive metadata is preserved so the widget can still render an
        // "updated"/demo state without exposing balances.
        #expect(masked.updatedAt == now)
        #expect(!masked.isDemo)
    }

    @Test("Unmasked build is unchanged and carries real values")
    func unmaskedBuildIsUnchanged() throws {
        let now = try #require(Formatters.parseTransactionDate("2026-06-14"))
        let previous = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let history = [
            BalanceSnapshot(date: previous, balance: 1_000),
            BalanceSnapshot(date: now, balance: 1_250),
        ]

        let masked = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: history,
            updatedAt: now,
            isDemo: false,
            isMasked: false
        )
        // Default (no `isMasked` argument) must match the explicit-unmasked build,
        // so existing callers keep their behavior.
        let defaulted = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: history,
            updatedAt: now,
            isDemo: false
        )

        #expect(!masked.isRedacted)
        #expect(masked.netWorth == 1_250)
        #expect(masked.todayChange == 250)
        #expect(masked.changeDirection == .up)
        #expect(masked.sparkline.count >= 2)
        #expect(masked == defaulted)
    }

    @Test("redacted() clears figures but keeps metadata")
    func redactedClearsFiguresButKeepsMetadata() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let real = GlanceSnapshot(
            netWorth: 17_604.24,
            todayChange: -42,
            updatedAt: updatedAt,
            sparkline: [0, 0.5, 1],
            isDemo: true
        )

        let redacted = real.redacted()

        #expect(redacted.isRedacted)
        #expect(redacted.netWorth == 0)
        #expect(redacted.todayChange == 0)
        #expect(redacted.sparkline.isEmpty)
        #expect(redacted.updatedAt == updatedAt)
        #expect(redacted.isDemo)
    }

    @Test("Redacted snapshot JSON on disk carries no real figures")
    func redactedSnapshotJSONOnDiskCarriesNoRealFigures() throws {
        let directory = temporaryDirectory()
        let masked = GlanceSnapshot(
            netWorth: 17_604.24,
            todayChange: -421.55,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sparkline: [0.12, 0.48, 0.97],
            isDemo: false
        ).redacted()

        try GlanceSnapshotStore.save(masked, directory: directory)
        let json = try String(
            contentsOf: GlanceSnapshotStore.snapshotURL(directory: directory),
            encoding: .utf8
        )

        // The redaction flag is recorded and the on-disk figures are zeroed —
        // not the real values written before masking.
        #expect(json.contains("\"isRedacted\":true"))
        #expect(!json.contains("17604"))
        #expect(!json.contains("421.55"))
        #expect(!json.contains("0.48"))
        #expect(json.contains("\"netWorth\":0"))
        #expect(json.contains("\"todayChange\":0"))
        #expect(json.contains("\"sparkline\":[]"))

        // Round-trips back as a redacted, value-free snapshot.
        let reloaded = try GlanceSnapshotStore.load(directory: directory)
        #expect(reloaded.isRedacted)
        #expect(reloaded.netWorth == 0)
        #expect(reloaded.sparkline.isEmpty)
    }

    @Test("Enabling mask redacts the persisted snapshot (transition)")
    func enablingMaskRedactsPersistedSnapshot() throws {
        let directory = temporaryDirectory()
        let now = try #require(Formatters.parseTransactionDate("2026-06-14"))
        let previous = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let history = [
            BalanceSnapshot(date: previous, balance: 1_000),
            BalanceSnapshot(date: now, balance: 1_250),
        ]

        // 1. Unmasked: the real snapshot lands on disk with live figures.
        let real = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: history,
            updatedAt: now,
            isDemo: false,
            isMasked: false
        )
        #expect(try GlanceSnapshotStore.saveIfChanged(real, directory: directory))
        #expect(try GlanceSnapshotStore.load(directory: directory).netWorth == 1_250)

        // 2. Mask turns on — the writer rebuilds and the persisted file is
        // rewritten value-free (the change in `isRedacted`/figures defeats the
        // saveIfChanged short-circuit).
        let masked = GlanceSnapshot.make(
            netWorth: 1_250,
            balanceHistory: history,
            updatedAt: now,
            isDemo: false,
            isMasked: true
        )
        #expect(try GlanceSnapshotStore.saveIfChanged(masked, directory: directory))

        let onDisk = try GlanceSnapshotStore.load(directory: directory)
        #expect(onDisk.isRedacted)
        #expect(onDisk.netWorth == 0)
        #expect(onDisk.todayChange == 0)
        #expect(onDisk.sparkline.isEmpty)
    }

    @Test("Legacy snapshot without isRedacted decodes as not redacted")
    func legacySnapshotWithoutIsRedactedDecodesAsNotRedacted() throws {
        // A glance-snapshot.json written by a pre-AND-517 build has no
        // `isRedacted` key. It must decode as a normal, non-redacted snapshot so
        // upgrades never treat a real snapshot as masked.
        let legacyJSON = """
        {"isDemo":false,"netWorth":17604.24,"sparkline":[0,0.5,1],\
        "todayChange":-42,"updatedAt":"2026-06-14T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GlanceSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(!snapshot.isRedacted)
        #expect(snapshot.netWorth == 17_604.24)
        #expect(snapshot.todayChange == -42)
        #expect(snapshot.sparkline == [0, 0.5, 1])
    }

    @Test("Timestamp display changes rewrite the file")
    func timestampDisplayChangesRewriteFile() throws {
        let directory = temporaryDirectory()
        let original = GlanceSnapshot(
            netWorth: 17_604.24,
            todayChange: -42,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sparkline: [0, 0.5, 1],
            isDemo: false
        )
        let timestampOnlyChange = GlanceSnapshot(
            netWorth: original.netWorth,
            todayChange: original.todayChange,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_300),
            sparkline: original.sparkline,
            isDemo: original.isDemo
        )

        #expect(try GlanceSnapshotStore.saveIfChanged(original, directory: directory))
        let url = GlanceSnapshotStore.snapshotURL(directory: directory)
        let firstData = try Data(contentsOf: url)

        #expect(try GlanceSnapshotStore.saveIfChanged(timestampOnlyChange, directory: directory))
        #expect(try Data(contentsOf: url) != firstData)
        #expect(try GlanceSnapshotStore.load(directory: directory) == timestampOnlyChange)
    }

    @Test("Meaningful display changes rewrite the file")
    func meaningfulDisplayChangesRewriteFile() throws {
        let directory = temporaryDirectory()
        let original = GlanceSnapshot(
            netWorth: 17_604.24,
            todayChange: -42,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sparkline: [0, 0.5, 1],
            isDemo: false
        )
        let changed = GlanceSnapshot(
            netWorth: 17_650,
            todayChange: 3.74,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_300),
            sparkline: [0.1, 0.4, 1],
            isDemo: false
        )

        #expect(try GlanceSnapshotStore.saveIfChanged(original, directory: directory))
        #expect(try GlanceSnapshotStore.saveIfChanged(changed, directory: directory))
        #expect(try GlanceSnapshotStore.load(directory: directory) == changed)
    }

    @Test("Debouncer coalesces burst writes to the latest snapshot")
    func debouncerCoalescesBurstWritesToLatestSnapshot() async throws {
        let scheduler = ManualDebounceScheduler()
        let debouncer = GlanceSnapshotWriteDebouncer(delay: .milliseconds(25), scheduler: scheduler)
        let recorder = SnapshotWriteRecorder()

        await debouncer.schedule(firstSnapshot(netWorth: 100)) { snapshot in
            await recorder.record(snapshot)
        }
        await debouncer.schedule(firstSnapshot(netWorth: 200)) { snapshot in
            await recorder.record(snapshot)
        }
        await debouncer.schedule(firstSnapshot(netWorth: 300)) { snapshot in
            await recorder.record(snapshot)
        }

        // Each scheduled task parks in the manual scheduler instead of sleeping
        // on a real clock. Once all three are parked, release them together: the
        // two superseded tasks bail at their cancellation check and only the
        // latest snapshot is written — no wall-clock window to race.
        await scheduler.waitForParkedSleepers(count: 3)
        await scheduler.releaseAll()

        let firstWrite = await recorder.waitForWrite()
        #expect(firstWrite.netWorth == 300)

        let snapshots = await recorder.snapshots
        #expect(snapshots.map(\.netWorth) == [300])
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

    private func firstSnapshot(netWorth: Double) -> GlanceSnapshot {
        GlanceSnapshot(
            netWorth: netWorth,
            todayChange: 0,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            sparkline: [0, 1],
            isDemo: false
        )
    }
}

private actor SnapshotWriteRecorder {
    private(set) var snapshots: [GlanceSnapshot] = []
    private var pendingWaiter: CheckedContinuation<GlanceSnapshot, Never>?

    func record(_ snapshot: GlanceSnapshot) {
        snapshots.append(snapshot)
        if let waiter = pendingWaiter {
            pendingWaiter = nil
            waiter.resume(returning: snapshot)
        }
    }

    /// Suspends until the first write lands (or returns immediately if one
    /// already has), so the test awaits the real write event instead of a
    /// fixed wall-clock budget.
    func waitForWrite() async -> GlanceSnapshot {
        if let latest = snapshots.last {
            return latest
        }
        return await withCheckedContinuation { continuation in
            pendingWaiter = continuation
        }
    }
}

/// A `DebounceScheduler` whose `sleep` parks the caller until the test releases
/// it, making debounce coalescing deterministic with no dependence on a real
/// debounce window. The requested `duration` is intentionally ignored.
private actor ManualDebounceScheduler: DebounceScheduler {
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var parkWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async {
        await withCheckedContinuation { continuation in
            parked.append(continuation)
            resolveParkWaiters()
        }
    }

    /// Suspends until at least `count` callers are parked inside `sleep`.
    func waitForParkedSleepers(count: Int) async {
        if parked.count >= count {
            return
        }
        await withCheckedContinuation { continuation in
            parkWaiters.append((threshold: count, continuation: continuation))
        }
    }

    /// Resumes every parked sleeper at once. Superseded debouncer tasks then
    /// return at their cancellation check; only the latest task runs its
    /// operation.
    func releaseAll() {
        let resumable = parked
        parked.removeAll()
        for continuation in resumable {
            continuation.resume()
        }
    }

    private func resolveParkWaiters() {
        parkWaiters.removeAll { waiter in
            guard parked.count >= waiter.threshold else { return false }
            waiter.continuation.resume()
            return true
        }
    }
}
