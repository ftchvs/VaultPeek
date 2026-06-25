import Foundation

/// Wire DTOs for the **opt-in** server-synced review state (AND-552 — deferred
/// epic AND-524).
///
/// ## What this is (and is not)
///
/// Today the transaction review state — the per-transaction overrides in
/// ``TransactionReviewMetadata`` (user category, merchant rename, transfer flag,
/// budget exclusion, note, status) plus the user's ``TransactionRule`` set — is
/// **app-local JSON only**; the local server never sees it. AND-552 adds an
/// *optional* multi-device sync of exactly that state through a new `/api/review`
/// table, gated by the ``ServerSyncedReviewFeatureFlag`` (default **OFF**).
///
/// These DTOs are the on-the-wire shape the app pushes to / pulls from the local
/// server when, and only when, the user has explicitly opted in. They are
/// `Sendable` value types living in `PlaidBarCore` so both the app's sync client
/// and the server's route/store share one contract.
///
/// ## Trust-boundary note
///
/// A synced record stores **user category overrides** (and merchant renames,
/// notes, etc.) on the local server's SQLite — state the server otherwise never
/// holds. That expansion is documented in `SECURITY.md`. It happens only on
/// explicit opt-in; with the flag OFF nothing here is ever constructed or sent,
/// so the not-opted-in user's behavior is byte-identical to today.

// MARK: - Per-record sync envelopes

/// One synced review-metadata record: the full ``TransactionReviewMetadata`` plus
/// the `updatedAt` timestamp that drives last-writer-wins conflict resolution.
///
/// The metadata's own `reviewedAt` marks *when the user reviewed the charge*, not
/// *when this record was last written*, so it cannot order concurrent edits. A
/// dedicated monotonic `updatedAt` (set by the writer on every change) is the LWW
/// clock: the record with the newer `updatedAt` wins a conflict on the same id.
public struct ReviewMetadataRecordDTO: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity — the transaction id the metadata belongs to (mirrors
    /// ``TransactionReviewMetadata/id``).
    public var id: String { metadata.id }
    /// The full review metadata for this transaction.
    public let metadata: TransactionReviewMetadata
    /// LWW clock: when this record was last written on the originating device.
    public let updatedAt: Date

    public init(metadata: TransactionReviewMetadata, updatedAt: Date) {
        self.metadata = metadata
        self.updatedAt = updatedAt
    }
}

/// One synced categorization-rule record: the full ``TransactionRule`` plus the
/// `updatedAt` LWW clock. The rule's own `createdAt` orders creation, not edits,
/// so `updatedAt` is carried separately for conflict resolution.
public struct ReviewRuleRecordDTO: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity — the rule's UUID (mirrors ``TransactionRule/id``).
    public var id: UUID { rule.id }
    /// The full categorization rule.
    public let rule: TransactionRule
    /// LWW clock: when this rule was last written on the originating device.
    public let updatedAt: Date

    public init(rule: TransactionRule, updatedAt: Date) {
        self.rule = rule
        self.updatedAt = updatedAt
    }
}

// MARK: - Snapshot (request + response payloads)

/// The full opt-in review-state snapshot exchanged with `/api/review`.
///
/// `GET /api/review` returns the server's current snapshot; `PUT /api/review`
/// uploads the device's snapshot and returns the **merged** result (the server
/// resolves conflicts via ``ReviewStateConflictResolver`` and echoes the union
/// back so the device converges in one round-trip). Both directions use this one
/// shape so the contract is symmetric.
public struct ReviewStateSnapshotDTO: Codable, Sendable, Equatable {
    /// Schema version so a future shape change reads older snapshots as a miss
    /// rather than a hard decode failure (mirrors ``BudgetingV2Schema``).
    public static let currentSchemaVersion = 1

    /// The schema version this snapshot was written with.
    public let schemaVersion: Int
    /// All synced per-transaction review metadata records.
    public let metadata: [ReviewMetadataRecordDTO]
    /// All synced categorization-rule records.
    public let rules: [ReviewRuleRecordDTO]

    public init(
        schemaVersion: Int = ReviewStateSnapshotDTO.currentSchemaVersion,
        metadata: [ReviewMetadataRecordDTO],
        rules: [ReviewRuleRecordDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.rules = rules
    }

    /// An empty snapshot (no synced records) at the current schema version.
    public static var empty: ReviewStateSnapshotDTO {
        ReviewStateSnapshotDTO(metadata: [], rules: [])
    }

    /// Whether this snapshot matches the current schema version.
    public var isCurrentSchema: Bool {
        schemaVersion == Self.currentSchemaVersion
    }
}
