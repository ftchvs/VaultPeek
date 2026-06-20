import Foundation
import PlaidBarCore
import Testing

@Suite("Account list grouping for the Accounts destination (AND-623)")
struct AccountListGroupingTests {
    private func account(_ id: String, type: AccountType) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: "item-\(id)",
            name: "Account \(id)",
            type: type,
            balances: BalanceDTO(available: 100, current: 100, isoCurrencyCode: "USD")
        )
    }

    @Test("Empty input produces no sections")
    func emptyInput() {
        #expect(AccountListGrouping.sections(for: []).isEmpty)
    }

    @Test("Sections appear in the fixed asset-then-liability order, skipping absent types")
    func sectionOrder() {
        let accounts = [
            account("c1", type: .credit),
            account("d1", type: .depository),
            account("i1", type: .investment),
        ]

        let sections = AccountListGrouping.sections(for: accounts)

        // No loan / other accounts present ⇒ no empty headers for them.
        #expect(sections.map(\.type) == [.depository, .credit, .investment])
    }

    @Test("Accounts keep their input order within a section (stable grouping)")
    func stableWithinSection() {
        let accounts = [
            account("d2", type: .depository),
            account("d1", type: .depository),
            account("d3", type: .depository),
        ]

        let sections = AccountListGrouping.sections(for: accounts)

        #expect(sections.count == 1)
        #expect(sections[0].accounts.map(\.id) == ["d2", "d1", "d3"])
    }

    @Test("A type with no accounts never yields an empty section")
    func noEmptySections() {
        let sections = AccountListGrouping.sections(for: [account("o1", type: .other)])

        #expect(sections.count == 1)
        #expect(sections[0].type == .other)
        #expect(sections[0].accounts.count == 1)
    }

    @Test("Section count and title match the bucket")
    func sectionMetadata() {
        let accounts = [
            account("c1", type: .credit),
            account("c2", type: .credit),
        ]

        let sections = AccountListGrouping.sections(for: accounts)

        #expect(sections.count == 1)
        #expect(sections[0].title == AccountListGrouping.title(for: .credit))
        #expect(sections[0].accounts.count == 2)
        // Section id is its type, so SwiftUI ForEach has a stable identity.
        #expect(sections[0].id == .credit)
    }

    @Test("Every account type has a non-empty title")
    func titlesPresent() {
        for type in [AccountType.depository, .credit, .loan, .investment, .other] {
            #expect(!AccountListGrouping.title(for: type).isEmpty)
        }
    }
}
