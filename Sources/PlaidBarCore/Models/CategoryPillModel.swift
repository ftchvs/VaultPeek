import Foundation

/// The display contract for a colored icon+text category pill (AND-530).
///
/// A review-inbox row tags each transaction with its effective ``SpendingCategory``
/// (or "Uncategorized" when none resolves yet). The pill renders that tag as a glyph
/// plus the category name plus an accent — the accent is a *redundant* layer only:
/// the title text and the glyph always carry the meaning, so the pill never conveys
/// the category by color alone (ACCESSIBILITY.md).
///
/// This is the pure, `Sendable`, testable half: it owns the title / glyph / accent-hex
/// mapping so the view stays a thin renderer. The view maps `accentColorHex` to a
/// SwiftUI `Color` through the app's `CategoryAccentTokens`; the hex carried here is the
/// canonical chart hex the rest of the app already keys off, so the pill's accent never
/// drifts from the donut / status bars for the same category.
public struct CategoryPillModel: Sendable, Hashable {
    /// The category this pill represents, or `nil` for an unresolved/uncategorized row.
    public let category: SpendingCategory?
    /// The user-facing label — always shown, so meaning never rides on color.
    public let title: String
    /// SF Symbol name shown alongside the title (the redundant glyph layer).
    public let glyph: String
    /// Canonical accent hex (light appearance) the view resolves to a `Color`. Kept in
    /// sync with ``SpendingCategory/colorHex`` so the pill matches the dashboard accents.
    public let accentColorHex: String

    public init(category: SpendingCategory?, title: String, glyph: String, accentColorHex: String) {
        self.category = category
        self.title = title
        self.glyph = glyph
        self.accentColorHex = accentColorHex
    }

    /// The placeholder title shown when a row has no resolved category.
    public static let uncategorizedTitle = "Uncategorized"
    /// The placeholder glyph for an uncategorized row — a neutral tag outline that reads
    /// as "no category yet" rather than borrowing any real category's symbol.
    public static let uncategorizedGlyph = "tag"
    /// Neutral grey accent hex for the uncategorized pill (mirrors `SpendingCategory.other`).
    public static let uncategorizedAccentHex = "#BDC3C7"

    /// Builds the pill model for an effective category. Passing `nil` yields the neutral
    /// "Uncategorized" pill, so a review row that has not been categorized still shows a
    /// labelled, glyphed pill instead of nothing.
    public static func make(category: SpendingCategory?) -> CategoryPillModel {
        guard let category else {
            return CategoryPillModel(
                category: nil,
                title: uncategorizedTitle,
                glyph: uncategorizedGlyph,
                accentColorHex: uncategorizedAccentHex
            )
        }
        return CategoryPillModel(
            category: category,
            title: category.displayName,
            glyph: category.iconName,
            accentColorHex: category.colorHex
        )
    }
}
