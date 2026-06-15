import Foundation

public struct TransactionDerivedIndex: Sendable {
    public struct Entry: Sendable, Hashable {
        public let transaction: TransactionDTO
        public let parsedDate: Date?
        public let isIncome: Bool
        public let isTransfer: Bool
        public let isExpense: Bool
        public let displayAmount: Double

        public var rawDate: String { transaction.date }
        public var accountId: String { transaction.accountId }
        public var itemId: String? { transaction.itemId }
        public var merchantName: String? { transaction.merchantName }
        public var category: SpendingCategory? { transaction.category }

        fileprivate init(transaction: TransactionDTO, parsedDate: Date?) {
            self.transaction = transaction
            self.parsedDate = parsedDate
            self.isIncome = transaction.isIncome
            self.isTransfer = transaction.category == .transfer || transaction.category == .transferOut
            self.isExpense = !transaction.isIncome && transaction.category != .transfer && transaction.category != .transferOut
            self.displayAmount = transaction.displayAmount
        }
    }

    public let entries: [Entry]
    public let accountBuckets: [String: [Entry]]
    public let itemBuckets: [String: [Entry]]
    public let merchantBuckets: [String: [Entry]]
    public let categoryTotals: [SpendingCategory: Double]
    public let recentFeedEntries: [Entry]
    public let latestTransactionDate: Date?

    public init(
        transactions: [TransactionDTO],
        recentLimit: Int = PlaidBarConstants.maxRecentTransactions,
        parseDate: (String) -> Date? = Formatters.parseTransactionDate
    ) {
        var entries: [Entry] = []
        entries.reserveCapacity(transactions.count)

        var accountBuckets: [String: [Entry]] = [:]
        var itemBuckets: [String: [Entry]] = [:]
        var merchantBuckets: [String: [Entry]] = [:]
        var categoryTotals: [SpendingCategory: Double] = [:]
        var latestTransactionDate: Date?

        for transaction in transactions {
            let entry = Entry(transaction: transaction, parsedDate: parseDate(transaction.date))
            entries.append(entry)

            accountBuckets[entry.accountId, default: []].append(entry)
            if let itemId = entry.itemId {
                itemBuckets[itemId, default: []].append(entry)
            }
            if let merchantName = entry.merchantName {
                merchantBuckets[merchantName, default: []].append(entry)
            }
            if entry.isExpense {
                categoryTotals[entry.category ?? .other, default: 0] += entry.displayAmount
            }
            if let parsedDate = entry.parsedDate,
               latestTransactionDate.map({ parsedDate > $0 }) ?? true {
                latestTransactionDate = parsedDate
            }
        }

        self.entries = entries
        self.accountBuckets = accountBuckets
        self.itemBuckets = itemBuckets
        self.merchantBuckets = merchantBuckets
        self.categoryTotals = categoryTotals
        self.recentFeedEntries = Array(entries.sorted(by: Self.isPreferredInFeed).prefix(recentLimit))
        self.latestTransactionDate = latestTransactionDate
    }

    public func entries(forAccountId accountId: String) -> [Entry] {
        accountBuckets[accountId] ?? []
    }

    public func entries(forItemId itemId: String) -> [Entry] {
        itemBuckets[itemId] ?? []
    }

    public func entries(forMerchantName merchantName: String) -> [Entry] {
        merchantBuckets[merchantName] ?? []
    }

    public func recentEntries(
        from startDate: Date,
        through endDate: Date
    ) -> [Entry] {
        entries(in: entries, from: startDate, through: endDate)
    }

    public func entries(
        in source: [Entry],
        from startDate: Date,
        through endDate: Date
    ) -> [Entry] {
        source.filter { entry in
            guard let date = entry.parsedDate else { return false }
            return date >= startDate && date <= endDate
        }
    }

    public func sortedForFeed(_ source: [Entry]) -> [Entry] {
        source.sorted(by: Self.isPreferredInFeed)
    }

    public static func isPreferredInFeed(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhsDate = lhs.parsedDate ?? .distantPast
        let rhsDate = rhs.parsedDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        if lhs.transaction.pending != rhs.transaction.pending {
            return lhs.transaction.pending
        }

        if lhs.displayAmount != rhs.displayAmount {
            return lhs.displayAmount > rhs.displayAmount
        }

        let nameComparison = lhs.transaction.displayName.localizedStandardCompare(rhs.transaction.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.transaction.id < rhs.transaction.id
    }
}

public struct FinanceDerivedSnapshot: Sendable {
    public let accounts: [AccountDTO]
    public let accountsById: [String: AccountDTO]
    public let transactionIndex: TransactionDerivedIndex

    public init(accounts: [AccountDTO], transactions: [TransactionDTO]) {
        self.accounts = accounts
        self.accountsById = accounts.reduce(into: [:]) { result, account in
            result[account.id] = account
        }
        self.transactionIndex = TransactionDerivedIndex(transactions: transactions)
    }
}
