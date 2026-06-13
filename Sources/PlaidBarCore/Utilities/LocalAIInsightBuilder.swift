import Foundation

public enum LocalAICategorizationResolver {
    public static let defaultHighConfidenceThreshold = 0.85

    public static func resolve(
        transaction: TransactionDTO,
        suggestion: LocalAICategorySuggestion?,
        highConfidenceThreshold: Double = defaultHighConfidenceThreshold
    ) -> LocalAICategoryResolution {
        if let suggestion,
           suggestion.transactionId == transaction.id,
           suggestion.status != .rejected,
           suggestion.status == .accepted || suggestion.confidence >= highConfidenceThreshold
        {
            return LocalAICategoryResolution(
                transactionId: transaction.id,
                effectiveCategory: suggestion.suggestedCategory,
                plaidCategory: transaction.category,
                suggestion: suggestion,
                source: .localAISuggestion
            )
        }

        if let category = transaction.category {
            return LocalAICategoryResolution(
                transactionId: transaction.id,
                effectiveCategory: category,
                plaidCategory: transaction.category,
                suggestion: suggestion,
                source: .plaidCategory
            )
        }

        return LocalAICategoryResolution(
            transactionId: transaction.id,
            effectiveCategory: .other,
            plaidCategory: nil,
            suggestion: suggestion,
            source: .fallbackOther
        )
    }
}

public enum LocalAICategorySuggestionGenerator {
    public static let generatedBy = "local-ai/deterministic"

    public static func suggestions(from transactions: [TransactionDTO]) -> [LocalAICategorySuggestion] {
        transactions.compactMap(suggestion)
            .sorted { lhs, rhs in
                if lhs.transactionId != rhs.transactionId { return lhs.transactionId < rhs.transactionId }
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.suggestedCategory.rawValue < rhs.suggestedCategory.rawValue
            }
    }

    private static func suggestion(for transaction: TransactionDTO) -> LocalAICategorySuggestion? {
        guard let match = categoryMatch(for: transaction) else { return nil }
        guard transaction.category != match.category else { return nil }

        var evidence = [
            LocalAIInsightEvidence(
                kind: .localHeuristic,
                sourceId: transaction.id,
                label: match.reason,
                transactionIds: [transaction.id],
                accountIds: [transaction.accountId],
                amount: transaction.displayAmount,
                date: transaction.date
            ),
        ]

        if let plaidCategory = transaction.category {
            evidence.append(
                LocalAIInsightEvidence(
                    kind: .plaidCategory,
                    sourceId: transaction.id,
                    label: "Plaid category: \(plaidCategory.displayName)",
                    transactionIds: [transaction.id],
                    accountIds: [transaction.accountId]
                )
            )
        }

        return LocalAICategorySuggestion(
            transactionId: transaction.id,
            suggestedCategory: match.category,
            confidence: match.confidence,
            status: .proposed,
            evidence: evidence,
            generatedBy: generatedBy
        )
    }

