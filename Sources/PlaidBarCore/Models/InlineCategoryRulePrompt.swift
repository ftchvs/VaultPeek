import Foundation

/// Pure model for the inline "always categorize <merchant> as <category>?" rule
/// prompt the Review Inbox surfaces the moment a user recategorizes a row
/// (AND-531).
///
/// When the user assigns a category to a transaction in the inbox, that is a
/// one-off correction. Copilot-style review turns that single correction into a
/// durable signal by offering — *inline and dismissible* — to create a
/// deterministic `TransactionRule` ("always categorize this merchant as this
/// category"). Accepting flows through the **existing** rule path
/// (`AppState.createRule`), so the same rule then feeds the override-aware spend
/// math on `main`.
///
/// This is the pure, `Sendable`, testable half. It owns two decisions so the
/// view and `AppState` stay thin:
/// 1. **Should we even prompt?** — `make` returns `nil` (no prompt) when the
///    merchant is blank or an identical rule already exists, so the offer never
///    nags about a rule the user already created.
/// 2. **What rule would Accept create?** — `buildRule` produces the exact
///    `TransactionRule` the existing `createRule(from:category:)` path appends,
///    so the prompt's "this is what will happen" copy and the dedupe check match
///    the rule that is actually written.
///
/// Privacy: the prompt carries only a (possibly user-renamed) merchant label and
/// a category name — never an amount or other sensitive figure. The view also
/// suppresses it entirely while Privacy Mask / App Lock is active (the inbox
/// renders no rows at all in that state), so nothing leaks.
public struct InlineCategoryRulePrompt: Sendable, Equatable, Identifiable {
    /// Stable identity so SwiftUI can animate one prompt in/out and so a newer
    /// correction's prompt replaces an older one rather than stacking.
    public var id: String { transactionID }

    /// The review row that was just recategorized — used to drive the existing
    /// `createRule(from:category:)` path on accept (it carries the matcher,
    /// merchant name, and transfer/exclusion context).
    public let transactionID: String
    /// The display merchant label shown in the prompt copy ("always categorize
    /// **<merchant>** as …"). Always the row's effective (possibly renamed) name.
    public let merchantName: String
    /// The category the user just assigned — the rule's target category.
    public let category: SpendingCategory

    public init(transactionID: String, merchantName: String, category: SpendingCategory) {
        self.transactionID = transactionID
        self.merchantName = merchantName
        self.category = category
    }

    /// The merchant token a rule built from `(merchantName, category)` matches on.
    /// Mirrors `AppState.createRule`'s `matchMerchantContains` exactly (trimmed
    /// effective merchant name) so the dedupe check and the rule that is actually
    /// written can never drift apart.
    public var ruleMatcher: String {
        merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds the `TransactionRule` an Accept would create.
    ///
    /// Mirrors the category branch of `AppState.createRule(from:category:)`: a
    /// merchant-contains matcher on the trimmed effective merchant name, carrying
    /// the chosen category and the normalized merchant label. Returns `nil` when
    /// the merchant is blank (no stable token to match on) — the same guard
    /// `createRule` applies — so an unmatchable rule is never produced.
    public func buildRule(id: UUID = UUID(), createdAt: Date = Date()) -> TransactionRule? {
        let matcher = ruleMatcher
        guard !matcher.isEmpty else { return nil }
        return TransactionRule(
            id: id,
            matchMerchantContains: matcher,
            matchOriginalNameContains: nil,
            category: category,
            merchantName: matcher,
            isTransfer: nil,
            excludedFromBudgets: nil,
            createdAt: createdAt
        )
    }

    /// Whether `rules` already contains a rule equivalent to the one this prompt
    /// would create — same merchant matcher (case-insensitive) **and** same target
    /// category. When true the prompt is redundant and `make` suppresses it.
    public func isAlreadyCovered(by rules: [TransactionRule]) -> Bool {
        let matcher = ruleMatcher
        guard !matcher.isEmpty else { return false }
        return rules.contains { rule in
            rule.category == category
                && (rule.matchMerchantContains?.compare(matcher, options: .caseInsensitive) == .orderedSame)
        }
    }

    /// Builds a prompt for a just-applied recategorization, or `nil` when no
    /// prompt should be shown.
    ///
    /// Returns `nil` (non-nagging) when:
    /// - the merchant has no stable token to match on (blank after trimming), or
    /// - an identical rule (same merchant + category) already exists, so creating
    ///   another would be a no-op duplicate.
    ///
    /// - Parameters:
    ///   - transactionID: the recategorized row's id.
    ///   - merchantName: the row's effective (possibly renamed) merchant name.
    ///   - category: the category the user just assigned.
    ///   - existingRules: the current rule set, to suppress duplicate offers.
    public static func make(
        transactionID: String,
        merchantName: String,
        category: SpendingCategory,
        existingRules: [TransactionRule]
    ) -> InlineCategoryRulePrompt? {
        let prompt = InlineCategoryRulePrompt(
            transactionID: transactionID,
            merchantName: merchantName,
            category: category
        )
        guard !prompt.ruleMatcher.isEmpty else { return nil }
        guard !prompt.isAlreadyCovered(by: existingRules) else { return nil }
        return prompt
    }
}
