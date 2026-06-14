import Foundation
@testable import PlaidBarCore
import Testing

@Suite("SubscriptionPlan Tests")
struct SubscriptionPlanTests {
    @Test("Plan institution limits match the proposed entitlement design")
    func planInstitutionLimits() {
        #expect(SubscriptionPlan.personal.institutionLimit == 3)
        #expect(SubscriptionPlan.plus.institutionLimit == 8)
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

@Suite("Billing lifecycle Tests")
struct BillingLifecycleTests {
    @Test(
        "Feature gates respond predictably to subscription statuses",
        arguments: [
            (BillingSubscriptionStatus.active, false),
            (.trialing, false),
            (.pastDue, true),
            (.canceled, true),
            (.expired, true),
        ]
    )
    func featureGateStatusMatrix(status: BillingSubscriptionStatus, isLocked: Bool) {
        let subscription = BillingSubscription(
            status: status,
            plan: .personal,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let result = BillingFeatureGate.evaluate(
            featureName: "managed insights",
            subscription: subscription
        )

        #expect(result.isLocked == isLocked)
    }

    @Test("Locked copy explains the failed-payment recovery path")
    func failedPaymentCopyExplainsRecovery() throws {
        let subscription = BillingSubscription(
            status: .pastDue,
            plan: .plus,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )

        let result = BillingFeatureGate.evaluate(
            featureName: "managed insights",
            subscription: subscription
        )

        guard case .locked(let lock) = result else {
            Issue.record("Expected past_due to lock the feature")
            return
        }
        #expect(lock.title == "managed insights is locked")
        #expect(lock.message.contains("payment failed subscription"))
        #expect(lock.message.contains("Local financial data stays on this Mac"))
        #expect(lock.recoveryAction == "Update your payment method to restore access.")
    }

    @Test("Missing local subscription state leaves local-first installs ungated")
    func nilSubscriptionAllowsLocalFirstInstalls() {
        let result = BillingFeatureGate.evaluate(
            featureName: "managed insights",
            subscription: nil
        )
        #expect(result == .available)
    }

    @Test("Upgrade and downgrade transitions preserve local financial data")
    func planTransitionsPreserveLocalData() {
        let upgrade = BillingPlanTransition(from: .personal, to: .plus)
        let downgrade = BillingPlanTransition(from: .plus, to: .personal)

        #expect(upgrade.isDowngrade == false)
        #expect(upgrade.preservesLocalFinancialData)
        #expect(downgrade.isDowngrade)
        #expect(downgrade.preservesLocalFinancialData)
        #expect(downgrade.explanation.contains("does not delete local accounts"))
    }
}

@Suite("InstitutionUsage Tests")
struct InstitutionUsageTests {
    @Test("Summary text reports count of limit when a limit exists")
    func summaryTextWithLimit() {
        let usage = InstitutionUsage(connectedCount: 2, plan: .personal)
        #expect(usage.summaryText == "2 of 3 institutions connected")
    }

    @Test("Summary text drops the cap when there is no limit")
    func summaryTextWithoutLimit() {
        #expect(InstitutionUsage(connectedCount: 5, limit: nil).summaryText == "5 institutions connected")
        #expect(InstitutionUsage(connectedCount: 1, limit: nil).summaryText == "1 institution connected")
    }

    @Test("Under the limit is not at limit")
    func underLimit() {
        let usage = InstitutionUsage(connectedCount: 2, plan: .personal)
        #expect(usage.isAtLimit == false)
        #expect(usage.summaryText == "2 of 3 institutions connected")
    }

    @Test("At the limit is at limit")
    func atLimit() {
        let usage = InstitutionUsage(connectedCount: 3, plan: .personal)
        #expect(usage.isAtLimit == true)
        #expect(usage.summaryText == "3 of 3 institutions connected")
    }

    @Test("Over the limit is at limit")
    func overLimit() {
        let usage = InstitutionUsage(connectedCount: 4, plan: .personal)
        #expect(usage.isAtLimit == true)
        #expect(usage.summaryText == "4 of 3 institutions connected")
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
