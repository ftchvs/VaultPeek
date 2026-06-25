import Foundation
import Testing
@testable import PlaidBarCore

/// Intent-layer tests for the finance App Intents package (AND-638): the
/// value/dialog mapping the intents surface, the value-free error contract for the
/// locked / unavailable states, the deep-link URLs the navigation intents open, and
/// the pure ``FinanceSnippetPresentation`` models the AND-637 SnippetIntents render.
///
/// The intents themselves (`GetSafeToSpendIntent` …) are thin shells that load the
/// shared snapshot and map a ``FinanceIntentResolution`` into an AppIntents result;
/// driving their `perform()` would read the process-global App Group store (real
/// `~/.vaultpeek/` on a dev machine), so these pin the deterministic, injectable
/// logic those shells delegate to instead.
@Suite("Finance App Intents package (AND-637 / AND-638)")
struct FinanceAppIntentsPackageTests {
    private let asOf = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - Value / dialog mapping (what the value intents return)

    @Test("Safe-to-spend value intent surfaces the value and a spoken dialog")
    func safeToSpendValueAndDialog() {
        guard case let .value(value, dialog) = FinanceIntentQueries.safeToSpend(from: snapshot(safeToSpend: 1_500)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 1_500)
        #expect(dialog.contains("safe to spend"))
    }

    @Test("Total-balance value intent surfaces the value")
    func totalBalanceValue() {
        guard case let .value(value, _) = FinanceIntentQueries.totalBalance(from: snapshot(totalBalance: 8_400)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 8_400)
    }

