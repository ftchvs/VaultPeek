import Foundation

/// Display-safe, deterministic receipt for the dashboard's "what changed?" glance.
///
/// The receipt uses only local balance history, locally cached transactions, and
/// local item status metadata. It summarizes the latest local snapshot window;
/// it never includes account IDs, item IDs, raw Plaid payloads, or transaction names.
public struct DashboardChangeReceipt: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        public let accessibilityText: String

        public init(id: String, label: String, value: String, accessibilityText: String) {
            self.id = id
            self.label = label
            self.value = value
            self.accessibilityText = accessibilityText
        }
    }

    public let title: String
    public let summary: String
    public let rows: [Row]
    public let accessibilitySummary: String

    public init(title: String, summary: String, rows: [Row], accessibilitySummary: String) {
        self.title = title
        self.summary = summary
        self.rows = rows
        self.accessibilitySummary = accessibilitySummary
    }

    public static func evaluate(
        history: [BalanceSnapshot],
        transactions: [TransactionDTO],
        itemStatuses: [ItemStatus],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardChangeReceipt? {
        let points = history
            .filter { $0.date <= now }
            .sorted { $0.date < $1.date }

        guard let latest = points.last else { return nil }

        let degradedItemCount = itemStatuses.count { $0.status == .loginRequired || $0.status == .error }

        guard points.count >= 2 else {
            var rows = [Row(
                id: "baseline",
                label: "Baseline",
                value: "Saved",
                accessibilityText: "First local snapshot saved. VaultPeek will compare future local snapshots against this baseline."
            )]

            if degradedItemCount > 0 {
                rows.append(degradedItemsRow(count: degradedItemCount))
            }

            let summary = "First local snapshot saved"
            return DashboardChangeReceipt(
                title: "Latest local changes",
                summary: summary,
                rows: rows,
                accessibilitySummary: "Latest local changes. \(summary). \(rows.map(\.accessibilityText).joined(separator: " "))"
            )
        }

        let previous = points[points.count - 2]
        let delta = latest.balance - previous.balance
        let changedTransactions = transactionsChanged(since: previous.date, through: latest.date, transactions: transactions, calendar: calendar)

        var rows: [Row] = [balanceRow(delta: delta)]
        rows.append(transactionRow(count: changedTransactions.count))

        if degradedItemCount > 0 {
            rows.append(degradedItemsRow(count: degradedItemCount))
        }

        let summary = summaryText(delta: delta, transactionCount: changedTransactions.count, degradedItemCount: degradedItemCount)
        return DashboardChangeReceipt(
            title: "Latest local changes",
            summary: summary,
            rows: Array(rows.prefix(3)),
            accessibilitySummary: "Latest local changes. \(summary). \(rows.map(\.accessibilityText).joined(separator: " "))"
        )
    }

    private static func balanceRow(delta: Double) -> Row {
        let direction: String
        let value: String
        if abs(delta) < 0.005 {
            direction = "unchanged"
            value = "No change"
        } else if delta > 0 {
            direction = "up"
            value = "+\(Formatters.currency(abs(delta), format: .compact))"
        } else {
            direction = "down"
            value = "-\(Formatters.currency(abs(delta), format: .compact))"
        }

        return Row(
            id: "net-worth",
            label: "Net",
            value: value,
            accessibilityText: "Net worth \(direction)\(abs(delta) < 0.005 ? "" : " " + Formatters.currency(abs(delta), format: .full))."
        )
    }

    private static func transactionRow(count: Int) -> Row {
        Row(
            id: "transactions",
            label: "Activity",
            value: count == 0 ? "No new tx" : "\(count) new tx",
            accessibilityText: count == 0
                ? "No newly dated transactions since the prior local snapshot."
                : "\(count) newly dated transaction\(count == 1 ? "" : "s") since the prior local snapshot."
        )
    }

    private static func degradedItemsRow(count: Int) -> Row {
        Row(
            id: "attention",
            label: "Needs attention",
            value: "\(count) item\(count == 1 ? "" : "s")",
            accessibilityText: "\(count) linked item\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention."
        )
    }

    private static func summaryText(delta: Double, transactionCount: Int, degradedItemCount: Int) -> String {
        var parts: [String] = []
        if abs(delta) < 0.005 {
            parts.append("net unchanged")
        } else if delta > 0 {
            parts.append("net up \(Formatters.currency(abs(delta), format: .compact))")
        } else {
            parts.append("net down \(Formatters.currency(abs(delta), format: .compact))")
        }

        if transactionCount > 0 {
            parts.append("\(transactionCount) new tx")
        }

        if degradedItemCount > 0 {
            parts.append("\(degradedItemCount) item\(degradedItemCount == 1 ? "" : "s") need attention")
        }

        return parts.joined(separator: " · ")
    }

    private static func transactionsChanged(
        since startDate: Date,
        through endDate: Date,
        transactions: [TransactionDTO],
        calendar: Calendar
    ) -> [TransactionDTO] {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        return transactions.filter { transaction in
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return false }
            let transactionDay = calendar.startOfDay(for: date)
            return transactionDay > startDay && transactionDay <= endDay
        }
    }
}
