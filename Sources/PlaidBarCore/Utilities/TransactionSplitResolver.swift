import Foundation

/// Expands transactions into split-aware **spend rows** (AND-550).
///
/// This is the single additive seam every spend consumer routes through to become
/// split-aware. Given a transaction and (optionally) its ``TransactionSplit``, it
/// emits one ``SpendRow`` per category allocation:
///
/// - **No split** (the common case): exactly **one** row, carrying the parent's
///   own id / amount / category / date — byte-identical to the un-split transaction
///   the consumer used before. This is the v1-safety guarantee: a user with no
///   splits is unaffected across every consumer.
/// - **A valid split**: one row **per allocation**, each with its own category,
///   its own signed amount, and its own budget-exclude flag. The parent itself
///   never appears as a row, so rollups count the **parts, not the parent**
///   (the AC's invariant). Because a valid split's parts sum to the parent amount,
///   the *total* spend is conserved — only the per-category attribution changes.
/// - **A malformed split** (empty, or allocations that don't sum to the parent):
///   treated as no split — the resolver falls back to the single parent row, so a
///   bad record never drops or double-counts the charge. Editing/removing the
///   split therefore restores the original automatically (no split → parent row).
///
/// Pure, `Sendable`, deterministic — no I/O, no hidden `Date()`. Aggregations
/// (`CategoryBudgetPlanner`, `SpendingSummary`, exports, charts) call ``spendRows``
/// instead of iterating raw transactions to inherit split-awareness with a default
/// of "no splits = unchanged".
public enum TransactionSplitResolver {
    /// One unit of spend attribution after splits are applied: either a whole
    /// (un-split) transaction or one allocation of a split. Carries the values an
    /// aggregator needs — id, signed amount, category, date, the parent transaction
    /// for further resolution (overrides/rules), and whether this row is excluded.
    public struct SpendRow: Sendable, Equatable {
        /// The originating transaction. For a split allocation this is the parent;
        /// the allocation does not invent a synthetic transaction, so a consumer
        /// that still needs the parent's merchant/name/override metadata can read it.
        public let transaction: TransactionDTO
        /// The signed amount attributed to this row (Plaid convention: positive =
        /// money out). For an un-split transaction this equals `transaction.amount`;
        /// for a split allocation it is the allocation's slice.
        public let amount: Double
        /// The budget category for this row. For an un-split transaction this is the
        /// transaction's own ``TransactionDTO/category`` (which the aggregator may
        /// still override via metadata/rules); for a split allocation it is the
        /// allocation's declared category, which **supersedes** the parent category
        /// and is not subject to per-parent recategorization (the user already chose
        /// it explicitly when splitting).
        public let category: SpendingCategory?
        /// Whether this row was explicitly excluded from budgets at the **split**
        /// level (the allocation's flag). An un-split row is never split-excluded
        /// (`false`); its exclusion is still decided downstream by the override
        /// resolver as before. A split allocation marked excluded drops out of
        /// rollups regardless of category.
        public let isSplitExcluded: Bool
        /// Whether this row originated from a split allocation (vs. a whole
        /// transaction). Lets a consumer that needs to *bypass* per-parent
        /// override/rule resolution (because the split already declared the
        /// category) branch on it.
        public let isSplitAllocation: Bool
        /// Stable identity for the row: the parent id for an un-split transaction,
        /// or `"<txid>#<allocationUUID>"` for a split allocation, so per-row dedup /
        /// addressing stays unique across a split's parts.
        public let id: String

        public init(
            transaction: TransactionDTO,
            amount: Double,
            category: SpendingCategory?,
            isSplitExcluded: Bool,
            isSplitAllocation: Bool,
            id: String
        ) {
            self.transaction = transaction
            self.amount = amount
            self.category = category
            self.isSplitExcluded = isSplitExcluded
            self.isSplitAllocation = isSplitAllocation
            self.id = id
        }

        /// The row's date — always the parent transaction's date, so a split's
        /// parts land in the same month/period as the original charge.
        public var date: String { transaction.date }
    }

    /// Index a split list by its parent `transaction_id` for O(1) lookup during a
    /// single aggregation pass. On a duplicate parent id the first split wins
    /// (deterministic) — a store should never hold two splits for one transaction,
    /// but the resolver stays total in case it does.
    public static func index(_ splits: [TransactionSplit]) -> [String: TransactionSplit] {
        Dictionary(splits.map { ($0.transactionId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Expand one transaction into its spend rows given a pre-built split index.
    ///
    /// Returns a single parent row when the transaction has no split, or an empty/
    /// invalid split; otherwise one row per allocation. The `splitsByTransactionId`
    /// index is built once by the caller (see ``index(_:)``) so a full pass stays
    /// O(transactions + allocations).
    public static func spendRows(
        for transaction: TransactionDTO,
        splitsByTransactionId: [String: TransactionSplit]
    ) -> [SpendRow] {
        guard let split = splitsByTransactionId[transaction.id], split.isValid else {
            return [parentRow(for: transaction)]
        }
        return split.allocations.map { allocation in
            SpendRow(
                transaction: transaction,
                amount: allocation.amount,
                category: allocation.category,
                isSplitExcluded: allocation.excludedFromBudgets,
                isSplitAllocation: true,
                id: "\(transaction.id)#\(allocation.id.uuidString)"
            )
        }
    }

    /// Expand a whole transaction list into split-aware spend rows. With an empty
    /// `splits` argument (the default), this is exactly one row per transaction,
    /// each equal to its parent — the byte-identical no-split path.
    public static func spendRows(
        from transactions: [TransactionDTO],
        splits: [TransactionSplit] = []
    ) -> [SpendRow] {
        guard !splits.isEmpty else { return transactions.map(parentRow(for:)) }
        let index = index(splits)
        return transactions.flatMap { spendRows(for: $0, splitsByTransactionId: index) }
    }

    /// The single row for an un-split transaction: parent id, parent signed amount,
    /// parent category, never split-excluded.
    private static func parentRow(for transaction: TransactionDTO) -> SpendRow {
        SpendRow(
            transaction: transaction,
            amount: transaction.amount,
            category: transaction.category,
            isSplitExcluded: false,
            isSplitAllocation: false,
            id: transaction.id
        )
    }
}
