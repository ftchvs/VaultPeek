import Foundation

/// Explainable "safe to spend" result.
///
/// The headline `amount` is the conservative discretionary balance the user can
/// spend through `SafeToSpendInputs.horizon` without touching money already
/// committed to known obligations or the user's safety buffer. It is the signed
/// sum of `components` (see the sign convention below), so the breakdown always
/// reconciles to the number — there is no hidden math.
///
/// Sign convention (documented and enforced by `SafeToSpendCalculator`):
/// every component's `amount` is signed relative to the final balance. Inflows
/// (starting cash, expected income) are positive; outflows (upcoming
/// obligations, credit-card payments, budget reservations, safety buffer) are
/// negative. `amount == components.reduce(0) { $0 + $1.amount }`. The number is
/// allowed to go negative — a negative result is reported honestly rather than
/// clamped to zero, because hiding a shortfall would be the opposite of safe.
public struct SafeToSpendResult: Sendable, Equatable {
    /// The conservative discretionary balance. May be negative when committed
    /// outflows and the buffer exceed available cash plus expected income.
    public let amount: Double

    /// Ordered, signed breakdown. Always reconciles: the components sum to
    /// `amount`. Order follows the calculation: cash, income, then the
    /// subtractions in `SafeToSpendComponentKind` declaration order.
    public let components: [SafeToSpendComponent]

    /// How much trust the UI should place in `amount`. Drives the confidence
    /// cue so the number is never presented as more certain than the inputs
    /// justify.
    public let confidence: SafeToSpendConfidence

    /// End of the look-ahead window the result covers (inclusive). Surfaced so
    /// the UI can say "through <date>" without re-deriving the horizon.
    public let horizonEnd: Date

    public init(
        amount: Double,
        components: [SafeToSpendComponent],
        confidence: SafeToSpendConfidence,
        horizonEnd: Date
    ) {
        self.amount = amount
        self.components = components
        self.confidence = confidence
        self.horizonEnd = horizonEnd
    }

    /// Components that carry a non-zero amount, in display order. The starting
    /// cash and (when present) income lines are always kept even at zero so the
    /// breakdown reads as a complete statement; pure-zero subtractions are
    /// dropped to avoid noise.
    public var visibleComponents: [SafeToSpendComponent] {
        components.filter { component in
            switch component.kind {
            case .startingCash, .expectedIncome:
                return true
            default:
                return component.amount != 0
            }
        }
    }
}

/// One signed line in the safe-to-spend breakdown.
public struct SafeToSpendComponent: Sendable, Equatable, Identifiable {
    public let kind: SafeToSpendComponentKind
    /// Human-readable label, e.g. "Starting cash" or "Upcoming bills".
    public let label: String
    /// Signed contribution to `SafeToSpendResult.amount` (positive = inflow,
    /// negative = outflow). See the type-level sign convention.
    public let amount: Double

    public init(kind: SafeToSpendComponentKind, label: String, amount: Double) {
        self.kind = kind
        self.label = label
        self.amount = amount
    }

    public var id: SafeToSpendComponentKind { kind }
}

/// The fixed set of breakdown line kinds, in calculation/display order.
public enum SafeToSpendComponentKind: String, Sendable, CaseIterable, Hashable {
    case startingCash
    case expectedIncome
    case upcomingObligations
    case loanPayments
    case budgetReservations
    case safetyBuffer

    /// SF Symbol used by the UI for this line. Paired with text everywhere so
    /// meaning never rides on color alone (ACCESSIBILITY.md).
    public var iconName: String {
        switch self {
        case .startingCash: "banknote"
        case .expectedIncome: "arrow.down.circle"
        case .upcomingObligations: "calendar.badge.clock"
        case .loanPayments: "creditcard"
        case .budgetReservations: "tray.full"
        case .safetyBuffer: "shield.lefthalf.filled"
        }
    }
}

