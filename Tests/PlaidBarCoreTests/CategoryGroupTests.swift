import Foundation
import Testing
@testable import PlaidBarCore

@Suite("CategoryGroup map + SpendingCategory.group (AND-535)")
struct CategoryGroupTests {
    @Test("every SpendingCategory case maps to a group (exhaustive)")
    func everyCategoryMapsToAGroup() {
        // Iterating CaseIterable guarantees the assertion stays exhaustive as cases
        // are added: a new SpendingCategory case is automatically covered here, and
        // the non-optional `group` property forces the mapping to be total.
        for category in SpendingCategory.allCases {
            let group = category.group
            #expect(CategoryGroup.allCases.contains(group))
        }
    }

    @Test("every CategoryGroup is reachable from at least one SpendingCategory")
    func everyGroupIsReachable() {
        let reached = Set(SpendingCategory.allCases.map(\.group))
        for group in CategoryGroup.allCases {
            #expect(reached.contains(group), "Group \(group) has no SpendingCategory mapped to it")
        }
    }

    @Test("group ordering is stable, total, and duplicate-free")
    func orderingIsStable() {
        let ordered = CategoryGroup.displayOrder
        // Ordering covers every group exactly once.
        #expect(ordered.count == CategoryGroup.allCases.count)
        #expect(Set(ordered).count == ordered.count)
        #expect(Set(ordered) == Set(CategoryGroup.allCases))
        // sortIndex is consistent with the ordering and contiguous from 0.
        for (index, group) in ordered.enumerated() {
            #expect(group.sortIndex == index)
        }
        // Pinned anchors the dashboard relies on: Income first, Other last.
        #expect(ordered.first == .income)
        #expect(ordered.last == .other)
    }

    @Test("group titles are stable, non-empty, and unique")
    func titlesAreStableAndUnique() {
        let titles = CategoryGroup.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
        // A few stable, load-bearing titles the dashboard/spec reference by name.
        #expect(CategoryGroup.income.title == "Income")
        #expect(CategoryGroup.foodAndDining.title == "Food & Dining")
        #expect(CategoryGroup.billsAndUtilities.title == "Bills & Utilities")
        #expect(CategoryGroup.healthAndWellness.title == "Health & Wellness")
        #expect(CategoryGroup.transfers.title == "Transfers")
        #expect(CategoryGroup.other.title == "Other")
    }

    @Test("representative SpendingCategory cases land in the expected group")
    func representativeMappings() {
        #expect(SpendingCategory.income.group == .income)
        #expect(SpendingCategory.foodAndDrink.group == .foodAndDining)
        #expect(SpendingCategory.transportation.group == .transportation)
        #expect(SpendingCategory.shopping.group == .shopping)
        #expect(SpendingCategory.billsAndUtilities.group == .billsAndUtilities)
        #expect(SpendingCategory.subscriptions.group == .billsAndUtilities)
        #expect(SpendingCategory.healthAndFitness.group == .healthAndWellness)
        #expect(SpendingCategory.personalCare.group == .healthAndWellness)
        #expect(SpendingCategory.entertainment.group == .entertainment)
        #expect(SpendingCategory.homeImprovement.group == .housing)
        #expect(SpendingCategory.transfer.group == .transfers)
        #expect(SpendingCategory.transferOut.group == .transfers)
        #expect(SpendingCategory.bankFees.group == .other)
        #expect(SpendingCategory.government.group == .other)
        #expect(SpendingCategory.other.group == .other)
    }

    @Test("group exposes its member categories and membership round-trips")
    func membershipRoundTrips() {
        // Every category listed by a group's `categories` actually maps back to it,
        // and the union of all members covers the full SpendingCategory set.
        var union: Set<SpendingCategory> = []
        for group in CategoryGroup.allCases {
            for category in group.categories {
                #expect(category.group == group)
                union.insert(category)
            }
        }
        #expect(union == Set(SpendingCategory.allCases))
    }
}
