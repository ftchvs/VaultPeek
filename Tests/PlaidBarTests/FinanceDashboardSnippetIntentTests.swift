import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the app-target finance SnippetIntents (AND-637 / AND-638):
/// `FinanceDashboardSnippetIntent` and the focused AND-637 snippets
/// (`SafeToSpendSnippetIntent`, `NextBillsSnippetIntent`,
/// `CreditUtilizationSnippetIntent`).
///
/// PlaidBar is a `@main` executable target, so it can't be `@testable import`ed
/// (mirroring the note in `PlaidBarTests`). This suite therefore exercises the
/// SnippetIntents two ways:
///   1. **Model → view contract** through the pure `PlaidBarCore` presentation
///      models the views render 1:1 — the masked / nil / populated snapshot cases
///      and the timestamp the snippet footer formats.
///   2. **Source-level invariants** on the intent files: each `perform()` RE-LOADS
///      the snapshot (the SnippetIntent multiple-invocation contract), is gated to
///      macOS 26+, renders through `FinanceSnippetPresentation` /
///      `SnippetDashboardPresentation`, and handles the withheld state — none of
///      which CI can assert by running the GUI executable.
@Suite("Finance SnippetIntents (AND-637 / AND-638)")
struct FinanceDashboardSnippetIntentTests {
    private let asOf = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - perform() model: dashboard snippet (the model FinanceDashboardSnippetIntent renders)

    @Test("Populated snapshot renders the dashboard snippet model the intent shows")
    func dashboardSnippetPopulated() {
        let model = SnippetDashboardPresentation.model(from: populatedSnapshot())
        #expect(!model.isWithheld)
        #expect(model.rows.count == 3)
        // The footer renders `updatedAt`; it must carry the snapshot timestamp.
        #expect(model.updatedAt == asOf)
    }

    @Test("Masked snapshot renders the withheld dashboard snippet — no leaked figure")
    func dashboardSnippetMasked() {
        let model = SnippetDashboardPresentation.model(from: populatedSnapshot(isMasked: true))
        #expect(model.isWithheld)
        for row in model.rows {
            #expect(row.value == PrivacyMaskPresentation.compactValue)
        }
        #expect(!model.accessibilityLabel.contains("8,000"))
    }

    @Test("Nil snapshot renders the dashboard snippet setup state")
    func dashboardSnippetNil() {
        let model = SnippetDashboardPresentation.model(from: nil)
        #expect(model.isWithheld)
        #expect(model.rows.isEmpty)
    }

    // MARK: - perform() model: focused snippets

    @Test("Safe-to-spend snippet model: populated vs masked vs nil")
    func safeToSpendSnippetStates() {
        let populated = FinanceSnippetPresentation.safeToSpend(from: populatedSnapshot(confidence: .ok, horizonEnd: asOf))
        #expect(!populated.isWithheld)
        #expect(populated.confidenceLabel == SafeToSpendConfidence.ok.label)
        #expect(populated.updatedAt == asOf)

        let masked = FinanceSnippetPresentation.safeToSpend(from: populatedSnapshot(isMasked: true))
        #expect(masked.isWithheld)
        #expect(masked.amount == PrivacyMaskPresentation.compactValue)

        let unavailable = FinanceSnippetPresentation.safeToSpend(from: nil)
        #expect(unavailable.withholdReason == .unavailable)
    }

    @Test("Next-bills snippet model: populated vs masked vs nil")
    func nextBillsSnippetStates() {
        let bills = [
            FinanceSnapshot.UpcomingBill(merchantName: "Rent", amount: 1_800, nextExpectedDate: "2026-07-01"),
            FinanceSnapshot.UpcomingBill(merchantName: "Gym", amount: 40, nextExpectedDate: "2026-07-05"),
        ]
        let populated = FinanceSnippetPresentation.nextBills(from: populatedSnapshot(bills: bills))
        #expect(!populated.isWithheld)
        #expect(populated.rows.count == 2)
        #expect(populated.rows.first?.merchantName == "Rent")

        let masked = FinanceSnippetPresentation.nextBills(from: populatedSnapshot(bills: bills, isMasked: true))
        #expect(masked.isWithheld)
        #expect(masked.rows.isEmpty)

        let unavailable = FinanceSnippetPresentation.nextBills(from: nil)
        #expect(unavailable.withholdReason == .unavailable)
    }

    @Test("Credit-utilization snippet model: populated vs masked vs nil")
    func creditUtilizationSnippetStates() {
        let populated = FinanceSnippetPresentation.creditUtilization(from: populatedSnapshot(creditUtilization: 30))
        #expect(!populated.isWithheld)
        #expect(populated.fraction == 0.30)

        let masked = FinanceSnippetPresentation.creditUtilization(from: populatedSnapshot(creditUtilization: 30, isMasked: true))
        #expect(masked.isWithheld)
        #expect(masked.percentText == PrivacyMaskPresentation.compactValue)

        let unavailable = FinanceSnippetPresentation.creditUtilization(from: nil)
        #expect(unavailable.withholdReason == .unavailable)
    }

