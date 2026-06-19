import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Item recovery target selection")
struct ItemRecoveryTargetTests {
    private func status(
        _ id: String,
        _ connection: ItemConnectionStatus,
        institution: String? = "Acme Bank"
    ) -> ItemStatus {
        ItemStatus(id: id, institutionName: institution, status: connection)
    }

    // MARK: Selection

    @Test("Error items outrank update-mode items as the recovery target")
    func errorOutranksUpdateMode() {
        let statuses = [
            status("a", .loginRequired),
            status("b", .error),
        ]
        #expect(ItemRecoveryTarget.item(from: statuses)?.id == "b")
        #expect(ItemRecoveryTarget.itemId(from: statuses) == "b")
    }

    @Test("First update-mode item is chosen when nothing is in error")
    func firstUpdateModeChosen() {
        let statuses = [
            status("a", .connected),
            status("b", .pendingExpiration),
            status("c", .permissionRevoked),
        ]
        #expect(ItemRecoveryTarget.itemId(from: statuses) == "b")
    }

    @Test("Healthy / transient-only items expose no recovery target")
    func noTargetForHealthyOrTransient() {
        let statuses = [
            status("a", .connected),
            status("b", .loginRepaired),
            status("c", .providerOutage),
        ]
        #expect(ItemRecoveryTarget.item(from: statuses) == nil)
        #expect(ItemRecoveryTarget.itemId(from: statuses) == nil)
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == nil)
        #expect(ItemRecoveryTarget.recoveryDetail(from: statuses) == nil)
    }

    @Test("Empty input has no target")
    func emptyInput() {
        #expect(ItemRecoveryTarget.itemId(from: []) == nil)
        #expect(ItemRecoveryTarget.actionTitle(from: []) == nil)
        #expect(ItemRecoveryTarget.recoveryDetail(from: []) == nil)
    }

    // MARK: Action titles

    @Test("Action title reconnects a named institution on error")
    func actionTitleReconnectNamed() {
        #expect(ItemRecoveryTarget.actionTitle(from: [status("a", .error)]) == "Reconnect Acme Bank")
    }

    @Test("Action title updates a named institution for new accounts")
    func actionTitleUpdateNamed() {
        #expect(
            ItemRecoveryTarget.actionTitle(from: [status("a", .newAccountsAvailable)]) == "Update Acme Bank"
        )
    }

    @Test("Action title falls back to a generic verb when the institution is unnamed")
    func actionTitleFallback() {
        #expect(ItemRecoveryTarget.actionTitle(from: [status("a", .error, institution: nil)]) == "Reconnect Item")
        #expect(
            ItemRecoveryTarget.actionTitle(from: [status("a", .newAccountsAvailable, institution: nil)]) == "Update Item"
        )
    }

    @Test("Blank institution names are treated as unnamed (trimmed)")
    func blankInstitutionTreatedAsUnnamed() {
        #expect(ItemRecoveryTarget.actionTitle(from: [status("a", .error, institution: "   ")]) == "Reconnect Item")
    }

    // MARK: Recovery detail

    @Test("Each actionable status has distinct named recovery copy")
    func recoveryDetailNamedPerStatus() {
        let actionable: [ItemConnectionStatus] = [
            .loginRequired, .pendingExpiration, .pendingDisconnect,
            .permissionRevoked, .newAccountsAvailable, .error,
        ]
        var seen = Set<String>()
        for connection in actionable {
            let detail = ItemRecoveryTarget.recoveryDetail(from: [status("a", connection)])
            #expect(detail?.isEmpty == false)
            #expect(detail?.contains("Acme Bank") == true)
            if let detail { seen.insert(detail) }
        }
        #expect(seen.count == actionable.count)
    }

    @Test("Recovery detail has an unnamed fallback for each actionable status")
    func recoveryDetailUnnamedPerStatus() {
        let actionable: [ItemConnectionStatus] = [
            .loginRequired, .pendingExpiration, .pendingDisconnect,
            .permissionRevoked, .newAccountsAvailable, .error,
        ]
        for connection in actionable {
            let detail = ItemRecoveryTarget.recoveryDetail(from: [status("a", connection, institution: nil)])
            #expect(detail?.isEmpty == false)
            #expect(detail?.contains("Acme Bank") == false)
        }
    }
}
