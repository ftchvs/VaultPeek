import Foundation

/// Splitting a single transaction into N category allocations (AND-550).
///
/// ## What this is (and the v1-safety contract)
///
/// A **child-allocation** model layered *additively* on top of ``TransactionDTO``.
/// The parent transaction is never mutated, re-keyed, or removed: a split is a
/// separate, opt-in record keyed by the parent's `transaction_id`. A user who
/// does **not** split anything has no ``TransactionSplit`` records, so every
/// consumer of transaction spend (budgets, summaries, review, exports, charts)
/// sees byte-identical prior behavior. This is the deferred budgeting-v2 (AND-524)
/// re-opening of scope that AND-399 explicitly cut.
///
/// A split divides the parent's signed amount (Plaid convention: positive = money
/// out, negative = money in) into ``TransactionSplitAllocation`` parts. Each part
/// carries its **own** budget category and its **own** budget-exclude flag, so a
/// `$150` Target run can be `$90` Groceries + `$60` Home, or one part can be
/// excluded from budgets while the rest counts. The defining **sum invariant** is
/// that the parts' signed amounts sum back to the parent amount (within a cent),
/// so splitting never creates or destroys money — it only re-attributes it.
///
/// ## Why a value type in `PlaidBarCore`
///
/// Pure, `Sendable`, no I/O, no hidden `Date()`. The split-aware spend math
/// (``TransactionSplitResolver``) and every aggregation that reads it stay
/// testable and shared across processes, per the project's "logic in Core"
/// doctrine. Persistence (the app-only `PlaidBarCache` store) and the editor UI
/// are separate, later surfaces — this file is the model + the sum invariant.

// MARK: - Allocation (one category slice of a split)

/// One slice of a split transaction: a signed amount attributed to a single
/// budget category, with its own budget-exclusion flag.
///
/// Each allocation has a stable `id` so the editor can address an individual part
/// (rename its category, toggle its exclude flag, change its amount) without
/// reordering the rest. The `amount` is **signed**, in the parent's currency, and
/// follows the same Plaid convention as ``TransactionDTO/amount`` (positive =
/// money out). For a normal expense the parts are positive and sum to the
/// positive parent amount; the model does not assume a sign so a refund (negative
/// parent) splits the same way.
public struct TransactionSplitAllocation: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity for this allocation row, independent of its position in the
    /// split. A fresh UUID by default so a newly-added part never collides with an
    /// existing one.
    public let id: UUID
    /// The budget category this slice is attributed to. The parent's own
    /// ``TransactionDTO/category`` is ignored once a split exists — each part
    /// declares its own bucket.
    public let category: SpendingCategory
    /// The signed amount of this slice, in the parent's currency (Plaid
    /// convention: positive = money out). The parts' amounts must sum to the
    /// parent amount (the split's sum invariant).
    public let amount: Double
    /// Whether this individual slice is excluded from budget/spend rollups. A
    /// part can be excluded while its siblings still count — e.g. a reimbursable
    /// line item carved out of a shared receipt. Defaults to `false` so an
    /// allocation counts unless explicitly excluded.
    public let excludedFromBudgets: Bool

    public init(
        id: UUID = UUID(),
        category: SpendingCategory,
        amount: Double,
        excludedFromBudgets: Bool = false
    ) {
        self.id = id
        self.category = category
        self.amount = amount
        self.excludedFromBudgets = excludedFromBudgets
    }
}

// MARK: - Split (parent → N allocations)

/// A transaction split: the parent transaction id plus the N allocations its
/// amount is divided into.
///
/// Identity is the parent's `transaction_id` (one split per transaction), so a
/// store can look a split up directly by the transaction it belongs to. The
/// `expectedTotal` is the parent's signed amount captured at split time; the
/// split is **valid** only when the allocations sum to it within a cent
/// (``isBalanced(tolerance:)``) and there is at least one allocation. An empty or
/// unbalanced split is treated as "no split" by the resolver, so a malformed
/// record degrades to the parent's own category rather than dropping or
/// double-counting the spend.
public struct TransactionSplit: Codable, Sendable, Hashable, Identifiable {
    /// Default balance tolerance in the parent's currency unit (one cent). Floating
    /// point sums of currency parts can drift sub-cent; anything within this is
    /// considered balanced. Mirrors the cent-level tolerances used elsewhere in the
    /// review engine (e.g. `reviewedChargeChanged`'s `0.005` amount compare).
    public static let balanceTolerance = 0.005

