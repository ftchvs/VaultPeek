import Testing
@testable import PlaidBarCore
// Foundation symbols available via PlaidBarCore's transitive import

@Suite("PlaidBarCore Tests")
struct PlaidBarCoreTests {

    // MARK: - BalanceDTO Tests

    @Test("BalanceDTO effectiveBalance prefers available")
    func effectiveBalanceAvailable() {
        let balance = BalanceDTO(available: 1000, current: 1200)
        #expect(balance.effectiveBalance == 1000)
    }

    @Test("BalanceDTO effectiveBalance falls back to current")
    func effectiveBalanceCurrent() {
        let balance = BalanceDTO(available: nil, current: 1200)
        #expect(balance.effectiveBalance == 1200)
    }

    @Test("BalanceDTO effectiveBalance defaults to 0")
    func effectiveBalanceDefault() {
        let balance = BalanceDTO()
        #expect(balance.effectiveBalance == 0)
    }

    @Test("BalanceDTO utilization calculated correctly")
    func utilizationPercent() {
        let balance = BalanceDTO(current: 300, limit: 1000)
        #expect(balance.utilizationPercent! == 30.0)
    }

    @Test("BalanceDTO utilization nil without limit")
    func utilizationNilWithoutLimit() {
        let balance = BalanceDTO(current: 300)
        #expect(balance.utilizationPercent == nil)
    }

    @Test("BalanceDTO utilization nil without current")
    func utilizationNilWithoutCurrent() {
        let balance = BalanceDTO(available: 500, limit: 1000)
        #expect(balance.utilizationPercent == nil)
    }

    @Test("BalanceDTO utilization with negative current")
    func utilizationNegativeCurrent() {
        let balance = BalanceDTO(current: -850, limit: 10000)
        #expect(balance.utilizationPercent! == 8.5)
    }

    // MARK: - TransactionDTO Tests

    @Test("TransactionDTO income detection (negative amount)")
    func transactionIncome() {
        let tx = TransactionDTO(id: "1", accountId: "a", amount: -1200, date: "2026-01-15", name: "Stripe")
        #expect(tx.isIncome == true)
        #expect(tx.displayAmount == 1200)
    }

    @Test("TransactionDTO expense detection (positive amount)")
    func transactionExpense() {
        let tx = TransactionDTO(id: "2", accountId: "a", amount: 67, date: "2026-01-15", name: "Whole Foods")
        #expect(tx.isIncome == false)
        #expect(tx.displayAmount == 67)
    }

    @Test("TransactionDTO displayName prefers merchantName")
    func transactionDisplayName() {
        let tx = TransactionDTO(id: "3", accountId: "a", amount: 15, date: "2026-01-15", name: "NFLX*STREAMING", merchantName: "Netflix")
        #expect(tx.displayName == "Netflix")
    }

    @Test("TransactionDTO displayName falls back to name")
    func transactionDisplayNameFallback() {
        let tx = TransactionDTO(id: "4", accountId: "a", amount: 15, date: "2026-01-15", name: "Some Payment")
        #expect(tx.displayName == "Some Payment")
    }

    @Test("TransactionDTO zero amount is not income")
    func transactionZeroAmount() {
        let tx = TransactionDTO(id: "5", accountId: "a", amount: 0, date: "2026-01-15", name: "Void")
        #expect(tx.isIncome == false)
        #expect(tx.displayAmount == 0)
    }

    // MARK: - AccountDTO Tests