    // MARK: - Timestamp formatting (the snippet footers render `updatedAt`)

    @Test("Every snippet model surfaces the snapshot timestamp for its footer")
    func snippetModelsCarryTimestamp() {
        let snapshot = populatedSnapshot()
        #expect(FinanceSnippetPresentation.safeToSpend(from: snapshot).updatedAt == asOf)
        #expect(FinanceSnippetPresentation.nextBills(from: snapshot).updatedAt == asOf)
        #expect(FinanceSnippetPresentation.creditUtilization(from: snapshot).updatedAt == asOf)
        #expect(SnippetDashboardPresentation.model(from: snapshot).updatedAt == asOf)
    }

    // MARK: - Source-level invariants on the intent files
    //
    // The app target can't be @testable-imported and CI can't run the SnippetIntent
    // pipeline, so these pin the SnippetIntent contract as source invariants —
    // exactly the pattern PlaidBarTests uses for AccountSpotlightIndexer etc.

    @Test("Each focused SnippetIntent re-loads the snapshot inside perform() and is macOS-26 gated")
    func focusedSnippetIntentsReloadAndGate() throws {
        let source = try snippetIntentsSource()

        // SnippetIntent.perform() may be called multiple times → re-load per call.
        // Each of the three focused intents reads the store inside perform().
        let reloads = source.components(separatedBy: "AppGroupSnapshotStore.loadIfAvailable()").count - 1
        #expect(reloads == 3, "each focused snippet intent must re-load the snapshot in perform()")

        // All three intents + their views are gated to macOS 26 (SnippetIntent's
        // minimum). Six declarations: 3 intents + 3 views, plus shared chrome.
        #expect(source.contains("@available(macOS 26.0, *)"))
        #expect(source.contains("struct SafeToSpendSnippetIntent: SnippetIntent"))
        #expect(source.contains("struct NextBillsSnippetIntent: SnippetIntent"))
        #expect(source.contains("struct CreditUtilizationSnippetIntent: SnippetIntent"))

        // Each renders through the pure presentation, never inline figure math.
        #expect(source.contains("FinanceSnippetPresentation.safeToSpend(from:"))
        #expect(source.contains("FinanceSnippetPresentation.nextBills(from:"))
        #expect(source.contains("FinanceSnippetPresentation.creditUtilization(from:"))

        // Each view handles the withheld affordance.
        let withheldHandling = source.components(separatedBy: "if let reason = model.withholdReason").count - 1
        #expect(withheldHandling == 3, "each snippet view must render the withheld state")
    }

    @Test("Dashboard SnippetIntent re-loads the snapshot inside perform() and is macOS-26 gated")
    func dashboardSnippetIntentReloadsAndGates() throws {
        let source = try dashboardSnippetIntentSource()
        #expect(source.contains("@available(macOS 26.0, *)"))
        #expect(source.contains("struct FinanceDashboardSnippetIntent: SnippetIntent"))
        // Re-loads inside perform() (multiple-invocation contract) and renders the
        // pure SnippetDashboardPresentation model.
        #expect(source.contains("func perform() async throws"))
        #expect(source.contains("SnippetDashboardPresentation.model(from: AppGroupSnapshotStore.loadIfAvailable())"))
    }

    @Test("The focused snippets are registered with the AppShortcutsProvider")
    func focusedSnippetsAreRegistered() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Intents/FinanceAppIntents.swift"),
            encoding: .utf8
        )
        #expect(source.contains("intent: SafeToSpendSnippetIntent()"))
        #expect(source.contains("intent: NextBillsSnippetIntent()"))
        #expect(source.contains("intent: CreditUtilizationSnippetIntent()"))
    }

    // MARK: - Helpers

    private func snippetIntentsSource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Intents/FinanceSnippetIntents.swift"),
            encoding: .utf8
        )
    }

    private func dashboardSnippetIntentSource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Intents/FinanceDashboardSnippetIntent.swift"),
            encoding: .utf8
        )
    }

    private func populatedSnapshot(
        bills: [FinanceSnapshot.UpcomingBill] = [],
        creditUtilization: Double? = 22,
        isMasked: Bool = false,
        confidence: SafeToSpendConfidence? = nil,
        horizonEnd: Date? = nil
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 1_200,
            totalBalance: 8_000,
            accountBalances: [FinanceSnapshot.AccountBalance(displayName: "Checking", balance: 8_000)],
            nextRecurringBills: bills,
            creditUtilization: creditUtilization,
            generatedAt: asOf,
            isMasked: isMasked,
            periodSpending: 540,
            topSpendingCategories: [
                FinanceSnapshot.CategorySpend(category: .foodAndDrink, amount: 320),
                FinanceSnapshot.CategorySpend(category: .shopping, amount: 180),
            ],
            safeToSpendConfidence: confidence,
            safeToSpendHorizonEnd: horizonEnd
        )
    }
}
