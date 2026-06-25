import Foundation

/// Pure, deterministic per-month budget + rollover ("envelope carry") planning
/// for budgeting v2 (AND-548 — deferred epic AND-524).
///
/// ## What this adds on top of AND-546
///
/// The merged v2 schema (AND-546) already persists ``MonthlyBudgetV2`` rows keyed
/// by `(month, category)` with a per-row `rollover` flag. The *foundation only
/// stores* those fields. This planner is the **math**: given a category's
/// chronological budget rows and that category's per-month spend, it computes the
/// envelope carry — the unspent (or overspent) remainder of each month rolled into
/// the next month's available amount when rollover is enabled for that month.
///
/// ## Carry-forward rule
///
/// For one category, walking its months in chronological order, with `carryIn`
/// seeded to `0` for the first month:
///
/// ```text
/// available = monthlyLimit + carryIn
/// spent     = override-aware net spend for the month  (signed; refunds net in)
/// remaining = available - spent
/// carryOut  = (this month's row.rollover) ? remaining : 0
/// ```
///
/// `carryOut` feeds the next chronological month's `carryIn`. The carry is a true
/// **envelope**: a positive `remaining` (under budget) *adds* to next month, and a
/// negative `remaining` (over budget) *subtracts* from it — overspend carries too,
/// matching the issue's "unspent **or** overspend" rule. A gap month with no
/// budget row breaks the chain (there is no envelope to carry through), so a later
/// month starts fresh from its own limit.
///
/// ## Per-category opt-out
///
/// Rollover is opt-in per `(month, category)` via the row's `rollover` flag, so a
/// category opts out simply by having `rollover == false` on its rows — that month
/// keeps `carryOut == 0` and the next month starts from its bare limit. A whole
/// category can be opted out in one call with ``optedOutCategoryIds``, which forces
/// `carryOut == 0` for every one of its months regardless of the row flag (the
/// UI's per-category toggle); the stored rows are never mutated.
///
/// ## Historical immutability
///
/// The planner is read-only — it never edits a row. Whether a month is *editable*
/// is a policy the UI enforces; ``isMonthEditable(_:asOf:calendar:)`` encodes it
/// (only the current month and the future are editable; past months are frozen
/// history). The carry math itself reads every month, past and present, so a frozen
/// historical month still contributes its remainder to the carry.
///
/// ## Determinism
///
/// Like ``CategoryBudgetPlanner`` and ``SafeToSpendCalculator``, every entry point
/// takes an explicit `Calendar` (and, where "now" matters, an explicit `asOf`
/// month key) — there is no hidden `Date()`. Results are fully reproducible in
/// `PlaidBarCore` unit tests.
public enum RolloverBudgetPlanner {

    // MARK: - Per-month result

    /// The resolved budget for a single `(category, month)` after applying the
    /// envelope carry. Pure value type; `Sendable`.
    public struct MonthResult: Sendable, Hashable {
        /// The budgeted month, `YYYY-MM`.
        public let month: String
        /// The v2 category id (``BudgetCategoryV2/id``).
        public let categoryId: String
        /// The month's own stored limit (``MonthlyBudgetV2/monthlyLimit``).
        public let baseLimit: Double
        /// Remainder carried *into* this month from the prior month's envelope.
        /// `0` for the first month in the chain, for a month whose predecessor had
        /// rollover off, or after a gap. Can be negative (carried overspend).
        public let carriedIn: Double
        /// Effective spending power this month: `baseLimit + carriedIn`.
        public let available: Double
        /// Override-aware net spend booked against this category this month.
        public let spent: Double
        /// What's left after spend: `available - spent`. Negative when overspent.
        public let remaining: Double
        /// Remainder carried *out* of this month into the next: `remaining` when
        /// rollover is active for this month, else `0`.
        public let carriedOut: Double
        /// Whether rollover was active for this month (row flag on, category not
        /// globally opted out). Surfaced so the UI can label the carry without
        /// re-deriving it (never communicate the on/off state by color alone).
        public let rolloverActive: Bool

