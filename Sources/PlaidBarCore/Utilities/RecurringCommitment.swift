import Foundation

/// Pure rollup of *committed* monthly recurring spend per category — how much of a
/// category's budget is already spoken-for by detected recurring bills
/// (``RecurringDetector``). Feeds the dashed "committed" ghost segment drawn on
/// the category status bars (AND-559).
///
/// Each stream's average charge is normalized to a monthly-equivalent cost via
/// ``RecurringFrequency/monthlyMultiplier`` (a weekly $10 stream commits
/// ~$43.33/month), then summed into its ``SpendingCategory``. A stream with no
/// category, a non-positive amount, or a transfer category contributes nothing — a
/// transfer is never category spend, mirroring the aggregation contract in
/// ``EffectiveCategoryResolver``. The result therefore only ever maps a category
/// to a strictly-positive committed amount, so a consumer can treat "absent" as
/// "no recurring stream maps here" and hide the ghost segment entirely.
///
/// Stateless `enum`, fully deterministic (no hidden `Date()`), and `Sendable`.
public enum RecurringCommitment {
    /// Monthly-equivalent committed recurring spend per category. Categories with
    /// no mapped stream are absent (the caller hides the ghost segment for them),
    /// and every value is strictly positive.
    public static func monthlyByCategory(
        _ streams: [RecurringTransaction]
    ) -> [SpendingCategory: Double] {
        var committed: [SpendingCategory: Double] = [:]
        for stream in streams {
            guard let category = stream.category,
                  !EffectiveCategoryResolver.isTransferCategory(category),
                  stream.averageAmount > 0
            else { continue }
            let monthly = stream.averageAmount * stream.frequency.monthlyMultiplier
            guard monthly > 0 else { continue }
            committed[category, default: 0] += monthly
        }
        return committed
    }
}
