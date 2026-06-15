import Foundation

public enum WeeklyReviewCadence: String, Codable, Sendable, CaseIterable, Hashable {
    case weekly

    public var days: Int {
        switch self {
        case .weekly: 7
        }
    }
}

public struct WeeklyReviewState: Codable, Sendable, Equatable {
    public var lastCompletedAt: Date?
    public var cadence: WeeklyReviewCadence
    public var completedItemIds: Set<String>
    public var dismissedItemIds: Set<String>

    public init(
        lastCompletedAt: Date? = nil,
        cadence: WeeklyReviewCadence = .weekly,
        completedItemIds: Set<String> = [],
        dismissedItemIds: Set<String> = []
    ) {
        self.lastCompletedAt = lastCompletedAt
        self.cadence = cadence
        self.completedItemIds = completedItemIds
        self.dismissedItemIds = dismissedItemIds
    }

    public func nextReviewDueAt(calendar: Calendar = .current) -> Date? {
        guard let lastCompletedAt else { return nil }
        return calendar.date(byAdding: .day, value: cadence.days, to: lastCompletedAt)
    }

    public func isDue(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let dueAt = nextReviewDueAt(calendar: calendar) else { return true }
        return date >= dueAt
    }

    public static let empty = WeeklyReviewState()
}

public struct WeeklyReviewTransactionState: Sendable, Equatable {
    public let trustedTransactionIds: Set<String>
    public let unreviewedTransactionIds: Set<String>

    public init(
        trustedTransactionIds: Set<String>,
        unreviewedTransactionIds: Set<String>
    ) {
        self.trustedTransactionIds = trustedTransactionIds
        self.unreviewedTransactionIds = unreviewedTransactionIds
    }
}

public enum WeeklyReviewOutcome: String, Sendable, Equatable {
    case looksGood
    case reviewItems
    case payAttention
    case waitingForTransactionReview

    public var title: String {
        switch self {
        case .looksGood: "Looks good"
        case .reviewItems: "Review these few items"
        case .payAttention: "Pay attention"
        case .waitingForTransactionReview: "Transaction review required"
        }
    }
}

public enum WeeklyReviewItemKind: String, Sendable, Hashable, CaseIterable {
    case transactionReview
    case categoryDrift
    case upcomingBills
    case safeToSpendChange
    case subscriptionChange
    case connectionHealth
}

/// In-popover surface a weekly-review action should navigate to. The popover
/// observes this so review-checklist buttons open a real destination instead of
/// silently doing nothing.
public enum WeeklyReviewNavigationTarget: String, Sendable, Hashable {
    case reviewInbox
    case recurring
    case safeToSpend
}

public enum WeeklyReviewAction: String, Sendable, Hashable {
    case openReviewInbox
    case inspectCategory
    case reviewRecurring
    case inspectSafeToSpend
    case reconnectAccount
    case refreshData

    public var title: String {
        switch self {
        case .openReviewInbox: "Open Review Inbox"
        case .inspectCategory: "Inspect Category"
        case .reviewRecurring: "Review Recurring"
        case .inspectSafeToSpend: "Inspect Breakdown"
        case .reconnectAccount: "Reconnect"
        case .refreshData: "Refresh"
        }
    }

    public var iconName: String {
        switch self {
        case .openReviewInbox: "checklist"
        case .inspectCategory: "tag"
        case .reviewRecurring: "calendar.badge.clock"
        case .inspectSafeToSpend: "banknote"
        case .reconnectAccount: "link.badge.plus"
        case .refreshData: "arrow.clockwise"
        }
    }
}

public struct WeeklyReviewItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: WeeklyReviewItemKind
    public let severity: AttentionQueueSeverity
    public let title: String
    public let detail: String
    public let action: WeeklyReviewAction
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        id: String,
        kind: WeeklyReviewItemKind,
        severity: AttentionQueueSeverity,
        title: String,
        detail: String,
        action: WeeklyReviewAction,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.action = action
        self.accessibilityLabel = accessibilityLabel ?? "\(severity.statusLabel). \(title). \(detail)"
        self.accessibilityHint = accessibilityHint ?? action.title
    }
}