/// Confidence in the headline number. Ordered from least to most trustworthy so
/// callers can compare and the UI can pick a matching cue.
public enum SafeToSpendConfidence: String, Sendable, CaseIterable, Comparable {
    /// Inputs too thin to stand behind a number (no obligation history AND no
    /// income signal). The UI should treat `amount` as indicative only.
    case insufficientData
    /// Income was estimated from recurring inflows or cashflow rather than a
    /// manual override, so the upside is softer than the cash floor.
    case lowConfidence
    /// Inputs are defensible: real cash plus either a manual income override or
    /// no reliance on estimated income.
    case ok

    private var rank: Int {
        switch self {
        case .insufficientData: 0
        case .lowConfidence: 1
        case .ok: 2
        }
    }

    public static func < (lhs: SafeToSpendConfidence, rhs: SafeToSpendConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Short label for the confidence cue.
    public var label: String {
        switch self {
        case .insufficientData: "Estimate only"
        case .lowConfidence: "Lower confidence"
        case .ok: "On track"
        }
    }

    /// SF Symbol paired with `label` so the cue is never color-only.
    public var iconName: String {
        switch self {
        case .insufficientData: "questionmark.circle"
        case .lowConfidence: "exclamationmark.circle"
        case .ok: "checkmark.circle"
        }
    }
}

/// How far ahead the safe-to-spend window looks.
public enum SafeToSpendHorizon: Sendable, Equatable {
    /// To the end of the current calendar month (inclusive of the last day).
    case endOfMonth
    /// A fixed number of days from `asOf` (clamped to at least 1 day).
    case days(Int)

    /// Resolves the inclusive end-of-window date for a reference date.
    public func endDate(asOf date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        switch self {
        case .endOfMonth:
            guard
                let monthInterval = calendar.dateInterval(of: .month, for: startOfDay),
                let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)
            else {
                return startOfDay
            }
            return calendar.startOfDay(for: lastDay)
        case let .days(count):
            let clamped = max(count, 1)
            return calendar.date(byAdding: .day, value: clamped, to: startOfDay) ?? startOfDay
        }
    }
}

/// Configuration for a safe-to-spend computation: which accounts count as
/// spendable cash, the user's safety buffer, the look-ahead horizon, any budget
/// reservations, and an optional manual income override.
public struct SafeToSpendInputs: Sendable, Equatable {
    /// Account types treated as spendable cash for "starting cash". Defaults to
    /// depository only — credit, loan, and investment are excluded so the floor
    /// reflects money actually available to spend.
    public let includedCashAccountTypes: Set<AccountType>
    /// Amount the user always wants to keep untouched. Subtracted from the
    /// result. Clamped to non-negative.
    public let safetyBuffer: Double
    /// Money the user has earmarked (e.g. a sinking fund) that should not count
    /// as spendable. Subtracted. Clamped to non-negative.
    public let budgetReservations: Double
    /// Look-ahead window for obligations and income.
    public let horizon: SafeToSpendHorizon
    /// Manual expected-income override for the horizon. When set (>= 0) it is
    /// used verbatim and yields full confidence on the income side; when nil
    /// the calculator falls back to estimated income at lower confidence.
    public let manualExpectedIncome: Double?

    public init(
        includedCashAccountTypes: Set<AccountType> = [.depository],
        safetyBuffer: Double = 0,
        budgetReservations: Double = 0,
        horizon: SafeToSpendHorizon = .endOfMonth,
        manualExpectedIncome: Double? = nil
    ) {
        self.includedCashAccountTypes = includedCashAccountTypes
        self.safetyBuffer = max(safetyBuffer, 0)
        self.budgetReservations = max(budgetReservations, 0)
        self.horizon = horizon
        self.manualExpectedIncome = manualExpectedIncome.map { max($0, 0) }
    }

    /// Sensible default: depository cash only, no buffer, end-of-month horizon.
    public static let `default` = SafeToSpendInputs()
}
