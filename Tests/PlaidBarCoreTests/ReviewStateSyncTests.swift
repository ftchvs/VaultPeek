import Foundation
import Testing
@testable import PlaidBarCore

/// Opt-in server-synced review state — pure Core logic (AND-552).
///
/// Covers the last-writer-wins conflict resolver, the wire DTO JSON contract, and
/// the opt-in feature flag (default OFF). The route/store CRUD lives in the server
/// test target; the app-side gate ("opt-out sends nothing") lives in the app test
/// target.
@Suite("Server-synced review state — Core (AND-552)")
struct ReviewStateSyncTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func metadataRecord(
        id: String,
        category: SpendingCategory?,
        updatedAt: Date
    ) -> ReviewMetadataRecordDTO {
        ReviewMetadataRecordDTO(
            metadata: TransactionReviewMetadata(
                id: id,
                status: .reviewed,
                userCategory: category
            ),
            updatedAt: updatedAt
        )
    }

    private func ruleRecord(
        id: UUID,
        merchantContains: String,
        category: SpendingCategory?,
        updatedAt: Date
    ) -> ReviewRuleRecordDTO {
        ReviewRuleRecordDTO(
            rule: TransactionRule(
                id: id,
                matchMerchantContains: merchantContains,
                category: category,
                createdAt: epoch
            ),
            updatedAt: updatedAt
        )
    }

    // MARK: - LWW: distinct ids are unioned

    @Test("Distinct ids never conflict — both survive the merge")
    func distinctIdsUnioned() {
        let base = ReviewStateSnapshotDTO(
            metadata: [metadataRecord(id: "tx-a", category: .foodAndDrink, updatedAt: epoch)],
            rules: []
        )
        let incoming = ReviewStateSnapshotDTO(
            metadata: [metadataRecord(id: "tx-b", category: .shopping, updatedAt: epoch)],
            rules: []
        )

        let merged = ReviewStateConflictResolver.merge(base: base, incoming: incoming)
        #expect(merged.metadata.map(\.id) == ["tx-a", "tx-b"])
        #expect(merged.metadata.first { $0.id == "tx-a" }?.metadata.userCategory == .foodAndDrink)
        #expect(merged.metadata.first { $0.id == "tx-b" }?.metadata.userCategory == .shopping)
    }

    // MARK: - LWW: newer write wins same id

    @Test("Same id — the record with the newer updatedAt wins")
    func newerWriteWinsSameId() {
        let older = metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)
        let newer = metadataRecord(
            id: "tx-1",
            category: .shopping,
            updatedAt: epoch.addingTimeInterval(60)
        )

        // Newer arriving as the upload wins.
        let mergedForward = ReviewStateConflictResolver.merge(
            base: ReviewStateSnapshotDTO(metadata: [older], rules: []),
            incoming: ReviewStateSnapshotDTO(metadata: [newer], rules: [])
        )
        #expect(mergedForward.metadata.count == 1)
        #expect(mergedForward.metadata.first?.metadata.userCategory == .shopping)

        // And it still wins when it is already the stored side (older uploaded).
        let mergedReverse = ReviewStateConflictResolver.merge(
            base: ReviewStateSnapshotDTO(metadata: [newer], rules: []),
            incoming: ReviewStateSnapshotDTO(metadata: [older], rules: [])
        )
        #expect(mergedReverse.metadata.count == 1)
        #expect(mergedReverse.metadata.first?.metadata.userCategory == .shopping)
    }

    @Test("Exact updatedAt tie resolves to the incoming (latest deliberate) write")
    func tieResolvesToIncoming() {
        let stored = metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)
        let uploaded = metadataRecord(id: "tx-1", category: .entertainment, updatedAt: epoch)

        let merged = ReviewStateConflictResolver.merge(
            base: ReviewStateSnapshotDTO(metadata: [stored], rules: []),
            incoming: ReviewStateSnapshotDTO(metadata: [uploaded], rules: [])
        )
        #expect(merged.metadata.first?.metadata.userCategory == .entertainment)
    }

    @Test("Rules merge by UUID with the same LWW rule")
    func rulesMergeByUUID() {
        let ruleId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let older = ruleRecord(id: ruleId, merchantContains: "Old", category: .foodAndDrink, updatedAt: epoch)
        let newer = ruleRecord(
            id: ruleId,
            merchantContains: "New",
            category: .shopping,
            updatedAt: epoch.addingTimeInterval(120)
        )
        let otherId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let other = ruleRecord(id: otherId, merchantContains: "Other", category: .travel, updatedAt: epoch)

        let merged = ReviewStateConflictResolver.merge(
            base: ReviewStateSnapshotDTO(metadata: [], rules: [older, other]),
            incoming: ReviewStateSnapshotDTO(metadata: [], rules: [newer])
        )
        #expect(merged.rules.count == 2)
        let winning = merged.rules.first { $0.id == ruleId }
        #expect(winning?.rule.matchMerchantContains == "New")
        #expect(winning?.rule.category == .shopping)
        #expect(merged.rules.contains { $0.id == otherId })
    }

    // MARK: - Determinism

    @Test("Merge is deterministic and order-independent in its result set")
    func mergeDeterministicOrdering() {
        let a = metadataRecord(id: "tx-c", category: .shopping, updatedAt: epoch)
        let b = metadataRecord(id: "tx-a", category: .foodAndDrink, updatedAt: epoch)
        let c = metadataRecord(id: "tx-b", category: .travel, updatedAt: epoch)

        let merged = ReviewStateConflictResolver.merge(
            base: ReviewStateSnapshotDTO(metadata: [a, b], rules: []),
            incoming: ReviewStateSnapshotDTO(metadata: [c], rules: [])
        )
        // Sorted by transaction id, independent of input order.
        #expect(merged.metadata.map(\.id) == ["tx-a", "tx-b", "tx-c"])
    }

    @Test("Re-merging an identical snapshot is idempotent")
    func mergeIdempotent() {
        let snapshot = ReviewStateSnapshotDTO(
            metadata: [metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)],
            rules: [
                ruleRecord(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    merchantContains: "Coffee",
                    category: .foodAndDrink,
                    updatedAt: epoch
                ),
            ]
        )
        let once = ReviewStateConflictResolver.merge(base: snapshot, incoming: snapshot)
        let twice = ReviewStateConflictResolver.merge(base: once, incoming: snapshot)
        #expect(once == snapshot)
        #expect(twice == once)
    }

    // MARK: - Wire DTO JSON contract

    @Test("Snapshot round-trips through its documented JSON contract")
    func snapshotJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = ReviewStateSnapshotDTO(
            metadata: [metadataRecord(id: "tx-1", category: .foodAndDrink, updatedAt: epoch)],
            rules: [
                ruleRecord(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    merchantContains: "Starbucks",
                    category: .foodAndDrink,
                    updatedAt: epoch
                ),
            ]
        )
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(ReviewStateSnapshotDTO.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == ReviewStateSnapshotDTO.currentSchemaVersion)
    }

    @Test("Empty snapshot is current-schema and carries no records")
    func emptySnapshot() {
        let empty = ReviewStateSnapshotDTO.empty
        #expect(empty.metadata.isEmpty)
        #expect(empty.rules.isEmpty)
        #expect(empty.isCurrentSchema)
    }

    // MARK: - Opt-in flag (default OFF)

    @Test("Server-synced review is OFF by default")
    func flagDefaultsOff() {
        #expect(ServerSyncedReviewFeatureFlag.defaultValue == false)
        // No CLI override, no stored preference ⇒ OFF.
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: nil) == false)
    }

    @Test("Stored opt-in and CLI override turn syncing on; unparseable never enables")
    func flagResolution() {
        // Stored preference honored when no CLI override.
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: true) == true)
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: false) == false)
        // CLI override wins over the stored preference.
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: "on", storedValue: false) == true)
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: "off", storedValue: true) == false)
        // Unparseable token falls through to the stored value / default — never
        // silently enabling.
        #expect(ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: "maybe", storedValue: nil) == false)
        #expect(ServerSyncedReviewFeatureFlag.parse("garbage") == nil)
    }

    // MARK: - Sync gate (opt-out sends nothing)

    @Test("When NOT opted in, the sync gate skips — no network, nothing leaves the device")
    func gateSkipsWhenNotOptedIn() {
        #expect(ReviewSyncGate.action(isOptedIn: false) == .skip)
        #expect(ReviewSyncGate.allowsNetwork(isOptedIn: false) == false)
    }

    @Test("When opted in, the sync gate proceeds")
    func gateProceedsWhenOptedIn() {
        #expect(ReviewSyncGate.action(isOptedIn: true) == .proceed)
        #expect(ReviewSyncGate.allowsNetwork(isOptedIn: true) == true)
    }

    @Test("The gate's default (flag OFF) skips — local-first end to end")
    func gateDefaultSkips() {
        // Compose the actual gate decision over the actual default flag value:
        // a fresh install with no preference must skip.
        let defaultDecision = ReviewSyncGate.allowsNetwork(
            isOptedIn: ServerSyncedReviewFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: nil)
        )
        #expect(defaultDecision == false)
    }

    // MARK: - Assembler round-trip

    @Test("Assembler builds a stamped snapshot and flattens it back losslessly")
    func assemblerRoundTrip() {
        let metadata = [
            TransactionReviewMetadata(id: "tx-b", status: .reviewed, userCategory: .shopping),
            TransactionReviewMetadata(id: "tx-a", status: .ignored, userCategory: .foodAndDrink),
        ]
        let rules = [
            TransactionRule(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                matchMerchantContains: "Coffee",
                category: .foodAndDrink,
                createdAt: epoch
            ),
        ]
        let snapshot = ReviewSyncAssembler.snapshot(metadata: metadata, rules: rules, updatedAt: epoch)
        // Every record stamped with the one push timestamp, sorted by id.
        #expect(snapshot.metadata.map(\.id) == ["tx-a", "tx-b"])
        #expect(snapshot.metadata.allSatisfy { $0.updatedAt == epoch })

        let flattened = ReviewSyncAssembler.localState(from: snapshot)
        #expect(flattened.metadata.map(\.id) == ["tx-a", "tx-b"])
        #expect(flattened.metadata.first?.userCategory == .foodAndDrink)
        #expect(flattened.rules.first?.matchMerchantContains == "Coffee")
    }
}
