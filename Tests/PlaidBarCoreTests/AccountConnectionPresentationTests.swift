import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Account connection presentation")
struct AccountConnectionPresentationTests {
    private func evaluate(
        isDemoMode: Bool = false,
        serverConnected: Bool = true,
        isSyncStale: Bool = false,
        statusSyncText: String = "Updated just now",
        itemStatus: ItemConnectionStatus?,
        institutionName: String? = "Acme Bank",
        itemLastSyncRelative: String? = "2m ago"
    ) -> AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            isSyncStale: isSyncStale,
            statusSyncText: statusSyncText,
            itemStatus: itemStatus,
            institutionName: institutionName,
            itemLastSyncRelative: itemLastSyncRelative
        )
    }

    @Test("Demo mode short-circuits to the demo presentation")
    func demo() {
        let presentation = evaluate(isDemoMode: true, itemStatus: .error)
        #expect(presentation.level == .demo)
        #expect(!presentation.showsRecoveryActions)
        // statusFilterSubtitle defaults to detailLabel when not supplied.
        #expect(presentation.statusFilterSubtitle == "Demo data")
    }

    @Test("Offline server outranks item status")
    func offline() {
        let presentation = evaluate(serverConnected: false, itemStatus: .connected)
        #expect(presentation.level == .offline)
        #expect(!presentation.showsRecoveryActions)
    }

    @Test("Connected and fresh is healthy with no recovery")
    func healthy() {
        let presentation = evaluate(itemStatus: .connected)
        #expect(presentation.level == .healthy)
        #expect(presentation.signalLabel == "Fresh")
        #expect(!presentation.showsRecoveryActions)
        #expect(presentation.statusFilterSubtitle == "Healthy • Last sync 2m ago")
    }

    @Test("Connected but stale offers a refresh")
    func stale() {
        let presentation = evaluate(isSyncStale: true, itemStatus: .connected)
        #expect(presentation.level == .stale)
        #expect(presentation.recoveryActionTitle == "Refresh")
        #expect(presentation.showsRecoveryActions)
        #expect(presentation.recoveryDetailLabel?.contains("stale") == true)
    }

    @Test("login_repaired is treated as a healthy sync")
    func loginRepaired() {
        #expect(evaluate(itemStatus: .loginRepaired).level == .healthy)
    }

    @Test("Unknown item status reads as unknown with no recovery")
    func unknown() {
        let presentation = evaluate(itemStatus: nil)
        #expect(presentation.level == .unknown)
        #expect(!presentation.showsRecoveryActions)
        #expect(presentation.signalLabel == "Unknown")
    }

    @Test("Item error surfaces a reconnect naming the institution")
    func errorNamed() {
        let presentation = evaluate(itemStatus: .error, institutionName: "Acme Bank")
        #expect(presentation.level == .error)
        #expect(presentation.recoveryActionTitle == "Reconnect Acme Bank")
        #expect(presentation.detailLabel == "Acme Bank item error")
        #expect(presentation.recoveryDetailLabel?.contains("Acme Bank") == true)
    }

    @Test("Item error falls back to a generic reconnect when unnamed")
    func errorUnnamed() {
        let presentation = evaluate(itemStatus: .error, institutionName: nil)
        #expect(presentation.recoveryActionTitle == "Reconnect Item")
        #expect(presentation.detailLabel == "Item error")
    }

    @Test("Provider outage is advisory and non-actionable")
    func providerOutage() {
        let presentation = evaluate(itemStatus: .providerOutage, institutionName: "Acme Bank")
        #expect(presentation.level == .stale)
        #expect(!presentation.showsRecoveryActions)
        #expect(presentation.signalLabel == "Outage")
        #expect(presentation.recoveryDetailLabel?.contains("retry automatically") == true)
    }

    @Test("new_accounts_available uses an Update verb; other repairs use Reconnect")
    func repairVerbs() {
        #expect(evaluate(itemStatus: .newAccountsAvailable, institutionName: "Acme Bank").recoveryActionTitle == "Update Acme Bank")
        #expect(evaluate(itemStatus: .newAccountsAvailable, institutionName: nil).recoveryActionTitle == "Update Item")
        #expect(evaluate(itemStatus: .loginRequired, institutionName: "Acme Bank").recoveryActionTitle == "Reconnect Acme Bank")
    }

    @Test("Every repair status maps to a distinct recovery presentation")
    func repairStatuses() {
        let statuses: [ItemConnectionStatus] = [
            .loginRequired, .pendingExpiration, .pendingDisconnect, .permissionRevoked, .newAccountsAvailable,
        ]
        var signals = Set<String>()
        var details = Set<String>()
        for status in statuses {
            let named = evaluate(itemStatus: status, institutionName: "Acme Bank")
            #expect(named.level == .loginRequired)
            #expect(named.showsRecoveryActions)
            #expect(named.recoveryActionTitle?.isEmpty == false)
            #expect(named.recoveryDetailLabel?.contains("Acme Bank") == true)
            signals.insert(named.signalLabel)
            if let detail = named.recoveryDetailLabel { details.insert(detail) }

            let unnamed = evaluate(itemStatus: status, institutionName: nil)
            #expect(unnamed.recoveryDetailLabel?.contains("Acme Bank") == false)
        }
        #expect(signals.count == statuses.count)
        #expect(details.count == statuses.count)
    }

    @Test("A blank institution name is treated as unnamed")
    func blankInstitutionName() {
        #expect(evaluate(itemStatus: .error, institutionName: "   ").recoveryActionTitle == "Reconnect Item")
    }

    @Test("Missing item sync timestamp reads as no sync recorded")
    func itemSyncLabelFallback() {
        let withSync = evaluate(itemStatus: .error, itemLastSyncRelative: "5m ago")
        #expect(withSync.itemSyncLabel == "Last sync 5m ago")
        #expect(withSync.statusFilterSubtitle.contains("Last sync 5m ago"))

        let noSync = evaluate(itemStatus: .error, itemLastSyncRelative: nil)
        #expect(noSync.itemSyncLabel == "No sync recorded")
        #expect(noSync.statusFilterSubtitle.contains("No sync recorded"))
    }
}
