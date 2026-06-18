import Foundation

/// Aggregation + layout geometry for the Income → Category flow ("Sankey")
/// surface (AND-500).
///
/// Swift Charts has no native flow/Sankey mark, so the ribbons are hand-rendered
/// over node rectangles. ALL the geometry here is pure value types
/// (`FlowRect`/`FlowRibbon` use plain `Double`), unit-testable with zero
/// SwiftUI. The aggregation honestly models an *aggregate-proportional* flow:
/// per-transaction income→category attribution does not exist in the data, so
/// each income source's total is split across spend categories by each
/// category's share of total spend. This is documented as such, not implied.
public enum IncomeCategoryFlow {
    /// One node in either column (an income source or a spend category).
    public struct Node: Sendable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let amount: Double
        /// Color hex for light backgrounds (categories use their own; sources
        /// share a neutral income tint).
        public let colorHex: String
        public let colorHexDark: String

        public init(id: String, label: String, amount: Double, colorHex: String, colorHexDark: String) {
            self.id = id
            self.label = label
            self.amount = amount
            self.colorHex = colorHex
            self.colorHexDark = colorHexDark
        }
    }

    /// A proportional link from a source to a category.
    public struct Link: Sendable, Equatable {
        public let sourceID: String
        public let categoryID: String
        public let amount: Double

        public init(sourceID: String, categoryID: String, amount: Double) {
            self.sourceID = sourceID
            self.categoryID = categoryID
            self.amount = amount
        }
    }

    /// The aggregated two-column graph for one period.
    public struct Graph: Sendable, Equatable {
        public let sources: [Node]
        public let categories: [Node]
        public let links: [Link]

        public init(sources: [Node], categories: [Node], links: [Link]) {
            self.sources = sources
            self.categories = categories
            self.links = links
        }

        public var isEmpty: Bool { sources.isEmpty || categories.isEmpty }
        public var totalIncome: Double { sources.reduce(0) { $0 + $1.amount } }
        public var totalSpend: Double { categories.reduce(0) { $0 + $1.amount } }
    }

    /// Neutral income tints used for source nodes (no per-source semantic color).
    static let incomeColorHex = "#82E0AA"
    static let incomeColorHexDark = "#6FCC98"

    /// Build the flow graph for a period's transactions.
    ///
    /// - Income sources: inflows grouped by merchant (`merchantName ?? name`),
    ///   summed via `displayAmount`, sorted descending.
    /// - Spend categories: delegated to `SpendingSummary.spendingByCategory`
    ///   (already excludes income + transfers and sorts descending).
    /// - Links: each source's total split across categories by each category's
    ///   share of total spend (aggregate-proportional).
    public static func graph(from transactions: [TransactionDTO]) -> Graph {
        let sources = incomeSources(from: transactions)
        let categoryTotals = SpendingSummary.spendingByCategory(from: transactions)
        let categories = categoryTotals.map { category, amount in
            Node(
                id: category.rawValue,
                label: category.displayName,
                amount: amount,
                colorHex: category.colorHex,
                colorHexDark: category.colorHexDark
            )
        }

        let totalSpend = categories.reduce(0) { $0 + $1.amount }
        var links: [Link] = []
        if totalSpend > 0 {
            for source in sources {
                for category in categories {
                    let share = category.amount / totalSpend
                    let amount = source.amount * share
                    guard amount > 0 else { continue }
                    links.append(Link(sourceID: source.id, categoryID: category.id, amount: amount))
                }
            }
        }

        return Graph(sources: sources, categories: categories, links: links)
    }

    /// Income sources grouped by merchant, summed (abs), sorted descending.
    public static func incomeSources(from transactions: [TransactionDTO]) -> [Node] {
        let inflows = transactions.filter(\.isIncome)
        var totals: [String: Double] = [:]
        var order: [String] = []
        for transaction in inflows {
            let label = transaction.displayName
            if totals[label] == nil { order.append(label) }
            totals[label, default: 0] += transaction.displayAmount
        }
        return order
            .map { label in
                Node(
                    id: "income:\(label)",
                    label: label,
                    amount: totals[label] ?? 0,
                    colorHex: incomeColorHex,
                    colorHexDark: incomeColorHexDark
                )
            }
            .filter { $0.amount > 0 }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.label < rhs.label
            }
    }
}

/// A laid-out node rectangle in flow-view coordinates (origin top-left, y down).
/// Pure `Double` so it is testable without CoreGraphics/SwiftUI.
public struct FlowRect: Sendable, Equatable {
    public let id: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(id: String, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midY: Double { y + height / 2 }
}

/// A laid-out ribbon connecting a source rect's right edge to a category rect's
/// left edge, as a cubic Bezier band described by its endpoints + control points.
public struct FlowRibbon: Sendable, Equatable {
    public let sourceID: String
    public let categoryID: String
    /// Vertical thickness of the band (proportional to the link amount).
    public let thickness: Double
    /// Start (source side) and end (category side) anchor points — band centers.
    public let startX: Double
    public let startY: Double
    public let endX: Double
    public let endY: Double
    /// Cubic control points (horizontal tangents for an S-curve).
    public let control1X: Double
    public let control1Y: Double
    public let control2X: Double
    public let control2Y: Double

