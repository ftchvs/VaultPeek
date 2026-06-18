import Foundation

/// Display-ready model for the Income → Category flow surface (AND-500).
///
/// Wraps `IncomeCategoryFlow.Graph` with formatted labels + a VoiceOver summary
/// so the view stays thin and the wording is testable without rendering.
public struct IncomeCategoryFlowPresentation: Sendable, Equatable {
    public struct NodeRow: Sendable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let amountText: String
        public let colorHex: String
        public let colorHexDark: String

        public init(id: String, label: String, amountText: String, colorHex: String, colorHexDark: String) {
            self.id = id
            self.label = label
            self.amountText = amountText
            self.colorHex = colorHex
            self.colorHexDark = colorHexDark
        }
    }

    public let graph: IncomeCategoryFlow.Graph
    public let sources: [NodeRow]
    public let categories: [NodeRow]
    public let totalIncomeText: String
    public let totalSpendText: String
    public let summaryText: String
    public let accessibilityLabel: String
    public let isEmpty: Bool
    public let emptyTitle: String
    public let emptyDetail: String

    public init(
        graph: IncomeCategoryFlow.Graph,
        sources: [NodeRow],
        categories: [NodeRow],
        totalIncomeText: String,
        totalSpendText: String,
        summaryText: String,
        accessibilityLabel: String,
        isEmpty: Bool,
        emptyTitle: String,
        emptyDetail: String
    ) {
        self.graph = graph
        self.sources = sources
        self.categories = categories
        self.totalIncomeText = totalIncomeText
        self.totalSpendText = totalSpendText
        self.summaryText = summaryText
        self.accessibilityLabel = accessibilityLabel
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
    }

    public static func make(from transactions: [TransactionDTO]) -> IncomeCategoryFlowPresentation {
        let graph = IncomeCategoryFlow.graph(from: transactions)
        let sources = graph.sources.map(Self.row(from:))
        let categories = graph.categories.map(Self.row(from:))
        let isEmpty = graph.isEmpty

        let totalIncomeText = Formatters.currency(graph.totalIncome, format: .compact)
        let totalSpendText = Formatters.currency(graph.totalSpend, format: .compact)
        let summaryText = isEmpty
            ? "No income-to-spending flow for this period."
            : "\(graph.sources.count) income source\(graph.sources.count == 1 ? "" : "s") → \(graph.categories.count) categor\(graph.categories.count == 1 ? "y" : "ies")"

        let accessibilityLabel: String
        if isEmpty {
            accessibilityLabel = "Income to category flow. No data for this period."
        } else {
            let sourceList = graph.sources.map { "\($0.label) \(Formatters.currency($0.amount, format: .compact))" }.joined(separator: ", ")
            let categoryList = graph.categories.map { "\($0.label) \(Formatters.currency($0.amount, format: .compact))" }.joined(separator: ", ")
            accessibilityLabel = "Income to category flow. Income: \(sourceList). Spending: \(categoryList). Flows are aggregate-proportional, not per-transaction."
        }

        return IncomeCategoryFlowPresentation(
            graph: graph,
            sources: sources,
            categories: categories,
            totalIncomeText: totalIncomeText,
            totalSpendText: totalSpendText,
            summaryText: summaryText,
            accessibilityLabel: accessibilityLabel,
            isEmpty: isEmpty,
            emptyTitle: "No flow to show yet",
            emptyDetail: "VaultPeek maps income sources to spending categories once this period has both income and spending in synced local transactions."
        )
    }

    private static func row(from node: IncomeCategoryFlow.Node) -> NodeRow {
        NodeRow(
            id: node.id,
            label: node.label,
            amountText: Formatters.currency(node.amount, format: .compact),
            colorHex: node.colorHex,
            colorHexDark: node.colorHexDark
        )
    }
}
