import Foundation

/// Pure, deterministic per-category budget-alert crossing logic (AND-642).
///
/// The user already has per-category budgets (``CategoryBudgetPlanner`` /
/// ``CategoryBudgetPresentation``). This evaluator answers a single question for
/// the notification layer: **which budgeted categories have crossed into the
/// `nearing` or `over` band this month, and should fire an alert?**
///
/// Like ``WatchlistEvaluator`` it is a stateless `enum` with no hidden `Date()`;
/// the caller supplies `now` + `Calendar` so every result is reproducible. The
/// band classification is reused verbatim from ``CategoryBudgetStatus`` so the
/// alert verdict can never drift from the in-app budget UI.
///
/// ## Why a per-band crossing, not a per-amount one
/// The de-dup contract (see ``NotificationTriggerSelection``) keys an alert on
/// *category + month + band*, so a category fires **once** when it enters
/// `nearing` and **once more** if it later escalates to `over` — but not on every
/// refresh while it sits in the same band. Crossing `under → nearing → over` is
/// monotonic within a month, so this models the "near or exceed" requirement
/// without storing prior spend.
///
/// ## Privacy
/// This type emits no amounts — only the category and its band. The notification
/// layer renders a body from `category name + status` (or a fully generic body
/// when Privacy Mask is active), never a dollar figure (see
/// ``NotificationTriggerSelection``).
public enum CategoryBudgetAlertEvaluator {
    /// A budgeted category that has crossed into an attention band this month.
    public struct Alert: Sendable, Equatable, Identifiable {
        public let category: SpendingCategory
        /// The attention band reached: `.nearing` or `.over`. `.under` never
        /// produces an alert and is therefore not representable here.
        public let band: CategoryBudgetStatus
        /// `yyyy-MM` key for the budget period the band was reached in. Feeds the
        /// dedup key so each month re-arms the alert.
        public let monthKey: String

        /// Stable per-(category, month, band) identity, matching the dedup grain.
        public var id: String { "\(category.rawValue)#\(monthKey)#\(band.rawValue)" }

        public init(category: SpendingCategory, band: CategoryBudgetStatus, monthKey: String) {
            self.category = category
            self.band = band
            self.monthKey = monthKey
        }
    }

    /// Evaluate budgeted categories against the current month's spend.
    ///
    /// - Parameters:
    ///   - presentation: a finished, override-aware month rollup
    ///     (``CategoryBudgetPlanner/presentation`` /
    ///     ``CategoryBudgetPlanner/mergedPresentation``). Only items carrying a
    ///     positive `monthlyLimit` are alert-eligible.
    ///   - includeSuggested: when `false` (default) planner *suggestions* the user
    ///     has never saved do not alert — an alert should reflect a budget the
    ///     user actually set, not a guardrail the app proposed. Explicit budgets
    ///     always alert.
    ///   - nearThreshold: the `under`/`nearing` boundary as a fraction of the
    ///     limit, defaulting to ``CategoryBudgetStatus/nearingThreshold`` (0.8) so
    ///     the alert band matches the in-app budget UI. A caller may raise it
    ///     (e.g. only warn at 90%); values are clamped to `0...1`.
    ///   - now: reference "today" defining the current budget month.
    ///   - calendar: calendar used to derive the month key.
    /// - Returns: one ``Alert`` per category in the `nearing` or `over` band,
    ///   ordered worst-first (over before nearing), then by category name, so the
    ///   notification layer emits the most urgent alerts first.
    public static func evaluate(
        presentation: CategoryBudgetPresentation,
        includeSuggested: Bool = false,
        nearThreshold: Double = CategoryBudgetStatus.nearingThreshold,
        now: Date,
        calendar: Calendar = .current
    ) -> [Alert] {
        let monthKey = WatchlistEvaluator.monthKey(for: now, calendar: calendar)
        let clampedThreshold = min(1, max(0, nearThreshold))

        return presentation.items
            .compactMap { item -> Alert? in
                guard item.monthlyLimit > 0 else { return nil }
                if item.isSuggested, !includeSuggested { return nil }

                // Re-derive the band against the (possibly stricter) caller
                // threshold rather than reusing item.status, so a raised
                // near-threshold takes effect without recomputing the rollup.
                let band = band(forFraction: item.fractionUsed, nearThreshold: clampedThreshold)
                guard band != .under else { return nil }
                return Alert(category: item.category, band: band, monthKey: monthKey)
            }
            .sorted { lhs, rhs in
                if lhs.band != rhs.band {
                    // .over (worst) before .nearing.
                    return rank(lhs.band) < rank(rhs.band)
                }
                return lhs.category.displayName < rhs.category.displayName
            }
    }

    /// Band for a consumed fraction against an explicit near-threshold. `> 1.0`
    /// is over; `>= nearThreshold` (and `<= 1.0`) is nearing; else under. Mirrors
    /// ``CategoryBudgetStatus/init(fractionUsed:)`` but with a caller-supplied
    /// near-threshold so alerts can warn earlier or later than the UI default.
    static func band(forFraction fraction: Double, nearThreshold: Double) -> CategoryBudgetStatus {
        if fraction > 1.0 { return .over }
        if fraction >= nearThreshold { return .nearing }
        return .under
    }

    /// Worst-first ordering: over (0) before nearing (1). Under never alerts.
    private static func rank(_ band: CategoryBudgetStatus) -> Int {
        switch band {
        case .over: 0
        case .nearing: 1
        case .under: 2
        }
    }
}
