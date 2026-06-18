import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Automatic refresh policy")
struct AutomaticRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("Default is twice a day")
    func defaultIsTwiceDaily() {
        let twelveHours: TimeInterval = 12 * 60 * 60
        #expect(AutomaticRefreshPolicy.defaultValue == .twiceDaily)
        #expect(AutomaticRefreshPolicy.twiceDaily.minimumInterval == twelveHours)
        #expect(AutomaticRefreshPolicy.manualOnly.minimumInterval == nil)
    }

    @Test("Never-synced state refreshes once under a time-based policy")
    func neverSyncedRefreshesUnderTimedPolicy() {
        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(lastSync: nil, now: now) == true)
    }

    @Test("Twice-daily refreshes only after 12 hours have elapsed")
    func twiceDailyHonorsTwelveHourFloor() {
        let oneHourAgo = now.addingTimeInterval(-1 * 60 * 60)
        let elevenHoursAgo = now.addingTimeInterval(-11 * 60 * 60)
        let exactlyTwelveHoursAgo = now.addingTimeInterval(-12 * 60 * 60)
        let thirteenHoursAgo = now.addingTimeInterval(-13 * 60 * 60)

        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(lastSync: oneHourAgo, now: now) == false)
        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(lastSync: elevenHoursAgo, now: now) == false)
        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(lastSync: exactlyTwelveHoursAgo, now: now) == true)
        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(lastSync: thirteenHoursAgo, now: now) == true)
    }

    @Test("Manual only never auto-refreshes, even when never synced or long stale")
    func manualOnlyNeverAutoRefreshes() {
        let longAgo = now.addingTimeInterval(-100 * 24 * 60 * 60)
        #expect(AutomaticRefreshPolicy.manualOnly.shouldAutoRefresh(lastSync: nil, now: now) == false)
        #expect(AutomaticRefreshPolicy.manualOnly.shouldAutoRefresh(lastSync: longAgo, now: now) == false)
    }

    @Test("Immediate refresh needs do not override manual-only policy")
    func immediateRefreshNeedsRespectManualOnlyPolicy() {
        let recentSync = now.addingTimeInterval(-60 * 60)

        #expect(AutomaticRefreshPolicy.manualOnly.shouldAutoRefresh(
            lastSync: recentSync,
            now: now,
            hasImmediateNeed: true
        ) == false)
        #expect(AutomaticRefreshPolicy.twiceDaily.shouldAutoRefresh(
            lastSync: recentSync,
            now: now,
            hasImmediateNeed: true
        ) == true)
    }

    @Test("Display names and raw values round-trip for persistence")
    func metadataIsStable() {
        #expect(AutomaticRefreshPolicy.twiceDaily.displayName == "Twice a day")
        #expect(AutomaticRefreshPolicy.manualOnly.displayName == "Manual only")
        #expect(AutomaticRefreshPolicy.allCases.count == 2)
        for policy in AutomaticRefreshPolicy.allCases {
            #expect(AutomaticRefreshPolicy(rawValue: policy.rawValue) == policy)
        }
    }
}
