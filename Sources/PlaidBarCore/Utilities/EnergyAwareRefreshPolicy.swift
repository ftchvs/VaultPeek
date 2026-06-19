import Foundation

/// Pure, framework-light decision for whether the resident menu-bar app's
/// *automatic* background refresh should run right now, and how long to wait
/// before the next tick, given the device's energy and thermal conditions
/// (AND-568).
///
/// The resident app keeps a background loop that re-probes connectivity and
/// (when due, per ``AutomaticRefreshPolicy``) pulls fresh Plaid data. On a
/// laptop running on battery — Low Power Mode on, or the chassis already
/// throttling under thermal pressure — that periodic Plaid fetch is exactly the
/// kind of deferrable, non-urgent work the OS asks apps to back off. This type
/// encodes that back-off so it can be unit-tested without a live device:
///
/// - **Manual refresh always runs.** The user explicitly asked, so energy state
///   never suppresses it — only *automatic* (loop / popover-open) refreshes back
///   off. This mirrors ``AutomaticRefreshPolicy``'s manual-always contract.
/// - **Low Power Mode or hot thermal defers the automatic Plaid fetch.** The
///   connectivity re-probe and notification evaluation in the loop are cheap and
///   keep running; only the network-and-CPU-heavy data fetch is skipped.
/// - **The loop's sleep lengthens while constrained**, so a throttled machine
///   wakes the app less often instead of spinning a tight wall-clock timer.
///
/// The OS observers (`ProcessInfo.isLowPowerModeEnabled`,
/// `ProcessInfo.thermalState`, and the `…PowerStateDidChange` /
/// `thermalStateDidChange` notifications) live in the app layer and feed their
/// values into this pure decider; nothing here imports AppKit or touches global
/// state, so every branch is deterministic in tests.
public enum EnergyAwareRefreshPolicy: Sendable {
    /// Framework-light mirror of `ProcessInfo.ThermalState`. Mapping the live
    /// enum onto this at the app boundary keeps the decision testable without
    /// depending on the host machine's actual thermal state in CI (mirrors the
    /// `KeychainAccessPolicy.Accessibility` pattern).
    public enum EnergyThermalState: String, Sendable, CaseIterable, Equatable {
        /// `ProcessInfo.ThermalState.nominal` — no thermal pressure.
        case nominal
        /// `ProcessInfo.ThermalState.fair` — slightly elevated; still fine to work.
        case fair
        /// `ProcessInfo.ThermalState.serious` — the system is shedding heat and
        /// asks apps to reduce activity. Treated as constrained.
        case serious
        /// `ProcessInfo.ThermalState.critical` — the system is at risk and apps
        /// must stop non-essential work. Treated as constrained.
        case critical

        /// Whether this thermal state is hot enough that the app should defer
        /// non-urgent background work. `.serious` and `.critical` are the two
        /// states Apple documents as "reduce / stop activity".
        public var isConstrained: Bool {
            switch self {
            case .nominal, .fair: false
            case .serious, .critical: true
            }
        }
    }

    /// A snapshot of the device energy/thermal conditions the decider reads.
    /// Value type with no side effects so callers can build it from live
    /// `ProcessInfo` readings or from fixtures in tests.
    public struct EnergyConditions: Sendable, Equatable {
        /// `ProcessInfo.processInfo.isLowPowerModeEnabled` at read time.
        public let lowPowerMode: Bool
        /// Mapped `ProcessInfo.processInfo.thermalState` at read time.
        public let thermalState: EnergyThermalState

        public init(lowPowerMode: Bool, thermalState: EnergyThermalState) {
            self.lowPowerMode = lowPowerMode
            self.thermalState = thermalState
        }

        /// Whether the device is energy-constrained: Low Power Mode is on, or the
        /// thermal state is `.serious`/`.critical`. Under either condition the
        /// app backs off its automatic background data fetch.
        public var isConstrained: Bool {
            lowPowerMode || thermalState.isConstrained
        }

        /// Convenience for the unconstrained baseline (used as a safe default).
        public static let normal = EnergyConditions(lowPowerMode: false, thermalState: .nominal)
    }

    /// Multiplier applied to the loop's base sleep interval while the device is
    /// energy-constrained, so a throttled / battery-saving machine wakes the app
    /// less often. Strictly greater than 1 so constrained ticks are always less
    /// frequent than normal ones.
    public static let constrainedBackoffMultiplier: Double = 4

    /// Whether an *automatic* refresh should actually run now.
    ///
    /// - Parameters:
    ///   - conditions: live energy/thermal snapshot.
    ///   - automaticRefreshIsDue: whether the time-based throttle
    ///     (``AutomaticRefreshPolicy``) already says an automatic refresh is due.
    ///     Ignored for manual refreshes.
    ///   - isManual: whether the user explicitly triggered this refresh. Manual
    ///     refreshes always run and bypass both the time throttle and the energy
    ///     back-off.
    /// - Returns: `true` only when the refresh should proceed. Manual refreshes
    ///   always return `true`; automatic refreshes return `true` only when due
    ///   *and* the device is not energy-constrained.
    public static func shouldRunAutomaticRefresh(
        conditions: EnergyConditions,
        automaticRefreshIsDue: Bool,
        isManual: Bool
    ) -> Bool {
        // The user asked — never let battery/thermal state suppress it.
        if isManual { return true }
        // Not yet due per the time-based policy: nothing to do regardless of energy.
        guard automaticRefreshIsDue else { return false }
        // Due, but back off while the device is energy-constrained.
        return !conditions.isConstrained
    }

    /// The delay to sleep before the next background loop tick. Normal energy
    /// keeps the configured base interval; a constrained device lengthens it by
    /// ``constrainedBackoffMultiplier`` so the app wakes less often under battery
    /// or thermal pressure.
    ///
    /// Degenerate base intervals (non-finite or non-positive) fall back to a
    /// finite positive floor so the loop can never busy-spin or sleep forever.
    public static func nextTickDelay(
        baseInterval: TimeInterval,
        conditions: EnergyConditions
    ) -> TimeInterval {
        let sanitizedBase = (baseInterval.isFinite && baseInterval > 0)
            ? baseInterval
            : PlaidBarConstants.backgroundRefreshInterval
        guard conditions.isConstrained else { return sanitizedBase }
        // Sanitize the *product*, not just the base: a finite-but-very-large base
        // (e.g. near `.greatestFiniteMagnitude`) can overflow to `.infinity` once
        // multiplied, which would break the "never sleep forever" guarantee. When
        // that happens, fall back to the finite sanitized base.
        let constrained = sanitizedBase * constrainedBackoffMultiplier
        return (constrained.isFinite && constrained > 0) ? constrained : sanitizedBase
    }
}