public struct WeeklyReviewPresentation: Sendable, Equatable {
    public let outcome: WeeklyReviewOutcome
    public let isDue: Bool
    public let nextReviewDueAt: Date?
    public let completedCount: Int
    public let totalCount: Int
    public let reviewedTransactionCount: Int
    public let items: [WeeklyReviewItem]
    public let isBlockedByTransactionReviewDependency: Bool

    public init(
        outcome: WeeklyReviewOutcome,
        isDue: Bool,
        nextReviewDueAt: Date?,
        completedCount: Int,
        totalCount: Int,
        reviewedTransactionCount: Int,
        items: [WeeklyReviewItem],
        isBlockedByTransactionReviewDependency: Bool
    ) {
        self.outcome = outcome
        self.isDue = isDue
        self.nextReviewDueAt = nextReviewDueAt
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.reviewedTransactionCount = reviewedTransactionCount
        self.items = items
        self.isBlockedByTransactionReviewDependency = isBlockedByTransactionReviewDependency
    }

    public var remainingCount: Int {
        max(totalCount - completedCount, 0)
    }

    public var menuBarPrompt: String? {
        if isBlockedByTransactionReviewDependency { return nil }
        guard isDue else { return nil }
        return remainingCount > 0 ? "\(remainingCount) items to review" : "Weekly review due"
    }

    public var notificationTitle: String {
        "Weekly review due"
    }

    public var notificationBody: String {
        if remainingCount > 0 {
            return "VaultPeek found \(remainingCount) private item\(remainingCount == 1 ? "" : "s") to review."
        }
        return "Open VaultPeek to complete your private weekly review."
    }

    public static let waitingForTransactionReview = WeeklyReviewPresentation(
        outcome: .waitingForTransactionReview,
        isDue: false,
        nextReviewDueAt: nil,
        completedCount: 0,
        totalCount: 0,
        reviewedTransactionCount: 0,
        items: [],
        isBlockedByTransactionReviewDependency: true
    )
}

public enum WeeklyReviewBuilder {
    public static let safeToSpendWarningAmount: Double = 0
    public static let safeToSpendDropThreshold: Double = 100

