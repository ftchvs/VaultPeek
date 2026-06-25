import Foundation

/// Pure, deterministic per-month budget editing for budgeting v2 (AND-548).
///
/// The carry math lives in ``RolloverBudgetPlanner``; this is the small companion
/// that *mutates the stored set* of ``MonthlyBudgetV2`` rows while enforcing the
/// AC's immutability rule: **historical months are frozen, the current and future
/// months are editable**. Every entry point returns a new ``BudgetingV2Schema``
/// (value semantics) and leaves the input untouched, so it stays `Sendable` and
/// trivially testable — no hidden `Date()`; "now" is the explicit `asOf` month key.
///
/// Editing a frozen historical month is rejected by returning the schema unchanged
/// (a no-op), so a stale UI action can never rewrite history. Whether a month is
/// editable is decided by ``RolloverBudgetPlanner/isMonthEditable(_:asOf:)`` — the
/// single source of truth shared with the editor's enable/disable state.
public enum MonthlyBudgetEditor {

    /// The outcome of an edit attempt: the (possibly unchanged) schema plus whether
    /// the edit was applied. `applied == false` means the target month was frozen
    /// history and the schema is byte-identical to the input.
    public struct EditResult: Sendable, Hashable {
        public let schema: BudgetingV2Schema
        public let applied: Bool

        public init(schema: BudgetingV2Schema, applied: Bool) {
            self.schema = schema
            self.applied = applied
        }
    }

    /// Upsert a per-month limit (and rollover flag) for one category, but only when
    /// `month` is editable as of `asOf` (current or future). A frozen historical
    /// month is a no-op.
    ///
    /// - Parameters:
    ///   - schema: the current v2 snapshot.
    ///   - categoryId: the ``BudgetCategoryV2/id`` to budget. Must exist in the
    ///     schema's category table; an unknown id is rejected (no-op) so a budget can
    ///     never reference a missing category.
    ///   - month: the `YYYY-MM` month to set.
    ///   - monthlyLimit: the new limit. A non-finite or negative value is rejected
    ///     (no-op) — a budget limit is `>= 0`.
    ///   - rollover: whether this month's remainder carries into the next month.
    ///   - asOf: the current `YYYY-MM` (injected "now").
    /// - Returns: the updated schema and whether the edit applied.
    public static func setBudget(
        in schema: BudgetingV2Schema,
        categoryId: String,
        month: String,
        monthlyLimit: Double,
        rollover: Bool,
        asOf: String
    ) -> EditResult {
        guard
            RolloverBudgetPlanner.isMonthEditable(month, asOf: asOf),
            monthlyLimit.isFinite,
            monthlyLimit >= 0,
            schema.category(id: categoryId) != nil
        else {
            return EditResult(schema: schema, applied: false)
        }

        let updatedRow = MonthlyBudgetV2(
            month: month,
            categoryId: categoryId,
            monthlyLimit: monthlyLimit,
            rollover: rollover
        )

        var budgets = schema.budgets.filter {
            !($0.month == month && $0.categoryId == categoryId)
        }
        budgets.append(updatedRow)
        budgets.sort { lhs, rhs in
            lhs.month != rhs.month ? lhs.month < rhs.month : lhs.categoryId < rhs.categoryId
        }

        return EditResult(
            schema: BudgetingV2Schema(
                schemaVersion: schema.schemaVersion,
                groups: schema.groups,
                categories: schema.categories,
                budgets: budgets
            ),
            applied: true
        )
    }

    /// Remove a category's budget for `month`, but only when `month` is editable as
    /// of `asOf`. A frozen historical month is a no-op. Removing a row that doesn't
    /// exist still reports `applied == true` (the post-state is "no budget for that
    /// month", which is what was asked) but leaves the schema otherwise equal.
    public static func removeBudget(
        in schema: BudgetingV2Schema,
        categoryId: String,
        month: String,
        asOf: String
    ) -> EditResult {
        guard RolloverBudgetPlanner.isMonthEditable(month, asOf: asOf) else {
            return EditResult(schema: schema, applied: false)
        }
        let budgets = schema.budgets.filter {
            !($0.month == month && $0.categoryId == categoryId)
        }
        return EditResult(
            schema: BudgetingV2Schema(
                schemaVersion: schema.schemaVersion,
                groups: schema.groups,
                categories: schema.categories,
                budgets: budgets
            ),
            applied: true
        )
    }

    /// Seed the next month's budget rows from the current month's: every category
    /// budgeted in `fromMonth` gets the same limit and rollover flag in
    /// `nextMonthKey(fromMonth)`, unless that next month already has a row for the
    /// category (existing rows win — never clobber a user's forward edit). Only
    /// applies when the destination month is editable as of `asOf`.
    ///
    /// This is the "carry the budget template forward" convenience the per-month
    /// editor uses so a user doesn't re-enter every limit each month; the envelope
    /// *value* carry is separate (``RolloverBudgetPlanner``).
    public static func rolloverTemplateToNextMonth(
        in schema: BudgetingV2Schema,
        fromMonth: String,
        asOf: String
    ) -> EditResult {
        guard
            let nextMonth = RolloverBudgetPlanner.nextMonthKey(fromMonth),
            RolloverBudgetPlanner.isMonthEditable(nextMonth, asOf: asOf)
        else {
            return EditResult(schema: schema, applied: false)
        }

        let existingNextKeys = Set(
            schema.budgets
                .filter { $0.month == nextMonth }
                .map(\.categoryId)
        )
        let template = schema.budgets.filter { $0.month == fromMonth }
        guard !template.isEmpty else { return EditResult(schema: schema, applied: false) }

        var budgets = schema.budgets
        var addedAny = false
        for row in template where !existingNextKeys.contains(row.categoryId) {
            budgets.append(
                MonthlyBudgetV2(
                    month: nextMonth,
                    categoryId: row.categoryId,
                    monthlyLimit: row.monthlyLimit,
                    rollover: row.rollover
                )
            )
            addedAny = true
        }
        guard addedAny else { return EditResult(schema: schema, applied: false) }

        budgets.sort { lhs, rhs in
            lhs.month != rhs.month ? lhs.month < rhs.month : lhs.categoryId < rhs.categoryId
        }
        return EditResult(
            schema: BudgetingV2Schema(
                schemaVersion: schema.schemaVersion,
                groups: schema.groups,
                categories: schema.categories,
                budgets: budgets
            ),
            applied: true
        )
    }
}