    /// The parent ``TransactionDTO/id`` (Plaid `transaction_id`) this split divides.
    public let transactionId: String
    /// The parent's signed amount at the time the split was created — the value the
    /// allocations must sum to. Persisting it (rather than re-reading the live
    /// transaction) lets the resolver detect a stale split if the underlying charge
    /// later changes amount.
    public let expectedTotal: Double
    /// The category allocations, in user-entered order. At least one for a valid
    /// split.
    public let allocations: [TransactionSplitAllocation]

    /// Stable identity — one split per parent transaction.
    public var id: String { transactionId }

    public init(
        transactionId: String,
        expectedTotal: Double,
        allocations: [TransactionSplitAllocation]
    ) {
        self.transactionId = transactionId
        self.expectedTotal = expectedTotal
        self.allocations = allocations
    }

    /// Convenience initializer that captures the parent's amount as the
    /// `expectedTotal` directly from the transaction being split.
    public init(splitting transaction: TransactionDTO, into allocations: [TransactionSplitAllocation]) {
        self.init(
            transactionId: transaction.id,
            expectedTotal: transaction.amount,
            allocations: allocations
        )
    }

    /// The signed sum of every allocation's amount.
    public var allocatedTotal: Double {
        allocations.reduce(0) { $0 + $1.amount }
    }

    /// The signed gap between the parent amount and the allocated sum. Zero (within
    /// tolerance) when the split balances; non-zero is the amount still
    /// unallocated (positive) or over-allocated (negative). Exposed so an editor
    /// can show "$10 left to allocate" without re-deriving the math.
    public var unallocatedRemainder: Double {
        expectedTotal - allocatedTotal
    }

    /// Whether the allocations sum to the parent amount within `tolerance` — the
    /// split's defining sum invariant. An empty split is never balanced (a split
    /// must have at least one part to be meaningful).
    public func isBalanced(tolerance: Double = TransactionSplit.balanceTolerance) -> Bool {
        guard !allocations.isEmpty else { return false }
        return abs(unallocatedRemainder) <= tolerance
    }

    /// Whether this split may be applied: it has at least one allocation and it
    /// balances to the parent amount. The resolver applies a split only when this
    /// holds; otherwise it falls back to the parent transaction unchanged, so a
    /// malformed split never corrupts spend totals. ``transactionId`` matching the
    /// parent is the caller's responsibility (the resolver only applies a split it
    /// looked up by that id).
    public var isValid: Bool {
        isBalanced()
    }

    // MARK: - Editing

    /// Return a copy with `allocations` replaced, re-balancing against the same
    /// `expectedTotal`. The editor uses this to add/remove/edit parts; validity is
    /// re-derived from the new allocations via ``isValid``.
    public func replacingAllocations(_ newAllocations: [TransactionSplitAllocation]) -> TransactionSplit {
        TransactionSplit(
            transactionId: transactionId,
            expectedTotal: expectedTotal,
            allocations: newAllocations
        )
    }

    /// A two-way even split of `transaction` across two categories, used as a
    /// sensible editor default / fixture seed. The first part takes any rounding
    /// remainder so the two always sum to the parent exactly (the sum invariant
    /// holds with no tolerance slack). Amounts are rounded to the cent.
    public static func evenSplit(
        of transaction: TransactionDTO,
        between first: SpendingCategory,
        and second: SpendingCategory
    ) -> TransactionSplit {
        let total = transaction.amount
        let half = (total / 2 * 100).rounded() / 100
        let remainder = (total - half)
        return TransactionSplit(
            splitting: transaction,
            into: [
                TransactionSplitAllocation(category: first, amount: remainder),
                TransactionSplitAllocation(category: second, amount: half),
            ]
        )
    }
}