    public init(
        sourceID: String,
        categoryID: String,
        thickness: Double,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        control1X: Double,
        control1Y: Double,
        control2X: Double,
        control2Y: Double
    ) {
        self.sourceID = sourceID
        self.categoryID = categoryID
        self.thickness = thickness
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.control1X = control1X
        self.control1Y = control1Y
        self.control2X = control2X
        self.control2Y = control2Y
    }
}

/// The complete laid-out flow geometry for a given draw size.
public struct FlowLayout: Sendable, Equatable {
    public let sourceRects: [FlowRect]
    public let categoryRects: [FlowRect]
    public let ribbons: [FlowRibbon]
    /// True when there is nothing to draw (empty/degenerate period).
    public let isEmpty: Bool

    public init(sourceRects: [FlowRect], categoryRects: [FlowRect], ribbons: [FlowRibbon], isEmpty: Bool) {
        self.sourceRects = sourceRects
        self.categoryRects = categoryRects
        self.ribbons = ribbons
        self.isEmpty = isEmpty
    }

    public static let empty = FlowLayout(sourceRects: [], categoryRects: [], ribbons: [], isEmpty: true)

    /// Compute node rectangles + ribbon geometry for a `Graph` in a draw area of
    /// `width` × `height`, with `nodeGap` vertical spacing between stacked nodes
    /// and `nodeWidth` column thickness.
    ///
    /// Node heights are proportional to value; the stacked heights + gaps exactly
    /// fill the available height per column. Guards empty/degenerate input.
    public static func compute(
        graph: IncomeCategoryFlow.Graph,
        width: Double,
        height: Double,
        nodeGap: Double = 8,
        nodeWidth: Double = 14
    ) -> FlowLayout {
        guard !graph.isEmpty, width > 0, height > 0 else { return .empty }

        let sourceRects = column(
            nodes: graph.sources,
            x: 0,
            columnHeight: height,
            nodeGap: nodeGap,
            nodeWidth: nodeWidth
        )
        let categoryRects = column(
            nodes: graph.categories,
            x: width - nodeWidth,
            columnHeight: height,
            nodeGap: nodeGap,
            nodeWidth: nodeWidth
        )
        guard !sourceRects.isEmpty, !categoryRects.isEmpty else { return .empty }

        let sourceByID = Dictionary(uniqueKeysWithValues: sourceRects.map { ($0.id, $0) })
        let categoryByID = Dictionary(uniqueKeysWithValues: categoryRects.map { ($0.id, $0) })
        let sourceTotals = Dictionary(uniqueKeysWithValues: graph.sources.map { ($0.id, $0.amount) })
        let categoryTotals = Dictionary(uniqueKeysWithValues: graph.categories.map { ($0.id, $0.amount) })

        // Running offsets so multiple ribbons stack within each node's height.
        var sourceOffset: [String: Double] = [:]
        var categoryOffset: [String: Double] = [:]

        var ribbons: [FlowRibbon] = []
        for link in graph.links {
            guard let sourceRect = sourceByID[link.sourceID],
                  let categoryRect = categoryByID[link.categoryID],
                  let sourceTotal = sourceTotals[link.sourceID], sourceTotal > 0,
                  let categoryTotal = categoryTotals[link.categoryID], categoryTotal > 0
            else { continue }

            // Thickness on each side is proportional to the link's share of that
            // node; use the source side for the band thickness.
            let sourceThickness = sourceRect.height * (link.amount / sourceTotal)
            let categoryThickness = categoryRect.height * (link.amount / categoryTotal)

            let sOff = sourceOffset[link.sourceID, default: 0]
            let cOff = categoryOffset[link.categoryID, default: 0]
            let startY = sourceRect.minY + sOff + sourceThickness / 2
            let endY = categoryRect.minY + cOff + categoryThickness / 2
            sourceOffset[link.sourceID] = sOff + sourceThickness
            categoryOffset[link.categoryID] = cOff + categoryThickness

            let startX = sourceRect.maxX
            let endX = categoryRect.x
            let midX = (startX + endX) / 2

            ribbons.append(
                FlowRibbon(
                    sourceID: link.sourceID,
                    categoryID: link.categoryID,
                    thickness: sourceThickness,
                    startX: startX,
                    startY: startY,
                    endX: endX,
                    endY: endY,
                    control1X: midX,
                    control1Y: startY,
                    control2X: midX,
                    control2Y: endY
                )
            )
        }

        return FlowLayout(
            sourceRects: sourceRects,
            categoryRects: categoryRects,
            ribbons: ribbons,
            isEmpty: false
        )
    }

    /// Stack nodes vertically, height ∝ value, total stacked height + gaps == columnHeight.
    private static func column(
        nodes: [IncomeCategoryFlow.Node],
        x: Double,
        columnHeight: Double,
        nodeGap: Double,
        nodeWidth: Double
    ) -> [FlowRect] {
        guard !nodes.isEmpty else { return [] }
        let total = nodes.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let gapCount = max(nodes.count - 1, 0)
        let totalGap = nodeGap * Double(gapCount)
        let availableForNodes = max(columnHeight - totalGap, 0)

        var rects: [FlowRect] = []
        var y = 0.0
        for node in nodes {
            let nodeHeight = availableForNodes * (node.amount / total)
            rects.append(FlowRect(id: node.id, x: x, y: y, width: nodeWidth, height: nodeHeight))
            y += nodeHeight + nodeGap
        }
        return rects
    }
}

private extension FlowRect {
    var maxX: Double { x + width }
}
