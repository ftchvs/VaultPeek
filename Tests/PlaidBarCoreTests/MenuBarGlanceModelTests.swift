import Foundation
@testable import PlaidBarCore
import Testing

/// The pure menu-bar **glance** contract (ADR-001 §6, AND-616): at most four
/// glance metrics, at most three attention chips, every chip's route, and
/// Privacy-Mask redaction of currency metrics. Testing the assembly here at the
/// Core layer keeps the contract enforceable without launching the SwiftUI app.
@Suite("MenuBarGlanceModel contract")
struct MenuBarGlanceModelTests {
    // MARK: - Helpers

    /// A financial-cockpit attention row (one of the chips that deep-links into a
    /// window destination).
    private func financialRow(id: String, title: String) -> AttentionQueueRow {
        AttentionQueueRow(
            id: id,
            severity: .warning,
            title: title,
            detail: "Detail for \(title)",
            menuBarAttentionText: title
        )
    }

    /// A local-infrastructure row (server / credentials) that keeps its in-place
    /// action and carries no route.
    private func infraRow(id: String, action: DashboardStatusReadinessAction) -> AttentionQueueRow {
        AttentionQueueRow(
            id: id,
            severity: .blocked,
            title: "Infra \(id)",
            detail: "Infra detail",
            action: action
        )
    }

    // MARK: - Metric contract

    @Test("Surfaces net worth and safe-to-spend, plus to-review only when nonzero")
    func metricsSurfaceTheRightSignals() {
        let withReview = MenuBarGlanceModel.make(
            netWorth: 12_450,
            safeToSpend: 800,
            unreviewedCount: 3,
            syncStatusText: "Synced now",
            syncSeverity: .healthy,
            attention: AttentionQueue(rows: []),
            isMasked: false
        )
        #expect(withReview.metrics.map(\.id) == ["net-worth", "safe-to-spend", "to-review"])
        #expect(withReview.metrics.first { $0.id == "to-review" }?.value == "3")
        // Every metric pairs a glyph with its label — meaning is never tint alone.
        #expect(withReview.metrics.allSatisfy { !$0.glyph.isEmpty && !$0.label.isEmpty })

        let noReview = MenuBarGlanceModel.make(
            netWorth: 12_450,
            safeToSpend: 800,
            unreviewedCount: 0,
            syncStatusText: "Synced now",
            syncSeverity: .healthy,
            attention: AttentionQueue(rows: []),
            isMasked: false
        )
        // Nothing to review ⇒ the count metric is omitted, keeping the glance lean.
        #expect(noReview.metrics.map(\.id) == ["net-worth", "safe-to-spend"])
    }