    private static func categoryMatch(for transaction: TransactionDTO)
        -> (category: SpendingCategory, confidence: Double, reason: String)?
    {
        let text = normalizedSearchText(for: transaction)

        if transaction.amount < 0, containsAny(text, ["payroll", "salary", "paycheck", "direct deposit", "stripe payout"]) {
            return (.income, 0.95, "Income keyword matched local transaction text")
        }

        if containsAny(text, ["refund", "reversal", "cashback", "cash back", "credit adjustment"]) {
            return (.income, 0.88, "Refund or credit keyword matched local transaction text")
        }

        if containsAny(text, ["transfer", "zelle", "venmo", "cash app", "paypal transfer"]) {
            let category: SpendingCategory = transaction.amount < 0 ? .transfer : .transferOut
            return (category, 0.88, "Transfer keyword matched local transaction text")
        }

        let expenseRules: [(SpendingCategory, Double, [String])] = [
            (.foodAndDrink, 0.91, ["coffee", "cafe", "restaurant", "grocery", "supermarket", "whole foods", "trader joe", "doordash", "uber eats", "chipotle", "pizza"]),
            (.transportation, 0.90, ["uber", "lyft", "taxi", "transit", "parking", "shell", "chevron", "exxon", "gas station", "metro"]),
            (.shopping, 0.90, ["amazon", "target", "walmart", "costco", "best buy", "ebay", "store", "shop"]),
            (.entertainment, 0.89, ["netflix", "spotify", "hulu", "disney", "amc", "cinema", "movie", "steam"]),
            (.personalCare, 0.88, ["salon", "barber", "spa"]),
            (.healthAndFitness, 0.89, ["pharmacy", "cvs", "walgreens", "doctor", "dentist", "gym", "medical"]),
            (.billsAndUtilities, 0.90, ["rent", "utility", "electric", "power", "water", "internet", "comcast", "xfinity", "verizon", "at&t", "t-mobile"]),
            (.homeImprovement, 0.88, ["home depot", "lowe", "ikea", "hardware"]),
            (.travel, 0.90, ["airline", "hotel", "airbnb", "delta", "united", "southwest", "marriott", "hilton"]),
            (.education, 0.88, ["tuition", "school", "university", "bookstore"]),
            (.subscriptions, 0.88, ["subscription", "recurring", "apple.com/bill", "google storage", "adobe", "patreon"]),
            (.bankFees, 0.91, ["atm fee", "overdraft", "bank fee", "monthly fee"]),
            (.government, 0.88, ["irs", "tax", "dmv", "government"]),
        ]

        for rule in expenseRules where containsAny(text, rule.2) {
            return (rule.0, rule.1, "\(rule.0.displayName) keyword matched local transaction text")
        }

        if transaction.amount < 0 {
            return (.income, 0.86, "Incoming Plaid amount convention matched local transaction text")
        }

        return nil
    }

