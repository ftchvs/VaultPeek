import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Figure Provenance Tests")
struct FigureProvenanceTests {
    // MARK: - Net worth

    @Test("Net worth provenance lists contributing accounts and excludes investments")
    func netWorthProvenance() {
        let accounts = [
            AccountDTO(id: "acct_checking", itemId: "item_1", name: "Everyday Checking", type: .depository, mask: "4321", balances: BalanceDTO(available: 4_200, current: 4_250)),
            AccountDTO(id: "acct_card", itemId: "item_1", name: "Travel Card", type: .credit, balances: BalanceDTO(current: -800, limit: 5_000)),
            AccountDTO(id: "acct_brokerage", itemId: "item_2", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 30_000)),
        ]
        let freshness = Formatters.parseTransactionDate("2026-06-20")

        let provenance = FigureProvenance.netWorth(accounts: accounts, freshness: freshness)

        #expect(provenance.figureTitle == "Net worth")
        // Investments are excluded; only the two cash/debt accounts contribute.
        #expect(provenance.sources.count == 2)
        #expect(provenance.sources.contains { $0.label.contains("Everyday Checking") })
        // The investment exclusion is surfaced explicitly.
        #expect(provenance.exclusions.contains { $0.contains("Investment accounts (1)") })
        #expect(provenance.localOnlyBadge == "Local-only")
    }

    @Test("Net worth source labels carry the masked last-4 but never raw IDs")
    func netWorthNoRawIdentifiers() {
        let accounts = [
            AccountDTO(id: "acct_secret_id", itemId: "item_secret_id", name: "Checking", type: .depository, mask: "9911", balances: BalanceDTO(current: 1_000)),
        ]

        let provenance = FigureProvenance.netWorth(accounts: accounts, freshness: nil)

        let blob = provenance.accessibilitySummary
            + provenance.sources.map { "\($0.id)\($0.label)\($0.accessibilityLabel)\($0.value ?? "")" }.joined()
        #expect(blob.contains("••9911"))
        // The source `id` carries the account id for SwiftUI identity, but no
        // user-visible label or accessibility string leaks the raw account/item id.
        #expect(!provenance.accessibilitySummary.contains("acct_secret_id"))
        #expect(!provenance.accessibilitySummary.contains("item_secret_id"))
        #expect(provenance.sources.allSatisfy { !$0.label.contains("acct_secret_id") })
        #expect(provenance.sources.allSatisfy { !$0.accessibilityLabel.contains("item_secret_id") })
    }

    @Test("Net worth without a sync reports a not-yet-synced freshness")
    func netWorthFreshnessFallback() {
        let provenance = FigureProvenance.netWorth(accounts: [], freshness: nil)
        #expect(provenance.freshnessText == "Not yet synced")
        #expect(provenance.freshness == nil)
    }

    // MARK: - Privacy mask

    @Test("Masked net worth provenance never renders a real balance")
    func maskedNetWorthHidesValues() {
        let accounts = [
            AccountDTO(id: "acct", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(current: 12_345.67)),
        ]

        let provenance = FigureProvenance.netWorth(
            accounts: accounts,
            freshness: nil,
            privacyMaskEnabled: true
        )

        // Every source value is the dotted placeholder, never the real amount.
        #expect(provenance.sources.allSatisfy { $0.value == PrivacyMaskPresentation.compactValue })
        let blob = provenance.sources.map { "\($0.value ?? "")\($0.accessibilityLabel)" }.joined()
            + provenance.accessibilitySummary
        #expect(!blob.contains("12,345"))
        #expect(!blob.contains("12345"))
    }

    // MARK: - Safe to spend

    @Test("Safe-to-spend provenance maps visible components to source rows")
    func safeToSpendProvenance() {
        let result = SafeToSpendResult(
            amount: 420,
            components: [
                SafeToSpendComponent(kind: .startingCash, label: "Starting cash", amount: 1_000),
                SafeToSpendComponent(kind: .expectedIncome, label: "Expected income", amount: 0),
                SafeToSpendComponent(kind: .upcomingObligations, label: "Upcoming bills", amount: -580),
            ],
            confidence: .lowConfidence,
            horizonEnd: Formatters.parseTransactionDate("2026-06-30") ?? Date()
        )

        let provenance = FigureProvenance.safeToSpend(result: result, freshness: nil)

        #expect(provenance.figureTitle == "Safe to spend")
        // startingCash + expectedIncome are always visible; upcomingObligations is non-zero.
        #expect(provenance.sources.count == 3)
        #expect(provenance.sources.contains { $0.label == "Upcoming bills" })
        // The low-confidence caveat is surfaced as an exclusion.
        #expect(provenance.exclusions.contains { $0.contains("estimated") })
        // The horizon date range is surfaced.
        #expect(provenance.exclusions.contains { $0.contains("Looks ahead through") })
    }

    @Test("Masked safe-to-spend provenance hides component amounts")
    func maskedSafeToSpendHidesValues() {
        let result = SafeToSpendResult(
            amount: 999,
            components: [
                SafeToSpendComponent(kind: .startingCash, label: "Starting cash", amount: 5_555),
            ],
            confidence: .ok,
            horizonEnd: Date()
        )

        let provenance = FigureProvenance.safeToSpend(
            result: result,
            freshness: nil,
            privacyMaskEnabled: true
        )

        #expect(provenance.sources.allSatisfy { $0.value == PrivacyMaskPresentation.compactValue })
        #expect(!provenance.accessibilitySummary.contains("5,555"))
    }

    // MARK: - Credit utilization

    @Test("Credit-utilization provenance lists cards and excludes limit-less cards")
    func creditUtilizationProvenance() {
        let summary = WealthSummaryPresentation.CreditUtilizationSummary(
            percent: 24,
            usedCredit: 1_200,
            totalLimit: 5_000,
            statusLabel: "Healthy",
            exceedsThreshold: false
        )
        let creditAccounts = [
            AccountDTO(id: "card_a", itemId: "item", name: "Cashback Card", type: .credit, balances: BalanceDTO(current: -1_200, limit: 5_000)),
            AccountDTO(id: "card_b", itemId: "item", name: "Store Card", type: .credit, balances: BalanceDTO(current: -50)), // no limit
        ]

        let provenance = FigureProvenance.creditUtilization(
            summary: summary,
            creditAccounts: creditAccounts,
            freshness: nil
        )

        #expect(provenance.figureTitle == "Credit utilization")
        // Only the card with a limit contributes a source row.
        #expect(provenance.sources.count == 1)
        #expect(provenance.sources.contains { $0.label.contains("Cashback Card") })
        // The limit-less card is surfaced as an exclusion.
        #expect(provenance.exclusions.contains { $0.contains("without a reported limit") })
        // Unmasked derivation includes the status label.
        #expect(provenance.derivation.contains("Healthy"))
    }

    @Test("Masked credit-utilization derivation drops the status label and amounts")
    func maskedCreditUtilizationHidesValues() {
        let summary = WealthSummaryPresentation.CreditUtilizationSummary(
            percent: 88,
            usedCredit: 4_400,
            totalLimit: 5_000,
            statusLabel: "High",
            exceedsThreshold: true
        )
        let creditAccounts = [
            AccountDTO(id: "card", itemId: "item", name: "Card", type: .credit, balances: BalanceDTO(current: -4_400, limit: 5_000)),
        ]

        let provenance = FigureProvenance.creditUtilization(
            summary: summary,
            creditAccounts: creditAccounts,
            freshness: nil,
            privacyMaskEnabled: true
        )

        // The status label ("High") is a value-ish judgement; mask drops it.
        #expect(!provenance.derivation.contains("High"))
        #expect(provenance.sources.allSatisfy { $0.value == PrivacyMaskPresentation.compactValue })
        #expect(!provenance.accessibilitySummary.contains("4,400"))
    }
}
