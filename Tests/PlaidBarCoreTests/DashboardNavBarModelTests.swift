import Foundation
@testable import PlaidBarCore
import Testing

@Suite("DashboardNavBarModel Tests")
struct DashboardNavBarModelTests {
    // MARK: - Synthetic fixtures (never real account data)

    private static let degradedItemId = "item-degraded"
    private static let healthyItemId = "item-healthy"

    private static func makeAccount(
        id: String,
        itemId: String = healthyItemId,
        type: AccountType,
        subtype: String? = nil
    ) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: itemId,
            name: "Synthetic \(id)",
            type: type,
            subtype: subtype,
            balances: BalanceDTO(available: 100, current: 100)
        )
    }

    /// Mixed set: 2 depository (one savings, matched case-insensitively),
    /// 1 credit (on a degraded item), 1 loan.
    private static let mixedAccounts: [AccountDTO] = [
        makeAccount(id: "chk-1", type: .depository, subtype: "checking"),
        makeAccount(id: "sav-1", type: .depository, subtype: "SAVINGS"),
        makeAccount(id: "cc-1", itemId: degradedItemId, type: .credit, subtype: "credit card"),
        makeAccount(id: "loan-1", type: .loan, subtype: "student"),
    ]

    private static func count(
        _ kind: DashboardAccountFilterKind,
        in items: [DashboardNavBarItem]
    ) -> Int {
        items.first { $0.kind == kind }?.count ?? -1
    }

    // MARK: - Counts

    @Test("Counts per filter kind for a mixed synthetic account set")
    func countsPerFilterKind() {
        let items = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )

        #expect(items.count == DashboardAccountFilterKind.allCases.count)
        #expect(Self.count(.all, in: items) == 4)
        #expect(Self.count(.cash, in: items) == 2)
        #expect(Self.count(.credit, in: items) == 1)
        #expect(Self.count(.savings, in: items) == 1)
        #expect(Self.count(.debt, in: items) == 2)
        #expect(Self.count(.status, in: items) == 1)
    }

    @Test("Savings subtype matches case-insensitively")
    func savingsSubtypeCaseInsensitive() {
        let accounts = [
            Self.makeAccount(id: "sav-upper", type: .depository, subtype: "SAVINGS"),
            Self.makeAccount(id: "sav-mixed", type: .depository, subtype: "Premium Saving"),
            Self.makeAccount(id: "chk", type: .depository, subtype: "checking"),
        ]

        let items = DashboardNavBarModel.items(accounts: accounts)
        #expect(Self.count(.savings, in: items) == 2)
    }

    @Test("Status count is driven by degradedItemIds membership")
    func statusCountTracksDegradedItems() {
        let noneDegraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: []
        )
        #expect(Self.count(.status, in: noneDegraded) == 0)

        let healthyItemDegraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.healthyItemId]
        )
        // Three synthetic accounts live on the healthy item.
        #expect(Self.count(.status, in: healthyItemDegraded) == 3)

        let unknownItemDegraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: ["item-unknown"]
        )
        #expect(Self.count(.status, in: unknownItemDegraded) == 0)
    }

    // MARK: - Attention badge

    @Test("Attention badge shows only for status with degraded items")
    func attentionBadgeOnlyForStatusWithDegradedItems() {
        let items = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )

        for item in items {
            if item.kind == .status {
                #expect(item.showsAttentionBadge)
            } else {
                // Non-status segments never badge, even with nonzero counts.
                #expect(!item.showsAttentionBadge)
            }
        }
    }

    @Test("Status with zero degraded items shows no attention badge")
    func noAttentionBadgeWithoutDegradedItems() {
        let items = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: []
        )

        #expect(items.allSatisfy { !$0.showsAttentionBadge })
    }

    // MARK: - Shortcut ordinals

    @Test("Shortcut ordinals run 1 through 6 in allCases order")
    func shortcutOrdinalsMatchDisplayOrder() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        #expect(items.map(\.shortcutOrdinal) == Array(1 ... DashboardAccountFilterKind.allCases.count))
        #expect(items.map(\.shortcutOrdinal) == [1, 2, 3, 4, 5, 6])
        #expect(items.map(\.kind) == DashboardAccountFilterKind.allCases)
    }

    // MARK: - Accessibility

    @Test("Accessibility label names the filter")
    func accessibilityLabelNamesFilter() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        #expect(items.first { $0.kind == .cash }?.accessibilityLabel == "Cash account filter")
        #expect(items.first { $0.kind == .all }?.accessibilityLabel == "All account filter")
        #expect(items.first { $0.kind == .status }?.accessibilityLabel == "Status account filter")
    }

    @Test("Accessibility value pluralizes for zero, one, and many")
    func accessibilityValuePluralization() {
        let items = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )

        // Zero: empty account set.
        let zeroItems = DashboardNavBarModel.items(accounts: [], degradedItemIds: [])
        #expect(zeroItems.first { $0.kind == .cash }?.accessibilityValue == "0 matching accounts")

        // One: exactly one credit account in the mixed set.
        #expect(items.first { $0.kind == .credit }?.accessibilityValue == "1 matching account")

        // Many: two depository accounts.
        #expect(items.first { $0.kind == .cash }?.accessibilityValue == "2 matching accounts")
    }

    @Test("Status accessibility value says needs attention only when degraded")
    func statusAccessibilityValueAnnouncesAttention() {
        let degraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )
        let statusValue = degraded.first { $0.kind == .status }?.accessibilityValue
        #expect(statusValue?.hasSuffix(", needs attention") == true)

        // Non-status segments never gain the suffix, even with degraded items.
        for item in degraded where item.kind != .status {
            #expect(!item.accessibilityValue.contains("needs attention"))
        }

        // Healthy state: no attention wording anywhere.
        let healthy = DashboardNavBarModel.items(accounts: Self.mixedAccounts, degradedItemIds: [])
        #expect(healthy.allSatisfy { !$0.accessibilityValue.contains("needs attention") })
    }

    // MARK: - Help text

    @Test("Help text names the filter and its command shortcut")
    func helpTextIncludesShortcut() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        #expect(items.first { $0.kind == .all }?.helpText == "Show All accounts (⌘1)")
        #expect(items.first { $0.kind == .cash }?.helpText == "Show Cash accounts (⌘2)")
        #expect(items.first { $0.kind == .status }?.helpText == "Show Status accounts (⌘6)")
    }

    // MARK: - Status icon

    @Test("Status icon pairs attention state with a non-color signal")
    func statusIconReflectsAttentionState() {
        let badged = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )
        #expect(badged.first { $0.kind == .status }?.statusIconName == "exclamationmark.triangle.fill")

        let quiet = DashboardNavBarModel.items(accounts: Self.mixedAccounts)
        #expect(quiet.first { $0.kind == .status }?.statusIconName == "checkmark.circle")
    }

    @Test("Non-status segments never show a status icon")
    func nonStatusSegmentsHaveNoStatusIcon() {
        let items = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )

        #expect(items.filter { $0.kind != .status }.allSatisfy { $0.statusIconName == nil })
    }

    @Test("Status indicator a11y label appears only for degraded status")
    func statusIndicatorAccessibilityLabelForDegradedStatus() {
        // One degraded credit account on the degraded item -> count 1, singular.
        let degraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.degradedItemId]
        )
        #expect(
            degraded.first { $0.kind == .status }?.statusIndicatorAccessibilityLabel
                == "1 item needs attention"
        )
        // Non-status segments never expose the indicator label.
        #expect(degraded.filter { $0.kind != .status }.allSatisfy { $0.statusIndicatorAccessibilityLabel == nil })

        // Multiple degraded accounts -> plural wording.
        let healthyItemDegraded = DashboardNavBarModel.items(
            accounts: Self.mixedAccounts,
            degradedItemIds: [Self.healthyItemId]
        )
        #expect(
            healthyItemDegraded.first { $0.kind == .status }?.statusIndicatorAccessibilityLabel
                == "3 items need attention"
        )

        // Healthy Status: no indicator label.
        let healthy = DashboardNavBarModel.items(accounts: Self.mixedAccounts)
        #expect(healthy.first { $0.kind == .status }?.statusIndicatorAccessibilityLabel == nil)
    }

    // MARK: - Summary

    @Test("Summary for the all filter reads All: N accounts")
    func summaryForAllFilter() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        let summary = DashboardNavBarModel.summary(selected: .all, items: items)
        #expect(summary == "All: 4 accounts")
    }

    @Test("Summary for a non-all filter reads N of M accounts")
    func summaryForNonAllFilter() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        let cashSummary = DashboardNavBarModel.summary(selected: .cash, items: items)
        #expect(cashSummary == "Cash: 2 of 4 accounts")

        let creditSummary = DashboardNavBarModel.summary(selected: .credit, items: items)
        #expect(creditSummary == "Credit: 1 of 4 accounts")
    }

    @Test("Summary uses singular account when total is one")
    func summarySingularTotal() {
        let single = [Self.makeAccount(id: "chk-only", type: .depository, subtype: "checking")]
        let items = DashboardNavBarModel.items(accounts: single)

        #expect(DashboardNavBarModel.summary(selected: .all, items: items) == "All: 1 account")
        #expect(DashboardNavBarModel.summary(selected: .cash, items: items) == "Cash: 1 of 1 account")
    }

    // MARK: - Container accessibility label

    @Test("Container label folds the selected-filter summary into the announced label")
    func containerAccessibilityLabelIncludesSummary() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        #expect(
            DashboardNavBarModel.containerAccessibilityLabel(selected: .all, items: items, hasSelectedAccount: false)
                == "Account filters. All: 4 accounts; select a row for details"
        )
        #expect(
            DashboardNavBarModel.containerAccessibilityLabel(selected: .cash, items: items, hasSelectedAccount: false)
                == "Account filters. Cash: 2 of 4 accounts; select a row for details"
        )
    }

    @Test("Container label announces drill-in state when a row is selected")
    func containerAccessibilityLabelAnnouncesDrillInState() {
        let items = DashboardNavBarModel.items(accounts: Self.mixedAccounts)

        #expect(
            DashboardNavBarModel.containerAccessibilityLabel(selected: .cash, items: items, hasSelectedAccount: true)
                == "Account filters. Cash: 2 of 4 accounts; selected row shows details"
        )
    }

    @Test("Container label handles an empty account set")
    func containerAccessibilityLabelEmptyAccounts() {
        let items = DashboardNavBarModel.items(accounts: [], degradedItemIds: [])

        #expect(
            DashboardNavBarModel.containerAccessibilityLabel(selected: .all, items: items, hasSelectedAccount: false)
                == "Account filters. All: 0 accounts; select a row for details"
        )
        #expect(
            DashboardNavBarModel.containerAccessibilityLabel(selected: .status, items: items, hasSelectedAccount: false)
                == "Account filters. Status: 0 of 0 accounts; select a row for details"
        )
    }

    // MARK: - Empty input

    @Test("Empty accounts input produces zeroed items and summary")
    func emptyAccountsInput() {
        let items = DashboardNavBarModel.items(accounts: [], degradedItemIds: [])

        #expect(items.count == DashboardAccountFilterKind.allCases.count)
        #expect(items.allSatisfy { $0.count == 0 })
        #expect(items.allSatisfy { !$0.showsAttentionBadge })
        #expect(items.map(\.shortcutOrdinal) == [1, 2, 3, 4, 5, 6])
        #expect(DashboardNavBarModel.summary(selected: .all, items: items) == "All: 0 accounts")
        #expect(DashboardNavBarModel.summary(selected: .debt, items: items) == "Debt: 0 of 0 accounts")
    }
}