    public static func evaluate(
        state: WeeklyReviewState,
        transactionState: WeeklyReviewTransactionState?,
        transactions: [TransactionDTO],
        recurringTransactions: [RecurringTransaction],
        safeToSpend: SafeToSpendResult,
        previousSafeToSpendAmount: Double? = nil,
        categoryBudgets: CategoryBudgetPresentation = .empty,
        itemStatuses: [ItemStatus] = [],
        isSyncStale: Bool = false,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReviewPresentation {
        guard let transactionState else {
            return .waitingForTransactionReview
        }

        let isDue = state.isDue(asOf: date, calendar: calendar)
        let nextDue = state.nextReviewDueAt(calendar: calendar)
        let reviewedCount = reviewedTransactionCount(
            transactions: transactions,
            trustedIds: transactionState.trustedTransactionIds,
            since: state.lastCompletedAt,
            asOf: date,
            calendar: calendar
        )
        let items = reviewItems(
            transactionState: transactionState,
            recurringTransactions: recurringTransactions,
            safeToSpend: safeToSpend,
            previousSafeToSpendAmount: previousSafeToSpendAmount,
            categoryBudgets: categoryBudgets,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale,
            asOf: date,
            calendar: calendar
        )
        // Item ids are fixed by kind, so completions/dismissals from a prior
        // weekly cycle must not carry into a new one — otherwise a fresh pending
        // transaction or upcoming bill a week later would render as already
        // reviewed ("Nothing needs review"). Once a new cycle is due after the
        // last completion, ignore the previous cycle's resolved ids.
        let isNewCycle = state.lastCompletedAt != nil && isDue
        let completedItemIds = isNewCycle ? Set<String>() : state.completedItemIds
        let dismissedItemIds = isNewCycle ? Set<String>() : state.dismissedItemIds

        let activeItems = items.filter { !dismissedItemIds.contains($0.id) }
        let completedCount = activeItems.reduce(0) { total, item in
            total + (completedItemIds.contains(item.id) ? 1 : 0)
        }
        let unresolvedItems = activeItems.filter { !completedItemIds.contains($0.id) }
        let outcome = outcome(for: unresolvedItems)

        return WeeklyReviewPresentation(
            outcome: outcome,
            isDue: isDue,
            nextReviewDueAt: nextDue,
            completedCount: completedCount,
            totalCount: activeItems.count,
            reviewedTransactionCount: reviewedCount,
            items: activeItems,
            isBlockedByTransactionReviewDependency: false
        )
    }

    private static func reviewItems(
        transactionState: WeeklyReviewTransactionState,
        recurringTransactions: [RecurringTransaction],
        safeToSpend: SafeToSpendResult,
        previousSafeToSpendAmount: Double?,
        categoryBudgets: CategoryBudgetPresentation,
        itemStatuses: [ItemStatus],
        isSyncStale: Bool,
        asOf date: Date,
        calendar: Calendar
    ) -> [WeeklyReviewItem] {
        var items: [WeeklyReviewItem] = []

        if !transactionState.unreviewedTransactionIds.isEmpty {
            let count = transactionState.unreviewedTransactionIds.count
            items.append(WeeklyReviewItem(
                id: "weekly-review.transactions",
                kind: .transactionReview,
                severity: .warning,
                title: "\(count) transaction\(count == 1 ? "" : "s") need review",
                detail: "Approve or categorize the latest inbox items before closing the week.",
                action: .openReviewInbox,
                accessibilityHint: "Opens the transaction review inbox."
            ))
        }

        let budgetItems = categoryBudgets.items.filter(\.needsAttention)
        if !budgetItems.isEmpty {
            let overCount = categoryBudgets.overBudgetCount
            let title = overCount > 0
                ? "\(overCount) budget\(overCount == 1 ? "" : "s") over"
                : "\(categoryBudgets.nearingCount) budget\(categoryBudgets.nearingCount == 1 ? "" : "s") close"
            items.append(WeeklyReviewItem(
                id: "weekly-review.category-drift",
                kind: .categoryDrift,
                severity: overCount > 0 ? .blocked : .warning,
                title: title,
                detail: "Category pressure changed this month.",
                action: .inspectCategory,
                accessibilityHint: "Opens the category budget details."
            ))
        }

        let upcomingCount = upcomingRecurringCount(
            recurringTransactions,
            asOf: date,
            calendar: calendar
        )
        if upcomingCount > 0 {
            items.append(WeeklyReviewItem(
                id: "weekly-review.upcoming-bills",
                kind: .upcomingBills,
                severity: .warning,
                title: "\(upcomingCount) upcoming bill\(upcomingCount == 1 ? "" : "s")",
                detail: "Confirm known obligations before they hit.",
                action: .reviewRecurring,
                accessibilityHint: "Opens recurring obligations."
            ))
        }

        if let safeToSpendItem = safeToSpendReviewItem(
            safeToSpend: safeToSpend,
            previousAmount: previousSafeToSpendAmount
        ) {
            items.append(safeToSpendItem)
        }

        let changedRecurringCount = recurringTransactions.filter {
            !$0.flags(asOf: date, calendar: calendar).isEmpty
        }.count
        if changedRecurringCount > 0 {
            items.append(WeeklyReviewItem(
                id: "weekly-review.subscription-changes",
                kind: .subscriptionChange,
                severity: .warning,
                title: "\(changedRecurringCount) recurring charge\(changedRecurringCount == 1 ? "" : "s") changed",
                detail: "Review price increases or missing expected charges.",
                action: .reviewRecurring,
                accessibilityHint: "Opens recurring obligations."
            ))
        }

        // `.loginRepaired` is a healthy, non-degraded state; counting it via
        // `!= .connected` produced a false "needs a check" nag right after a
        // successful repair. Use the shared degraded predicate instead.
        let unhealthyItems = itemStatuses.filter { $0.status.isDegraded }.count
        if unhealthyItems > 0 || isSyncStale {
            // A login-required item needs the reconnect/update-link flow, not
            // another refresh — treat it as reconnectable alongside errors so
            // the checklist action can actually recover it.
            let needsReconnect = itemStatuses.contains { $0.status == .error || $0.status.needsUpdateMode }
            let blocked = itemStatuses.contains { $0.status == .error }
            items.append(WeeklyReviewItem(
                id: "weekly-review.connection-health",
                kind: .connectionHealth,
                severity: blocked ? .blocked : .warning,
                title: needsReconnect ? "Connection needs attention" : "Connection freshness changed",
                detail: unhealthyItems > 0
                    ? "\(unhealthyItems) linked item\(unhealthyItems == 1 ? "" : "s") need a check."
                    : "Refresh local data before trusting this review.",
                action: needsReconnect ? .reconnectAccount : .refreshData,
                accessibilityHint: needsReconnect ? "Reconnects the affected institution." : "Refreshes local data."
            ))
        }

        return items
    }

    private static func reviewedTransactionCount(
        transactions: [TransactionDTO],
        trustedIds: Set<String>,
        since lastCompletedAt: Date?,
        asOf date: Date,
        calendar: Calendar
    ) -> Int {
        // Before any review baseline exists, counting every trusted id as
        // "reviewed this week" would surface months of history as this week's
        // progress. Bound the first-run count to the current 7-day window.
        let sinceDay: String
        if let lastCompletedAt {
            sinceDay = Formatters.transactionDateString(calendar.startOfDay(for: lastCompletedAt))
        } else if let weekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: date)) {
            sinceDay = Formatters.transactionDateString(weekStart)
        } else {
            return 0
        }
        return transactions.reduce(0) { count, transaction in
            guard trustedIds.contains(transaction.id), transaction.date >= sinceDay else {
                return count
            }
            return count + 1
        }
    }

    private static func upcomingRecurringCount(
        _ recurringTransactions: [RecurringTransaction],
        asOf date: Date,
        calendar: Calendar
    ) -> Int {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return 0 }
        return recurringTransactions.reduce(0) { count, recurring in
            guard let nextDate = Formatters.parseTransactionDate(recurring.nextExpectedDate) else {
                return count
            }
            return (nextDate >= start && nextDate <= end) ? count + 1 : count
        }
    }

    private static func safeToSpendReviewItem(
        safeToSpend: SafeToSpendResult,
        previousAmount: Double?
    ) -> WeeklyReviewItem? {
        if safeToSpend.amount < safeToSpendWarningAmount {
            return WeeklyReviewItem(
                id: "weekly-review.safe-to-spend",
                kind: .safeToSpendChange,
                severity: .blocked,
                title: "Safe-to-spend is below zero",
                detail: "Committed obligations exceed available money for this period.",
                action: .inspectSafeToSpend,
                accessibilityHint: "Opens the safe-to-spend breakdown."
            )
        }

        if let previousAmount {
            let drop = previousAmount - safeToSpend.amount
            if drop >= safeToSpendDropThreshold {
                return WeeklyReviewItem(
                    id: "weekly-review.safe-to-spend",
                    kind: .safeToSpendChange,
                    severity: .warning,
                    title: "Safe-to-spend dropped",
                    detail: "Available money moved materially since the last review.",
                    action: .inspectSafeToSpend,
                    accessibilityHint: "Opens the safe-to-spend breakdown."
                )
            }
        }

        if safeToSpend.confidence < .ok {
            return WeeklyReviewItem(
                id: "weekly-review.safe-to-spend",
                kind: .safeToSpendChange,
                severity: .warning,
                title: "Safe-to-spend confidence is low",
                detail: "A review will be more useful after recurring income and obligations settle.",
                action: .inspectSafeToSpend,
                accessibilityHint: "Opens the safe-to-spend breakdown."
            )
        }

        return nil
    }

    private static func outcome(for unresolvedItems: [WeeklyReviewItem]) -> WeeklyReviewOutcome {
        guard !unresolvedItems.isEmpty else { return .looksGood }
        if unresolvedItems.contains(where: { $0.severity == .blocked }) {
            return .payAttention
        }
        return .reviewItems
    }
}
