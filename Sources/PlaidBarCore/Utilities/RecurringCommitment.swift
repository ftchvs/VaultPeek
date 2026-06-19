import Foundation

/// Pure rollup of *committed* monthly recurring spend per category — how much of a
/// category's budget is already spoken-for by detected recurring bills
/// (``RecurringDetector``). Feeds the dashed "committed" ghost segment drawn on
/// the category status bars (AND-559).
///
/// Each stream's average charge is normalized to a monthly-equivalent cost via
/// ``RecurringFrequency/monthlyMultiplier`` (a weekly $10 stream commits
/// ~$43.33/month), then summed into its **effective** ``SpendingCategory``.
///
/// Mapping mirrors how spend is bucketed so the ghost stays consistent with the
/// fill and budget row:
/// - **Override-aware:** a stream's category is resolved through the same
///   ``EffectiveCategoryResolver`` the planner/dashboard use, so a rule that
///   recategorizes the merchant (or marks it a transfer / excluded) moves the
///   committed ghost in lockstep with the spend fill instead of stranding it on the
///   raw Plaid category.
/// - **Stale-aware:** when a reference `asOf` date is supplied, a stream the
///   detector flags as stale (``RecurringTransaction/isStale(asOf:calendar:)`` — a
///   stopped/canceled subscription) is dropped, so it can't keep a category looking
///   budget-committed after the charges have stopped.
///
/// A stream with no resolved category, a transfer category, an excluded rule, or a
/// non-positive amount contributes nothing — so "absent" cleanly means "no
/// recurring stream maps here, hide the ghost". Stateless `enum`, deterministic
/// (no hidden `Date()`), and `Sendable`.
public enum RecurringCommitment {
    /// Monthly-equivalent committed recurring spend per category. Categories with
    /// no mapped stream are absent (the caller hides the ghost segment for them),
    /// and every value is strictly positive.
    ///
    /// - Parameters:
    ///   - streams: detected recurring streams.
    ///   - asOf: optional reference date; when supplied, stale (stopped) streams are
    ///     dropped. Defaults to `nil` (no stale filtering).
    ///   - calendar: calendar used for the staleness check (injected for determinism).
    ///   - rules: recategorization rules applied to each stream's merchant, so the
    ///     ghost follows user recategorization / transfer / exclude decisions.
    public static func monthlyByCategory(
        _ streams: [RecurringTransaction],
        asOf: Date? = nil,
        calendar: Calendar = .current,
        rules: [TransactionRule] = []
    ) -> [SpendingCategory: Double] {
        var committed: [SpendingCategory: Double] = [:]
        for stream in streams {
            // Drop streams the detector would consider stale (stopped / canceled)
            // when a reference date is available.
            if let asOf, stream.isStale(asOf: asOf, calendar: calendar) { continue }
            guard stream.averageAmount > 0 else { continue }
            guard let category = effectiveCategory(for: stream, rules: rules),
                  !EffectiveCategoryResolver.isTransferCategory(category)
            else { continue }
            let monthly = stream.averageAmount * stream.frequency.monthlyMultiplier
            guard monthly > 0 else { continue }
            committed[category, default: 0] += monthly
        }
        return committed
    }

    /// The stream's override-aware budget category, or `nil` when it should not
    /// count (genuinely uncategorized, a transfer, or excluded by a rule).
    ///
    /// A recurring stream is a merchant-level aggregate, not a single transaction, so
    /// only *rules* (which match by merchant) apply — per-transaction review metadata
    /// has no merchant-level analogue here. We resolve a representative transaction
    /// through ``EffectiveCategoryResolver`` so the precedence (rule override → raw
    /// category, transfer/exclude handling) is identical to the spend path.
    private static func effectiveCategory(
        for stream: RecurringTransaction,
        rules: [TransactionRule]
    ) -> SpendingCategory? {
        let representative = TransactionDTO(
            id: "recurring-\(stream.id)",
            accountId: "",
            amount: stream.averageAmount,
            date: stream.lastDate,
            name: stream.merchantName,
            merchantName: stream.merchantName,
            category: stream.category
        )
        let resolution = EffectiveCategoryResolver.resolve(
            transaction: representative,
            metadata: nil,
            rules: rules
        )
        if resolution.excludedFromBudgets { return nil }
        // Fall back to the stream's own detected category when the resolver returns
        // none (no rule, non-confident Plaid category) but the stream did carry one.
        return resolution.category ?? stream.category
    }
}
