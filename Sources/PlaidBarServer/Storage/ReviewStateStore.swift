import FluentKit
import Foundation
import HummingbirdFluent
import PlaidBarCore

/// Local persistence for the **opt-in** server-synced review state (AND-552 —
/// deferred epic AND-524).
///
/// Mirrors `BudgetStore`: an `actor` over the same Fluent/SQLite store so writes
/// are serialized and the database stays single-writer. It persists the user's
/// review overrides and categorization rules — display-safe derived values only
/// (no Plaid tokens or access secrets), and only ever populated after an explicit
/// client opt-in. With no opted-in client these tables stay empty.
///
/// ## Conflict resolution
/// A device upload is folded into the stored snapshot with per-record
/// last-writer-wins (``ReviewStateConflictResolver``): for a given transaction id
/// or rule id, the record with the newer `updatedAt` survives; distinct ids are
/// unioned. The merged union is returned so the uploading device converges in one
/// round-trip.
actor ReviewStateStore {
    private let fluent: Fluent
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fluent: Fluent) {
        self.fluent = fluent
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Read

    /// The full stored review-state snapshot. Rows whose JSON payload no longer
    /// decodes against the current DTO (e.g. a future schema change) are skipped
    /// rather than surfaced as garbage, mirroring `BudgetStore.allBudgets()`.
    /// Metadata is returned sorted by transaction id and rules by rule id, so the
    /// snapshot is deterministic.
    func snapshot() async throws -> ReviewStateSnapshotDTO {
        let metadataRows = try await ReviewMetadataModel.query(on: fluent.db()).all()
        let ruleRows = try await ReviewRuleModel.query(on: fluent.db()).all()

        let metadata = metadataRows
            .compactMap { row -> ReviewMetadataRecordDTO? in
                guard let data = row.payload.data(using: .utf8) else { return nil }
                return try? decoder.decode(ReviewMetadataRecordDTO.self, from: data)
            }
            .sorted { $0.id < $1.id }

        let rules = ruleRows
            .compactMap { row -> ReviewRuleRecordDTO? in
                guard let data = row.payload.data(using: .utf8) else { return nil }
                return try? decoder.decode(ReviewRuleRecordDTO.self, from: data)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        return ReviewStateSnapshotDTO(metadata: metadata, rules: rules)
    }

    // MARK: - Merge upload (LWW)

    /// Fold `incoming` into the stored snapshot with per-record last-writer-wins,
    /// persist the merged result, and return it. Idempotent: re-uploading the same
    /// snapshot yields the same stored state. A row only changes on disk when the
    /// incoming record actually wins its id, so a redundant upload is cheap.
    @discardableResult
    func merge(incoming: ReviewStateSnapshotDTO) async throws -> ReviewStateSnapshotDTO {
        let base = try await snapshot()
        let merged = ReviewStateConflictResolver.merge(base: base, incoming: incoming)

        try await upsertMetadata(merged.metadata, previous: base.metadata)
        try await upsertRules(merged.rules, previous: base.rules)

        return merged
    }

    // MARK: - Opt-out / reset

    /// Remove all synced review state (opt-out, or a local-data reset). Safe to
    /// call when nothing is stored. Leaves every other table untouched.
    func clearAll() async throws {
        try await ReviewMetadataModel.query(on: fluent.db()).delete()
        try await ReviewRuleModel.query(on: fluent.db()).delete()
    }

    // MARK: - Private

    private func upsertMetadata(
        _ merged: [ReviewMetadataRecordDTO],
        previous: [ReviewMetadataRecordDTO]
    ) async throws {
        let previousById = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in merged {
            // Skip rows the merge left identical to what is already stored.
            if previousById[record.id] == record { continue }
            let payload = try jsonString(record)
            if let existing = try await ReviewMetadataModel.find(record.id, on: fluent.db()) {
                existing.payload = payload
                existing.updatedAt = record.updatedAt
                try await existing.save(on: fluent.db())
            } else {
                try await ReviewMetadataModel(
                    transactionId: record.id,
                    payload: payload,
                    updatedAt: record.updatedAt
                ).save(on: fluent.db())
            }
        }
    }

    private func upsertRules(
        _ merged: [ReviewRuleRecordDTO],
        previous: [ReviewRuleRecordDTO]
    ) async throws {
        let previousById = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in merged {
            if previousById[record.id] == record { continue }
            let key = record.id.uuidString
            let payload = try jsonString(record)
            if let existing = try await ReviewRuleModel.find(key, on: fluent.db()) {
                existing.payload = payload
                existing.updatedAt = record.updatedAt
                try await existing.save(on: fluent.db())
            } else {
                try await ReviewRuleModel(
                    ruleId: key,
                    payload: payload,
                    updatedAt: record.updatedAt
                ).save(on: fluent.db())
            }
        }
    }

    private func jsonString(_ value: some Encodable) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
