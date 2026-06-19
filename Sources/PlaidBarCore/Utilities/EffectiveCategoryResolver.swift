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
        /// The category to attribute spend to. `nil` means genuinely
        /// uncategorized (no override, no usable Plaid category, no trusted NL
        /// inference, no rule) — the row keeps surfacing for review.
        public let category: SpendingCategory?
        /// Provenance of `category`. `.appleNaturalLanguage` is the on-device NL
        /// suggestion tier (AND-507); `nil` when the category came from the user
        /// override or a rule. Mirrors `TransactionReviewItem.categorySource`.
        public let source: LocalAICategoryResolutionSource?
        /// Whether this row is a transfer (own-account move / card payment) and so
        /// must never count as category spend.
        public let isTransfer: Bool
        /// Whether this row is excluded from budget aggregation (explicit user
        /// choice, a rule, or — by default — because it is a transfer).
        public let excludedFromBudgets: Bool

        public init(
            category: SpendingCategory?,
            source: LocalAICategoryResolutionSource?,
            isTransfer: Bool,
            excludedFromBudgets: Bool
        ) {
            self.category = category
            self.source = source
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
    /// - **Category:** user override → matching rule's category → Plaid →
    ///   on-device NL → uncategorized. (The user-override / Plaid / NL chain is
    ///   identical to `resolveCategory`; a rule's category slots in just below the
    ///   user override, since a rule is an explicit user intent too.)
    /// - **Transfer:** user `isTransferOverride` → matching rule's `isTransfer` →
    ///   transfer-category inference (`TRANSFER_IN`/`TRANSFER_OUT`).
    /// - **Excluded from budgets:** user `excludedFromBudgets` → matching rule's
    ///   `excludedFromBudgets` → transfers are excluded by default.
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

        // Category: user override wins outright; otherwise a matching rule's
        // category is an explicit user intent that beats Plaid/NL; otherwise fall
        // back to the verbatim Plaid → NL → uncategorized chain.
        let resolvedCategory: ResolvedCategory
        if let userCategory = metadata?.userCategory {
            resolvedCategory = ResolvedCategory(category: userCategory, source: nil)
        } else if let ruleCategory = firstRuleValue(matchedRules, \.category) {
            resolvedCategory = ResolvedCategory(category: ruleCategory, source: nil)
        } else {
            resolvedCategory = resolveCategory(
                transaction: transaction,
                userCategory: nil,
                nlCategorizer: nlCategorizer
            )
        }

        // Transfer: explicit metadata override → rule → category-derived.
        let isTransfer = metadata?.isTransferOverride
            ?? firstRuleValue(matchedRules, \.isTransfer)
            ?? resolvedCategory.category.map(isTransferCategory)
            ?? false

        // Exclusion: explicit metadata flag → rule → transfers excluded by default.
        let excludedFromBudgets = metadataExclusion(metadata)
            ?? firstRuleValue(matchedRules, \.excludedFromBudgets)
            ?? isTransfer

        return Resolution(
            category: resolvedCategory.category,
            source: resolvedCategory.source,
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

    /// The user's explicit budget-exclusion choice, or `nil` when they never set
    /// one. `excludedFromBudgets` is a non-optional `false` default on the model,
    /// so an unset choice is indistinguishable from an explicit `false` — we treat
    /// an unset metadata as "no opinion" (let rules / the transfer default decide)
    /// and a present metadata as the user's stated choice. This preserves the
    /// inbox's `metadata?.excludedFromBudgets ?? isTransfer` semantics: when
    /// metadata exists, its value (incl. `false`) is honored over the default.
    private static func metadataExclusion(_ metadata: TransactionReviewMetadata?) -> Bool? {
        guard let metadata else { return nil }
        return metadata.excludedFromBudgets
    }
}
