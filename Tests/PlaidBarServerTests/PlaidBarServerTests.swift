import Testing
import Foundation
@testable import PlaidBarCore
@testable import PlaidBarServer

@Suite("PlaidBarServer")
struct PlaidBarServerTests {

    @Test func accountTypes() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 5000))
        let credit = AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -850, limit: 10000))
        #expect(checking.type == .depository)
        #expect(credit.type == .credit)
        #expect(credit.balances.utilizationPercent! == 8.5)
    }

    @Test func environmentCodable() throws {
        let sandbox = PlaidEnvironment.sandbox
        let data = try JSONEncoder().encode(sandbox)
        let decoded = try JSONDecoder().decode(PlaidEnvironment.self, from: data)
        #expect(decoded == .sandbox)
    }

    @Test func serverStatusCodable() throws {
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
        #expect(decoded.credentialsConfigured)
        #expect(decoded.storagePath == LocalDataStore.displayPath)
        #expect(decoded.syncReady)
    }

    @Test func linkResponseCodable() throws {
        let response = LinkResponse(linkToken: "token_123", linkUrl: "https://example.com/link")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        #expect(decoded.linkToken == "token_123")
    }

    @Test func unknownAccountType() {
        let type = AccountType(rawValue: "brokerage") ?? .other
        #expect(type == .other)
    }

    @Test func pendingLinkSessionIsConsumedOnce() async {
        let store = PendingLinkSessionStore()
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        let first = await store.consume(state: state)
        let replay = await store.consume(state: state)

        #expect(first?.linkToken == "link-token")
        #expect(replay == nil)
    }

    @Test func pendingLinkSessionExpires() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let store = PendingLinkSessionStore(ttl: 60) { currentDate }
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        currentDate = currentDate.addingTimeInterval(61)

        let expired = await store.consume(state: state)
        #expect(expired == nil)
    }

    @Test func linkTokenGetResponseReadsHostedLinkSessionResults() throws {
        let json = """
        {
          "link_token": "link-sandbox-token",
          "link_sessions": [
            {
              "link_session_id": "session-one",
              "results": {
                "item_add_results": [
                  { "public_token": "public-sandbox-one" },
                  { "public_token": "public-sandbox-two" }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(PlaidLinkTokenGetResponse.self, from: json)

        #expect(response.publicTokens == ["public-sandbox-one", "public-sandbox-two"])
    }

    @Test func linkTokenGetResponseAllowsUpdateModeWithoutPublicToken() throws {
        let json = """
        {
          "link_token": "link-sandbox-token",
          "on_success": {
            "public_token": null,
            "metadata": {}
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(PlaidLinkTokenGetResponse.self, from: json)

        #expect(response.publicTokens.isEmpty)
    }
}
