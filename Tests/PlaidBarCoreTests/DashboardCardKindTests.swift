import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard card kind")
struct DashboardCardKindTests {
    @Test("Each kind exposes a stable id matching its raw value")
    func identifiers() {
        for kind in DashboardCardKind.allCases {
            #expect(kind.id == kind.rawValue)
        }
    }

    @Test("Each kind has a distinct, human-readable display name")
    func displayNames() {
        #expect(DashboardCardKind.changeReceipt.displayName == "Latest changes")
        #expect(DashboardCardKind.weeklyReview.displayName == "Weekly review")
        #expect(DashboardCardKind.overview.displayName == "Accounts overview")
        #expect(DashboardCardKind.recentSpend.displayName == "Recent spend")
        #expect(DashboardCardKind.insights.displayName == "Insights")

        let names = DashboardCardKind.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(DashboardCardKind.allCases.count == 5)
    }
}
