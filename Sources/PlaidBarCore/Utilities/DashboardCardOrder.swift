import Foundation

/// The reorderable sections of the dashboard center column (AND-487). Codable
/// raw values let a saved order survive app updates; `CaseIterable` gives the
/// canonical default order (declaration order). Adding a future card is a
/// forward-compatible append — `DashboardCardOrder.resolve` slots new kinds in
/// at their default position even for users with an older saved order.
public enum DashboardCardKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case changeReceipt
    case weeklyReview
    case overview
    case recentSpend
    case insights

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .changeReceipt: return "Latest changes"
        case .weeklyReview: return "Weekly review"
        case .overview: return "Accounts overview"
        case .recentSpend: return "Recent spend"
        case .insights: return "Insights"
        }
    }
}

/// Pure resolver that turns a persisted order + pinned set into the concrete
/// sequence the view renders. Keeping this AppKit-free and Sendable makes the
/// forward-compat, drop-unknown, and pin-to-front rules unit-testable; the view
/// just renders `resolve(...)`'s output.
public enum DashboardCardOrder {
    /// The canonical default order: declaration order of `DashboardCardKind`.
    public static let `default`: [DashboardCardKind] = DashboardCardKind.allCases

    /// Resolves the order to render.
    ///
    /// - Drops entries in `savedOrder` that are no longer known kinds (handled
    ///   automatically: `savedOrder` is already `[DashboardCardKind]`, decoded
    ///   leniently upstream — see `decode(rawOrder:)`).
    /// - Appends any known kind missing from `savedOrder` at its position in
    ///   `defaultOrder` (forward-compat when a new card ships).
    /// - Floats every pinned kind to the front, preserving the relative order
    ///   the pinned kinds had among themselves in the resolved base order.
    ///
    /// - Parameters:
    ///   - savedOrder: the user's persisted order (may be empty or stale).
    ///   - pinned: kinds the user pinned to the top.
    ///   - defaultOrder: the canonical order; defaults to `DashboardCardOrder.default`.
    public static func resolve(
        savedOrder: [DashboardCardKind],
        pinned: Set<DashboardCardKind> = [],
        defaultOrder: [DashboardCardKind] = DashboardCardOrder.default
    ) -> [DashboardCardKind] {
        // 1. Start from the saved order, de-duplicated, keeping only known kinds.
        var seen = Set<DashboardCardKind>()
        var base: [DashboardCardKind] = []
        for kind in savedOrder where !seen.contains(kind) {
            base.append(kind)
            seen.insert(kind)
        }

        // 2. Append any defaultOrder kind not present, at its default position
        //    relative to the kinds that ARE present (insert in default order).
        for (index, kind) in defaultOrder.enumerated() where !seen.contains(kind) {
            // Find the insertion point: after the last already-placed kind that
            // precedes this one in defaultOrder, so a new middle card lands in
            // the middle, not at the very end.
            let precedingDefaults = defaultOrder.prefix(index)
            let insertAfter = precedingDefaults.last { base.contains($0) }
            if let insertAfter, let pos = base.firstIndex(of: insertAfter) {
                base.insert(kind, at: pos + 1)
            } else {
                // No earlier kind is placed yet: prepend so default ordering holds.
                base.insert(kind, at: 0)
            }
            seen.insert(kind)
        }

        // 3. Float pinned kinds to the front, preserving their relative order
        //    from the resolved base.
        guard !pinned.isEmpty else { return base }
        let pinnedInOrder = base.filter { pinned.contains($0) }
        let rest = base.filter { !pinned.contains($0) }
        return pinnedInOrder + rest
    }

    /// Leniently decodes a persisted raw-string order into known kinds, dropping
    /// any unknown/removed raw values (forward/backward compat).
    public static func decode(rawOrder: [String]) -> [DashboardCardKind] {
        rawOrder.compactMap(DashboardCardKind.init(rawValue:))
    }

    /// Encodes a resolved order back to raw strings for persistence.
    public static func encode(_ order: [DashboardCardKind]) -> [String] {
        order.map(\.rawValue)
    }
}
