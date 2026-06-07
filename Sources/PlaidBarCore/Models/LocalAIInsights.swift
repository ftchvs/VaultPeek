import Foundation

public enum LocalAIInsightWindow: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case last7days
    case lastMonth
    case yearOverYear

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .last7days: "Last 7D"
        case .lastMonth: "Last Month"
        case .yearOverYear: "YoY"
        }
    }
}

public struct LocalAIAvailability: Codable, Sendable, Hashable {
    public let state: LocalAIAvailabilityState
    public let runtimeName: String?
    public let detail: String
    public let supportsCloudModels: Bool

    public init(
        state: LocalAIAvailabilityState,
        runtimeName: String? = nil,
        detail: String,
        supportsCloudModels: Bool = false
    ) {
        self.state = state
        self.runtimeName = runtimeName
        self.detail = detail
        self.supportsCloudModels = supportsCloudModels
    }
}

public enum LocalAIAvailabilityState: String, Codable, Sendable, Hashable {
    case available
    case disabled
    case unavailable

    public var displayName: String {
        switch self {
        case .available: "Available"
        case .disabled: "Disabled"
        case .unavailable: "Unavailable"
        }
    }
}

public struct LocalAIInsightDateRange: Codable, Sendable, Hashable {
    public let startDate: String
    public let endDate: String

    public init(startDate: String, endDate: String) {
        self.startDate = startDate
        self.endDate = endDate
    }
}

public enum LocalAIEvidenceKind: String, Codable, Sendable, Hashable {
    case account
    case transaction
    case recurringTransaction
    case categoryTotal
    case localHeuristic
    case plaidCategory
}

public struct LocalAIInsightEvidence: Codable, Sendable, Hashable {
    public let kind: LocalAIEvidenceKind
    public let sourceId: String?
    public let label: String
    public let transactionIds: [String]
    public let accountIds: [String]
    public let amount: Double?
    public let date: String?

    public init(
        kind: LocalAIEvidenceKind,
        sourceId: String? = nil,
        label: String,
        transactionIds: [String] = [],
        accountIds: [String] = [],
        amount: Double? = nil,
        date: String? = nil
    ) {
        self.kind = kind
        self.sourceId = sourceId
        self.label = label
        self.transactionIds = transactionIds
        self.accountIds = accountIds
        self.amount = amount
        self.date = date
    }
}

public struct LocalAIActivitySummaryInput: Codable, Sendable, Hashable {
    public let window: LocalAIInsightWindow
    public let currentRange: LocalAIInsightDateRange
    public let priorRange: LocalAIInsightDateRange?
    public let accountSnapshot: LocalAIAccountSnapshot
    public let current: LocalAIActivityMetrics
    public let prior: LocalAIActivityMetrics?
    public let recurringSnapshot: LocalAIRecurringSnapshot
    public let evidence: [LocalAIInsightEvidence]

    public init(
        window: LocalAIInsightWindow,
        currentRange: LocalAIInsightDateRange,
        priorRange: LocalAIInsightDateRange?,
        accountSnapshot: LocalAIAccountSnapshot,
        current: LocalAIActivityMetrics,
        prior: LocalAIActivityMetrics?,
        recurringSnapshot: LocalAIRecurringSnapshot,
        evidence: [LocalAIInsightEvidence]
    ) {
        self.window = window
        self.currentRange = currentRange
        self.priorRange = priorRange
        self.accountSnapshot = accountSnapshot
        self.current = current
        self.prior = prior
        self.recurringSnapshot = recurringSnapshot
        self.evidence = evidence
    }
}

public struct LocalAIActivitySummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let window: LocalAIInsightWindow
    public let availability: LocalAIAvailability
    public let input: LocalAIActivitySummaryInput
    public let generatedSummary: String
    public let generatedBullets: [String]
    public let evidence: [LocalAIInsightEvidence]

    public init(
        window: LocalAIInsightWindow,
        availability: LocalAIAvailability,
        input: LocalAIActivitySummaryInput,
        generatedSummary: String,
        generatedBullets: [String],
        evidence: [LocalAIInsightEvidence]
    ) {
        id = window.rawValue
        self.window = window
        self.availability = availability
        self.input = input
        self.generatedSummary = generatedSummary
        self.generatedBullets = generatedBullets
        self.evidence = evidence
    }
}

public struct LocalAIAccountSnapshot: Codable, Sendable, Hashable {
    public let accountCount: Int
    public let accountIds: [String]
    public let cashTotal: Double
    public let debtTotal: Double
    public let creditUtilization: Double?

    public init(
        accountCount: Int,
        accountIds: [String],
        cashTotal: Double,
        debtTotal: Double,
        creditUtilization: Double?
    ) {
        self.accountCount = accountCount
        self.accountIds = accountIds
        self.cashTotal = cashTotal
        self.debtTotal = debtTotal
        self.creditUtilization = creditUtilization
    }
}

public struct LocalAIActivityMetrics: Codable, Sendable, Hashable {
    public let transactionCount: Int
    public let incomeTotal: Double
    public let expenseTotal: Double
    public let netCashflow: Double
    public let incomeTransactionIds: [String]
    public let expenseTransactionIds: [String]
    public let transferTransactionIds: [String]
    public let categoryTotals: [LocalAICategoryTotal]
    public let topExpenses: [LocalAITransactionInsightItem]
    public let topIncome: [LocalAITransactionInsightItem]

