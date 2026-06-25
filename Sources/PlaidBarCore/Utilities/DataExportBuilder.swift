import Foundation

/// Pure, Sendable serializer that turns the app's locally-held DTO arrays into
/// portable CSV documents and a combined JSON backup envelope (AND-492). No
/// AppKit, no I/O — string/Data math over Sendable DTOs, fully unit-testable.
public enum DataExportBuilder {
    /// Bumped whenever the JSON envelope shape changes so importers can branch.
    /// v2 adds the optional `budgets` array + `counts.budgets` (AND-645); v3 adds
    /// the optional `splits` array + `counts.splits` (AND-550). The new fields
    /// decode as empty/zero from an older file, so importers stay
    /// backward-compatible.
    public static let schemaVersion = 3

    // MARK: - Masked-state gating (AND-645)

    /// Pure, testable decision for whether a local export may run, given the
    /// effective Privacy-Mask state. Keeping this out of the SwiftUI view lets
    /// the gating rule be unit-tested: the export writes *real* balances,
    /// accounts, transactions, and budgets to disk, so it must never run while
    /// the UI is masked (Privacy Mask on) or locked (App Lock) — otherwise a
    /// quick over-the-shoulder mask or a locked session could be bypassed by
    /// silently writing the unmasked data to a file.
    ///
    /// `shouldMaskFinancialValues` is the app's single source of truth and is
    /// `true` for *both* the manual Privacy Mask toggle and an active App Lock,
    /// so a single input covers both cases. Export is allowed only when nothing
    /// is masked.
    public static func isExportAllowed(shouldMaskFinancialValues: Bool) -> Bool {
        !shouldMaskFinancialValues
    }

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