    @Test("Credit-utilization value intent surfaces the percent")
    func creditUtilizationValue() {
        guard case let .value(value, dialog) = FinanceIntentQueries.creditUtilization(from: snapshot(creditUtilization: 42)) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 42)
        #expect(dialog.contains("utilization"))
    }

    @Test("Bills message intent reads a dialog-only list")
    func billsMessage() {
        let bills = [FinanceSnapshot.UpcomingBill(merchantName: "Rent", amount: 1_800, nextExpectedDate: "2026-07-01")]
        guard case let .message(text) = FinanceIntentQueries.nextRecurringBills(from: snapshot(bills: bills)) else {
            Issue.record("Expected .message")
            return
        }
        #expect(text.contains("Rent"))
    }

    // MARK: - Error throwing (.locked / .unavailable)
    //
    // `FinanceAppIntentsPackage.valueResult`/`messageResult` map a withheld
    // resolution to `FinanceAppIntentError.locked` and an unavailable one to
    // `.unavailable`, throwing rather than returning a fabricated value. These pin
    // the error contract those throws rely on: the spoken resource is the safe,
    // value-free sentence.

    @Test("locked error carries the resolution's value-free dialog")
    func lockedErrorIsValueFree() {
        guard case let .withheld(dialog) = FinanceIntentQueries.safeToSpend(from: snapshot(safeToSpend: 4_321, isMasked: true)) else {
            Issue.record("Expected .withheld for a masked snapshot")
            return
        }
        let error = FinanceAppIntentError.locked(dialog)
        let spoken = String(localized: error.localizedStringResource)
        #expect(spoken == dialog)
        #expect(!spoken.contains("4,321"))
        #expect(!spoken.contains("4321"))
    }

    @Test("unavailable error carries the resolution's setup dialog")
    func unavailableErrorCarriesSetupDialog() {
        guard case let .unavailable(dialog) = FinanceIntentQueries.totalBalance(from: nil) else {
            Issue.record("Expected .unavailable for a nil snapshot")
            return
        }
        let error = FinanceAppIntentError.unavailable(dialog)
        let spoken = String(localized: error.localizedStringResource)
        #expect(spoken == dialog)
        #expect(spoken.lowercased().contains("vaultpeek"))
    }

    @Test("A masked snapshot withholds every value query the intents map")
    func maskedWithholdsEveryValueQuery() {
        let masked = snapshot(isMasked: true)
        for resolution in [
            FinanceIntentQueries.safeToSpend(from: masked),
            FinanceIntentQueries.totalBalance(from: masked),
            FinanceIntentQueries.creditUtilization(from: masked),
        ] {
            guard case .withheld = resolution else {
                Issue.record("Expected .withheld, got \(resolution)")
                continue
            }
        }
    }

    @Test("Snapshot-reading finance intents require local device authentication")
    func snapshotReadingFinanceIntentsRequireLocalDeviceAuthentication() throws {
        let source = try financeAppIntentsPackageSource()
        for intentName in [
            "GetSafeToSpendIntent",
            "GetTotalBalanceIntent",
            "NextRecurringBillsIntent",
            "GetCreditUtilizationIntent",
            "ShowSpendingIntent",
        ] {
            let block = try #require(intentBlock(named: intentName, in: source))
            #expect(
                block.contains("public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication"),
                "\(intentName) reads the shared finance snapshot and must not run while the local device is locked"
            )
        }
    }

    // MARK: - Deep-link URL building (openRouteIntent)
    //
    // The navigation intents open the window via `openRouteIntent(_:)`, which wraps
    // `RouteDeepLink.url(for:)`. These pin that every destination the intents open
    // forms the expected, non-nil `vaultpeek://route/<dest>` URL.

    @Test("Every navigation destination the intents open builds a non-nil deep link")
    func navigationDestinationsBuildDeepLinks() throws {
        for destination in [RouteDestination.budgets, .review, .dashboard] {
            let url = try #require(RouteDeepLink.url(for: destination))
            #expect(url.scheme == RouteDeepLink.scheme)
            #expect(url.absoluteString == "vaultpeek://route/\(destination.rawValue)")
            // Round-trips back to the destination's canonical route.
            #expect(RouteDeepLink.route(from: url) == Route.canonical(for: destination))
        }
    }

    @Test("Show-spending opens the budgets destination and returns the period total")
    func showSpendingOpensBudgetsWithTotal() throws {
        let categories = [FinanceSnapshot.CategorySpend(category: .foodAndDrink, amount: 320)]
        guard case let .value(value, _) = FinanceIntentQueries.showSpending(
            from: snapshot(periodSpending: 500, categories: categories)
        ) else {
            Issue.record("Expected .value")
            return
        }
        #expect(value == 500)
        // The intent maps this value to opening `.budgets`.
        let url = try #require(RouteDeepLink.url(for: .budgets))
        #expect(RouteDeepLink.route(from: url) == .budgets())
    }

    // MARK: - Snippet presentation: safe to spend (AND-637)

    @Test("Safe-to-spend snippet shows amount, confidence cue, and horizon")
    func safeToSpendSnippetPopulated() {
        let model = FinanceSnippetPresentation.safeToSpend(from: snapshot(
            safeToSpend: 1_200,
            confidence: .ok,
            horizonEnd: asOf
        ))
        #expect(!model.isWithheld)
        #expect(!model.isOverBudget)
        #expect(model.confidenceLabel == SafeToSpendConfidence.ok.label)
        #expect(model.confidenceSystemImage == SafeToSpendConfidence.ok.iconName)
        #expect(model.horizonLabel?.hasPrefix("through ") == true)
        #expect(!model.amount.isEmpty)
    }

    @Test("Negative safe-to-spend flags over budget without leaking via the placeholder")
    func safeToSpendSnippetOverBudget() {
        let model = FinanceSnippetPresentation.safeToSpend(from: snapshot(safeToSpend: -250))
        #expect(model.isOverBudget)
        #expect(model.amount != PrivacyMaskPresentation.compactValue)
        #expect(model.accessibilityLabel.lowercased().contains("over budget"))
    }

    @Test("Masked safe-to-spend snippet withholds the figure with the dot placeholder")
    func safeToSpendSnippetMasked() {
        let model = FinanceSnippetPresentation.safeToSpend(from: snapshot(safeToSpend: 9_999, isMasked: true))
        #expect(model.isWithheld)
        #expect(model.withholdReason == .masked)
        #expect(model.amount == PrivacyMaskPresentation.compactValue)
        #expect(model.confidenceLabel == nil)
        #expect(model.horizonLabel == nil)
        #expect(!model.accessibilityLabel.contains("9,999"))
        #expect(!model.accessibilityLabel.contains("9999"))
    }

    @Test("Nil snapshot drives the safe-to-spend setup affordance")
    func safeToSpendSnippetUnavailable() {
        let model = FinanceSnippetPresentation.safeToSpend(from: nil)
        #expect(model.isWithheld)
        #expect(model.withholdReason == .unavailable)
    }

    @Test("A pre-AND-637 snapshot (no confidence/horizon) simply omits the cue")
    func safeToSpendSnippetWithoutConfidence() {
        let model = FinanceSnippetPresentation.safeToSpend(from: snapshot(safeToSpend: 800))
        #expect(!model.isWithheld)
        #expect(model.confidenceLabel == nil)
        #expect(model.horizonLabel == nil)
    }

    // MARK: - Snippet presentation: next bills (AND-637)

    @Test("Next-bills snippet lists up to the cap and summarizes the remainder")
    func nextBillsSnippetCapAndRemainder() {
        let bills = (0..<5).map { index in
            FinanceSnapshot.UpcomingBill(
                merchantName: "Bill\(index)",
                amount: Double(index + 1),
                nextExpectedDate: "2026-07-0\(index + 1)"
            )
        }
        let model = FinanceSnippetPresentation.nextBills(from: snapshot(bills: bills))
        #expect(!model.isWithheld)
        #expect(model.rows.count == FinanceSnippetPresentation.maxBills)
        #expect(model.remainderCount == 5 - FinanceSnippetPresentation.maxBills)
        #expect(model.accessibilityLabel.contains("2 more"))
    }

    @Test("Next-bills snippet with no bills shows the no-bills state, not setup")
    func nextBillsSnippetEmpty() {
        let model = FinanceSnippetPresentation.nextBills(from: snapshot(bills: []))
        #expect(!model.isWithheld)
        #expect(model.rows.isEmpty)
        #expect(model.remainderCount == 0)
        #expect(model.headline.lowercased().contains("no upcoming bills"))
    }

    @Test("Masked next-bills snippet withholds every row")
    func nextBillsSnippetMasked() {
        let bills = [FinanceSnapshot.UpcomingBill(merchantName: "Rent", amount: 1_800, nextExpectedDate: "2026-07-01")]
        let model = FinanceSnippetPresentation.nextBills(from: snapshot(bills: bills, isMasked: true))
        #expect(model.isWithheld)
        #expect(model.rows.isEmpty)
        #expect(!model.accessibilityLabel.contains("Rent"))
        #expect(!model.accessibilityLabel.contains("1,800"))
    }

    // MARK: - Snippet presentation: credit utilization gauge (AND-637)

    @Test("Credit-utilization snippet drives a clamped gauge fraction")
    func creditUtilizationSnippetGauge() {
        let model = FinanceSnippetPresentation.creditUtilization(from: snapshot(creditUtilization: 42))
        #expect(!model.isWithheld)
        #expect(model.fraction == 0.42)
        #expect(model.percentText.contains("42"))
        #expect(model.noLimitMessage == nil)
    }

    @Test("Utilization at or above the warning threshold flags high with a non-colour cue")
    func creditUtilizationSnippetHigh() {
        let threshold = PlaidBarConstants.creditUtilizationWarningThreshold
        let model = FinanceSnippetPresentation.creditUtilization(from: snapshot(creditUtilization: threshold + 5))
        #expect(model.isHigh)
        #expect(model.accessibilityLabel.lowercased().contains("high"))
    }

    @Test("Utilization over 100% clamps the gauge fraction to 1")
    func creditUtilizationSnippetClampsAbove100() {
        let model = FinanceSnippetPresentation.creditUtilization(from: snapshot(creditUtilization: 130))
        #expect(model.fraction == 1.0)
    }

    @Test("No credit limit shows a real no-data message, distinct from masked/setup")
    func creditUtilizationSnippetNoLimit() {
        let model = FinanceSnippetPresentation.creditUtilization(from: snapshot(creditUtilization: nil))
        #expect(!model.isWithheld)
        #expect(model.fraction == nil)
        #expect(model.noLimitMessage != nil)
    }

    @Test("Masked credit-utilization snippet withholds the percent with the dot placeholder")
    func creditUtilizationSnippetMasked() {
        let model = FinanceSnippetPresentation.creditUtilization(from: snapshot(creditUtilization: 88, isMasked: true))
        #expect(model.isWithheld)
        #expect(model.withholdReason == .masked)
        #expect(model.percentText == PrivacyMaskPresentation.compactValue)
        #expect(model.fraction == nil)
        #expect(!model.accessibilityLabel.contains("88"))
    }

    // MARK: - Helpers

    private func snapshot(
        safeToSpend: Double = 1_000,
        totalBalance: Double = 5_000,
        bills: [FinanceSnapshot.UpcomingBill] = [],
        creditUtilization: Double? = 20,
        isMasked: Bool = false,
        periodSpending: Double = 0,
        categories: [FinanceSnapshot.CategorySpend] = [],
        confidence: SafeToSpendConfidence? = nil,
        horizonEnd: Date? = nil
    ) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: safeToSpend,
            totalBalance: totalBalance,
            accountBalances: [
                FinanceSnapshot.AccountBalance(displayName: "Checking", balance: totalBalance),
            ],
            nextRecurringBills: bills,
            creditUtilization: creditUtilization,
            generatedAt: asOf,
            isMasked: isMasked,
            periodSpending: periodSpending,
            topSpendingCategories: categories,
            safeToSpendConfidence: confidence,
            safeToSpendHorizonEnd: horizonEnd
        )
    }

    private func financeAppIntentsPackageSource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(
            contentsOf: root.appending(path: "Sources/PlaidBarCore/AppIntents/FinanceAppIntentsPackage.swift"),
            encoding: .utf8
        )
    }

    private func intentBlock(named intentName: String, in source: String) -> String? {
        guard let start = source.range(of: "public struct \(intentName): AppIntent")?.lowerBound else {
            return nil
        }
        let rest = source[start...]
        let end = rest.dropFirst().range(of: "\npublic struct ")?.lowerBound ?? source.endIndex
        return String(source[start..<end])
    }
}