    public init(
        transactionCount: Int,
        incomeTotal: Double,
        expenseTotal: Double,
        netCashflow: Double,
        incomeTransactionIds: [String],
        expenseTransactionIds: [String],
        transferTransactionIds: [String],
        categoryTotals: [LocalAICategoryTotal],
        topExpenses: [LocalAITransactionInsightItem],
        topIncome: [LocalAITransactionInsightItem]
    ) {
        self.transactionCount = transactionCount
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.netCashflow = netCashflow
        self.incomeTransactionIds = incomeTransactionIds
        self.expenseTransactionIds = expenseTransactionIds
        self.transferTransactionIds = transferTransactionIds
        self.categoryTotals = categoryTotals
        self.topExpenses = topExpenses
        self.topIncome = topIncome
    }
}

public struct LocalAICategoryTotal: Codable, Sendable, Hashable, Identifiable {
    public let category: SpendingCategory
    public let totalAmount: Double
    public let transactionCount: Int
    public let transactionIds: [String]
    public let evidence: [LocalAIInsightEvidence]

    public var id: String {
        category.rawValue
    }

    public init(
        category: SpendingCategory,
        totalAmount: Double,
        transactionCount: Int,
        transactionIds: [String],
        evidence: [LocalAIInsightEvidence]
    ) {
        self.category = category
        self.totalAmount = totalAmount
        self.transactionCount = transactionCount
        self.transactionIds = transactionIds
        self.evidence = evidence
    }
}

public struct LocalAITransactionInsightItem: Codable, Sendable, Hashable, Identifiable {
    public let transactionId: String
    public let accountId: String
    public let date: String
    public let displayName: String
    public let amount: Double
    public let effectiveCategory: SpendingCategory
    public let plaidCategory: SpendingCategory?
    public let categorySource: LocalAICategoryResolutionSource
    public let pending: Bool
    public let evidence: [LocalAIInsightEvidence]

    public var id: String {
        transactionId
    }

    public init(
        transactionId: String,
        accountId: String,
        date: String,
        displayName: String,
        amount: Double,
        effectiveCategory: SpendingCategory,
        plaidCategory: SpendingCategory?,
        categorySource: LocalAICategoryResolutionSource,
        pending: Bool,
        evidence: [LocalAIInsightEvidence]
    ) {
        self.transactionId = transactionId
        self.accountId = accountId
        self.date = date
        self.displayName = displayName
        self.amount = amount
        self.effectiveCategory = effectiveCategory
        self.plaidCategory = plaidCategory
        self.categorySource = categorySource
        self.pending = pending
        self.evidence = evidence
    }
}

public struct LocalAIRecurringSnapshot: Codable, Sendable, Hashable {
    public let estimatedMonthlyTotal: Double
    public let items: [LocalAIRecurringInsightItem]

    public init(estimatedMonthlyTotal: Double, items: [LocalAIRecurringInsightItem]) {
        self.estimatedMonthlyTotal = estimatedMonthlyTotal
        self.items = items
    }
}

public struct LocalAIRecurringInsightItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let merchantName: String
    public let frequency: RecurringFrequency
    public let estimatedMonthlyAmount: Double
    public let category: SpendingCategory?
    public let transactionCount: Int
    public let confidence: Double
    public let evidence: [LocalAIInsightEvidence]

    public init(
        id: String,
        merchantName: String,
        frequency: RecurringFrequency,
        estimatedMonthlyAmount: Double,
        category: SpendingCategory?,
        transactionCount: Int,
        confidence: Double,
        evidence: [LocalAIInsightEvidence]
    ) {
        self.id = id
        self.merchantName = merchantName
        self.frequency = frequency
        self.estimatedMonthlyAmount = estimatedMonthlyAmount
        self.category = category
        self.transactionCount = transactionCount
        self.confidence = confidence
        self.evidence = evidence
    }
}

public enum LocalAICategorySuggestionStatus: String, Codable, Sendable, Hashable {
    case proposed
    case accepted
    case rejected
}

public struct LocalAICategorySuggestion: Codable, Sendable, Hashable, Identifiable {
    public let transactionId: String
    public let suggestedCategory: SpendingCategory
    public let confidence: Double
    public let status: LocalAICategorySuggestionStatus
    public let evidence: [LocalAIInsightEvidence]
    public let generatedBy: String

    public var id: String {
        "\(transactionId)-\(suggestedCategory.rawValue)"
    }

    public init(
        transactionId: String,
        suggestedCategory: SpendingCategory,
        confidence: Double,
        status: LocalAICategorySuggestionStatus = .proposed,
        evidence: [LocalAIInsightEvidence],
        generatedBy: String = "local-ai"
    ) {
        self.transactionId = transactionId
        self.suggestedCategory = suggestedCategory
        self.confidence = confidence
        self.status = status
        self.evidence = evidence
        self.generatedBy = generatedBy
    }
}

public struct LocalAICategoryResolution: Codable, Sendable, Hashable {
    public let transactionId: String
    public let effectiveCategory: SpendingCategory
    public let plaidCategory: SpendingCategory?
    public let suggestion: LocalAICategorySuggestion?
    public let source: LocalAICategoryResolutionSource

    public init(
        transactionId: String,
        effectiveCategory: SpendingCategory,
        plaidCategory: SpendingCategory?,
        suggestion: LocalAICategorySuggestion?,
        source: LocalAICategoryResolutionSource
    ) {
        self.transactionId = transactionId
        self.effectiveCategory = effectiveCategory
        self.plaidCategory = plaidCategory
        self.suggestion = suggestion
        self.source = source
    }
}

public enum LocalAICategoryResolutionSource: String, Codable, Sendable, Hashable {
    case localAISuggestion
    case plaidCategory
    case fallbackOther

    public var displayName: String {
        switch self {
        case .localAISuggestion: "Local AI"
        case .plaidCategory: "Plaid"
        case .fallbackOther: "Other"
        }
    }
}
