import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Data Export Builder Tests")
struct DataExportBuilderTests {
    private func sampleAccount(
        id: String = "acc1",
        officialName: String? = "Chase Total Checking",
        mask: String? = "0000",
        limit: Double? = 500
    ) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: "item1",
            name: "Checking",
            officialName: officialName,
            type: .depository,
            subtype: "checking",
            mask: mask,
            balances: BalanceDTO(available: 100.5, current: 120.25, limit: limit, isoCurrencyCode: "USD"),
            institutionName: "Chase"
        )
    }

    private func sampleTransaction(
        id: String = "tx1",
        name: String = "WHOLEFDS",
        merchantName: String? = "Whole Foods"
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acc1",
            amount: 12.34,
            date: "2026-06-15",
            name: name,
            merchantName: merchantName,
            category: .foodAndDrink,
            pending: false,
            isoCurrencyCode: "USD"
        )
    }

    @Test("transactionsCSV produces a header plus one row per transaction in declared field order")
    func transactionsCSVHeaderAndRows() {
        let csv = DataExportBuilder.transactionsCSV([
            sampleTransaction(id: "tx1"),
            sampleTransaction(id: "tx2"),
        ])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 3) // header + 2 rows
        #expect(lines[0] == "transaction_id,account_id,date,name,merchant_name,amount,currency,category,pending")
        #expect(lines[1].hasPrefix("tx1,acc1,2026-06-15,WHOLEFDS,Whole Foods,12.34,USD,FOOD_AND_DRINK,false"))
    }

    @Test("csvField quotes and escapes commas, quotes, and newlines; leaves plain values unquoted")
    func csvFieldEscaping() {
        #expect(DataExportBuilder.csvField("plain") == "plain")
        #expect(DataExportBuilder.csvField("a,b") == "\"a,b\"")
        #expect(DataExportBuilder.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(DataExportBuilder.csvField("line1\nline2") == "\"line1\nline2\"")
    }

    @Test("csvField neutralizes formula-leading text but leaves plain numbers untouched")
    func csvFieldFormulaInjection() {
        // Untrusted names beginning with a formula trigger get an apostrophe prefix.
        #expect(DataExportBuilder.csvField("=SUM(A1)") == "'=SUM(A1)")
        #expect(DataExportBuilder.csvField("@cmd") == "'@cmd")
        #expect(DataExportBuilder.csvField("+1-555") == "'+1-555")
        // A value needing both neutralization and quoting (contains a comma).
        #expect(DataExportBuilder.csvField("=HYPERLINK(\"x\"),y") == "\"'=HYPERLINK(\"\"x\"\"),y\"")
        // Plain numbers, including negatives, are left machine-readable.
        #expect(DataExportBuilder.csvField("-100.50") == "-100.50")
        #expect(DataExportBuilder.csvField("100.50") == "100.50")
    }

    @Test("accountsCSV neutralizes a formula-leading institution name")
    func accountsCSVNeutralizesFormulaName() {
        let account = AccountDTO(
            id: "acc1", itemId: "item1", name: "=2+5",
            type: .depository,
            balances: BalanceDTO(available: 1, current: -2, limit: nil, isoCurrencyCode: "USD"),
            institutionName: "@SUM"
        )
        let csv = DataExportBuilder.accountsCSV([account])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let fields = lines[1].components(separatedBy: ",")
        #expect(fields[2] == "'=2+5")     // name neutralized
        #expect(fields[7] == "'@SUM")     // institution_name neutralized
        #expect(fields[9] == "-2.00")     // negative current balance untouched
    }

    @Test("accountsCSV renders nil officialName/mask/limit as empty fields and formats balances with fixed decimals")
    func accountsCSVNilFields() {
        let csv = DataExportBuilder.accountsCSV([
            sampleAccount(officialName: nil, mask: nil, limit: nil),
        ])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2)
        let fields = lines[1].components(separatedBy: ",")
        // account_id,item_id,name,official_name,type,subtype,mask,institution_name,available,current,limit,currency
        #expect(fields[3] == "") // official_name nil -> empty, not "nil"
        #expect(fields[6] == "") // mask nil -> empty
        #expect(fields[8] == "100.50") // available, fixed 2 decimals
        #expect(fields[9] == "120.25") // current
        #expect(fields[10] == "") // limit nil -> empty
        #expect(!lines[1].contains("nil"))
    }

    @Test("balanceHistoryCSV emits canonical YYYY-MM-DD dates")
    func balanceHistoryCSVCanonicalDates() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 9
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let csv = DataExportBuilder.balanceHistoryCSV([BalanceSnapshot(date: date, balance: 1234.5)])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines[0] == "date,balance")
        #expect(lines[1] == "2026-06-09,1234.50")
        #expect(lines[1].hasPrefix(Formatters.transactionDateString(date)))
    }

    @Test("combinedJSON round-trips and carries schemaVersion + counts")
    func combinedJSONRoundTrips() throws {
        let accounts = [sampleAccount()]
        let transactions = [sampleTransaction()]
        let history = [BalanceSnapshot(date: Date(timeIntervalSince1970: 1_700_000_000), balance: 500)]
        let data = try DataExportBuilder.combinedJSON(
            accounts: accounts,
            transactions: transactions,
            balanceHistory: history,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            environment: "sandbox"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DataExportBuilder.Envelope.self, from: data)
        #expect(envelope.schemaVersion == DataExportBuilder.schemaVersion)
        #expect(envelope.counts.accounts == 1)
        #expect(envelope.counts.transactions == 1)
        #expect(envelope.counts.balanceHistory == 1)
        #expect(envelope.environment == "sandbox")
        #expect(envelope.accounts == accounts)
        #expect(envelope.transactions == transactions)
        #expect(envelope.balanceHistory == history)
    }

    @Test("Empty input yields header-only CSV and a zero-count envelope without crashing")
    func emptyInput() throws {
        let accountsCSV = DataExportBuilder.accountsCSV([])
        let transactionsCSV = DataExportBuilder.transactionsCSV([])
        let historyCSV = DataExportBuilder.balanceHistoryCSV([])
        #expect(accountsCSV.split(separator: "\n", omittingEmptySubsequences: true).count == 1)
        #expect(transactionsCSV.split(separator: "\n", omittingEmptySubsequences: true).count == 1)
        #expect(historyCSV.split(separator: "\n", omittingEmptySubsequences: true).count == 1)

        let data = try DataExportBuilder.combinedJSON(
            accounts: [],
            transactions: [],
            balanceHistory: [],
            exportedAt: Date()
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DataExportBuilder.Envelope.self, from: data)
        #expect(envelope.counts.accounts == 0)
        #expect(envelope.counts.transactions == 0)
        #expect(envelope.counts.balanceHistory == 0)
    }

    @Test("sqliteFilename composes the documented per-environment backup path")
    func sqliteFilename() {
        #expect(LocalDataStore.sqliteFilename(for: .sandbox) == "plaidbar-sandbox.sqlite")
        #expect(LocalDataStore.sqliteFilename(for: .production) == "plaidbar-production.sqlite")
        let path = LocalDataStore.displayPath + LocalDataStore.sqliteFilename(for: .sandbox)
        #expect(path == "~/.vaultpeek/plaidbar-sandbox.sqlite")
    }
}