    @Test("Never exceeds the four-metric cap")
    func metricCapHolds() {
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 9,
            syncStatusText: "Synced",
            syncSeverity: .healthy,
            attention: AttentionQueue(rows: []),
            isMasked: false
        )
        #expect(model.metrics.count <= MenuBarGlanceModel.maximumMetricCount)
    }

    @Test("Privacy Mask redacts currency metrics but not the review count")
    func privacyMaskRedactsCurrencyOnly() {
        let model = MenuBarGlanceModel.make(
            netWorth: 12_450,
            safeToSpend: 800,
            unreviewedCount: 4,
            syncStatusText: "Synced",
            syncSeverity: .healthy,
            attention: AttentionQueue(rows: []),
            isMasked: true
        )
        let netWorth = model.metrics.first { $0.id == "net-worth" }
        let safeToSpend = model.metrics.first { $0.id == "safe-to-spend" }
        let toReview = model.metrics.first { $0.id == "to-review" }
        #expect(netWorth?.value == PrivacyMaskPresentation.compactValue)
        #expect(safeToSpend?.value == PrivacyMaskPresentation.compactValue)
        // A count is not a balance, so it stays visible under Privacy Mask.
        #expect(toReview?.value == "4")
    }

    // MARK: - Chip contract

    @Test("Chips never exceed the three-chip cap and mirror the attention rows")
    func chipCapAndMirroring() {
        let rows = [
            financialRow(id: "financial-low-cash", title: "Cash"),
            financialRow(id: "financial-high-utilization", title: "Credit"),
            financialRow(id: "financial-unusual-spending", title: "Spend"),
        ]
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 0,
            syncStatusText: "Synced",
            syncSeverity: .warning,
            attention: AttentionQueue(rows: rows),
            isMasked: false
        )
        #expect(model.chips.count <= MenuBarGlanceModel.maximumChipCount)
        #expect(model.chips.map(\.id) == rows.map(\.id))
        // Each chip carries a shaped severity glyph (never color alone).
        #expect(model.chips.allSatisfy { !$0.glyph.isEmpty })
    }

    @Test("Financial chips deep-link into window destinations")
    func financialChipsDeepLink() {
        let rows = [
            financialRow(id: "financial-low-cash", title: "Cash"),
            financialRow(id: "financial-high-utilization", title: "Credit"),
            financialRow(id: "financial-unusual-spending", title: "Spend"),
        ]
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 0,
            syncStatusText: "Synced",
            syncSeverity: .warning,
            attention: AttentionQueue(rows: rows),
            isMasked: false
        )
        // Every financial chip routes (no inert chip); matches Route.from(attentionRow:).
        let allDeepLink = model.chips.allSatisfy { $0.deepLinks }
        #expect(allDeepLink)
        let byID = Dictionary(uniqueKeysWithValues: model.chips.map { ($0.id, $0) })
        #expect(byID["financial-low-cash"]?.route == .accounts())
        #expect(byID["financial-high-utilization"]?.route == .accounts())
        #expect(byID["financial-unusual-spending"]?.route == .transactions())
    }

    @Test("A degraded-item chip routes to Accounts at the affected item")
    func degradedItemChipRoutesToAccountsItem() {
        let row = AttentionQueueRow(
            id: "item-error-bank42",
            severity: .blocked,
            title: "Reconnect Example Bank",
            detail: "Sign in again to keep balances current.",
            action: .reconnect,
            targetItemId: "bank42"
        )
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 0,
            syncStatusText: "Needs attention",
            syncSeverity: .blocked,
            attention: AttentionQueue(rows: [row]),
            isMasked: false
        )
        let chip = model.chips.first
        #expect(chip?.deepLinks == true)
        #expect(chip?.route == .accounts(itemID: "bank42"))
    }

    @Test("Local-infra chips carry no route and keep their in-place action")
    func infraChipsFallBackToAction() {
        let rows = [
            infraRow(id: "server-offline", action: .checkServer),
            infraRow(id: "credentials-missing", action: .openSettings),
        ]
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 0,
            syncStatusText: "Server offline",
            syncSeverity: .blocked,
            attention: AttentionQueue(rows: rows),
            isMasked: false
        )
        let byID = Dictionary(uniqueKeysWithValues: model.chips.map { ($0.id, $0) })
        #expect(byID["server-offline"]?.route == nil)
        #expect(byID["server-offline"]?.deepLinks == false)
        #expect(byID["server-offline"]?.fallbackAction == .checkServer)
        #expect(byID["credentials-missing"]?.route == nil)
        #expect(byID["credentials-missing"]?.fallbackAction == .openSettings)
    }

    // MARK: - Sync status

    @Test("Sync line carries the supplied text and a shaped severity glyph")
    func syncLineCarriesTextAndGlyph() {
        let model = MenuBarGlanceModel.make(
            netWorth: 1,
            safeToSpend: 1,
            unreviewedCount: 0,
            syncStatusText: "Updated 2m ago",
            syncSeverity: .warning,
            attention: AttentionQueue(rows: []),
            isMasked: false
        )
        #expect(model.syncStatusText == "Updated 2m ago")
        #expect(model.syncStatusGlyph == AttentionQueueSeverity.warning.statusSymbolName)
    }

    // MARK: - Init defends the caps

    @Test("init truncates over-supplied metrics and chips to the contract caps")
    func initDefendsCaps() {
        let chips = (0..<10).map { i in
            MenuBarGlanceModel.Chip(
                id: "c\(i)",
                title: "t",
                detail: "d",
                severity: .warning,
                glyph: "exclamationmark.triangle.fill",
                accessibilityLabel: "a",
                accessibilityHint: nil,
                route: .dashboard,
                fallbackAction: nil
            )
        }
        let metrics = (0..<10).map { i in
            MenuBarGlanceModel.Metric(id: "m\(i)", label: "l", value: "v", glyph: "g")
        }
        let model = MenuBarGlanceModel(
            syncStatusText: "x",
            syncStatusGlyph: "g",
            metrics: metrics,
            chips: chips
        )
        #expect(model.metrics.count == MenuBarGlanceModel.maximumMetricCount)
        #expect(model.chips.count == MenuBarGlanceModel.maximumChipCount)
    }
}
