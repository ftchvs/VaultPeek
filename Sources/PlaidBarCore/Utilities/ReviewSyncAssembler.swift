import Foundation

/// Pure assembly/flatten helpers for the opt-in review sync (AND-552).
///
/// AppState owns the in-memory review state (`[TransactionReviewMetadata]` +
/// `[TransactionRule]`); these helpers turn that into the ``ReviewStateSnapshotDTO``
/// wire shape to push, and fold a server snapshot back into the plain in-memory
/// arrays. They live in `PlaidBarCore` (not the `@main` app target) so they are
/// `Sendable` and unit-testable without a server.
public enum ReviewSyncAssembler {
    /// Build a wire snapshot from in-memory review metadata + rules, stamping each
    /// record with `updatedAt` as its last-writer-wins clock. One `updatedAt` is
    /// applied to every record in a single push — the device writes its review
    /// state atomically (see `ReviewStorageWriter`), so all records in one upload
    /// share that write's timestamp. Records are sorted (metadata by transaction
    /// id, rules by UUID) so two devices that converge produce identical snapshots.
    public static func snapshot(
        metadata: [TransactionReviewMetadata],
        rules: [TransactionRule],
        updatedAt: Date
    ) -> ReviewStateSnapshotDTO {
        ReviewStateSnapshotDTO(
            metadata: metadata
                .map { ReviewMetadataRecordDTO(metadata: $0, updatedAt: updatedAt) }
                .sorted { $0.id < $1.id },
            rules: rules
                .map { ReviewRuleRecordDTO(rule: $0, updatedAt: updatedAt) }
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    /// Flatten a wire snapshot back into the plain in-memory review metadata + rules
    /// AppState holds (dropping the per-record sync clocks). Metadata is returned in
    /// transaction-id order and rules in UUID order so a converged device renders a
    /// stable list.
    public static func localState(
        from snapshot: ReviewStateSnapshotDTO
    ) -> (metadata: [TransactionReviewMetadata], rules: [TransactionRule]) {
        let metadata = snapshot.metadata
            .sorted { $0.id < $1.id }
            .map(\.metadata)
        let rules = snapshot.rules
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map(\.rule)
        return (metadata, rules)
    }
}
