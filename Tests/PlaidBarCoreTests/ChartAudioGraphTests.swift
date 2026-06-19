import Foundation
import Testing
@testable import PlaidBarCore

@Suite("ChartAudioGraph data → audio-graph descriptor mapping (AND-569)")
struct ChartAudioGraphTests {
    // MARK: - NumericAxis invariants

    @Test("numeric axis keeps an ordered range")
    func axisKeepsOrderedRange() {
        let axis = ChartAudioGraph.NumericAxis(title: "Y", lowerBound: 10, upperBound: 100)
        #expect(axis.lowerBound == 10)
        #expect(axis.upperBound == 100)
    }

    @Test("numeric axis normalizes an inverted range")
    func axisNormalizesInvertedRange() {
        let axis = ChartAudioGraph.NumericAxis(title: "Y", lowerBound: 100, upperBound: 10)
        #expect(axis.lowerBound == 10)
        #expect(axis.upperBound == 100)
    }

    // MARK: - Trend

    private func snapshot(_ daysAgo: Int, _ balance: Double, now: Date = Date()) -> BalanceSnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return BalanceSnapshot(date: date, balance: balance)
    }

    @Test("trend maps every snapshot to an ordered continuous point")
    func trendMapsPoints() {
        let now = Date()
        let history = [snapshot(2, 1000, now: now), snapshot(1, 1500, now: now), snapshot(0, 1200, now: now)]
        let trend = try! #require(BalanceTrend.evaluate(history: history, now: now, windowDays: 90))

        let descriptor = ChartAudioGraph.trend(trend)

        #expect(!descriptor.isEmpty)
        #expect(descriptor.points.count == 3)
        #expect(descriptor.isContinuous)
        // x is a 0-based, monotonically increasing day index.
        #expect(descriptor.points.map(\.xValue) == [0, 1, 2])
        // y carries the real recorded balances in chronological order.
        #expect(descriptor.points.map(\.yValue) == [1000, 1500, 1200])
        // y axis spans the min/max balance.
        #expect(descriptor.yAxis.lowerBound == 1000)
        #expect(descriptor.yAxis.upperBound == 1500)
        #expect(descriptor.yAxis.title == "Net worth")
        // x axis spans the index range.
        #expect(descriptor.xAxis.lowerBound == 0)
        #expect(descriptor.xAxis.upperBound == 2)
        // Summary reuses the chart's spoken summary so audio + label agree.
        #expect(descriptor.summary == trend.accessibilitySummary)
    }

    @Test("trend point labels include the formatted balance")
    func trendPointLabelsHaveAmounts() {
        let now = Date()
        let history = [snapshot(1, 1000, now: now), snapshot(0, 2000, now: now)]
        let trend = try! #require(BalanceTrend.evaluate(history: history, now: now, windowDays: 90))

        let descriptor = ChartAudioGraph.trend(trend)
        // Last point is "today" with the $2,000 balance.
        let last = try! #require(descriptor.points.last)
        #expect(last.label.contains("2,000"))
        #expect(last.xLabel == Formatters.displayDate(history[1].date))
    }

    // MARK: - Donut

    private func donutModel(_ pairs: [(CategoryGroup, SpendingCategory, Double)]) -> SpendDonutModel {
        let groups = pairs.map { group, leaf, spent in
            CategoryDashboardPresentation.GroupRollup(
                group: group,
                leaves: [CategoryDashboardPresentation.Leaf(category: leaf, spent: spent, monthlyLimit: nil)]
            )
        }
        return SpendDonutModel(presentation: CategoryDashboardPresentation(groups: groups))
    }

    @Test("donut maps each slice to a discrete point, spend-heaviest first")
    func donutMapsSlices() {
        let model = donutModel([
            (.shopping, .shopping, 100),
            (.foodAndDining, .foodAndDrink, 400),
            (.transportation, .transportation, 250),
        ])

        let descriptor = ChartAudioGraph.donut(model)

        #expect(descriptor.points.count == 3)
        #expect(!descriptor.isContinuous)
        // Ordered spend-heaviest first (inherited from the donut model order).
        #expect(descriptor.points.map(\.yValue) == [400, 250, 100])
        #expect(descriptor.points.map(\.xValue) == [0, 1, 2])
        #expect(descriptor.points.map(\.xLabel) == ["Food & Dining", "Transportation", "Shopping"])
        // y axis upper bound is the heaviest slice; floored at 0.
        #expect(descriptor.yAxis.lowerBound == 0)
        #expect(descriptor.yAxis.upperBound == 400)
        // Unmasked summary is the donut's full spoken label.
        #expect(descriptor.summary == model.accessibilityLabel)
    }

    @Test("donut point label carries amount + share when unmasked")
    func donutLabelsHaveAmounts() {
        let model = donutModel([(.foodAndDining, .foodAndDrink, 400)])
        let descriptor = ChartAudioGraph.donut(model)
        let point = try! #require(descriptor.points.first)
        #expect(point.label.contains("Food & Dining"))
        #expect(point.label.contains("$400"))
        #expect(point.label.contains("100%"))
    }

    @Test("donut masks amounts in labels + summary when Privacy Mask is on")
    func donutMaskedHidesAmounts() {
        let model = donutModel([
            (.foodAndDining, .foodAndDrink, 400),
            (.shopping, .shopping, 100),
        ])
        let descriptor = ChartAudioGraph.donut(model, isPrivacyMasked: true)

        // Pitch still carries relative magnitude (values are intact)...
        #expect(descriptor.points.map(\.yValue) == [400, 100])
        // ...but no spoken label or summary leaks a dollar amount.
        for point in descriptor.points {
            #expect(!point.label.contains("$"))
            #expect(point.label.contains("%")) // share is kept
        }
        #expect(!descriptor.summary.contains("$"))
        #expect(descriptor.summary.contains("Privacy Mask"))
    }

    @Test("empty donut yields an empty descriptor")
    func donutEmpty() {
        let model = SpendDonutModel(presentation: .empty)
        let descriptor = ChartAudioGraph.donut(model)
        #expect(descriptor.isEmpty)
        #expect(descriptor.points.isEmpty)
        // Degenerate index range stays non-inverted.
        #expect(descriptor.xAxis.lowerBound == 0)
        #expect(descriptor.xAxis.upperBound == 0)
    }

    // MARK: - Heatmap

    private func transaction(_ date: String, amount: Double, category: SpendingCategory = .shopping) -> TransactionDTO {
        TransactionDTO(
            id: "\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: "tx",
            category: category
        )
    }

    private func heatmapLayout(_ transactions: [TransactionDTO], mode: SpendingHeatmapMode = .spending) -> SpendingHeatmapLayout {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -10, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: mode,
            calendar: calendar
        )
    }

    @Test("heatmap sonifies only active days, in order")
    func heatmapActiveDaysOnly() {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let day1 = Formatters.transactionDateString(calendar.date(byAdding: .day, value: -3, to: end)!)
        let day2 = Formatters.transactionDateString(calendar.date(byAdding: .day, value: -1, to: end)!)

        let layout = heatmapLayout([
            transaction(day1, amount: 50),
            transaction(day2, amount: 120),
        ])

        let descriptor = ChartAudioGraph.heatmap(layout)

        // Only the two days with transactions become points (silent days dropped).
        #expect(descriptor.points.count == 2)
        #expect(!descriptor.isContinuous)
        #expect(descriptor.points.map(\.xValue) == [0, 1])
        // Chronological: day1 (older) before day2 (newer).
        #expect(descriptor.points[0].yValue == 50)
        #expect(descriptor.points[1].yValue == 120)
        #expect(descriptor.yAxis.title == "Spend")
    }

    @Test("heatmap point labels carry the amount when unmasked and hide it when masked")
    func heatmapLabelMasking() {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let day = Formatters.transactionDateString(calendar.date(byAdding: .day, value: -2, to: end)!)
        let layout = heatmapLayout([transaction(day, amount: 75)])

        let unmasked = ChartAudioGraph.heatmap(layout)
        #expect(try! #require(unmasked.points.first).label.contains("$75"))

        let masked = ChartAudioGraph.heatmap(layout, isPrivacyMasked: true)
        let maskedPoint = try! #require(masked.points.first)
        #expect(!maskedPoint.label.contains("$"))
        #expect(maskedPoint.label.contains("transaction"))
    }

    @Test("empty heatmap yields an empty descriptor")
    func heatmapEmpty() {
        let layout = heatmapLayout([])
        let descriptor = ChartAudioGraph.heatmap(layout)
        #expect(descriptor.isEmpty)
        #expect(descriptor.points.isEmpty)
    }

    // MARK: - Y-axis value description (Privacy Mask)

    // This is the value description VoiceOver speaks while scrubbing the audio
    // graph's value axis — the SwiftUI representable's `yAxis` provider calls this
    // exact function, so testing it here covers the representable-level masking
    // without a host view.

    @Test("y-axis value description carries the exact amount when unmasked")
    func yAxisValueUnmaskedHasAmount() {
        let description = ChartAudioGraph.yAxisValueDescription(1234.56, isMasked: false)
        #expect(description == Formatters.currency(1234.56, format: .full))
        #expect(description.contains("1,234"))
        #expect(description.contains("$"))
    }

    @Test("y-axis value description redacts the amount when masked")
    func yAxisValueMaskedHidesAmount() {
        let description = ChartAudioGraph.yAxisValueDescription(1234.56, isMasked: true)
        // No exact figure / currency leaks through the spoken value axis.
        #expect(!description.contains("$"))
        #expect(!description.contains("1,234"))
        #expect(!description.contains("1234"))
        #expect(description == PrivacyMaskPresentation.compactValue)
    }

    @Test("donut descriptor carries the mask flag so the y-axis provider can redact")
    func donutDescriptorPropagatesMaskFlag() {
        let model = donutModel([(.foodAndDining, .foodAndDrink, 400)])

        let unmasked = ChartAudioGraph.donut(model, isPrivacyMasked: false)
        #expect(!unmasked.isPrivacyMasked)
        #expect(ChartAudioGraph.yAxisValueDescription(unmasked.points[0].yValue, isMasked: unmasked.isPrivacyMasked).contains("$400"))

        let masked = ChartAudioGraph.donut(model, isPrivacyMasked: true)
        #expect(masked.isPrivacyMasked)
        // y values are intact for pitch...
        #expect(masked.points.map(\.yValue) == [400])
        // ...but the spoken value description leaks no amount.
        #expect(!ChartAudioGraph.yAxisValueDescription(masked.points[0].yValue, isMasked: masked.isPrivacyMasked).contains("$"))
    }

    @Test("heatmap descriptor carries the mask flag so the y-axis provider can redact")
    func heatmapDescriptorPropagatesMaskFlag() {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let day = Formatters.transactionDateString(calendar.date(byAdding: .day, value: -2, to: end)!)
        let layout = heatmapLayout([transaction(day, amount: 75)])

        let unmasked = ChartAudioGraph.heatmap(layout, isPrivacyMasked: false)
        #expect(!unmasked.isPrivacyMasked)
        #expect(ChartAudioGraph.yAxisValueDescription(unmasked.points[0].yValue, isMasked: unmasked.isPrivacyMasked).contains("$"))

        let masked = ChartAudioGraph.heatmap(layout, isPrivacyMasked: true)
        #expect(masked.isPrivacyMasked)
        #expect(!ChartAudioGraph.yAxisValueDescription(masked.points[0].yValue, isMasked: masked.isPrivacyMasked).contains("$"))
    }

    @Test("trend descriptor is unmasked (trend chart is not privacy-masked)")
    func trendDescriptorIsUnmasked() {
        let now = Date()
        let history = [snapshot(1, 1000, now: now), snapshot(0, 2000, now: now)]
        let trend = try! #require(BalanceTrend.evaluate(history: history, now: now, windowDays: 90))
        let descriptor = ChartAudioGraph.trend(trend)
        #expect(!descriptor.isPrivacyMasked)
    }
}
