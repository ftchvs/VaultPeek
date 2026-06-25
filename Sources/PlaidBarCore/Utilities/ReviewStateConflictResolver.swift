import Foundation

/// Pure, deterministic **last-writer-wins** conflict resolution for the opt-in
/// server-synced review state (AND-552).
///
/// ## Why LWW (and not per-field merge)
///
/// A single review record (the override on one transaction, or one rule) is the
/// unit a user edits atomically — they pick a category, rename a merchant, mark a
/// transfer. Merging two concurrent edits to the *same* record field-by-field
/// would manufacture a third state the user never chose (e.g. device A's category
/// with device B's merchant rename), which is more surprising than simply keeping
/// the most recent deliberate edit. So conflict resolution is **per-record LWW**,
/// keyed on each record's monotonic `updatedAt`: for a given id, the record with
/// the newer timestamp wins; ties break deterministically so the merge is a pure
/// function of its inputs (no clock, no I/O, no randomness) and fully testable.
///
/// Distinct ids never conflict — they are unioned. So this is "merge the two
/// snapshots, and where both sides carry the same id, keep the newer write."
///
/// ## Where it runs
///
/// The local server runs `merge(...)` when a device `PUT`s its snapshot: it folds
/// the upload into the stored snapshot and returns the union, so every device
/// converges to the same set in one round-trip. The app can run the same function
/// locally to reconcile a pulled snapshot against unsynced local edits before
/// writing them back — same rule on both sides, by construction.
public enum ReviewStateConflictResolver {
    // MARK: - Snapshot merge

    /// Merge two review-state snapshots with per-record last-writer-wins.
    ///
    /// For each id present in either side: if only one side has it, that record is
    /// kept; if both do, the record with the newer `updatedAt` wins (ties resolve
    /// to `incoming`, treating the upload as the latest deliberate write). The
    /// result is ordered deterministically (metadata by transaction id, rules by
    /// rule UUID string) so two devices that converge produce byte-identical
    /// snapshots.
    ///
    /// - Parameters:
    ///   - base: the existing snapshot (e.g. the server's stored state).
    ///   - incoming: the newly uploaded snapshot (the device's state).
    /// - Returns: the merged snapshot at the current schema version.
    public static func merge(
        base: ReviewStateSnapshotDTO,
        incoming: ReviewStateSnapshotDTO
    ) -> ReviewStateSnapshotDTO {
        let mergedMetadata = mergeMetadata(base: base.metadata, incoming: incoming.metadata)
        let mergedRules = mergeRules(base: base.rules, incoming: incoming.rules)
        return ReviewStateSnapshotDTO(metadata: mergedMetadata, rules: mergedRules)
    }

    // MARK: - Record merges

    /// Per-record LWW merge of two metadata record lists, keyed on transaction id,
    /// returned sorted by id.
    public static func mergeMetadata(
        base: [ReviewMetadataRecordDTO],
        incoming: [ReviewMetadataRecordDTO]
    ) -> [ReviewMetadataRecordDTO] {
        var byId = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: newerMetadata)
        for record in incoming {
            if let existing = byId[record.id] {
                byId[record.id] = newerMetadata(existing, record)
            } else {
                byId[record.id] = record
            }
        }
        return byId.values.sorted { $0.id < $1.id }
    }

    /// Per-record LWW merge of two rule record lists, keyed on rule UUID, returned
    /// sorted by the UUID's string form for a stable order.
    public static func mergeRules(
        base: [ReviewRuleRecordDTO],
        incoming: [ReviewRuleRecordDTO]
    ) -> [ReviewRuleRecordDTO] {
        var byId = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: newerRule)
        for record in incoming {
            if let existing = byId[record.id] {
                byId[record.id] = newerRule(existing, record)
            } else {
                byId[record.id] = record
            }
        }
        return byId.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Pairwise winner (the LWW rule)

    /// The winner of a same-id metadata conflict: the newer `updatedAt`. On an
    /// exact tie the **second** argument wins, so when called as
    /// `newerMetadata(existing, incoming)` the freshly uploaded write is treated
    /// as the latest deliberate edit. Deterministic given its inputs.
    static func newerMetadata(
        _ lhs: ReviewMetadataRecordDTO,
        _ rhs: ReviewMetadataRecordDTO
    ) -> ReviewMetadataRecordDTO {
        rhs.updatedAt >= lhs.updatedAt ? rhs : lhs
    }

    /// The winner of a same-id rule conflict: the newer `updatedAt`, with the
    /// second argument winning an exact tie (see ``newerMetadata(_:_:)``).
    static func newerRule(
        _ lhs: ReviewRuleRecordDTO,
        _ rhs: ReviewRuleRecordDTO
    ) -> ReviewRuleRecordDTO {
        rhs.updatedAt >= lhs.updatedAt ? rhs : lhs
    }
}