    /// CSV of transactions. `metadata`/`rules` (AND-527) are optional and default
    /// to `nil`, which writes the raw Plaid `category` column unchanged (legacy
    /// behavior — existing importers and tests keep working). When supplied, the
    /// `category` column reflects the *effective* category (user override → rule →
    /// raw Plaid → empty) via the persisted-only `EffectiveCategoryResolver`, so an
    /// exported file matches what the user reviewed in-app rather than the raw Plaid
    /// guess. NL suggestions are display-only and never exported. Pending-phase
    /// review metadata stored under a charge's `pendingTransactionId` is carried
    /// into its posted replacement (mirrors `CategoryBudgetPlanner`). The row count
    /// and every other column are unchanged — only the `category` cell may differ.
    public static func transactionsCSV(
        _ transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata]? = nil,
        rules: [TransactionRule]? = nil
    ) -> String {
        let header = row([
            "transaction_id", "account_id", "date", "name", "merchant_name",
            "amount", "currency", "category", "pending",
        ])

        // Legacy path: no review state supplied → raw Plaid category.
        let resolveCategory: (TransactionDTO) -> String
        if metadata == nil, rules == nil {
            resolveCategory = { $0.category?.rawValue ?? "" }
        } else {
            let metadataById = Dictionary(
                (metadata ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let activeRules = rules ?? []
            resolveCategory = { transaction in
                // Carry pending-phase review metadata into the posted charge
                // (mirrors `CategoryBudgetPlanner.netSpendByCategory`).
                let effectiveMetadata = metadataById[transaction.id]
                    ?? transaction.pendingTransactionId.flatMap { metadataById[$0] }
                let resolution = EffectiveCategoryResolver.resolve(
                    transaction: transaction,
                    metadata: effectiveMetadata,
                    rules: activeRules
                )
                // The effective budget category (override/rule/confident Plaid);
                // when none resolved, fall back to the raw Plaid category so the
                // export keeps a genuinely-categorized row's bucket and leaves a
                // truly-uncategorized row blank — an NL suggestion is never written.
                return (resolution.category ?? transaction.category)?.rawValue ?? ""
            }
        }

        let rows = transactions.map { transaction in
            row([
                transaction.id,
                transaction.accountId,
                transaction.date,
                transaction.name,
                transaction.merchantName ?? "",
                decimalString(transaction.amount),
                transaction.isoCurrencyCode ?? "",
                resolveCategory(transaction),
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

    /// CSV of the user's saved monthly category budgets (AND-645). Rows are
    /// sorted by the Plaid category raw value so the output is deterministic
    /// regardless of the `[SpendingCategory: Double]` dictionary iteration order
    /// the app holds them in — stable column order is required for diff-able,
    /// re-importable backups. `category` is the machine raw value (e.g.
    /// `FOOD_AND_DRINK`), `category_name` the human label, both run through the
    /// same field escaping/neutralization as every other column.
    public static func budgetsCSV(_ budgets: [CategoryBudgetDTO]) -> String {
        let header = row(["category", "category_name", "monthly_limit"])
        let rows = budgets
            .sorted { $0.category.rawValue < $1.category.rawValue }
            .map { budget in
                row([
                    budget.category.rawValue,
                    budget.category.displayName,
                    decimalString(budget.monthlyLimit),
                ])
            }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Convenience overload that accepts the app's in-memory
    /// `[SpendingCategory: Double]` budget map and normalizes it into stably
    /// ordered `CategoryBudgetDTO`s before serializing.
    public static func budgetsCSV(_ budgets: [SpendingCategory: Double]) -> String {
        budgetsCSV(budgetDTOs(from: budgets))
    }

    /// Normalizes the app's budget dictionary into a stably ordered DTO array
    /// (sorted by category raw value) so both the CSV and the JSON envelope emit
    /// budgets in the same deterministic order.
    public static func budgetDTOs(from budgets: [SpendingCategory: Double]) -> [CategoryBudgetDTO] {
        budgets
            .map { CategoryBudgetDTO(category: $0.key, monthlyLimit: $0.value) }
            .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    /// CSV of transaction splits (AND-550). One row **per allocation**, so a split
    /// transaction contributes N rows joined by the shared `transaction_id` — the
    /// transactions CSV keeps its one-row-per-transaction contract while this file
    /// carries the per-category breakdown. Rows are ordered by `transaction_id`
    /// then allocation index for a deterministic, diff-able backup. `expected_total`
    /// is the parent's signed amount the allocations must sum to (the invariant);
    /// `amount` is the signed slice; `excluded_from_budgets` is the allocation's own
    /// flag.
    public static func splitsCSV(_ splits: [TransactionSplit]) -> String {
        let header = row([
            "transaction_id", "expected_total", "allocation_index",
            "category", "category_name", "amount", "excluded_from_budgets",
        ])
        let rows = splits
            .sorted { $0.transactionId < $1.transactionId }
            .flatMap { split in
                split.allocations.enumerated().map { index, allocation in
                    row([
                        split.transactionId,
                        decimalString(split.expectedTotal),
                        String(index),
                        allocation.category.rawValue,
                        allocation.category.displayName,
                        decimalString(allocation.amount),
                        allocation.excludedFromBudgets ? "true" : "false",
                    ])
                }
            }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    // MARK: - JSON

    /// Versioned, stable backup envelope: schemaVersion, exportedAt, environment,
    /// per-array counts, then the DTO arrays (reusing their Codable
    /// conformances). Round-trips back into the original DTO arrays.
    ///
    /// `budgets` (and `counts.budgets`) were added in schemaVersion 2 (AND-645).
    /// They decode as empty/zero when reading a v1 file that lacks them, so
    /// older backups stay importable.
    public struct Envelope: Codable, Sendable, Equatable {
        public struct Counts: Codable, Sendable, Equatable {
            public let accounts: Int
            public let transactions: Int
            public let balanceHistory: Int
            public let budgets: Int
            public let splits: Int

            public init(
                accounts: Int,
                transactions: Int,
                balanceHistory: Int,
                budgets: Int,
                splits: Int = 0
            ) {
                self.accounts = accounts
                self.transactions = transactions
                self.balanceHistory = balanceHistory
                self.budgets = budgets
                self.splits = splits
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                accounts = try container.decode(Int.self, forKey: .accounts)
                transactions = try container.decode(Int.self, forKey: .transactions)
                balanceHistory = try container.decode(Int.self, forKey: .balanceHistory)
                // Absent in v1 envelopes → treat as zero.
                budgets = try container.decodeIfPresent(Int.self, forKey: .budgets) ?? 0
                // Absent in v1/v2 envelopes → treat as zero (AND-550).
                splits = try container.decodeIfPresent(Int.self, forKey: .splits) ?? 0
            }
        }

        public let schemaVersion: Int
        public let exportedAt: Date
        public let environment: String?
        public let counts: Counts
        public let accounts: [AccountDTO]
        public let transactions: [TransactionDTO]
        public let balanceHistory: [BalanceSnapshot]
        public let budgets: [CategoryBudgetDTO]
        public let splits: [TransactionSplit]

        public init(
            schemaVersion: Int,
            exportedAt: Date,
            environment: String?,
            counts: Counts,
            accounts: [AccountDTO],
            transactions: [TransactionDTO],
            balanceHistory: [BalanceSnapshot],
            budgets: [CategoryBudgetDTO],
            splits: [TransactionSplit] = []
        ) {
            self.schemaVersion = schemaVersion
            self.exportedAt = exportedAt
            self.environment = environment
            self.counts = counts
            self.accounts = accounts
            self.transactions = transactions
            self.balanceHistory = balanceHistory
            self.budgets = budgets
            self.splits = splits
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            exportedAt = try container.decode(Date.self, forKey: .exportedAt)
            environment = try container.decodeIfPresent(String.self, forKey: .environment)
            counts = try container.decode(Counts.self, forKey: .counts)
            accounts = try container.decode([AccountDTO].self, forKey: .accounts)
            transactions = try container.decode([TransactionDTO].self, forKey: .transactions)
            balanceHistory = try container.decode([BalanceSnapshot].self, forKey: .balanceHistory)
            // Absent in v1 envelopes → decode as no budgets.
            budgets = try container.decodeIfPresent([CategoryBudgetDTO].self, forKey: .budgets) ?? []
            // Absent in v1/v2 envelopes → decode as no splits (AND-550).
            splits = try container.decodeIfPresent([TransactionSplit].self, forKey: .splits) ?? []
        }
    }

    public static func envelope(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        balanceHistory: [BalanceSnapshot],
        budgets: [CategoryBudgetDTO] = [],
        splits: [TransactionSplit] = [],
        exportedAt: Date,
        environment: String? = nil
    ) -> Envelope {
        // Stable order: budgets are sorted by category raw value so the JSON
        // backup matches the CSV order and produces diff-able files.
        let orderedBudgets = budgets.sorted { $0.category.rawValue < $1.category.rawValue }
        // Splits sorted by parent transaction id, matching `splitsCSV`, so the JSON
        // and CSV exports stay diff-able and re-importable (AND-550).
        let orderedSplits = splits.sorted { $0.transactionId < $1.transactionId }
        return Envelope(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            environment: environment,
            counts: Envelope.Counts(
                accounts: accounts.count,
                transactions: transactions.count,
                balanceHistory: balanceHistory.count,
                budgets: orderedBudgets.count,
                splits: orderedSplits.count
            ),
            accounts: accounts,
            transactions: transactions,
            balanceHistory: balanceHistory,
            budgets: orderedBudgets,
            splits: orderedSplits
        )
    }

    public static func combinedJSON(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        balanceHistory: [BalanceSnapshot],
        budgets: [CategoryBudgetDTO] = [],
        splits: [TransactionSplit] = [],
        exportedAt: Date,
        environment: String? = nil
    ) throws -> Data {
        let envelope = envelope(
            accounts: accounts,
            transactions: transactions,
            balanceHistory: balanceHistory,
            budgets: budgets,
            splits: splits,
            exportedAt: exportedAt,
            environment: environment
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
