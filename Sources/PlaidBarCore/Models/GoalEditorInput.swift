import Foundation

/// Pure validation + parsing for the Goals editor (AND-606).
///
/// Keeps the create/edit form's rules out of the SwiftUI sheet so they are
/// `Sendable` and unit-testable (CLAUDE.md: shared logic lives in `PlaidBarCore`).
/// The sheet binds raw text fields; this turns them into either a committable
/// ``Draft`` or a human-readable validation message.
public enum GoalEditorInput {
    /// The minimum positive target a goal may have (a goal of $0 makes no sense).
    public static let minimumTarget = 0.01

    /// A validated, ready-to-persist set of goal fields. The view folds this into a
    /// new ``Goal`` or onto an existing one (preserving its id / createdAt).
    public struct Draft: Sendable, Equatable {
        public let name: String
        public let targetAmount: Double
        public let contributedAmount: Double
        public let targetDate: Date?
        public let linkedCategory: SpendingCategory?

        public init(
            name: String,
            targetAmount: Double,
            contributedAmount: Double,
            targetDate: Date?,
            linkedCategory: SpendingCategory?
        ) {
            self.name = name
            self.targetAmount = targetAmount
            self.contributedAmount = contributedAmount
            self.targetDate = targetDate
            self.linkedCategory = linkedCategory
        }
    }

    /// The outcome of validating the current field values.
    public enum Outcome: Sendable, Equatable {
        case valid(Draft)
        case invalid(message: String)

        /// Whether the form can be committed (Save enabled).
        public var isCommittable: Bool {
            if case .valid = self { return true }
            return false
        }

        /// The committable draft, or `nil` when invalid.
        public var draft: Draft? {
            if case let .valid(draft) = self { return draft }
            return nil
        }

        /// The validation message to surface, or `nil` when valid.
        public var message: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    /// Validate the raw form fields.
    ///
    /// - `nameText`: trimmed; must be non-empty.
    /// - `targetText`: parsed as currency; must be ≥ ``minimumTarget``.
    /// - `contributedText`: parsed as currency; empty ⇒ 0; must be ≥ 0 and may not
    ///   exceed the target (a goal can't be over-funded at entry — the saved
    ///   amount equals the target when complete).
    /// - `targetDate`: optional; when present must be on or after `now` (a deadline
    ///   in the past makes the pace meaningless).
    public static func validate(
        nameText: String,
        targetText: String,
        contributedText: String,
        targetDate: Date?,
        linkedCategory: SpendingCategory?,
        now: Date = Date()
    ) -> Outcome {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .invalid(message: "Enter a name for this goal.")
        }

        guard let target = parseAmount(targetText), target >= minimumTarget else {
            return .invalid(message: "Enter a target amount greater than zero.")
        }

        let contributed: Double
        if contributedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contributed = 0
        } else if let parsed = parseAmount(contributedText), parsed >= 0 {
            contributed = parsed
        } else {
            return .invalid(message: "Enter a saved amount of zero or more.")
        }

        guard contributed <= target else {
            return .invalid(message: "Saved amount can't be more than the target.")
        }

        if let targetDate, targetDate < Calendar.current.startOfDay(for: now) {
            return .invalid(message: "Choose a target date that isn't in the past.")
        }

        return .valid(
            Draft(
                name: name,
                targetAmount: target,
                contributedAmount: contributed,
                targetDate: targetDate,
                linkedCategory: linkedCategory
            )
        )
    }

    /// Parse a currency-ish string ("1,250.50", "$1250", "1250", "1.250,50") into a
    /// `Double`, or `nil` when it has no parseable numeric content. Tolerant of
    /// grouping separators, a leading currency symbol, and surrounding whitespace.
    ///
    /// Handles both the US ("1,250.50") and European ("1.250,50") conventions: when
    /// both `.` and `,` are present, the *last-occurring* one is treated as the
    /// decimal separator and the other as grouping. The comma-only case keeps US
    /// grouping semantics ("5,000" ⇒ 5000) to preserve existing behavior.
    public static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowed = Set("0123456789.,-")
        let stripped = String(trimmed.filter { allowed.contains($0) })
        guard !stripped.isEmpty else { return nil }

        // Decide the decimal separator: the last-occurring of '.'/',' when both are
        // present (the other is grouping); comma-only stays US grouping.
        let lastDot = stripped.lastIndex(of: ".")
        let lastComma = stripped.lastIndex(of: ",")
        let normalized: String
        switch (lastDot, lastComma) {
        case let (d?, c?):
            normalized = d > c
                ? stripped.replacingOccurrences(of: ",", with: "")
                : stripped.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        case (nil, _?):
            normalized = stripped.replacingOccurrences(of: ",", with: "")
        default:
            normalized = stripped
        }
        return Double(normalized)
    }
}