    @Test("AccountDTO Codable roundtrip")
    func accountCodable() throws {
        let account = AccountDTO(
            id: "acc_123",
            itemId: "item_456",
            name: "Chase Checking",
            type: .depository,
            mask: "4567",
            balances: BalanceDTO(available: 8200, current: 8200)
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(AccountDTO.self, from: data)
        #expect(decoded.id == "acc_123")
        #expect(decoded.itemId == "item_456")
        #expect(decoded.name == "Chase Checking")
        #expect(decoded.type == .depository)
        #expect(decoded.mask == "4567")
        #expect(decoded.balances.effectiveBalance == 8200)
    }

    @Test("AccountDTO all types")
    func accountTypes() {
        let types: [AccountType] = [.depository, .credit, .loan, .investment, .other]
        for accountType in types {
            let account = AccountDTO(id: "id", itemId: "item", name: "Test", type: accountType, balances: BalanceDTO())
            #expect(account.type == accountType)
        }
    }

    @Test("AccountType Codable roundtrip")
    func accountTypeCodable() throws {
        for accountType in [AccountType.depository, .credit, .loan, .investment, .other] {
            let data = try JSONEncoder().encode(accountType)
            let decoded = try JSONDecoder().decode(AccountType.self, from: data)
            #expect(decoded == accountType)
        }
    }

    // MARK: - SpendingCategory Tests

    @Test("SpendingCategory has display names for all cases")
    func categoryDisplayNames() {
        for category in SpendingCategory.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.iconName.isEmpty)
            #expect(!category.colorHex.isEmpty)
        }
    }

    @Test("SpendingCategory Codable with Plaid values")
    func categoryCodable() throws {
        let json = "\"FOOD_AND_DRINK\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SpendingCategory.self, from: data)
        #expect(decoded == .foodAndDrink)
        #expect(decoded.displayName == "Food & Drink")
    }

    @Test("SpendingCategory all raw values roundtrip")
    func categoryAllRawValues() throws {
        for category in SpendingCategory.allCases {
            let encoded = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SpendingCategory.self, from: encoded)
            #expect(decoded == category)
        }
    }

    @Test("SpendingCategory color hex format")
    func categoryColorFormat() {
        for category in SpendingCategory.allCases {
            #expect(category.colorHex.hasPrefix("#"))
            #expect(category.colorHex.count == 7)
        }
    }

    // MARK: - Formatters Tests

    @Test("Currency full format")
    func currencyFull() {
        let result = Formatters.currency(12450.32, format: .full)
        #expect(result.contains("12,450.32") || result.contains("12450.32") || result.contains("12.450,32"))
    }

    @Test("Currency abbreviated format thousands")
    func currencyAbbreviated() {
        let result = Formatters.currency(12450.32, format: .abbreviated)
        #expect(result.contains("12.5K") || result.contains("12.4K"))
    }

    @Test("Currency abbreviated millions")
    func currencyMillions() {
        let result = Formatters.currency(2_500_000, format: .abbreviated)
        #expect(result.contains("2.5M"))
    }

    @Test("Currency abbreviated small amount")
    func currencySmall() {
        let result = Formatters.currency(42.50, format: .abbreviated)
        #expect(result.contains("$43") || result.contains("$42"))
    }

    @Test("Currency abbreviated negative")
    func currencyNegative() {
        let result = Formatters.currency(-5000, format: .abbreviated)
        #expect(result.contains("-"))
        #expect(result.contains("5.0K"))
    }

    @Test("Percent formatting")
    func percentFormat() {
        #expect(Formatters.percent(30.5) == "30.5%")
        #expect(Formatters.percent(100.0, decimals: 0) == "100%")
        #expect(Formatters.percent(0.0) == "0.0%")
    }

    @Test("Date parsing valid")
    func dateParsingValid() {
        let date = Formatters.parseTransactionDate("2026-01-15")
        #expect(date != nil)
    }

    @Test("Date parsing invalid")
    func dateParsingInvalid() {
        let invalid = Formatters.parseTransactionDate("not-a-date")
        #expect(invalid == nil)
    }

    @Test("Date parsing empty string")
    func dateParsingEmpty() {
        let empty = Formatters.parseTransactionDate("")
        #expect(empty == nil)
    }

    // MARK: - SyncResponse Tests

    @Test("SyncResponse Codable")
    func syncResponseCodable() throws {
        let response = SyncResponse(
            added: [TransactionDTO(id: "1", accountId: "a", amount: 50, date: "2026-01-15", name: "Test")],
            modified: [],
            removed: ["old_id"],
            hasMore: false,
            nextCursor: "cursor_abc"
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        #expect(decoded.added.count == 1)
        #expect(decoded.added[0].id == "1")
        #expect(decoded.removed == ["old_id"])
        #expect(decoded.hasMore == false)
        #expect(decoded.nextCursor == "cursor_abc")
    }

    @Test("SyncResponse empty")
    func syncResponseEmpty() throws {
        let response = SyncResponse(added: [], modified: [], removed: [], hasMore: false)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        #expect(decoded.added.isEmpty)
        #expect(decoded.modified.isEmpty)
        #expect(decoded.removed.isEmpty)
        #expect(decoded.hasMore == false)
        #expect(decoded.nextCursor == nil)
    }

    // MARK: - LinkResponse Tests

    @Test("LinkResponse Codable")
    func linkResponseCodable() throws {
        let response = LinkResponse(linkToken: "token_123", linkUrl: "https://example.com/link")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        #expect(decoded.linkToken == "token_123")
        #expect(decoded.linkUrl == "https://example.com/link")
    }

    // MARK: - ServerStatus Tests

    @Test("ServerStatus Codable")
    func serverStatusCodable() throws {
        let status = ServerStatus(version: "0.1.0", environment: .sandbox, itemCount: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerStatus.self, from: data)
        #expect(decoded.version == "0.1.0")
        #expect(decoded.environment == .sandbox)
        #expect(decoded.itemCount == 2)
        #expect(decoded.lastSync == nil)
    }

    @Test("ServerStatus with lastSync")
    func serverStatusWithLastSync() throws {
        let now = Date()
        let status = ServerStatus(version: "0.1.0", environment: .production, itemCount: 1, lastSync: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerStatus.self, from: data)
        #expect(decoded.environment == .production)
        #expect(decoded.lastSync != nil)
    }

    // MARK: - ItemStatus Tests

    @Test("ItemStatus Codable")
    func itemStatusCodable() throws {
        let status = ItemStatus(id: "item_1", institutionName: "Chase", status: .connected)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ItemStatus.self, from: data)
        #expect(decoded.id == "item_1")
        #expect(decoded.institutionName == "Chase")
        #expect(decoded.status == .connected)
    }

    @Test("ItemConnectionStatus all values")
    func itemConnectionStatuses() throws {
        let statuses: [ItemConnectionStatus] = [.connected, .loginRequired, .error]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ItemConnectionStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    // MARK: - PlaidEnvironment Tests

    @Test("PlaidEnvironment raw values")
    func plaidEnvironmentRawValues() {
        #expect(PlaidEnvironment.sandbox.rawValue == "sandbox")
        #expect(PlaidEnvironment.production.rawValue == "production")
    }

    // MARK: - Constants Tests

    @Test("Server URL uses correct port and host")
    func serverURL() {
        #expect(PlaidBarConstants.serverBaseURL == "http://127.0.0.1:8484")
        #expect(PlaidBarConstants.defaultServerPort == 8484)
        #expect(PlaidBarConstants.defaultServerHost == "127.0.0.1")
    }

    @Test("Constants have reasonable values")
    func constantsReasonable() {
        #expect(PlaidBarConstants.backgroundRefreshInterval > 0)
        #expect(PlaidBarConstants.transactionSyncInterval > 0)
        #expect(PlaidBarConstants.creditUtilizationWarningThreshold > 0)
        #expect(PlaidBarConstants.maxRecentTransactions > 0)
        #expect(PlaidBarConstants.initialSyncDays > 0)
        #expect(!PlaidBarConstants.keychainServiceName.isEmpty)
        #expect(!PlaidBarConstants.appVersion.isEmpty)
        #expect(!PlaidBarConstants.appName.isEmpty)
    }
}
