import Foundation

/// Pure description of the *blast radius* of a bulk "Mark N reviewed" action on
/// the Review Inbox (AND-528).
///
/// The Review Inbox lets the user clear individual rows; a bulk action must make
/// its scope explicit *before* applying — how many rows, and exactly which ones —
/// so a single click never silently resolves more than the user can see. This
/// type computes that scope from the inbox items currently on screen plus an
/// optional explicit selection, with no SwiftUI or AppState dependency so the
/// "which rows are affected" decision is unit-testable.
///
/// Scope rules:
/// - Only items the resolver still considers *unresolved* (`status != .reviewed`)
///   are eligible — an already-reviewed row that lingers (e.g. reopened) is not
///   re-marked, and ignored rows are left as the user set them.
/// - With no explicit selection (`selectedIDs == nil`) the radius is every
///   eligible row currently listed — "mark everything I can see".
/// - With an explicit selection the radius is the intersection of the selection
///   and the eligible listed rows, so a stale id (a row that already left the
///   list) can never mark a transaction that is no longer shown.
public struct ReviewBulkActionPlan: Sendable, Equatable {
    /// Transaction ids that will be marked reviewed, in the order they appear in
    /// the inbox list (stable, so the announced "which" matches the visual order).
    public let affectedIDs: [String]

    /// Merchant names of the affected rows, list order, for an explicit
    /// "which transactions" preview (deduped is intentionally NOT applied — two
    /// distinct rows from the same merchant are two distinct resolutions).
    public let affectedMerchantNames: [String]

    public var count: Int { affectedIDs.count }

    public var isEmpty: Bool { affectedIDs.isEmpty }

    public init(affectedIDs: [String], affectedMerchantNames: [String]) {
        self.affectedIDs = affectedIDs
        self.affectedMerchantNames = affectedMerchantNames
    }

    /// Computes the blast radius for marking inbox rows reviewed.
    ///
    /// - Parameters:
    ///   - items: the inbox rows currently listed (already truncated to what the
    ///     surface shows — the radius never exceeds the visible list).
    ///   - selectedIDs: an explicit selection, or `nil` to mean "all listed".
    public static func markReviewed(
        items: [TransactionReviewItem],
        selectedIDs: Set<String>? = nil
    ) -> ReviewBulkActionPlan {
        let eligible = items.filter { $0.status != .reviewed }
        let scoped: [TransactionReviewItem]
        if let selectedIDs {
            scoped = eligible.filter { selectedIDs.contains($0.id) }
        } else {
            scoped = eligible
        }
        return ReviewBulkActionPlan(
            affectedIDs: scoped.map(\.id),
            affectedMerchantNames: scoped.map(\.effectiveMerchantName)
        )
    }

    /// A short, plain-language description of which rows the action will resolve,
    /// suitable for a confirmation prompt and a VoiceOver announcement — count
    /// first, then a bounded list of merchant names so meaning never rides on a
    /// color or an unlabeled number alone.
    ///
    /// - Parameter previewLimit: how many merchant names to spell out before
    ///   collapsing the rest into "and N more".
    public func blastRadiusDescription(previewLimit: Int = 3) -> String {
        guard count > 0 else { return "No transactions to mark reviewed" }
        let noun = count == 1 ? "transaction" : "transactions"
        let names = affectedMerchantNames.prefix(max(previewLimit, 0))
        let remainder = count - names.count
        guard !names.isEmpty else { return "Mark \(count) \(noun) reviewed" }
        var preview = names.joined(separator: ", ")
        if remainder > 0 {
            preview += ", and \(remainder) more"
        }
        return "Mark \(count) \(noun) reviewed: \(preview)"
    }
}