        public init(
            month: String,
            categoryId: String,
            baseLimit: Double,
            carriedIn: Double,
            spent: Double,
            rolloverActive: Bool
        ) {
            self.month = month
            self.categoryId = categoryId
            self.baseLimit = baseLimit
            self.carriedIn = carriedIn
            self.available = baseLimit + carriedIn
            self.spent = spent
            self.remaining = (baseLimit + carriedIn) - spent
            self.carriedOut = rolloverActive ? ((baseLimit + carriedIn) - spent) : 0
            self.rolloverActive = rolloverActive
        }

        /// Stable identity — one result per `(month, category)`, matching
        /// ``MonthlyBudgetV2/id``.
        public var id: String { "\(month)|\(categoryId)" }
    }

    // MARK: - Carry-forward over one category's months

    /// Resolve the envelope carry across `budgets` for **one** category, in
    /// chronological month order.
    ///
    /// - Parameters:
    ///   - budgets: this category's ``MonthlyBudgetV2`` rows (any order; the planner
    ///     sorts by month). Rows for other categories are ignored. Duplicate months
    ///     for the category collapse to the last one seen after sort (a malformed
    ///     input degrades, never crashes).
    ///   - spendByMonth: override-aware net spend per `YYYY-MM` for this category
    ///     (typically derived from ``CategoryBudgetPlanner/overrideAwareSpend(transactions:month:metadata:rules:calendar:)``).
    ///     A missing month is treated as `0` spend.
    ///   - categoryId: the category these budgets belong to (used to filter
    ///     `budgets` and to ignore the global opt-out check). Pass the
    ///     ``BudgetCategoryV2/id``.
    ///   - optedOut: when `true`, this category is globally opted out of rollover —
    ///     every month's `carryOut` is forced to `0` regardless of its row flag.
    /// - Returns: one ``MonthResult`` per budgeted month, in chronological order.
    public static func resolveCarry(
        budgets: [MonthlyBudgetV2],
        spendByMonth: [String: Double],
        categoryId: String,
        optedOut: Bool = false
    ) -> [MonthResult] {
        // Only this category's rows; collapse dup months (last wins) and sort
        // chronologically — `YYYY-MM` sorts lexicographically in date order.
        var rowByMonth: [String: MonthlyBudgetV2] = [:]
        for budget in budgets where budget.categoryId == categoryId {
            rowByMonth[budget.month] = budget
        }
        let months = rowByMonth.keys.sorted()
        guard !months.isEmpty else { return [] }

        var results: [MonthResult] = []
        results.reserveCapacity(months.count)

        var carryIn = 0.0
        var previousMonth: String?

        for month in months {
            // A non-contiguous gap breaks the envelope: there's no budget row in the
            // intervening month(s) to carry through, so the chain restarts here.
            if let previousMonth, !Self.isImmediateSuccessor(previousMonth, of: month) {
                carryIn = 0
            }

            guard let row = rowByMonth[month] else { continue }
            let spent = spendByMonth[month] ?? 0
            // Rollover is active only when the row opts in AND the category isn't
            // globally opted out by the caller's per-category toggle.
            let rolloverActive = row.rollover && !optedOut

            let result = MonthResult(
                month: month,
                categoryId: categoryId,
                baseLimit: row.monthlyLimit,
                carriedIn: carryIn,
                spent: spent,
                rolloverActive: rolloverActive
            )
            results.append(result)

            carryIn = result.carriedOut
            previousMonth = month
        }
        return results
    }

