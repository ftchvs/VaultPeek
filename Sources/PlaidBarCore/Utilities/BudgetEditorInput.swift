import Foundation

/// Pure parsing + validation for the per-category budget editor (AND-540).
///
/// The `BudgetEditorSheet` lets a user type a monthly limit for one category and
/// either save it or clear it. All of the "is this a legal edit, and what does it
/// resolve to" logic lives here as a stateless `enum` so it is `Sendable`,
/// testable, and identical wherever a budget is edited — the view only renders the
/// result and dispatches the resulting `AppState.setCategoryBudget` /
/// `removeCategoryBudget` call.
///
/// Mirrors `CategoryBudgetPlanner` excluded-category rules: income and transfer
/// categories are never spend, so they can never carry a budget.
public enum BudgetEditorInput {
    /// Outcome of interpreting the editor's raw text for a category.
    public enum Outcome: Sendable, Hashable {
        /// The category itself cannot be budgeted (income / transfer).
        case categoryNotBudgetable
        /// Field is blank — nothing to do (Save is disabled).
        case empty
        /// Text is not a parseable, non-negative amount.
        case invalid
        /// A positive amount the user wants to save as the monthly limit.
        case save(amount: Double)
        /// A zero amount — interpreted as "clear this budget".
        case clear

        /// True when this outcome is something the user can commit with Save.
        public var isCommittable: Bool {
            switch self {
            case .save, .clear: true
            case .categoryNotBudgetable, .empty, .invalid: false
            }
        }
    }

    /// Categories that can never carry a budget (income + both transfer
    /// directions). Kept in lock-step with `CategoryBudgetPlanner.excludedCategories`.
    public static func isBudgetable(_ category: SpendingCategory) -> Bool {
        !CategoryBudgetPlanner.excludedCategories.contains(category)
    }

    /// Interpret the editor's raw text for `category`.
    ///
    /// - Trims whitespace; strips a single leading currency symbol and any grouping
    ///   separators so "$1,200" parses; accepts both `.` and `,` decimal forms.
    /// - A blank field is `.empty`; an unparseable / negative value is `.invalid`.
    /// - Exactly `0` resolves to `.clear` (remove the saved budget); any positive
    ///   amount resolves to `.save`.
    /// - A non-budgetable category short-circuits to `.categoryNotBudgetable`
    ///   regardless of the text.
    public static func parse(
        _ rawText: String,
        category: SpendingCategory
    ) -> Outcome {
        guard isBudgetable(category) else { return .categoryNotBudgetable }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard let amount = normalizedAmount(trimmed) else { return .invalid }
        guard amount >= 0, amount.isFinite else { return .invalid }

        return amount == 0 ? .clear : .save(amount: amount)
    }

    /// Parse a user-typed amount tolerant of a currency symbol, grouping
    /// separators, and either decimal convention. Returns `nil` when the residue
    /// is not a single non-negative number.
    private static func normalizedAmount(_ text: String) -> Double? {
        var cleaned = text
        // Drop a leading currency symbol (e.g. "$", "€", "£") and any spaces.
        cleaned.removeAll { $0 == "$" || $0 == "€" || $0 == "£" || $0 == " " }
        guard !cleaned.isEmpty else { return nil }

        // Reject anything that isn't digits plus at most the separators we handle,
        // so "12.3.4", "1e9", or "abc" never sneak through as a Double.
        let allowed = Set("0123456789.,")
        guard cleaned.allSatisfy({ allowed.contains($0) }) else { return nil }

        // Normalize to a `.`-decimal form. If both separators appear, the last one
        // is the decimal point and the other is grouping; if only commas appear,
        // treat a single trailing-group comma as decimal only when it looks like
        // cents (",dd"), otherwise as grouping.
        let normalized = normalizeSeparators(cleaned)
        guard let value = Double(normalized) else { return nil }
        return value
    }

    private static func normalizeSeparators(_ text: String) -> String {
        let hasDot = text.contains(".")
        let hasComma = text.contains(",")

        if hasDot && hasComma {
            // The right-most separator is the decimal point; strip the other.
            if let lastDot = text.lastIndex(of: "."),
               let lastComma = text.lastIndex(of: ",") {
                if lastDot > lastComma {
                    // "1,200.50" — comma groups, dot decimals.
                    return text.replacingOccurrences(of: ",", with: "")
                } else {
                    // "1.200,50" — dot groups, comma decimals.
                    return text
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                }
            }
        }

        if hasComma && !hasDot {
            // Only commas: a single comma followed by exactly two digits is a
            // decimal (e.g. "12,50"); anything else is grouping ("1,200").
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count == 2 {
                return parts[0] + "." + parts[1]
            }
            return text.replacingOccurrences(of: ",", with: "")
        }

        return text
    }
}
