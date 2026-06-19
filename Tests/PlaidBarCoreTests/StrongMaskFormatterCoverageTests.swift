import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Strong mask formatter coverage")
struct StrongMaskFormatterCoverageTests {
    @Test("Text masks present content per slot and is unavailable otherwise")
    func textSlots() {
        #expect(StrongMaskFormatter.text("Chase", slot: .primaryLabel) == StrongMaskFormatter.TextSlot.primaryLabel.mask)
        #expect(StrongMaskFormatter.text(nil, slot: .primaryLabel) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.text("   ", slot: .primaryLabel) == StrongMaskFormatter.unavailable)

        let masks = [
            StrongMaskFormatter.TextSlot.primaryLabel,
            .secondaryLabel, .metadata, .longDescription, .identifier,
        ].map(\.mask)
        #expect(masks.allSatisfy { !$0.isEmpty })
    }

    @Test("Named string helpers delegate to a slot mask, unavailable when empty")
    func namedHelpers() {
        #expect(StrongMaskFormatter.accountName("Everyday") == StrongMaskFormatter.TextSlot.primaryLabel.mask)
        #expect(StrongMaskFormatter.officialAccountName("Everyday Checking") == StrongMaskFormatter.TextSlot.secondaryLabel.mask)
        #expect(StrongMaskFormatter.institutionName("Acme") == StrongMaskFormatter.TextSlot.primaryLabel.mask)
        #expect(StrongMaskFormatter.merchantName("Starbucks") == StrongMaskFormatter.TextSlot.primaryLabel.mask)
        #expect(StrongMaskFormatter.transactionDescription("Coffee") == StrongMaskFormatter.TextSlot.longDescription.mask)
        #expect(StrongMaskFormatter.identifier("abc123") == StrongMaskFormatter.TextSlot.identifier.mask)
        #expect(StrongMaskFormatter.accountLastFour("1234") == StrongMaskFormatter.TextSlot.metadata.mask)
        #expect(StrongMaskFormatter.accountName(nil) == StrongMaskFormatter.unavailable)
    }

    @Test("Transaction display name prefers merchant, then the raw name")
    func transactionDisplayName() {
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: "Starbucks", name: "SQ *STARBUCKS") == StrongMaskFormatter.TextSlot.primaryLabel.mask)
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: nil, name: "SQ *STARBUCKS") == StrongMaskFormatter.TextSlot.longDescription.mask)
        #expect(StrongMaskFormatter.transactionDisplayName(merchantName: nil, name: nil) == StrongMaskFormatter.unavailable)
    }

    @Test("Money masks magnitude while optionally preserving sign (Double)")
    func moneyDouble() {
        // Explicit Double typing disambiguates from the Decimal overload.
        #expect(StrongMaskFormatter.money(Double?.none) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.money(Double.nan) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.money(Double(42)) == StrongMaskFormatter.maskedMoney)
        #expect(StrongMaskFormatter.money(Double(-42), preservesSign: true) == "-\(StrongMaskFormatter.maskedMoney)")
        #expect(StrongMaskFormatter.money(Double(42), preservesSign: true) == "+\(StrongMaskFormatter.maskedMoney)")
        #expect(StrongMaskFormatter.money(Double(0), preservesSign: true) == StrongMaskFormatter.maskedMoney)
    }

    @Test("Money masks magnitude while optionally preserving sign (Decimal)")
    func moneyDecimal() {
        #expect(StrongMaskFormatter.money(Decimal?.none) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.money(Decimal(42)) == StrongMaskFormatter.maskedMoney)
        #expect(StrongMaskFormatter.money(Decimal(-42), preservesSign: true) == "-\(StrongMaskFormatter.maskedMoney)")
        #expect(StrongMaskFormatter.money(Decimal(42), preservesSign: true) == "+\(StrongMaskFormatter.maskedMoney)")
        #expect(StrongMaskFormatter.money(Decimal(0), preservesSign: true) == StrongMaskFormatter.maskedMoney)
    }

    @Test("Percent, count, date, range, freshness, and generic masking")
    func miscMasks() {
        #expect(StrongMaskFormatter.percent(nil) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.percent(30) == StrongMaskFormatter.maskedPercent)

        #expect(StrongMaskFormatter.count(nil, label: "items") == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.count(5, label: "items") == "•• items")
        #expect(StrongMaskFormatter.count(5, label: "   ") == "••")

        #expect(StrongMaskFormatter.date("2026-06-14") == StrongMaskFormatter.maskedDate)
        #expect(StrongMaskFormatter.date(nil as String?) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.date(Date()) == StrongMaskFormatter.maskedDate)
        #expect(StrongMaskFormatter.date(nil as Date?) == StrongMaskFormatter.unavailable)

        #expect(StrongMaskFormatter.dateRange(nil, nil) == StrongMaskFormatter.unavailable)
        #expect(StrongMaskFormatter.dateRange("2026-06-01", nil) == StrongMaskFormatter.maskedDateRange)

        #expect(StrongMaskFormatter.freshness(prefix: "Updated", value: "2m ago") == "Updated •••")
        #expect(StrongMaskFormatter.freshness(prefix: "   ", value: "2m ago") == "•••")
        #expect(StrongMaskFormatter.freshness(prefix: "Updated", value: nil) == StrongMaskFormatter.unavailable)

        #expect(StrongMaskFormatter.generic("Checking") == "Checking")
        #expect(StrongMaskFormatter.generic(nil) == StrongMaskFormatter.unavailable)
    }

    @Test("Accessibility labels are present and distinct for every hidden value")
    func accessibilityLabels() {
        let kinds: [StrongMaskFormatter.AccessibilityHiddenValue] = [
            .accountName, .institution, .merchant, .description, .amount,
            .date, .identifier, .accountMask, .percentage, .count,
        ]
        let labels = kinds.map(StrongMaskFormatter.accessibilityLabel(for:))
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == kinds.count)
    }
}
