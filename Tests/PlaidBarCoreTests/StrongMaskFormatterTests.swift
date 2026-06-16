import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Strong mask formatter")
struct StrongMaskFormatterTests {
    @Test("text masks use fixed slots and do not leak length or Unicode content")
    func textMasksUseFixedSlots() {
        #expect(StrongMaskFormatter.text("Uber", slot: .primaryLabel) == "••••••")
        #expect(StrongMaskFormatter.text("Whole Foods Market", slot: .primaryLabel) == "••••••")
        #expect(StrongMaskFormatter.text("東京カード🌉", slot: .longDescription) == "•••••• ••••••")
        #expect(StrongMaskFormatter.text("acc_3PnX9e", slot: .identifier) == "••••••••")
    }

    @Test("nil empty and whitespace values keep unavailable placeholders")
    func unavailableValuesKeepPlaceholders() {
        #expect(StrongMaskFormatter.text(nil, slot: .primaryLabel) == "—")
        #expect(StrongMaskFormatter.text("", slot: .primaryLabel) == "—")
        #expect(StrongMaskFormatter.text("   \n\t", slot: .primaryLabel, unavailable: "Unknown") == "Unknown")
        #expect(StrongMaskFormatter.accountLastFour(nil) == "—")
        #expect(StrongMaskFormatter.accountLastFour("    ") == "—")
        #expect(StrongMaskFormatter.money(nil as Double?) == "—")
        #expect(StrongMaskFormatter.date(nil as String?) == "—")
    }

    @Test("account names institutions merchants descriptions and identifiers use semantic helpers")
    func semanticTextHelpersMaskSensitiveStrings() {
        #expect(StrongMaskFormatter.accountName("Chase Total Checking") == "••••••")
        #expect(StrongMaskFormatter.officialAccountName("PLAID CHECKING") == "•••• ••••")
        #expect(StrongMaskFormatter.institutionName("Plaid Bank") == "••••••")
        #expect(StrongMaskFormatter.merchantName("Whole Foods Market") == "••••••")
        #expect(StrongMaskFormatter.transactionDescription("WHOLEFDS LOS ANGELES CA 320104") == "•••••• ••••••")
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: "Uber", name: "UBER TRIP HELP.UBER.COM") == "••••••")
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: nil, name: "SQ *COFFEE BAR") == "•••••• ••••••")
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: " ", name: nil) == "—")
        #expect(StrongMaskFormatter.identifier("transaction-id-123") == "••••••••")
        #expect(StrongMaskFormatter.accountLastFour("1234") == "••••")
    }

    @Test("money percent counts and dates hide exact values while preserving shape")
    func numericAndDateMasksPreserveShape() {
        #expect(StrongMaskFormatter.money(4_823.19) == "$••••")
        #expect(StrongMaskFormatter.money(-87.42, preservesSign: true) == "-$••••")
        #expect(StrongMaskFormatter.money(Decimal(12_000), preservesSign: true) == "+$••••")
        #expect(StrongMaskFormatter.money(Decimal(-22.99), preservesSign: true) == "-$••••")
        #expect(StrongMaskFormatter.money(Double.nan) == "—")
        #expect(StrongMaskFormatter.money(Double.infinity) == "—")
        #expect(StrongMaskFormatter.money(3_250.0, preservesSign: true) == "+$••••")
        #expect(StrongMaskFormatter.money(0.0, preservesSign: true) == "$••••")
        #expect(StrongMaskFormatter.percent(43.2) == "••%")
        #expect(StrongMaskFormatter.count(3, label: "pending") == "•• pending")
        #expect(StrongMaskFormatter.date("2026-06-14") == "••/••/••")
        #expect(StrongMaskFormatter.dateRange("Jun 1", "Jun 30") == "••• •• – ••• ••")
        #expect(StrongMaskFormatter.freshness(prefix: "Updated", value: "2m ago") == "Updated •••")
    }

    @Test("generic account type category status and unavailable values can remain visible")
    func genericValuesRemainVisible() {
        #expect(StrongMaskFormatter.generic("Checking") == "Checking")
        #expect(StrongMaskFormatter.generic("Food & Drink") == "Food & Drink")
        #expect(StrongMaskFormatter.generic("Pending") == "Pending")
        #expect(StrongMaskFormatter.generic(nil) == "—")
    }

    @Test("accessibility labels announce hidden semantics instead of bullet characters")
    func accessibilityLabelsDescribeHiddenValues() {
        #expect(StrongMaskFormatter.accessibilityLabel(for: .accountName) == "Account name hidden")
        #expect(StrongMaskFormatter.accessibilityLabel(for: .merchant) == "Merchant hidden")
        #expect(StrongMaskFormatter.accessibilityLabel(for: .amount) == "Amount hidden")
        #expect(StrongMaskFormatter.accessibilityLabel(for: .identifier) == "Identifier hidden")
    }
}
