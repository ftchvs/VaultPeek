import Foundation

/// A user-defined spend watch: "nudge me when I cross $X at merchant Y / in
/// category Z this month" (AND-501).
///
/// Deliberately lightweight — this is a glance-line nudge, not envelope
/// budgeting. Persisted app-side as Codable JSON in UserDefaults. Pure value
/// type so the evaluator and persistence stay testable without UI or a server.
public struct WatchlistTarget: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
        case merchant
        case category

        public var displayName: String {
            switch self {
            case .merchant: "Merchant"
            case .category: "Category"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    /// For `.merchant`: the normalized merchant display name. For `.category`:
    /// the `SpendingCategory.rawValue`. Stored already-normalized for merchants
    /// so equality matching is cheap and case/whitespace-insensitive.
    public let key: String
    /// Month-to-date spend threshold in the account currency. Crossing it (>=)
    /// fires one nudge per month/threshold.
    public let monthlyThreshold: Double
    /// User-facing label for nudge copy, e.g. "Starbucks" or "Shopping".
    public let label: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        key: String,
        monthlyThreshold: Double,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.key = kind == .merchant ? WatchlistTarget.normalizeMerchant(key) : key
        self.monthlyThreshold = max(monthlyThreshold, 0)
        self.label = label
    }

    /// Build a merchant watch from a raw display name (normalizes the key and
    /// keeps the original text as the label).
    public static func merchant(_ name: String, threshold: Double, id: UUID = UUID()) -> WatchlistTarget {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchlistTarget(
            id: id,
            kind: .merchant,
            key: trimmed,
            monthlyThreshold: threshold,
            label: trimmed.isEmpty ? "Merchant" : trimmed
        )
    }

    /// Build a category watch from a `SpendingCategory`.
    public static func category(_ category: SpendingCategory, threshold: Double, id: UUID = UUID()) -> WatchlistTarget {
        WatchlistTarget(
            id: id,
            kind: .category,
            key: category.rawValue,
            monthlyThreshold: threshold,
            label: category.displayName
        )
    }

    /// The category this target watches, when it is a category target.
    public var category: SpendingCategory? {
        guard kind == .category else { return nil }
        return SpendingCategory(rawValue: key)
    }

    /// Lowercased, whitespace-trimmed merchant key so " Whole Foods " and
    /// "whole foods" resolve to the same watch.
    public static func normalizeMerchant(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
