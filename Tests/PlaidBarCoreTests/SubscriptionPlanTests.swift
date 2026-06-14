import Foundation
@testable import PlaidBarCore
import Testing

@Suite("SubscriptionPlan Tests")
struct SubscriptionPlanTests {
    @Test("Plan institution limits match the accepted entitlement matrix")
    func planInstitutionLimits() {
        #expect(SubscriptionPlan.free.institutionLimit == 0)
        #expect(SubscriptionPlan.plus.institutionLimit == 8)
    }

    @Test("Default plan is Free")
    func defaultPlan() {
        #expect(SubscriptionPlan.defaultPlan == .free)
    }

    @Test("Every plan exposes a display name and preview tagline")
    func planMetadataIsPopulated() {
        for plan in SubscriptionPlan.allCases {
            #expect(!plan.displayName.isEmpty)
            #expect(!plan.priceDescription.isEmpty)
            #expect(plan.id == plan.rawValue)
        }
    }

    @Test("Plans are Codable round-trip stable")
    func planCodableRoundTrip() throws {
        for plan in SubscriptionPlan.allCases {
            let encoded = try JSONEncoder().encode(plan)
            let decoded = try JSONDecoder().decode(SubscriptionPlan.self, from: encoded)
            #expect(decoded == plan)
        }
    }

    @Test("ItemOrigin encodes to the planned connection_origin wire values")
    func itemOriginRawValues() {
        #expect(ItemOrigin.managed.rawValue == "managed")
        #expect(ItemOrigin.bringYourOwn.rawValue == "byo")
    }
}

@Suite("InstitutionUsage Tests")
struct InstitutionUsageTests {
    @Test("Summary text reports count of limit when a limit exists")
    func summaryTextWithLimit() {
        let usage = InstitutionUsage(connectedCount: 2, plan: .plus)
        #expect(usage.summaryText == "2 of 8 institutions connected")
    }

    @Test("Summary text drops the cap when there is no limit")
    func summaryTextWithoutLimit() {
        #expect(InstitutionUsage(connectedCount: 5, limit: nil).summaryText == "5 institutions connected")
        #expect(InstitutionUsage(connectedCount: 1, limit: nil).summaryText == "1 institution connected")
    }

    @Test("Under the limit is not at limit")
    func underLimit() {
        let usage = InstitutionUsage(connectedCount: 2, plan: .plus)
        #expect(usage.isAtLimit == false)
        #expect(usage.summaryText == "2 of 8 institutions connected")
    }

    @Test("Free managed limit is zero")
    func freeLimitIsZero() {
        let usage = InstitutionUsage(connectedCount: 0, plan: .free)
        #expect(usage.limit == 0)
        #expect(usage.isAtLimit == true)
        #expect(usage.summaryText == "0 of 0 institutions connected")
    }

    @Test("Over the limit is at limit")
    func overLimit() {
        let usage = InstitutionUsage(connectedCount: 9, plan: .plus)
        #expect(usage.isAtLimit == true)
        #expect(usage.summaryText == "9 of 8 institutions connected")
    }

    @Test("A nil limit is never at limit, even with many connections")
    func nilLimitNeverAtLimit() {
        #expect(InstitutionUsage(connectedCount: 0, limit: nil).isAtLimit == false)
        #expect(InstitutionUsage(connectedCount: 99, limit: nil).isAtLimit == false)
    }

    @Test("Plus plan limit derives correctly from the plan initializer")
    func plusPlanLimit() {
        let usage = InstitutionUsage(connectedCount: 8, plan: .plus)
        #expect(usage.limit == 8)
        #expect(usage.isAtLimit == true)
        #expect(usage.summaryText == "8 of 8 institutions connected")
    }
}
