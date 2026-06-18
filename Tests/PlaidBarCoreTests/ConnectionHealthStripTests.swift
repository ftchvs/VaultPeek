import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Connection Health Strip Tests")
struct ConnectionHealthStripTests {
    private func status(_ id: String, _ state: ItemConnectionStatus) -> ItemStatus {
        ItemStatus(id: id, institutionName: id, status: state)
    }

    @Test("evaluate buckets a mixed list into Connected / Reconnect-needed / Provider-outage with correct counts")
    func bucketsMixedList() {
        let result = ConnectionHealthStrip.evaluate([
            status("a", .connected),
            status("b", .connected),
            status("c", .loginRequired),
            status("d", .error),
            status("e", .providerOutage),
        ])
        let byState = Dictionary(uniqueKeysWithValues: result.buckets.map { ($0.state, $0) })
        #expect(byState[.connected]?.count == 2)
        #expect(byState[.reconnectNeeded]?.count == 2) // loginRequired + error
        #expect(byState[.providerOutage]?.count == 1)
    }

    @Test("A provider-outage bucket is non-actionable with a distinct symbol and non-empty label")
    func outageBucketNonActionable() {
        let result = ConnectionHealthStrip.evaluate([status("a", .providerOutage)])
        let outage = result.buckets.first { $0.state == .providerOutage }
        #expect(outage?.isActionable == false)
        #expect(outage?.iconName.isEmpty == false)
        #expect(outage?.label.isEmpty == false)
        // Distinct from the reconnect-needed symbol.
        let reconnect = ConnectionHealthStrip.evaluate([status("b", .error)]).buckets.first
        #expect(outage?.iconName != reconnect?.iconName)
    }

    @Test("Reconnect-needed bucket is actionable, provider-outage is not")
    func actionableFlags() {
        let result = ConnectionHealthStrip.evaluate([
            status("a", .error),
            status("b", .providerOutage),
        ])
        #expect(result.hasActionableWork == true)
        #expect(result.hasProviderOutage == true)
    }

    @Test("providerOutage semantics: degraded but not update-mode")
    func providerOutageSemantics() {
        #expect(ItemConnectionStatus.providerOutage.isDegraded == true)
        #expect(ItemConnectionStatus.providerOutage.needsUpdateMode == false)
        #expect(ItemConnectionStatus.providerOutage.isProviderOutage == true)
    }

    @Test("ItemRecoveryTarget never selects an outage-only item as a reconnect target")
    func recoveryTargetIgnoresOutage() {
        let outageOnly = ConnectionHealthStrip.evaluate([status("a", .providerOutage)])
        #expect(outageOnly.hasActionableWork == false)
        // Direct recovery-target check: an outage-only list yields no target.
        let target = ItemRecoveryTarget.item(from: [
            status("a", .connected),
            status("b", .providerOutage),
        ])
        #expect(target == nil)
        // But a list with a real error still selects the error item.
        let withError = ItemRecoveryTarget.item(from: [
            status("a", .providerOutage),
            status("b", .error),
        ])
        #expect(withError?.id == "b")
    }

    @Test("AttentionQueue produces a .warning advisory (no reconnect) for an outage item")
    func attentionQueueOutageAdvisory() {
        let rows = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 0,
            itemStatuses: [status("a", .providerOutage)],
            isSyncStale: false,
            lastSyncRelative: "just now",
            errorMessage: nil
        ).rows
        let outageRow = rows.first { $0.id.hasPrefix("item-outage") }
        #expect(outageRow != nil)
        #expect(outageRow?.severity == .warning)
        #expect(outageRow?.action == nil) // no reconnect action
    }

    @Test("NotificationTriggerSelection emits a distinct providerOutage kind (not itemError) for outage")
    func notificationDistinctKind() {
        let evaluation = NotificationTriggerSelection.evaluate(
            itemStatuses: [status("a", .providerOutage)],
            isSyncStale: false,
            config: NotificationTriggers()
        )
        let kinds = Set(evaluation.decisions.map(\.kind))
        #expect(kinds.contains(.providerOutage))
        #expect(!kinds.contains(.itemError))
    }

    @Test("ItemStatus round-trips .providerOutage through Codable")
    func codableRoundTrip() throws {
        let original = ItemStatus(id: "a", institutionName: "Wells Fargo", status: .providerOutage, needsSync: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ItemStatus.self, from: data)
        #expect(decoded.status == .providerOutage)
        #expect(decoded.id == "a")
        #expect(decoded.status.rawValue == "provider_outage")
    }
}
