import Foundation
@testable import PlaidBarCore
import Testing

/// Priority #5: the deterministic on-device income subtype classifier + the
/// `IncomeCategory` taxonomy. All inputs are synthetic; no real Plaid data.
@Suite("Income Merchant Classifier Tests")
struct IncomeMerchantClassifierTests {
    private let classifier = IncomeMerchantClassifier()

    /// Income = money in (Plaid convention: negative amount).
    private func income(
        id: String = "inc-1",
        amount: Double = -2_500,
        name: String,
        merchantName: String? = nil,
        category: SpendingCategory? = .income
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct-1",
            amount: amount,
            date: "2026-06-19",
            name: name,
            merchantName: merchantName,
            category: category
        )
    }

    // MARK: - Taxonomy

    @Test("Every IncomeCategory has a non-empty display name and icon")
    func taxonomyComplete() {
        for category in IncomeCategory.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.iconName.isEmpty)
            // Raw values round-trip.
            #expect(IncomeCategory(rawValue: category.rawValue) == category)
        }
    }

    // MARK: - Lexicon hits (trusted)

    @Test("A payroll keyword classifies as salary (trusted)")
    func payrollIsSalary() {
        let inference = classifier.infer(for: income(name: "ACME PAYROLL DEP"))
        #expect(inference?.category == .salary)
        #expect(inference?.isTrusted == true)
    }

    @Test("A tax-refund phrase classifies as government (high)")
    func taxRefundIsGovernment() {
        let inference = classifier.infer(for: income(name: "IRS TAX REFUND 040"))
        #expect(inference?.category == .government)
        #expect(inference?.confidence == .high)
    }

    @Test("An interest deposit classifies as interest")
    func interestIsInterest() {
        let inference = classifier.infer(for: income(name: "INTEREST PAYMENT"))
        #expect(inference?.category == .interest)
        #expect(inference?.isTrusted == true)
    }

    @Test("A dividend classifies as dividend")
    func dividendIsDividend() {
        let inference = classifier.infer(for: income(name: "VANGUARD DIVIDEND"))
        #expect(inference?.category == .dividend)
    }

    @Test("A merchant refund classifies as refund")
    func merchantRefundIsRefund() {
        let inference = classifier.infer(for: income(name: "AMAZON REFUND"))
        #expect(inference?.category == .refund)
    }

    @Test("A Venmo inflow classifies as reimbursement")
    func venmoIsReimbursement() {
        let inference = classifier.infer(for: income(name: "VENMO CASHOUT"))
        #expect(inference?.category == .reimbursement)
    }

    // MARK: - Recurring heuristic (lexicon miss)

    @Test("A recurring inflow with no lexicon hit reads as salary (trusted)")
    func recurringMissIsSalary() {
        let inference = classifier.infer(for: income(name: "ZZQ EMPLOYER 88"), isRecurring: true)
        #expect(inference?.category == .salary)
        #expect(inference?.isTrusted == true)
    }

    @Test("A one-off inflow with no lexicon hit is untrusted other income")
    func oneOffMissIsUntrustedOther() {
        let inference = classifier.infer(for: income(name: "ZZQ UNKNOWN 88"), isRecurring: false)
        #expect(inference?.category == .otherIncome)
        #expect(inference?.isTrusted == false)
    }

    // MARK: - Guards

    @Test("A spend (money out) transaction is never classified as income")
    func spendIsNeverIncome() {
        let spend = income(amount: 42, name: "STARBUCKS", category: .foodAndDrink)
        #expect(classifier.infer(for: spend) == nil)
    }

    @Test("A lexicon hit on the cleaned merchant name still resolves")
    func merchantNameLexiconHit() {
        let inference = classifier.infer(for: income(name: "DD ACH 0099", merchantName: "Gusto Payroll"))
        #expect(inference?.category == .salary)
        #expect(inference?.isTrusted == true)
    }

    @Test("Deterministic: repeated calls yield the same inference")
    func deterministic() {
        let txn = income(name: "ACME PAYROLL DEP")
        let first = classifier.infer(for: txn)
        let second = classifier.infer(for: txn)
        #expect(first == second)
    }
}
