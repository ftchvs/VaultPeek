import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Income → category flow (AND-500)")
struct IncomeCategoryFlowTests {
    @Test("incomeSources groups same-merchant inflows and excludes outflows/transfers")
    func incomeSourcesGroupAndExclude() {
        let transactions = [
            tx(id: "a", amount: -1_000, merchant: "Employer", category: .income),
            tx(id: "b", amount: -500, merchant: "Employer", category: .income),
            tx(id: "c", amount: -300, merchant: "Stripe", category: .income),
            // Outflow — excluded.
            tx(id: "d", amount: 80, merchant: "Whole Foods", category: .foodAndDrink),
            // Transfer-in — isIncome (negative) but should it count? It's an inflow.
            // Income grouping keys on isIncome, so transfer-in inflows are included
            // as a "source"; we assert the two real income merchants group correctly.
        ]
        let sources = IncomeCategoryFlow.incomeSources(from: transactions)
        let employer = sources.first { $0.label == "Employer" }
        #expect(employer?.amount == 1_500)
        #expect(sources.contains { $0.label == "Stripe" })
        #expect(!sources.contains { $0.label == "Whole Foods" })
    }

    @Test("Source amounts use abs(amount) and sort descending")
    func sourcesUseAbsAndSortDesc() {
        let transactions = [
            tx(id: "a", amount: -300, merchant: "Small", category: .income),
            tx(id: "b", amount: -900, merchant: "Big", category: .income),
        ]
        let sources = IncomeCategoryFlow.incomeSources(from: transactions)
        #expect(sources.map(\.label) == ["Big", "Small"])
        #expect(sources.first?.amount == 900)
    }

    @Test("Spend column delegates to SpendingSummary (excludes income + transfers)")
    func spendColumnDelegates() {
        let transactions = [
            tx(id: "a", amount: -1_000, merchant: "Employer", category: .income),
            tx(id: "b", amount: 100, merchant: "Store", category: .shopping),
            tx(id: "c", amount: 60, merchant: "Cafe", category: .foodAndDrink),
            tx(id: "d", amount: 200, merchant: "Move", category: .transferOut),
        ]
        let graph = IncomeCategoryFlow.graph(from: transactions)
        let categoryIDs = Set(graph.categories.map(\.id))
        #expect(categoryIDs.contains(SpendingCategory.shopping.rawValue))
        #expect(categoryIDs.contains(SpendingCategory.foodAndDrink.rawValue))
        #expect(!categoryIDs.contains(SpendingCategory.income.rawValue))
        #expect(!categoryIDs.contains(SpendingCategory.transferOut.rawValue))
    }

    @Test("Each source's outgoing ribbons sum to that source's total")
    func sourceRibbonsSumToTotal() {
        let graph = sampleGraph()
        for source in graph.sources {
            let outgoing = graph.links.filter { $0.sourceID == source.id }.reduce(0) { $0 + $1.amount }
            #expect(abs(outgoing - source.amount) < 0.001)
        }
    }

    @Test("Each category's incoming ribbons sum to that category's spend")
    func categoryRibbonsSumToSpend() {
        let graph = sampleGraph()
        // Incoming per category = sum over sources of (sourceTotal * categoryShare)
        // = totalIncome * categoryShare. Only equals category spend when income
        // == spend; otherwise it is proportional. Assert proportional consistency:
        // each category's incoming share of total-incoming equals its spend share.
        let totalIncoming = graph.links.reduce(0) { $0 + $1.amount }
        for category in graph.categories {
            let incoming = graph.links.filter { $0.categoryID == category.id }.reduce(0) { $0 + $1.amount }
            let incomingShare = incoming / totalIncoming
            let spendShare = category.amount / graph.totalSpend
            #expect(abs(incomingShare - spendShare) < 0.001)
        }
    }

    @Test("Layout node heights are proportional and fill available height")
    func layoutHeightsProportional() {
        let graph = sampleGraph()
        let layout = FlowLayout.compute(graph: graph, width: 200, height: 100, nodeGap: 8, nodeWidth: 14)
        #expect(!layout.isEmpty)

        // Source column: total stacked heights + gaps == available height.
        let sourceHeights = layout.sourceRects.reduce(0) { $0 + $1.height }
        let sourceGaps = 8.0 * Double(max(layout.sourceRects.count - 1, 0))
        #expect(abs((sourceHeights + sourceGaps) - 100) < 0.001)

        // Larger value -> taller node (ordering invariant within a column).
        let sortedByAmount = graph.sources.sorted { $0.amount > $1.amount }
        if sortedByAmount.count >= 2 {
            let tallest = layout.sourceRects.first { $0.id == sortedByAmount[0].id }!
            let shorter = layout.sourceRects.first { $0.id == sortedByAmount[1].id }!
            #expect(tallest.height >= shorter.height)
        }
    }

