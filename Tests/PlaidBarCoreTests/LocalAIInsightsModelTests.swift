import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Local AI insights model accessors")
struct LocalAIInsightsModelTests {
    @Test("Insight window ids mirror their raw values")
    func windowIds() {
        for window in LocalAIInsightWindow.allCases {
            #expect(window.id == window.rawValue)
        }
    }

    @Test("Category resolution source has a distinct display name per case")
    func resolutionSourceDisplayNames() {
        #expect(LocalAICategoryResolutionSource.localAISuggestion.displayName == "Local AI")
        #expect(LocalAICategoryResolutionSource.appleNaturalLanguage.displayName == "Suggested")
        #expect(LocalAICategoryResolutionSource.plaidCategory.displayName == "Plaid")
        #expect(LocalAICategoryResolutionSource.fallbackOther.displayName == "Other")
    }

    @Test("DTO identities derive from their key fields")
    func dtoIdentities() {
        let total = LocalAICategoryTotal(
            category: .foodAndDrink, totalAmount: 100, transactionCount: 3,
            transactionIds: ["t1"], evidence: []
        )
        #expect(total.id == "FOOD_AND_DRINK")

        let item = LocalAITransactionInsightItem(
            transactionId: "t1", accountId: "a1", date: "2026-06-14", displayName: "Coffee",
            amount: 5, effectiveCategory: .foodAndDrink, plaidCategory: nil,
            categorySource: .appleNaturalLanguage, pending: false, evidence: []
        )
        #expect(item.id == "t1")

        let suggestion = LocalAICategorySuggestion(
            transactionId: "t1", suggestedCategory: .shopping, confidence: 0.9, evidence: []
        )
        #expect(suggestion.id == "t1-GENERAL_MERCHANDISE")
    }

    // MARK: - Window labels

    @Test("Each window has full display, long, and accessibility labels")
    func windowLabels() {
        #expect(LocalAIInsightWindow.last7days.displayName == "Last 7 days")
        #expect(LocalAIInsightWindow.lastMonth.displayName == "Last 30 days")
        #expect(LocalAIInsightWindow.yearOverYear.displayName == "Year over year")

        #expect(LocalAIInsightWindow.last7days.longDisplayName == "Last 7 days")
        #expect(LocalAIInsightWindow.lastMonth.longDisplayName == "Last 30 days")
        #expect(LocalAIInsightWindow.yearOverYear.longDisplayName == "Year over year")

        #expect(LocalAIInsightWindow.last7days.accessibilityName == "Last 7 days")
        #expect(LocalAIInsightWindow.lastMonth.accessibilityName == "Last 30 days")
        #expect(LocalAIInsightWindow.yearOverYear.accessibilityName == "Year over year")
    }

    @Test("Summary-sentence labels agree with picker labels for every window")
    func summaryLabelsAgreeWithPickerLabels() {
        // Bug guard: the segmented control reads `longDisplayName` and the
        // deterministic summary sentence reads `displayName`. They must say the
        // same thing so the period the user picks matches the period the summary
        // names across every local-AI insights window.
        for window in LocalAIInsightWindow.allCases {
            #expect(window.displayName == window.longDisplayName)

            let input = Self.makeInput(window: window, expenseTotal: 1200, incomeTotal: 3000, net: 1800)
            let text = LocalAIDeterministicSummary.summaryText(for: input)
            #expect(text.hasPrefix("\(window.longDisplayName):"))
        }
        #expect(!LocalAIDeterministicSummary.summaryText(for: Self.makeInput(window: .lastMonth, expenseTotal: 1200, incomeTotal: 3000, net: 1800)).contains("Last Month"))

        // SF Symbols pair text with a shape so the selector never rides on color
        // alone, and the three symbols are distinct.
        let symbols = Set(LocalAIInsightWindow.allCases.map(\.systemImage))
        #expect(symbols.count == LocalAIInsightWindow.allCases.count)
        for window in LocalAIInsightWindow.allCases {
            #expect(!window.systemImage.isEmpty)
        }
    }

    // MARK: - Date ranges (window-specific spans)

