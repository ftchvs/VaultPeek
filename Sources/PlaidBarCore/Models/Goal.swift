import Foundation

/// A user-defined **savings goal** (AND-606).
///
/// Net-new, app-local, local-first: a `Goal` is created and tracked entirely on
/// the user's machine (persisted as JSON under the app data dir — no server
/// schema, no Plaid call). It is a pure value type so the progress math below is
/// testable at the Core layer without SwiftUI (CLAUDE.md: shared logic lives in
/// `PlaidBarCore`).
///
/// `contributedAmount` is the running total the user has set aside toward
/// `targetAmount`. The optional `linkedCategory` lets a goal annotate which
/// spending category it relates to (display only — it does **not** drive any
/// aggregation here); the optional `targetDate` enables the on-track verdict.
public struct Goal: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    /// User-facing name, e.g. "Emergency fund".
    public var name: String
    /// The amount the user is saving toward (always treated as a positive target).
    public var targetAmount: Double
    /// Optional deadline; enables the on-track-vs-target-date verdict.
    public var targetDate: Date?
    /// Optional spending category this goal relates to (display annotation only).
    public var linkedCategory: SpendingCategory?
    /// The amount set aside so far toward `targetAmount`.
    public var contributedAmount: Double
    /// When the goal was created (also the start anchor for the on-track pace).
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        targetDate: Date? = nil,
        linkedCategory: SpendingCategory? = nil,
        contributedAmount: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.linkedCategory = linkedCategory
        self.contributedAmount = contributedAmount
        self.createdAt = createdAt
    }

    // MARK: - Pure progress math (unit-tested in Core)

    /// Progress as a fraction in `0...1`. Guards a non-positive target (returns
    /// `0`) so a malformed goal never divides by zero, and clamps an
    /// over-contribution to `1` so a funded goal reads as complete, not >100%.
    public var fractionComplete: Double {
        guard targetAmount > 0 else { return 0 }
        let raw = contributedAmount / targetAmount
        return min(max(raw, 0), 1)
    }

    /// Progress as a whole-number percent in `0...100`, rounded to the nearest
    /// integer — the value surfaced as text alongside the bar (never color alone).
    public var percentComplete: Int {
        Int((fractionComplete * 100).rounded())
    }

    /// Amount still needed to reach the target, never negative (a funded or
    /// over-funded goal reports `0` remaining).
    public var remainingAmount: Double {
        max(targetAmount - contributedAmount, 0)
    }

    /// Whether the goal has reached (or exceeded) its target.
    public var isComplete: Bool {
        targetAmount > 0 && contributedAmount >= targetAmount
    }

    /// The on-track verdict against an optional `targetDate`, evaluated `asOf` a
    /// reference instant. Pure so it is fully testable.
    ///
    /// - A complete goal is always ``Pace/onTrack`` (target met).
    /// - Without a `targetDate` the pace is ``Pace/noDeadline`` (nothing to be
    ///   behind on).
    /// - Otherwise it compares the *expected* contribution by now — a straight
    ///   line from `createdAt` (0%) to `targetDate` (100%) — against the actual
    ///   contribution: at/ahead ⇒ ``Pace/onTrack``, behind ⇒ ``Pace/behind``.
    ///   Past the target date while still short ⇒ ``Pace/behind``.
    public func pace(asOf now: Date) -> Pace {
        if isComplete { return .onTrack }
        guard let targetDate else { return .noDeadline }

        // A target date at or before the start can never be paced linearly;
        // treat any shortfall as behind.
        guard targetDate > createdAt else { return .behind }

        if now >= targetDate { return .behind }

        let totalInterval = targetDate.timeIntervalSince(createdAt)
        let elapsed = max(now.timeIntervalSince(createdAt), 0)
        let expectedFraction = min(elapsed / totalInterval, 1)
        let expectedAmount = targetAmount * expectedFraction

        return contributedAmount + Self.paceTolerance >= expectedAmount ? .onTrack : .behind
    }

    /// A small currency tolerance so floating-point dust never flips an
    /// exactly-on-pace goal to "behind".
    private static let paceTolerance = 0.005

    /// On-track verdict for a goal with a deadline. Carried by text + SF Symbol
    /// in the UI, never color alone (ACCESSIBILITY.md).
    public enum Pace: String, Codable, Sendable, Equatable, Hashable {
        /// At or ahead of the linear pace needed to hit the target date (or done).
        case onTrack
        /// Behind the linear pace, or past the deadline while still short.
        case behind
        /// No target date set — there is no pace to be behind on.
        case noDeadline

        /// Short human-readable label.
        public var label: String {
            switch self {
            case .onTrack: "On track"
            case .behind: "Behind"
            case .noDeadline: "No deadline"
            }
        }

        /// SF Symbol carrying the verdict redundantly with the label.
        public var systemImage: String {
            switch self {
            case .onTrack: "checkmark.circle.fill"
            case .behind: "exclamationmark.triangle.fill"
            case .noDeadline: "calendar.badge.minus"
            }
        }
    }
}
