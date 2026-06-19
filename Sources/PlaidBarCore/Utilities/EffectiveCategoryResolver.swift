import Foundation

/// Resolves a transaction's *effective* category, transfer-ness, and
/// budget-exclusion from its review metadata and any matching rules (AND-525).
///
/// This is the override-aware foundation the spec calls out as non-negotiable:
/// resolve `userCategory` / `isTransferOverride` / `excludedFromBudgets` / rules
/// **before** aggregation. The category-precedence chain was lifted verbatim from
/// `TransactionReviewInbox.resolveCategory` so the Review Inbox keeps its exact
/// behavior; this type simply gives the same logic a reusable, testable home that
/// `CategoryBudgetPlanner.netSpendByCategory` (AND-526) can call to make spend
/// math override-aware.
///
/// Pure value type — every function is stateless and `Sendable`, with no hidden
/// `Date()` or global state. The `NLMerchantCategorizer` is injected (defaulting
/// to a fresh instance) so callers can substitute a deterministic stub.
public enum EffectiveCategoryResolver {
    /// The fully-resolved spend attributes of a transaction.
    public struct Resolution: Sendable, Equatable {
        /// The category to attribute spend to *for budget aggregation*. `nil` means
        /// genuinely uncategorized (no override, no rule, no confident Plaid
        /// category) — the row keeps surfacing for review. An unapproved on-device
        /// NL inference is deliberately **not** used here (see `suggestedCategory`):
        /// the review flow treats NL categories as display-only until the user
        /// persists them as a `userCategory`, so counting one as spend before
        /// approval would silently mis-attribute budgets.
        public let category: SpendingCategory?
        /// Provenance of `category`. Always `nil` (user override / rule) or
        /// `.plaidCategory` here — never `.appleNaturalLanguage`, since the NL tier
        /// no longer feeds the budget `category`.
        public let source: LocalAICategoryResolutionSource?
        /// The display-only on-device NL suggestion (AND-507), when one exists and
        /// the budget `category` came from neither the user nor a rule. This is the
        /// same "Suggested" badge the Review Inbox shows; it is exposed here purely
        /// so a display consumer of `Resolution` can surface the hint, but it is
        /// **never** the aggregation category. `nil` when there is no trusted NL
        /// suggestion (or the category was already settled by user/rule).
        public let suggestedCategory: SpendingCategory?
        /// Whether this row is a transfer (own-account move / card payment) and so
        /// must never count as category spend.
        public let isTransfer: Bool
        /// Whether this row is excluded from budget aggregation (explicit user
        /// choice, a rule, or — by default — because it is a transfer).
        public let excludedFromBudgets: Bool

        public init(
            category: SpendingCategory?,
            source: LocalAICategoryResolutionSource?,
            suggestedCategory: SpendingCategory? = nil,
            isTransfer: Bool,
            excludedFromBudgets: Bool
        ) {
            self.category = category
            self.source = source
            self.suggestedCategory = suggestedCategory
            self.isTransfer = isTransfer
            self.excludedFromBudgets = excludedFromBudgets
        }
    }

    /// Resolved category plus the provenance that produced it. Kept as the
    /// category-only surface the Review Inbox consumes (it derives transfer /
    /// exclusion separately, alongside its other heuristics).
    public struct ResolvedCategory: Sendable, Equatable {
        public let category: SpendingCategory?
        public let source: LocalAICategoryResolutionSource?

        public init(category: SpendingCategory?, source: LocalAICategoryResolutionSource?) {
            self.category = category
            self.source = source
        }
    }

    // MARK: - Category

    /// Apply the category precedence chain: user override → Plaid → on-device NL
    /// inference (AND-507) → uncategorized. This is the verbatim lift of the
    /// former `TransactionReviewInbox.resolveCategory`, so the inbox's effective
    /// category is unchanged.
    ///
    /// The NL tier is consulted only when the user hasn't overridden AND Plaid
    /// returned nothing usable: a nil/`.other` category, or a category Plaid
    /// itself flagged LOW/UNKNOWN (`isLowConfidenceCategory`). Even then, only a
    /// *trusted* (high/medium) inference fills the category — a `low`-confidence
    /// inference is discarded so genuinely ambiguous merchants keep flowing to the
    /// Review Inbox instead of getting a confident wrong guess.
    public static func resolveCategory(
        transaction: TransactionDTO,
        userCategory: SpendingCategory?,
        nlCategorizer: NLMerchantCategorizer = NLMerchantCategorizer()
    ) -> ResolvedCategory {
        if let userCategory {
            return ResolvedCategory(category: userCategory, source: nil)
        }

        let plaidCategory = transaction.category
        let plaidIsUsable = plaidCategory != nil
            && plaidCategory != .other
            && !transaction.isLowConfidenceCategory
        if plaidIsUsable {
            return ResolvedCategory(category: plaidCategory, source: .plaidCategory)
        }

        if let inference = nlCategorizer.infer(for: transaction), inference.isTrusted {
            return ResolvedCategory(category: inference.category, source: .appleNaturalLanguage)
        }

        // Nothing usable: keep Plaid's (possibly nil/.other/low-confidence)
        // category so the `.uncategorized` heuristic still surfaces it.
        return ResolvedCategory(
            category: plaidCategory,
            source: plaidCategory == nil ? nil : .plaidCategory
        )
    }

    // MARK: - Full resolution (AND-526 surface)

