import Foundation

/// Pure, Sendable serializer that turns the app's locally-held DTO arrays into
/// portable CSV documents and a combined JSON backup envelope (AND-492). No
/// AppKit, no I/O — string/Data math over Sendable DTOs, fully unit-testable.
public enum DataExportBuilder {
    /// Bumped whenever the JSON envelope shape changes so importers can branch.
    public static let schemaVersion = 1

    // MARK: - CSV

    /// Escapes a single CSV field per RFC 4180 and neutralizes spreadsheet
    /// formula injection. Plaid account / transaction / merchant names are
    /// untrusted; a value that begins with `=`, `+`, `-`, or `@` can be executed
    /// as a formula when the CSV is opened in Excel / Numbers / Sheets. We prefix
    /// such values with a leading apostrophe so the cell renders as literal text.
    /// Pure numeric fields (e.g. a negative balance "-100.50") parse as a number
    /// and are left untouched so exported figures stay machine-readable.
    public static func csvField(_ value: String) -> String {
        let neutralized = neutralizingFormula(value)
        let needsQuoting = neutralized.contains(",")
            || neutralized.contains("\"")
            || neutralized.contains("\n")
            || neutralized.contains("\r")
        guard needsQuoting else { return neutralized }
        let escaped = neutralized.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Prefixes a leading `'` when `value` starts with a formula trigger
    /// (`=`, `+`, `-`, `@`) and is not a plain number. Plain numbers (including
    /// negatives) are returned unchanged so numeric columns stay parseable.
    private static func neutralizingFormula(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        // A bare numeric value like "-100.50" is safe — only neutralize text.
        if Double(value) != nil { return value }
        return "'\(value)"
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    private static func decimalString(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    public static func accountsCSV(_ accounts: [AccountDTO]) -> String {
        let header = row([
            "account_id", "item_id", "name", "official_name", "type", "subtype",
            "mask", "institution_name", "available", "current", "limit", "currency",
        ])
        let rows = accounts.map { account in
            row([
                account.id,
                account.itemId,
                account.name,
                account.officialName ?? "",
                account.type.rawValue,
                account.subtype ?? "",
                account.mask ?? "",
                account.institutionName ?? "",
                decimalString(account.balances.available),
                decimalString(account.balances.current),
                decimalString(account.balances.limit),
                account.balances.isoCurrencyCode ?? "",
            ])
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func transactionsCSV(_ transactions: [TransactionDTO]) -> String {
        let header = row([
            "transaction_id", "account_id", "date", "name", "merchant_name",
            "amount", "currency", "category", "pending",
        ])
        let rows = transactions.map { transaction in
            row([
                transaction.id,
                transaction.accountId,
                transaction.date,
                transaction.name,
                transaction.merchantName ?? "",
                decimalString(transaction.amount),
                transaction.isoCurrencyCode ?? "",
                transaction.category?.rawValue ?? "",
                transaction.pending ? "true" : "false",
            ])
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func balanceHistoryCSV(_ history: [BalanceSnapshot]) -> String {
        let header = row(["date", "balance"])
        let rows = history.map { snapshot in
            row([
                Formatters.transactionDateString(snapshot.date),
                decimalString(snapshot.balance),
            ])
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    // MARK: - JSON

    /// Versioned, stable backup envelope: schemaVersion, exportedAt, environment,
    /// per-array counts, then the three DTO arrays (reusing their Codable
    /// conformances). Round-trips back into the original DTO arrays.
    public struct Envelope: Codable, Sendable, Equatable {
        public struct Counts: Codable, Sendable, Equatable {
            public let accounts: Int
            public let transactions: Int
            public let balanceHistory: Int

            public init(accounts: Int, transactions: Int, balanceHistory: Int) {
                self.accounts = accounts
                self.transactions = transactions
                self.balanceHistory = balanceHistory
            }
        }

        public let schemaVersion: Int
        public let exportedAt: Date
        public let environment: String?
        public let counts: Counts
        public let accounts: [AccountDTO]
        public let transactions: [TransactionDTO]
        public let balanceHistory: [BalanceSnapshot]

        public init(
            schemaVersion: Int,
            exportedAt: Date,
            environment: String?,
            counts: Counts,
            accounts: [AccountDTO],
            transactions: [TransactionDTO],
            balanceHistory: [BalanceSnapshot]
        ) {
            self.schemaVersion = schemaVersion
            self.exportedAt = exportedAt
            self.environment = environment
            self.counts = counts
            self.accounts = accounts
            self.transactions = transactions
            self.balanceHistory = balanceHistory
        }
    }

    public static func envelope(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        balanceHistory: [BalanceSnapshot],
        exportedAt: Date,
        environment: String? = nil
    ) -> Envelope {
        Envelope(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            environment: environment,
            counts: Envelope.Counts(
                accounts: accounts.count,
                transactions: transactions.count,
                balanceHistory: balanceHistory.count
            ),
            accounts: accounts,
            transactions: transactions,
            balanceHistory: balanceHistory
        )
    }

    public static func combinedJSON(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        balanceHistory: [BalanceSnapshot],
        exportedAt: Date,
        environment: String? = nil
    ) throws -> Data {
        let envelope = envelope(
            accounts: accounts,
            transactions: transactions,
            balanceHistory: balanceHistory,
            exportedAt: exportedAt,
            environment: environment
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
