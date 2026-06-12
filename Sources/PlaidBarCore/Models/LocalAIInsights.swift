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
    public let categorySuggestions: [LocalAICategorySuggestion]
    public let accountSnapshot: LocalAIAccountSnapshot
    public let current: LocalAIActivityMetrics
    public let prior: LocalAIActivityMetrics?
    public let recurringSnapshot: LocalAIRecurringSnapshot
    public let evidence: [LocalAIInsightEvidence]

    public init(
        window: LocalAIInsightWindow,
        currentRange: LocalAIInsightDateRange,
        priorRange: LocalAIInsightDateRange?,
        categorySuggestions: [LocalAICategorySuggestion] = [],
        accountSnapshot: LocalAIAccountSnapshot,
        current: LocalAIActivityMetrics,
        prior: LocalAIActivityMetrics?,
        recurringSnapshot: LocalAIRecurringSnapshot,
        evidence: [LocalAIInsightEvidence]
    ) {
        self.window = window
        self.currentRange = currentRange
        self.priorRange = priorRange
        self.categorySuggestions = categorySuggestions
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

/// Display-safe receipt for optional local insight output.
///
/// The receipt is intentionally narrower than the source summary input: it keeps
/// only user-facing counts, category names, date-window copy, local-only status,
/// confidence/limitation copy, and reversible action language. It must not carry
/// raw account IDs, transaction IDs, item IDs, tokens, or Plaid payload text.
public struct LocalAIInsightReceipt: Equatable, Sendable {
    public struct EvidenceChip: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        public let systemImage: String

        public init(id: String, label: String, value: String, systemImage: String) {
            self.id = id
            self.label = label
            self.value = value
            self.systemImage = systemImage
        }
    }

    public let title: String
    public let headline: String
    public let evidenceChips: [EvidenceChip]
    public let timeWindow: String
    public let localOnlyBadge: String
    public let confidence: String
    public let limitations: [String]
    public let unavailableState: String?
    public let reversibleActionCopy: String
    public let accessibilitySummary: String

    public init(
        title: String,
        headline: String,
        evidenceChips: [EvidenceChip],
        timeWindow: String,
        localOnlyBadge: String,
        confidence: String,
        limitations: [String],
        unavailableState: String?,
        reversibleActionCopy: String,
        accessibilitySummary: String
    ) {
        self.title = title
        self.headline = headline
        self.evidenceChips = evidenceChips
        self.timeWindow = timeWindow
        self.localOnlyBadge = localOnlyBadge
        self.confidence = confidence
        self.limitations = limitations
        self.unavailableState = unavailableState
        self.reversibleActionCopy = reversibleActionCopy
        self.accessibilitySummary = accessibilitySummary
    }

    public static func make(
        summary: LocalAIActivitySummary?,
        availability: LocalAIAvailability
    ) -> LocalAIInsightReceipt {
        guard let summary else {
            return unavailable(availability: availability)
        }

        let input = summary.input
        var chips: [EvidenceChip] = [
            EvidenceChip(
                id: "transactions",
                label: "Source rows",
                value: "\(input.current.transactionCount)",
                systemImage: "list.bullet.rectangle"
            ),
            EvidenceChip(
                id: "window",
                label: "Window",
                value: timeWindow(for: input),
                systemImage: "calendar"
            ),
        ]

        if let topCategory = input.current.categoryTotals.first {
            chips.append(EvidenceChip(
                id: "top-category",
                label: "Top category",
                value: topCategory.category.displayName,
                systemImage: topCategory.category.iconName
            ))
        }

        if input.recurringSnapshot.estimatedMonthlyTotal > 0 {
            chips.append(EvidenceChip(
                id: "recurring",
                label: "Recurring est.",
                value: Formatters.currency(input.recurringSnapshot.estimatedMonthlyTotal, format: .compact),
                systemImage: "arrow.triangle.2.circlepath"
            ))
        }

        if !input.categorySuggestions.isEmpty {
            chips.append(EvidenceChip(
                id: "category-hints",
                label: "Category hints",
                value: "\(input.categorySuggestions.count)",
                systemImage: "tag"
            ))
        }

        let limitations = limitations(for: input, availability: availability)
        let unavailableState = unavailableState(for: availability)
        let rawHeadline = summary.generatedSummary.isEmpty
            ? fallbackHeadline(for: input)
            : summary.generatedSummary
        let headline = redactKnownSourceIdentifiers(in: rawHeadline, input: input)
        let confidence = confidenceText(for: input, availability: availability)
        let reversibleActionCopy = reversibleActionCopy(for: input)
        let timeWindow = timeWindow(for: input)
        let accessibility = [
            "Local insight receipt.",
            headline,
            "Window \(timeWindow).",
            "\(availability.state.displayName).",
            confidence,
            limitations.joined(separator: " "),
            reversibleActionCopy,
        ].filter { !$0.isEmpty }.joined(separator: " ")

        return LocalAIInsightReceipt(
            title: "Local Insight Receipt",
            headline: headline,
            evidenceChips: Array(chips.prefix(5)),
            timeWindow: timeWindow,
            localOnlyBadge: "Local-only",
            confidence: confidence,
            limitations: limitations,
            unavailableState: unavailableState,
            reversibleActionCopy: reversibleActionCopy,
            accessibilitySummary: accessibility
        )
    }

    private static func unavailable(availability: LocalAIAvailability) -> LocalAIInsightReceipt {
        let unavailableState = unavailableState(for: availability) ?? "Local insight receipt is unavailable until local transaction history exists."
        return LocalAIInsightReceipt(
            title: "Local Insight Receipt",
            headline: "Local insight receipt unavailable",
            evidenceChips: [
                EvidenceChip(id: "runtime", label: "Runtime", value: availability.state.displayName, systemImage: "cpu"),
                EvidenceChip(id: "window", label: "Window", value: "No data", systemImage: "calendar.badge.exclamationmark"),
            ],
            timeWindow: "No local history window",
            localOnlyBadge: "Local-only",
            confidence: "Confidence unavailable until local source rows exist.",
            limitations: [availability.detail, "VaultPeek will not call a cloud AI service to fill this state."],
            unavailableState: unavailableState,
            reversibleActionCopy: "No insight action is available yet. Connect data locally or keep using the dashboard without AI.",
            accessibilitySummary: "Local insight receipt unavailable. \(availability.state.displayName). \(availability.detail)"
        )
    }

    private static func confidenceText(
        for input: LocalAIActivitySummaryInput,
        availability: LocalAIAvailability
    ) -> String {
        if availability.state != .available {
            return "Deterministic confidence: local summary only; no model runtime contributed."
        }

        if input.current.transactionCount >= 10 {
            return "Confidence: higher, based on \(input.current.transactionCount) local source rows."
        }

        if input.current.transactionCount > 0 {
            return "Confidence: limited, based on \(input.current.transactionCount) local source row\(input.current.transactionCount == 1 ? "" : "s")."
        }

        return "Confidence: limited until transaction history is available."
    }

    private static func limitations(
        for input: LocalAIActivitySummaryInput,
        availability: LocalAIAvailability
    ) -> [String] {
        var result: [String] = []

        if availability.state == .disabled {
            result.append("Local AI is off; this receipt uses deterministic local totals and heuristics.")
        } else if availability.state == .unavailable {
            result.append("The configured local runtime is unavailable; VaultPeek does not fall back to cloud AI.")
        }

        if input.current.transactionCount == 0 {
            result.append("No transaction rows are available in this window.")
        }

        if input.prior == nil {
            result.append("No comparison window is available for trend language.")
        }

        result.append("Evidence is summarized as display-safe counts, categories, and amounts; raw IDs and Plaid payloads are excluded.")
        return result
    }

    private static func unavailableState(for availability: LocalAIAvailability) -> String? {
        switch availability.state {
        case .available:
            nil
        case .disabled:
            "No local AI runtime is enabled. Deterministic local receipts remain available when source data exists."
        case .unavailable:
            "Configured local runtime is unavailable. Cloud AI fallback is not supported."
        }
    }

    private static func reversibleActionCopy(for input: LocalAIActivitySummaryInput) -> String {
        guard !input.categorySuggestions.isEmpty else {
            return "This receipt changes nothing. Review the source dashboard rows before taking action."
        }

        return "Category hints are local overlays. Accepting or rejecting a hint is reversible and does not mutate raw Plaid records."
    }

    private static func fallbackHeadline(for input: LocalAIActivitySummaryInput) -> String {
        "\(input.window.displayName): \(input.current.transactionCount) local source rows reviewed."
    }

    private static func timeWindow(for input: LocalAIActivitySummaryInput) -> String {
        "\(input.currentRange.startDate) to \(input.currentRange.endDate)"
    }

    private static func redactKnownSourceIdentifiers(
        in text: String,
        input: LocalAIActivitySummaryInput
    ) -> String {
        let identifiers = knownSourceIdentifiers(input: input).sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0 < $1
        }
        return identifiers.reduce(text) { result, identifier in
            result.replacingOccurrences(of: identifier, with: "[redacted]")
        }
    }

    private static func knownSourceIdentifiers(input: LocalAIActivitySummaryInput) -> Set<String> {
        var identifiers = Set(input.accountSnapshot.accountIds)
        identifiers.formUnion(input.current.incomeTransactionIds)
        identifiers.formUnion(input.current.expenseTransactionIds)
        identifiers.formUnion(input.current.transferTransactionIds)
        identifiers.formUnion(input.prior?.incomeTransactionIds ?? [])
        identifiers.formUnion(input.prior?.expenseTransactionIds ?? [])
        identifiers.formUnion(input.prior?.transferTransactionIds ?? [])
        identifiers.formUnion(input.current.topExpenses.map(\.transactionId))
        identifiers.formUnion(input.current.topExpenses.map(\.accountId))
        identifiers.formUnion(input.current.topIncome.map(\.transactionId))
        identifiers.formUnion(input.current.topIncome.map(\.accountId))
        identifiers.formUnion(input.current.categoryTotals.flatMap(\.transactionIds))
        identifiers.formUnion(input.recurringSnapshot.items.map(\.id))
        identifiers.formUnion(input.recurringSnapshot.items.flatMap(\.evidence).flatMap(\.transactionIds))
        identifiers.formUnion(input.recurringSnapshot.items.flatMap(\.evidence).flatMap(\.accountIds))
        identifiers.formUnion(input.recurringSnapshot.items.flatMap(\.evidence).compactMap(\.sourceId))
        identifiers.formUnion(input.categorySuggestions.map(\.transactionId))
        identifiers.formUnion(input.categorySuggestions.flatMap(\.evidence).flatMap(\.transactionIds))
        identifiers.formUnion(input.categorySuggestions.flatMap(\.evidence).flatMap(\.accountIds))
        identifiers.formUnion(input.categorySuggestions.flatMap(\.evidence).compactMap(\.sourceId))
        identifiers.formUnion(input.evidence.flatMap(\.transactionIds))
        identifiers.formUnion(input.evidence.flatMap(\.accountIds))
        identifiers.formUnion(input.evidence.compactMap(\.sourceId))
        return identifiers.filter { !$0.isEmpty }
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
