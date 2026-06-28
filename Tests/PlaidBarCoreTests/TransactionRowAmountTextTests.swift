import Foundation
import PlaidBarCore
import Testing

/// Pins the exact output of `TransactionWorkspace.Row.signedAmountText(isMasked:)`,
/// extracted from byte-identical inline copies in `TransactionsTable` and
/// `TransactionInspectorView`. The reference strings are composed from
/// `Formatters.currency(_:format:)` (the repo convention for `.full` amounts,
/// which keeps the assertion locale-robust) so the test guarantees the helper
/// reproduces the prior inline expression exactly.
@Suite("Transaction Row Amount Text")
struct TransactionRowAmountTextTests {
    private func tx(_ id: String, amount: Double) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acc1",
            amount: amount,
            date: "2026-06-10",
            name: "Coffee Shop",
            merchantName: "Coffee Shop",
            category: .foodAndDrink,
            pending: false
        )
    }

    private func row(amount: Double) -> TransactionWorkspace.Row {
        let rows = TransactionWorkspace.rows(
            transactions: [tx("a", amount: amount)],
            metadata: [],
            rules: []
        )
        return rows[0]
    }

    // The original inline expression, reproduced verbatim, as the behavior oracle.
    private func reference(_ row: TransactionWorkspace.Row) -> String {
        let prefix = row.transaction.isIncome ? "+" : ""
        return "\(prefix)\(Formatters.currency(row.transaction.displayAmount, format: .full))"
    }

    @Test("An outflow renders unsigned at full precision")
    func outflowIsUnsigned() {
        let r = row(amount: 50) // Plaid: positive = money out
        #expect(r.signedAmountText(isMasked: false) == Formatters.currency(50, format: .full))
        #expect(r.signedAmountText(isMasked: false) == reference(r))
        #expect(!r.signedAmountText(isMasked: false).hasPrefix("+"))
    }

    @Test("Income carries a leading plus over the unsigned magnitude")
    func incomeIsSigned() {
        let r = row(amount: -120) // Plaid: negative = money in
        #expect(r.transaction.isIncome)
        #expect(r.signedAmountText(isMasked: false) == "+\(Formatters.currency(120, format: .full))")
        #expect(r.signedAmountText(isMasked: false) == reference(r))
    }

    @Test("Masking withholds the amount as the shared compact placeholder")
    func maskedWithholdsAmount() {
        let r = row(amount: 50)
        #expect(r.signedAmountText(isMasked: true) == PrivacyMaskPresentation.compactValue)
        #expect(r.signedAmountText(isMasked: true) == "••••")
    }

    @Test("Masking wins over the income sign")
    func maskedIncomeStillWithheld() {
        let r = row(amount: -120)
        #expect(r.signedAmountText(isMasked: true) == PrivacyMaskPresentation.compactValue)
    }

    @Test("Helper reproduces the prior inline expression across signs")
    func matchesReferenceAcrossSigns() {
        // `-0.0` is intentional: IEEE-754 `-0.0 < 0` is false, so it resolves to an
        // unsigned zero — both the helper and the oracle treat it identically.
        for amount in [50.0, -120.0, 0.0, -0.0, 1_234.56, -9_999.99] {
            let r = row(amount: amount)
            #expect(r.signedAmountText(isMasked: false) == reference(r))
        }
    }
}