    private static func normalizedSearchText(for transaction: TransactionDTO) -> String {
        [transaction.merchantName, transaction.name]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

public enum LocalAIInsightInputBuilder {
    public static func buildInputs(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        categorySuggestions: [LocalAICategorySuggestion] = [],
        anchorDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [LocalAIActivitySummaryInput] {
        LocalAIInsightWindow.allCases.map { window in
            buildInput(
                window: window,
                accounts: accounts,
                transactions: transactions,
                recurringTransactions: recurringTransactions,
                categorySuggestions: categorySuggestions,
                anchorDate: anchorDate,
                calendar: calendar
            )
        }
    }

    public static func buildInput(
        window: LocalAIInsightWindow,
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        categorySuggestions: [LocalAICategorySuggestion] = [],
        anchorDate: Date = Date(),
        calendar: Calendar = .current
    ) -> LocalAIActivitySummaryInput {
        let ranges = dateRanges(for: window, anchorDate: anchorDate, calendar: calendar)
        let resolvedCategorySuggestions = resolvedCategorySuggestions(
            explicitSuggestions: categorySuggestions,
            transactions: transactions
        )
        let suggestionsByTransaction = preferredSuggestionsByTransaction(resolvedCategorySuggestions)
        let current = metrics(
            from: transactions,
            in: ranges.current,
            suggestionsByTransaction: suggestionsByTransaction
        )
        let prior = ranges.prior.map {
            metrics(
                from: transactions,
                in: $0,
                suggestionsByTransaction: suggestionsByTransaction
            )
        }
        let accountSnapshot = accountSnapshot(from: accounts)
        let recurringSnapshot = recurringSnapshot(from: recurringTransactions, asOf: anchorDate, calendar: calendar)

        var evidence: [LocalAIInsightEvidence] = [
            LocalAIInsightEvidence(
                kind: .account,
                label: "\(accountSnapshot.accountCount) account snapshot",
                accountIds: accountSnapshot.accountIds
            ),
            LocalAIInsightEvidence(
                kind: .localHeuristic,
                sourceId: window.rawValue,
                label: "\(window.displayName) local summary window"
            ),
        ]
        evidence.append(contentsOf: current.categoryTotals.flatMap(\.evidence))
        evidence.append(contentsOf: current.topExpenses.flatMap(\.evidence))
        evidence.append(contentsOf: current.topIncome.flatMap(\.evidence))
        evidence.append(contentsOf: resolvedCategorySuggestions.flatMap(\.evidence))

        return LocalAIActivitySummaryInput(
            window: window,
            currentRange: ranges.current,
            priorRange: ranges.prior,
            categorySuggestions: resolvedCategorySuggestions,
            accountSnapshot: accountSnapshot,
            current: current,
            prior: prior,
            recurringSnapshot: recurringSnapshot,
            evidence: evidence
        )
    }

    public static func dateRanges(
        for window: LocalAIInsightWindow,
        anchorDate: Date,
        calendar: Calendar = .current
    ) -> (current: LocalAIInsightDateRange, prior: LocalAIInsightDateRange?) {
        let end = calendar.startOfDay(for: anchorDate)

        switch window {
        case .last7days:
            return rollingRange(ending: end, days: 7, calendar: calendar)
        case .lastMonth:
            return rollingRange(ending: end, days: 30, calendar: calendar)
        case .yearOverYear:
            let currentStart = calendar.date(byAdding: .day, value: -364, to: end) ?? end
            let priorStart = calendar.date(byAdding: .year, value: -1, to: currentStart) ?? currentStart
            let priorEnd = calendar.date(byAdding: .year, value: -1, to: end) ?? end
            return (
                current: dateRange(start: currentStart, end: end),
                prior: dateRange(start: priorStart, end: priorEnd)
            )
        }
    }

    public static func accountSnapshot(from accounts: [AccountDTO]) -> LocalAIAccountSnapshot {
        LocalAIAccountSnapshot(
            accountCount: accounts.count,
            accountIds: accounts.map(\.id).sorted(),
            cashTotal: MenuBarSummary.totalCash(from: accounts),
            debtTotal: MenuBarSummary.totalDebt(from: accounts),
            creditUtilization: MenuBarSummary.creditUtilization(from: accounts)
        )
    }

    public static func recurringSnapshot(
        from recurringTransactions: [RecurringTransaction],
        asOf date: Date? = nil,
        calendar: Calendar = .current
    )
        -> LocalAIRecurringSnapshot
    {
        let items = recurringTransactions.map { recurring in
            LocalAIRecurringInsightItem(
                id: recurring.id,
                merchantName: recurring.merchantName,
                frequency: recurring.frequency,
                estimatedMonthlyAmount: recurring.averageAmount * recurring.frequency.monthlyMultiplier,
                category: recurring.category,
                transactionCount: recurring.transactionCount,
                confidence: recurring.confidence,
                evidence: [
                    LocalAIInsightEvidence(
                        kind: .recurringTransaction,
                        sourceId: recurring.id,
                        label: "\(recurring.merchantName) \(recurring.frequency.displayName)",
                        amount: recurring.averageAmount,
                        date: recurring.lastDate
                    ),
                ]
            )
        }
        .sorted { $0.estimatedMonthlyAmount > $1.estimatedMonthlyAmount }

        return LocalAIRecurringSnapshot(
            estimatedMonthlyTotal: RecurringSummary.estimatedMonthlyTotal(
                from: recurringTransactions,
                asOf: date,
                calendar: calendar
            ),
            items: items
        )
    }

    private static func rollingRange(
        ending end: Date,
        days: Int,
        calendar: Calendar
    ) -> (current: LocalAIInsightDateRange, prior: LocalAIInsightDateRange?) {
        let currentStart = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let priorEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
        let priorStart = calendar.date(byAdding: .day, value: -(days - 1), to: priorEnd) ?? priorEnd
        return (
            current: dateRange(start: currentStart, end: end),
            prior: dateRange(start: priorStart, end: priorEnd)
        )
    }

    private static func dateRange(start: Date, end: Date) -> LocalAIInsightDateRange {
        LocalAIInsightDateRange(
            startDate: Formatters.transactionDateString(start),
            endDate: Formatters.transactionDateString(end)
        )
    }

    private static func metrics(
        from transactions: [TransactionDTO],
        in range: LocalAIInsightDateRange,
        suggestionsByTransaction: [String: LocalAICategorySuggestion]
    ) -> LocalAIActivityMetrics {
        let transactionsInRange = transactions
            .filter { range.contains($0.date) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.displayAmount > rhs.displayAmount
            }
        let classifiedTransactions = transactionsInRange.map { transaction in
            (
                transaction: transaction,
                resolution: LocalAICategorizationResolver.resolve(
                    transaction: transaction,
                    suggestion: suggestionsByTransaction[transaction.id]
                )
            )
        }
        let income = classifiedTransactions
            .filter { classification in
                Self.isIncome(
                    transaction: classification.transaction,
                    resolution: classification.resolution
                )
            }
            .map(\.transaction)
        let expenses = classifiedTransactions
            .filter { classification in
                !classification.resolution.effectiveCategory.isTransfer
                    && !Self.isIncome(
                        transaction: classification.transaction,
                        resolution: classification.resolution
                    )
            }
            .map(\.transaction)
        let transfers = classifiedTransactions
            .filter { $0.resolution.effectiveCategory.isTransfer }
            .map(\.transaction)

        let categoryTotals = categoryTotals(
            from: expenses,
            suggestionsByTransaction: suggestionsByTransaction
        )
        let topExpenses = topItems(
            from: expenses,
            suggestionsByTransaction: suggestionsByTransaction
        )
        let topIncome = topItems(
            from: income,
            suggestionsByTransaction: suggestionsByTransaction
        )
        let incomeTotal = income.reduce(0) { $0 + $1.displayAmount }
        let expenseTotal = expenses.reduce(0) { $0 + $1.displayAmount }

        return LocalAIActivityMetrics(
            transactionCount: transactionsInRange.count,
            incomeTotal: incomeTotal,
            expenseTotal: expenseTotal,
            netCashflow: incomeTotal - expenseTotal,
            incomeTransactionIds: income.map(\.id),
            expenseTransactionIds: expenses.map(\.id),
            transferTransactionIds: transfers.map(\.id),
            categoryTotals: categoryTotals,
            topExpenses: topExpenses,
            topIncome: topIncome
        )
    }

    private static func isIncome(
        transaction: TransactionDTO,
        resolution: LocalAICategoryResolution
    ) -> Bool {
        if resolution.effectiveCategory.isTransfer { return false }
        if resolution.effectiveCategory == .income { return true }
        if resolution.source == .localAISuggestion { return false }
        return transaction.isIncome
    }

    private static func categoryTotals(
        from transactions: [TransactionDTO],
        suggestionsByTransaction: [String: LocalAICategorySuggestion]
    ) -> [LocalAICategoryTotal] {
        let grouped = Dictionary(grouping: transactions) { transaction in
            LocalAICategorizationResolver.resolve(
                transaction: transaction,
                suggestion: suggestionsByTransaction[transaction.id]
            ).effectiveCategory
        }

        return grouped.map { category, transactions in
            let sortedTransactions = transactions.sorted { lhs, rhs in
                if lhs.displayAmount != rhs.displayAmount { return lhs.displayAmount > rhs.displayAmount }
                return lhs.date > rhs.date
            }
            let transactionIds = sortedTransactions.map(\.id)
            return LocalAICategoryTotal(
                category: category,
                totalAmount: sortedTransactions.reduce(0) { $0 + $1.displayAmount },
                transactionCount: sortedTransactions.count,
                transactionIds: transactionIds,
                evidence: [
                    LocalAIInsightEvidence(
                        kind: .categoryTotal,
                        sourceId: category.rawValue,
                        label: category.displayName,
                        transactionIds: transactionIds,
                        amount: sortedTransactions.reduce(0) { $0 + $1.displayAmount }
                    ),
                ]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalAmount != rhs.totalAmount { return lhs.totalAmount > rhs.totalAmount }
            return lhs.category.displayName < rhs.category.displayName
        }
    }

    private static func topItems(
        from transactions: [TransactionDTO],
        suggestionsByTransaction: [String: LocalAICategorySuggestion],
        limit: Int = 5
    ) -> [LocalAITransactionInsightItem] {
        transactions
            .sorted { lhs, rhs in
                if lhs.displayAmount != rhs.displayAmount { return lhs.displayAmount > rhs.displayAmount }
                return lhs.date > rhs.date
            }
            .prefix(limit)
            .map { transaction in
                let resolution = LocalAICategorizationResolver.resolve(
                    transaction: transaction,
                    suggestion: suggestionsByTransaction[transaction.id]
                )
                return LocalAITransactionInsightItem(
                    transactionId: transaction.id,
                    accountId: transaction.accountId,
                    date: transaction.date,
                    displayName: transaction.displayName,
                    amount: transaction.displayAmount,
                    effectiveCategory: resolution.effectiveCategory,
                    plaidCategory: transaction.category,
                    categorySource: resolution.source,
                    pending: transaction.pending,
                    evidence: [
                        LocalAIInsightEvidence(
                            kind: .transaction,
                            sourceId: transaction.id,
                            label: transaction.displayName,
                            transactionIds: [transaction.id],
                            accountIds: [transaction.accountId],
                            amount: transaction.displayAmount,
                            date: transaction.date
                        ),
                    ]
                )
            }
    }

    private static func preferredSuggestionsByTransaction(
        _ suggestions: [LocalAICategorySuggestion]
    ) -> [String: LocalAICategorySuggestion] {
        suggestions.reduce(into: [:]) { preferred, suggestion in
            guard let existing = preferred[suggestion.transactionId] else {
                preferred[suggestion.transactionId] = suggestion
                return
            }

            if suggestion.isPreferred(over: existing) {
                preferred[suggestion.transactionId] = suggestion
            }
        }
    }

    private static func resolvedCategorySuggestions(
        explicitSuggestions: [LocalAICategorySuggestion],
        transactions: [TransactionDTO]
    ) -> [LocalAICategorySuggestion] {
        let generated = LocalAICategorySuggestionGenerator.suggestions(from: transactions)
        return Array(preferredSuggestionsByTransaction(explicitSuggestions + generated).values)
            .sorted { lhs, rhs in
                if lhs.transactionId != rhs.transactionId { return lhs.transactionId < rhs.transactionId }
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.suggestedCategory.rawValue < rhs.suggestedCategory.rawValue
            }
    }
}

private extension LocalAIInsightDateRange {
    func contains(_ transactionDate: String) -> Bool {
        transactionDate >= startDate && transactionDate <= endDate
    }
}

private extension LocalAICategorySuggestion {
    func isPreferred(over other: LocalAICategorySuggestion) -> Bool {
        let statusRank: [LocalAICategorySuggestionStatus: Int] = [
            .accepted: 3,
            .proposed: 2,
            .rejected: 1,
        ]
        let rank = statusRank[status] ?? 0
        let otherRank = statusRank[other.status] ?? 0
        if rank != otherRank { return rank > otherRank }
        if confidence != other.confidence { return confidence > other.confidence }
        return suggestedCategory.rawValue < other.suggestedCategory.rawValue
    }
}

private extension SpendingCategory {
    var isTransfer: Bool {
        self == .transfer || self == .transferOut
    }
}