    @Test("7d / 30d / YoY windows produce their own current+prior spans")
    func windowDateRanges() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))

        let last7 = LocalAIInsightInputBuilder.dateRanges(for: .last7days, anchorDate: anchor)
        #expect(last7.current.startDate == "2026-03-09")
        #expect(last7.current.endDate == "2026-03-15")
        #expect(last7.prior?.startDate == "2026-03-02")
        #expect(last7.prior?.endDate == "2026-03-08")

        let lastMonth = LocalAIInsightInputBuilder.dateRanges(for: .lastMonth, anchorDate: anchor)
        #expect(lastMonth.current.startDate == "2026-02-14")
        #expect(lastMonth.current.endDate == "2026-03-15")

        let yoy = LocalAIInsightInputBuilder.dateRanges(for: .yearOverYear, anchorDate: anchor)
        #expect(yoy.current.startDate == "2025-03-16")
        #expect(yoy.current.endDate == "2026-03-15")
        #expect(yoy.prior?.startDate == "2024-03-16")
        #expect(yoy.prior?.endDate == "2025-03-15")

        // The three windows are distinct spans.
        #expect(last7.current.startDate != lastMonth.current.startDate)
        #expect(lastMonth.current.startDate != yoy.current.startDate)
    }

    // MARK: - Deterministic summary copy

    @Test("Deterministic summary headline is window-labeled with totals")
    func deterministicSummaryHeadline() {
        let input = Self.makeInput(window: .lastMonth, expenseTotal: 1200, incomeTotal: 3000, net: 1800)
        let text = LocalAIDeterministicSummary.summaryText(for: input)
        #expect(text.hasPrefix("Last 30 days:"))
        #expect(text.contains("expenses"))
        #expect(text.contains("income"))
        #expect(text.contains("net cashflow"))
    }

    @Test("Deterministic bullets phrase the comparison span per window")
    func deterministicBulletsAreWindowAware() {
        let prior = Self.makeMetrics(expenseTotal: 800, incomeTotal: 3000)

        let lastMonth = Self.makeInput(window: .lastMonth, expenseTotal: 1200, incomeTotal: 3000, net: 1800, prior: prior)
        let monthBullets = LocalAIDeterministicSummary.bullets(for: lastMonth).joined(separator: " ")
        #expect(monthBullets.contains("the prior 30 days"))

        let yoy = Self.makeInput(window: .yearOverYear, expenseTotal: 1200, incomeTotal: 3000, net: 1800, prior: prior)
        let yoyBullets = LocalAIDeterministicSummary.bullets(for: yoy).joined(separator: " ")
        #expect(yoyBullets.contains("the same period a year ago"))
        #expect(!yoyBullets.contains("the prior 30 days"))

        let last7 = Self.makeInput(window: .last7days, expenseTotal: 1200, incomeTotal: 3000, net: 1800, prior: prior)
        let weekBullets = LocalAIDeterministicSummary.bullets(for: last7).joined(separator: " ")
        #expect(weekBullets.contains("the prior 7 days"))
    }

    @Test("Comparison-window phrase differs across all three windows")
    func comparisonWindowPhrasePerWindow() {
        let phrases = LocalAIInsightWindow.allCases.map(LocalAIDeterministicSummary.comparisonWindowPhrase)
        #expect(Set(phrases).count == LocalAIInsightWindow.allCases.count)
        #expect(LocalAIDeterministicSummary.comparisonWindowPhrase(for: .yearOverYear) == "the same period a year ago")
    }

    @Test("signedCurrency prefixes positive, negative, and zero correctly")
    func signedCurrency() {
        #expect(LocalAIDeterministicSummary.signedCurrency(100).hasPrefix("+"))
        #expect(LocalAIDeterministicSummary.signedCurrency(-100).hasPrefix("-"))
        let zero = LocalAIDeterministicSummary.signedCurrency(0)
        #expect(!zero.hasPrefix("+"))
        #expect(!zero.hasPrefix("-"))
    }

    // MARK: - Window selection availability

    @Test("A window with no source rows is unusable and explained")
    func selectionMarksEmptyWindowsUnusable() {
        let summaries = [
            Self.makeSummary(window: .last7days, currentCount: 0),
            Self.makeSummary(window: .lastMonth, currentCount: 12),
            Self.makeSummary(window: .yearOverYear, currentCount: 0),
        ]
        let selection = LocalAIInsightWindowSelection.make(summaries: summaries, requestedSelection: .last7days)

        let byWindow = Dictionary(uniqueKeysWithValues: selection.options.map { ($0.window, $0) })
        #expect(byWindow[.last7days]?.isUsable == false)
        #expect(byWindow[.last7days]?.unavailableReason != nil)
        #expect(byWindow[.lastMonth]?.isUsable == true)
        #expect(byWindow[.lastMonth]?.unavailableReason == nil)
        // Requested 7-day window is unusable → resolves to the first usable one.
        #expect(selection.resolvedSelection == .lastMonth)
    }

    @Test("Year-over-year needs a prior window with history to be usable")
    func selectionYearOverYearNeedsPrior() {
        // YoY current has rows but no prior history → unusable.
        let noPrior = LocalAIInsightWindowSelection.make(
            summaries: [Self.makeSummary(window: .yearOverYear, currentCount: 20, priorCount: 0)],
            requestedSelection: .yearOverYear
        )
        let noPriorYoY = noPrior.options.first { $0.window == .yearOverYear }
        #expect(noPriorYoY?.isUsable == false)
        #expect(noPriorYoY?.unavailableReason?.contains("year of history") == true)

        // With prior history → usable and the request is honored.
        let withPrior = LocalAIInsightWindowSelection.make(
            summaries: [Self.makeSummary(window: .yearOverYear, currentCount: 20, priorCount: 18)],
            requestedSelection: .yearOverYear
        )
        let withPriorYoY = withPrior.options.first { $0.window == .yearOverYear }
        #expect(withPriorYoY?.isUsable == true)
        #expect(withPrior.resolvedSelection == .yearOverYear)
    }

    @Test("Always offers all three windows in order, even when none are usable")
    func selectionAlwaysOffersAllWindows() {
        let selection = LocalAIInsightWindowSelection.make(summaries: [], requestedSelection: .lastMonth)
        #expect(selection.options.map(\.window) == LocalAIInsightWindow.allCases)
        #expect(selection.options.allSatisfy { !$0.isUsable })
        // Nothing usable → keep the requested window so the selector stays stable.
        #expect(selection.resolvedSelection == .lastMonth)
    }

    @Test("A usable requested window is honored over the default order")
    func selectionHonorsUsableRequest() {
        let summaries = [
            Self.makeSummary(window: .last7days, currentCount: 5),
            Self.makeSummary(window: .lastMonth, currentCount: 20),
            Self.makeSummary(window: .yearOverYear, currentCount: 30, priorCount: 25),
        ]
        let selection = LocalAIInsightWindowSelection.make(summaries: summaries, requestedSelection: .yearOverYear)
        #expect(selection.resolvedSelection == .yearOverYear)
    }

    @Test("The displayed summary must follow the resolved selection, not the raw requested window (codex #9)")
    func displayedSummaryFollowsResolvedSelection() {
        // Requested YoY, but it became unusable (no prior-year rows) after a refresh.
        // The selector resolves to the first usable window (lastMonth). The displayed
        // summary AND the selected chip must follow `resolvedSelection` — keying off
        // the raw requested window would show a disabled/misleading YoY receipt.
        let summaries = [
            Self.makeSummary(window: .last7days, currentCount: 0),
            Self.makeSummary(window: .lastMonth, currentCount: 18),
            Self.makeSummary(window: .yearOverYear, currentCount: 30, priorCount: 0),
        ]
        let requested = LocalAIInsightWindow.yearOverYear
        let selection = LocalAIInsightWindowSelection.make(summaries: summaries, requestedSelection: requested)

        #expect(selection.resolvedSelection == .lastMonth)
        #expect(selection.resolvedSelection != requested)

        // Mirror AppState.summary(for:) — the displayed summary the surface renders.
        let displayed = Self.summary(for: selection.resolvedSelection, in: summaries)
        let misleading = Self.summary(for: requested, in: summaries)

        // Driving the receipt off the resolved selection shows the usable lastMonth
        // window, not the unusable requested YoY window.
        #expect(displayed?.window == .lastMonth)
        #expect(misleading?.window == .yearOverYear)
        #expect(displayed?.window != misleading?.window)

        // The selected chip is the resolved window, and it is a usable option.
        let resolvedOption = selection.options.first { $0.window == selection.resolvedSelection }
        #expect(resolvedOption?.isUsable == true)
    }

    /// The same closest-window fallback `AppState.summary(for:)` uses: exact window →
    /// lastMonth → first. Mirrored here so the pure model test pins the relationship
    /// the AppState fix relies on (the app target is not in this test binary).
    private static func summary(
        for window: LocalAIInsightWindow,
        in summaries: [LocalAIActivitySummary]
    ) -> LocalAIActivitySummary? {
        summaries.first { $0.window == window }
            ?? summaries.first { $0.window == .lastMonth }
            ?? summaries.first
    }

    // MARK: - Fixtures

    private static func makeMetrics(
        transactionCount: Int = 5,
        expenseTotal: Double = 1000,
        incomeTotal: Double = 0
    ) -> LocalAIActivityMetrics {
        LocalAIActivityMetrics(
            transactionCount: transactionCount,
            incomeTotal: incomeTotal,
            expenseTotal: expenseTotal,
            netCashflow: incomeTotal - expenseTotal,
            incomeTransactionIds: [],
            expenseTransactionIds: [],
            transferTransactionIds: [],
            categoryTotals: [],
            topExpenses: [],
            topIncome: []
        )
    }

    private static func makeInput(
        window: LocalAIInsightWindow,
        expenseTotal: Double,
        incomeTotal: Double,
        net: Double,
        prior: LocalAIActivityMetrics? = nil
    ) -> LocalAIActivitySummaryInput {
        let current = LocalAIActivityMetrics(
            transactionCount: 10,
            incomeTotal: incomeTotal,
            expenseTotal: expenseTotal,
            netCashflow: net,
            incomeTransactionIds: [],
            expenseTransactionIds: [],
            transferTransactionIds: [],
            categoryTotals: [],
            topExpenses: [],
            topIncome: []
        )
        return LocalAIActivitySummaryInput(
            window: window,
            currentRange: LocalAIInsightDateRange(startDate: "2026-05-13", endDate: "2026-06-11"),
            priorRange: prior == nil ? nil : LocalAIInsightDateRange(startDate: "2026-04-13", endDate: "2026-05-12"),
            categorySuggestions: [],
            accountSnapshot: LocalAIAccountSnapshot(accountCount: 1, accountIds: [], cashTotal: 0, debtTotal: 0, creditUtilization: nil),
            current: current,
            prior: prior,
            recurringSnapshot: LocalAIRecurringSnapshot(estimatedMonthlyTotal: 0, items: []),
            evidence: []
        )
    }

    private static func makeSummary(
        window: LocalAIInsightWindow,
        currentCount: Int,
        priorCount: Int? = nil
    ) -> LocalAIActivitySummary {
        let prior = priorCount.map { makeMetrics(transactionCount: $0) }
        let input = LocalAIActivitySummaryInput(
            window: window,
            currentRange: LocalAIInsightDateRange(startDate: "2026-05-13", endDate: "2026-06-11"),
            priorRange: prior == nil ? nil : LocalAIInsightDateRange(startDate: "2025-05-13", endDate: "2025-06-11"),
            categorySuggestions: [],
            accountSnapshot: LocalAIAccountSnapshot(accountCount: 1, accountIds: [], cashTotal: 0, debtTotal: 0, creditUtilization: nil),
            current: makeMetrics(transactionCount: currentCount),
            prior: prior,
            recurringSnapshot: LocalAIRecurringSnapshot(estimatedMonthlyTotal: 0, items: []),
            evidence: []
        )
        return LocalAIActivitySummary(
            window: window,
            availability: LocalAIAvailability(state: .disabled, detail: "test"),
            input: input,
            generatedSummary: "",
            generatedBullets: [],
            evidence: []
        )
    }
}