    /// Resolve the envelope carry for **every** category present in `budgets`,
    /// returning each category's chronological ``MonthResult`` chain keyed by
    /// category id. A convenience fan-out over ``resolveCarry(budgets:spendByMonth:categoryId:optedOut:)``.
    ///
    /// - Parameters:
    ///   - budgets: all ``MonthlyBudgetV2`` rows (mixed categories/months).
    ///   - spendByMonthByCategory: override-aware net spend keyed
    ///     `categoryId → (YYYY-MM → spend)`.
    ///   - optedOutCategoryIds: category ids globally opted out of rollover (the
    ///     per-category toggle); their `carryOut` is forced to `0` every month.
    public static func resolveCarryByCategory(
        budgets: [MonthlyBudgetV2],
        spendByMonthByCategory: [String: [String: Double]],
        optedOutCategoryIds: Set<String> = []
    ) -> [String: [MonthResult]] {
        let categoryIds = Set(budgets.map(\.categoryId))
        var out: [String: [MonthResult]] = [:]
        out.reserveCapacity(categoryIds.count)
        for categoryId in categoryIds {
            out[categoryId] = resolveCarry(
                budgets: budgets,
                spendByMonth: spendByMonthByCategory[categoryId] ?? [:],
                categoryId: categoryId,
                optedOut: optedOutCategoryIds.contains(categoryId)
            )
        }
        return out
    }

    // MARK: - Historical immutability policy

    /// Whether `month` (`YYYY-MM`) is editable as of `asOf` (`YYYY-MM`). The current
    /// month and any future month are editable; a past month is frozen history.
    ///
    /// This is the policy behind the AC "historical months immutable, current
    /// editable" — the planner exposes it so a single source of truth gates the
    /// editor UI. The carry math itself still reads frozen months (their stored
    /// remainder rolls forward); only *editing* a frozen month is disallowed.
    ///
    /// A malformed `month` or `asOf` key returns `false` (fail closed — never let a
    /// bad key make a historical month look editable).
    public static func isMonthEditable(_ month: String, asOf: String) -> Bool {
        guard Self.isCanonicalMonthKey(month), Self.isCanonicalMonthKey(asOf) else {
            return false
        }
        return month >= asOf
    }

    // MARK: - Month-key arithmetic

    /// The `YYYY-MM` month key for the month after `month`, or `nil` for a malformed
    /// key. Deterministic — pure string arithmetic on the canonical key, so it needs
    /// no `Calendar` and matches the lexicographic ordering the rest of the app sorts
    /// months by.
    public static func nextMonthKey(_ month: String) -> String? {
        guard let (year, monthValue) = parseMonthKey(month) else { return nil }
        let next = monthValue == 12 ? (year + 1, 1) : (year, monthValue + 1)
        return formatMonthKey(year: next.0, month: next.1)
    }

    /// The `YYYY-MM` month key for the month before `month`, or `nil` for a
    /// malformed key.
    public static func previousMonthKey(_ month: String) -> String? {
        guard let (year, monthValue) = parseMonthKey(month) else { return nil }
        let prev = monthValue == 1 ? (year - 1, 12) : (year, monthValue - 1)
        return formatMonthKey(year: prev.0, month: prev.1)
    }

    /// The `YYYY-MM` month key for the month containing `date` in `calendar`. The one
    /// entry point that consults a date — and only via an explicit injected
    /// `Calendar`, so "now" stays testable.
    public static func monthKey(for date: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        return formatMonthKey(year: year, month: month)
    }

    // MARK: - Internals

    /// Whether `candidate` is exactly the month after `month` (`YYYY-MM`). Used to
    /// detect a contiguous chain vs. a gap that resets the carry.
    static func isImmediateSuccessor(_ month: String, of candidate: String) -> Bool {
        nextMonthKey(month) == candidate
    }

    /// Fast structural check that `value` is a canonical `YYYY-MM` month key with an
    /// in-range month (`01`…`12`). Mirrors `Formatters.isCanonicalTransactionDateKey`
    /// for the month bucket.
    static func isCanonicalMonthKey(_ value: String) -> Bool {
        parseMonthKey(value) != nil
    }

    /// Parse a canonical `YYYY-MM` key into `(year, month)`, or `nil` when malformed
    /// (wrong length/shape, non-numeric, month out of `1...12`).
    static func parseMonthKey(_ value: String) -> (year: Int, month: Int)? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4,
              parts[1].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        return (year, month)
    }

    /// Format `(year, month)` back into a zero-padded canonical `YYYY-MM` key.
    static func formatMonthKey(year: Int, month: Int) -> String {
        let yearPart = String(format: "%04d", year)
        let monthPart = String(format: "%02d", month)
        return "\(yearPart)-\(monthPart)"
    }
}