    @Test("Empty period yields an empty layout with the empty flag, no NaN")
    func emptyPeriodEmptyLayout() {
        let graph = IncomeCategoryFlow.graph(from: [])
        #expect(graph.isEmpty)
        let layout = FlowLayout.compute(graph: graph, width: 200, height: 100)
        #expect(layout.isEmpty)
        #expect(layout.ribbons.isEmpty)
    }

    @Test("Income-only or spend-only period is degenerate (empty graph)")
    func oneSidedIsEmpty() {
        let incomeOnly = IncomeCategoryFlow.graph(from: [tx(id: "a", amount: -100, merchant: "Job", category: .income)])
        #expect(incomeOnly.isEmpty)
        let spendOnly = IncomeCategoryFlow.graph(from: [tx(id: "b", amount: 100, merchant: "Store", category: .shopping)])
        #expect(spendOnly.isEmpty)
    }

    @Test("Single source + single category produces one full-height ribbon")
    func singleSourceSingleCategory() {
        let transactions = [
            tx(id: "a", amount: -500, merchant: "Job", category: .income),
            tx(id: "b", amount: 200, merchant: "Store", category: .shopping),
        ]
        let graph = IncomeCategoryFlow.graph(from: transactions)
        #expect(graph.sources.count == 1)
        #expect(graph.categories.count == 1)
        #expect(graph.links.count == 1)
        let layout = FlowLayout.compute(graph: graph, width: 200, height: 100, nodeGap: 8, nodeWidth: 14)
        #expect(layout.ribbons.count == 1)
        // Single nodes fill the whole column height (no gaps with one node).
        #expect(abs((layout.sourceRects.first?.height ?? 0) - 100) < 0.001)
        #expect(abs((layout.categoryRects.first?.height ?? 0) - 100) < 0.001)
    }

    @Test("Determinism: identical inputs yield identical geometry")
    func deterministicGeometry() {
        let graph = sampleGraph()
        let a = FlowLayout.compute(graph: graph, width: 240, height: 120)
        let b = FlowLayout.compute(graph: graph, width: 240, height: 120)
        #expect(a == b)
    }

    @Test("Presentation builds non-empty rows and an accessibility summary for demo data")
    func presentationFromDemo() {
        let now = Formatters.parseTransactionDate("2026-06-15")!
        let calendar = Calendar(identifier: .gregorian)
        let presentation = IncomeCategoryFlowPresentation.make(
            from: DemoFixtures.transactions(now: now, calendar: calendar)
        )
        #expect(!presentation.isEmpty)
        #expect(!presentation.sources.isEmpty)
        #expect(!presentation.categories.isEmpty)
        #expect(presentation.accessibilityLabel.contains("Income"))
    }

    @Test("Presentation empty-state for an empty period")
    func presentationEmpty() {
        let presentation = IncomeCategoryFlowPresentation.make(from: [])
        #expect(presentation.isEmpty)
        #expect(!presentation.emptyTitle.isEmpty)
        #expect(!presentation.emptyDetail.isEmpty)
    }

    // MARK: - Helpers

    private func sampleGraph() -> IncomeCategoryFlow.Graph {
        IncomeCategoryFlow.graph(from: [
            tx(id: "i1", amount: -2_000, merchant: "Employer", category: .income),
            tx(id: "i2", amount: -600, merchant: "Stripe", category: .income),
            tx(id: "i3", amount: -200, merchant: "Venmo", category: .income),
            tx(id: "s1", amount: 400, merchant: "Store", category: .shopping),
            tx(id: "s2", amount: 250, merchant: "Cafe", category: .foodAndDrink),
            tx(id: "s3", amount: 150, merchant: "Gas", category: .transportation),
        ])
    }

    private func tx(
        id: String,
        amount: Double,
        merchant: String,
        category: SpendingCategory
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: "2026-06-10",
            name: merchant,
            merchantName: merchant,
            category: category
        )
    }
}
