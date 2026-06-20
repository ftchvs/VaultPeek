import Foundation

/// Pure presentation model for the Spotlight ``SnippetIntent`` mini-dashboard and
/// the `systemLarge` widget (AND-586). Both surfaces show the same compact set of
/// rows — net balance, safe-to-spend, this period's spend, top categories — so the
/// row selection, masking, and formatting all live here in ``PlaidBarCore`` where
/// they are `Sendable` and unit-tested without the SwiftUI snippet view.
///
/// Privacy mirrors ``FinanceIntentQueries`` and ``ControlValuePresentation``: when
/// the snapshot is masked, missing, or empty, every figure is withheld (replaced
/// with the shared dot placeholder) and the view shows a setup/locked state — a
/// figure is never leaked past App Lock / Privacy Mask.
public enum SnippetDashboardPresentation {
    /// One labelled figure row in the mini-dashboard.
    public struct MetricRow: Sendable, Equatable, Identifiable {
        public let id: String
        /// User-facing metric name (e.g. "Safe to spend").
        public let title: String
        /// The figure rendered to a display string, or the dot placeholder when masked.
        public let value: String
        /// SF Symbol whose SHAPE carries the metric identity (never colour alone).
        public let systemImage: String

        public init(id: String, title: String, value: String, systemImage: String) {
            self.id = id
            self.title = title
            self.value = value
            self.systemImage = systemImage
        }
    }

    /// A rendered mini-dashboard ready to drop into a snippet or widget view.
    public struct Model: Sendable, Equatable {
        /// Headline overview line shown above the rows.
        public let headline: String
        /// The metric rows, in display order.
        public let rows: [MetricRow]
        /// Top spending categories, each as a ready-to-render label + value pair.
        public let categories: [MetricRow]
        /// When the underlying snapshot was produced (chrome, never sensitive).
        public let updatedAt: Date
        /// True when every figure is withheld (masked) or the snapshot is missing
        /// / empty (setup). Drives the view's masked/setup affordance.
        public let isWithheld: Bool
        /// A self-contained accessibility sentence describing the whole snippet.
        public let accessibilityLabel: String

        public init(
            headline: String,
            rows: [MetricRow],
            categories: [MetricRow],
            updatedAt: Date,
            isWithheld: Bool,
            accessibilityLabel: String
        ) {
            self.headline = headline
            self.rows = rows
            self.categories = categories
            self.updatedAt = updatedAt
            self.isWithheld = isWithheld
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// How many top categories the mini-dashboard renders.
    public static let maxCategories = 3

    /// Builds the mini-dashboard model from the shared snapshot (or its absence).
    public static func model(from snapshot: FinanceSnapshot?) -> Model {
        guard let snapshot, !snapshot.isEmpty else {
            return unavailableModel(updatedAt: snapshot?.generatedAt ?? Date())
        }
        if snapshot.isMasked {
            return maskedModel(updatedAt: snapshot.generatedAt)
        }

        let currency = snapshot.isoCurrencyCode
        let rows: [MetricRow] = [
            MetricRow(
                id: "total-balance",
                title: "Balance",
                value: Formatters.currency(snapshot.totalBalance, format: .compact, currencyCode: currency),
                systemImage: "banknote"
            ),
            MetricRow(
                id: "safe-to-spend",
                title: "Safe to spend",
                value: Formatters.currency(snapshot.safeToSpend, format: .compact, currencyCode: currency),
                systemImage: "dollarsign.circle"
            ),
            MetricRow(
                id: "period-spending",
                title: "Spent this period",
                value: Formatters.currency(snapshot.periodSpending, format: .compact, currencyCode: currency),
                systemImage: "chart.bar"
            ),
        ]

        let categories = snapshot.topSpendingCategories.prefix(maxCategories).map { row in
            MetricRow(
                id: "category-\(row.categoryKey)",
                title: row.displayName,
                value: Formatters.currency(row.amount, format: .compact, currencyCode: currency),
                systemImage: row.category?.iconName ?? "circle"
            )
        }

        let headline = snapshot.isDemoHeadline
        let a11y = accessibilitySentence(rows: rows, categories: Array(categories))

        return Model(
            headline: headline,
            rows: rows,
            categories: Array(categories),
            updatedAt: snapshot.generatedAt,
            isWithheld: false,
            accessibilityLabel: a11y
        )
    }

    // MARK: - Withheld states

    private static func maskedModel(updatedAt: Date) -> Model {
        Model(
            headline: "Figures hidden",
            rows: withheldRows,
            categories: [],
            updatedAt: updatedAt,
            isWithheld: true,
            accessibilityLabel: "VaultPeek figures are hidden while Privacy Mask is on."
        )
    }

    private static func unavailableModel(updatedAt: Date) -> Model {
        Model(
            headline: "Open VaultPeek",
            rows: [],
            categories: [],
            updatedAt: updatedAt,
            isWithheld: true,
            accessibilityLabel: "VaultPeek hasn't synced yet. Open VaultPeek to connect an account."
        )
    }

    private static var withheldRows: [MetricRow] {
        let dot = PrivacyMaskPresentation.compactValue
        return [
            MetricRow(id: "total-balance", title: "Balance", value: dot, systemImage: "eye.slash"),
            MetricRow(id: "safe-to-spend", title: "Safe to spend", value: dot, systemImage: "eye.slash"),
            MetricRow(id: "period-spending", title: "Spent this period", value: dot, systemImage: "eye.slash"),
        ]
    }

    private static func accessibilitySentence(rows: [MetricRow], categories: [MetricRow]) -> String {
        let metrics = rows.map { "\($0.title) \($0.value)" }.joined(separator: ", ")
        guard !categories.isEmpty else { return metrics + "." }
        let cats = categories.map { "\($0.value) on \($0.title)" }.joined(separator: ", ")
        return metrics + ". Top categories: " + cats + "."
    }
}

private extension FinanceSnapshot {
    /// A short overview headline for the mini-dashboard, leading with net balance.
    var isDemoHeadline: String {
        "Net balance \(Formatters.currency(totalBalance, format: .compact, currencyCode: isoCurrencyCode))"
    }
}