    /// Fully resolve a transaction's spend attributes from its review metadata and
    /// any matching rules. This is the surface `CategoryBudgetPlanner` (AND-526)
    /// calls to make spend math override-aware.
    ///
    /// Precedence:
    /// - **Category (budget):** user override → matching rule's category → a
    ///   *confident* Plaid category → uncategorized. Unlike `resolveCategory`, the
    ///   budget surface deliberately **stops before the NL tier**: an unapproved
    ///   on-device NL suggestion must not be counted as that category before the
    ///   user approves it (the review flow treats NL categories as display-only
    ///   until persisted as a `userCategory`). The NL suggestion is still computed
    ///   and exposed on `Resolution.suggestedCategory` for display consumers.
    /// - **Transfer:** user `isTransferOverride` → matching rule's `isTransfer` →
    ///   transfer-category inference (`TRANSFER_IN`/`TRANSFER_OUT`).
    /// - **Excluded from budgets:** OR-combined positive exclude signals — the row
    ///   is excluded if the user explicitly excluded it (`excludedFromBudgets ==
    ///   true`), OR a matching rule excludes it, OR it is a transfer. (A first
    ///   non-nil chain can't be used: seeded metadata stores a non-optional
    ///   `false`, which would otherwise short-circuit and suppress both rule-based
    ///   and transfer-default exclusion.)
    ///
    /// When several rules match, the earliest in `rules` order with a value for a
    /// given field wins (callers keep rules in their intended priority order).
    public static func resolve(
        transaction: TransactionDTO,
        metadata: TransactionReviewMetadata? = nil,
        rules: [TransactionRule] = [],
        nlCategorizer: NLMerchantCategorizer = NLMerchantCategorizer()
    ) -> Resolution {
        let matchedRules = rules.filter { $0.matches(transaction) }

        // Budget category: user override wins outright; otherwise a matching rule's
        // category is an explicit user intent; otherwise a *confident* Plaid
        // category; otherwise uncategorized. The NL tier is intentionally excluded
        // here so an unapproved suggestion never becomes the aggregation category.
        let budgetCategory: SpendingCategory?
        let budgetSource: LocalAICategoryResolutionSource?
        if let userCategory = metadata?.userCategory {
            budgetCategory = userCategory
            budgetSource = nil
        } else if let ruleCategory = firstRuleValue(matchedRules, \.category) {
            budgetCategory = ruleCategory
            budgetSource = nil
        } else if let plaidCategory = confidentPlaidCategory(transaction) {
            budgetCategory = plaidCategory
            budgetSource = .plaidCategory
        } else {
            budgetCategory = nil
            budgetSource = nil
        }

        // Display-only NL suggestion: only meaningful when the budget category was
        // not already settled by the user or a rule. Mirrors the inbox's "Suggested"
        // badge but never feeds the aggregation category above.
        let suggestedCategory: SpendingCategory?
        if metadata?.userCategory == nil,
           firstRuleValue(matchedRules, \.category) == nil {
            let display = resolveCategory(
                transaction: transaction,
                userCategory: nil,
                nlCategorizer: nlCategorizer
            )
            suggestedCategory = display.source == .appleNaturalLanguage ? display.category : nil
        } else {
            suggestedCategory = nil
        }

        // Transfer: explicit metadata override → rule → category-derived.
        let isTransfer = metadata?.isTransferOverride
            ?? firstRuleValue(matchedRules, \.isTransfer)
            ?? budgetCategory.map(isTransferCategory)
            ?? false

        // Exclusion: OR-combine the positive exclude signals. A non-optional `false`
        // from seeded metadata is treated as "no opinion", NOT an explicit choice.
        //
        // v1 limitation: because the persisted `excludedFromBudgets` Bool can't
        // distinguish an explicit user "false" from the default "false", an explicit
        // user "include this transfer" expressed via the metadata bool *alone* is
        // not honored in v1 — a transfer stays excluded. The explicit-include path
        // that *is* honored is `isTransferOverride == false` (un-transfer the row),
        // which clears the transfer-default exclusion below. Revisit if a dedicated
        // tri-state include flag is needed.
        let excludedFromBudgets =
            (metadata?.excludedFromBudgets == true)
            || (firstRuleValue(matchedRules, \.excludedFromBudgets) == true)
            || isTransfer

        return Resolution(
            category: budgetCategory,
            source: budgetSource,
            suggestedCategory: suggestedCategory,
            isTransfer: isTransfer,
            excludedFromBudgets: excludedFromBudgets
        )
    }

    // MARK: - Helpers

    /// Whether `category` is one of the transfer cases (`TRANSFER_IN` /
    /// `TRANSFER_OUT`) that must never count as category spend.
    public static func isTransferCategory(_ category: SpendingCategory) -> Bool {
        category == .transfer || category == .transferOut
    }

    /// The first non-nil value of `keyPath` across the matched rules, in order.
    private static func firstRuleValue<Value>(
        _ rules: [TransactionRule],
        _ keyPath: KeyPath<TransactionRule, Value?>
    ) -> Value? {
        for rule in rules {
            if let value = rule[keyPath: keyPath] { return value }
        }
        return nil
    }

    /// The transaction's Plaid category when it is usable for budgeting: present,
    /// not `.other`, and not flagged low/unknown confidence. `nil` otherwise — the
    /// budget surface treats anything less as "no confident category" and falls
    /// through to uncategorized (NL suggestions stay display-only). Same usability
    /// test as the verbatim `resolveCategory` lift, minus the NL tier.
    private static func confidentPlaidCategory(_ transaction: TransactionDTO) -> SpendingCategory? {
        let plaidCategory = transaction.category
        let usable = plaidCategory != nil
            && plaidCategory != .other
            && !transaction.isLowConfidenceCategory
        return usable ? plaidCategory : nil
    }
}
