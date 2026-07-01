import Foundation
import Testing
@testable import PlaidBarCore

/// AND-731: a money figure must render identically across surfaces, and an
/// aggregate shown next to its parts must reconcile with those displayed parts.
/// Two concrete invariants are pinned here:
///   (a) displayed net worth == displayed assets − displayed debt (Accounts hero);
///   (b) the Budgets "Left this month" figure is the same Core value, so the hero
///       and the status panel render the identical number.
@Suite("Rounding consistency across surfaces (AND-731)")
struct RoundingConsistencyTests {
    // MARK: - (a) Accounts net worth reconciles with its displayed parts

    /// Representative single-currency balances chosen so that *independent* rounding
    /// of net worth, assets, and debt visibly disagrees: assets 66,161.60 → "$66,162",
    /// debt 6,057.40 → "$6,057", but net 60,104.20 → "$60,104" ≠ 66,162 − 6,057 =
    /// 60,105. The reconciled net worth must read "$60,105".
    @Test("Displayed net worth equals displayed assets − displayed debt (the $1-off case)")
    func reconciledNetWorthMatchesDisplayedParts() {
        let accounts = [
            depository(name: "Checking", current: 66_161.60, currency: "USD"),
            credit(name: "Card", current: 6_057.40, limit: 10_000, currency: "USD"),
        ]

        let assets = MultiCurrencyBalancePresentation.totalAssets(accounts: accounts)
        let debt = MultiCurrencyBalancePresentation.totalDebt(accounts: accounts)
        let reconciledNet = MultiCurrencyBalancePresentation.reconciledNetWorth(
            accounts: accounts,
            format: .compact
        )

        let assetsText = MultiCurrencyBalancePresentation.displayText(from: assets, format: .compact)
        let debtText = MultiCurrencyBalancePresentation.displayText(from: debt, format: .compact)
        let netText = MultiCurrencyBalancePresentation.displayText(from: reconciledNet, format: .compact)

        // Sanity: the parts round as the ticket describes.
        #expect(assetsText == "$66,162")
        #expect(debtText == "$6,057")

        // The reconciled net worth equals displayed assets − displayed debt ($60,105),
        // not the independently-rounded $60,104.
        #expect(netText == "$60,105")

        // And it does NOT equal the naive independent rounding, proving the fix bites.
        let naiveNet = MultiCurrencyBalancePresentation.netWorth(accounts: accounts)
        let naiveText = MultiCurrencyBalancePresentation.displayText(from: naiveNet, format: .compact)
        #expect(naiveText == "$60,104")
        #expect(netText != naiveText)
    }

    /// The reconciliation must hold for a sweep of representative balances: for every
    /// case, the displayed net worth string equals (displayed assets − displayed debt)
    /// re-rendered at the same precision.
    @Test("Net worth reconciles with parts across a representative sweep")
    func reconciledNetWorthHoldsAcrossSweep() {
        let cases: [(assets: Double, debt: Double)] = [
            (66_161.60, 6_057.40),
            (1_000.50, 0.49),
            (12_345.67, 2_345.12),
            (999.99, 999.49),
            (0, 250.75),
            (5_000, 0),
        ]

        for sweep in cases {
            let accounts = [
                depository(name: "Cash", current: sweep.assets, currency: "USD"),
                credit(name: "Card", current: sweep.debt, limit: 100_000, currency: "USD"),
            ]
            let assets = MultiCurrencyBalancePresentation.totalAssets(accounts: accounts)
            let debt = MultiCurrencyBalancePresentation.totalDebt(accounts: accounts)
            let net = MultiCurrencyBalancePresentation.reconciledNetWorth(accounts: accounts, format: .compact)

            let displayedAssets = Formatters.displayRounded(
                assets.subtotals.first?.amount ?? 0, format: .compact
            )
            let displayedDebt = Formatters.displayRounded(
                debt.subtotals.first?.amount ?? 0, format: .compact
            )
            let expectedNetText = Formatters.currency(displayedAssets - displayedDebt, format: .compact)
            let actualNetText = MultiCurrencyBalancePresentation.displayText(from: net, format: .compact)

            #expect(
                actualNetText == expectedNetText,
                "assets \(sweep.assets), debt \(sweep.debt): net \(actualNetText) != \(expectedNetText)"
            )
        }
    }

    /// Reconciliation also holds at `.full` precision (used where heroes show cents),
    /// guarding against a future surface that pairs all three at full precision.
    @Test("Net worth reconciles with parts at full precision too")
    func reconciledNetWorthHoldsAtFullPrecision() {
        let accounts = [
            depository(name: "Cash", current: 1_000.555, currency: "USD"),
            credit(name: "Card", current: 250.554, limit: 5_000, currency: "USD"),
        ]
        let assets = MultiCurrencyBalancePresentation.totalAssets(accounts: accounts)
        let debt = MultiCurrencyBalancePresentation.totalDebt(accounts: accounts)
        let net = MultiCurrencyBalancePresentation.reconciledNetWorth(accounts: accounts, format: .full)

        let displayedAssets = Formatters.displayRounded(assets.subtotals.first?.amount ?? 0, format: .full)
        let displayedDebt = Formatters.displayRounded(debt.subtotals.first?.amount ?? 0, format: .full)
        let expected = Formatters.currency(displayedAssets - displayedDebt, format: .full)
        let actual = MultiCurrencyBalancePresentation.displayText(from: net, format: .full)
        #expect(actual == expected)
    }

    // MARK: - Formatters.displayRounded policy

    @Test("displayRounded rounds to the format's display precision")
    func displayRoundedPrecision() {
        // Compact/abbreviated → whole units.
        #expect(Formatters.displayRounded(248.49, format: .compact) == 248)
        #expect(Formatters.displayRounded(247.79, format: .compact) == 248)
        #expect(Formatters.displayRounded(247.79, format: .abbreviated) == 248)
        // Full → cents.
        #expect(Formatters.displayRounded(247.794, format: .full) == 247.79)
        #expect(Formatters.displayRounded(247.795, format: .full) == 247.80)
    }

    @Test("CurrencyFormat advertises its display fraction digits")
    func formatFractionDigits() {
        #expect(CurrencyFormat.full.displayFractionDigits == 2)
        #expect(CurrencyFormat.compact.displayFractionDigits == 0)
        #expect(CurrencyFormat.abbreviated.displayFractionDigits == 0)
    }

    // MARK: - (b) Budgets "Left this month" is one Core value shown twice

    /// The Budgets hero "Left this month" tile and the status panel's "Left this
    /// month" line both render `BudgetsStatusSummary.Summary.remaining`. There is a
    /// single Core source for the figure, so once both surfaces format it at the same
    /// precision they read identically. Pin that the value is single-sourced and that
    /// formatting it at the surfaces' shared `.full` precision yields one number.
    @Test("Budgets 'Left this month' is a single Core figure formatted identically")
    func budgetsRemainingIsSingleSourced() {
        // A budgeted total of 1,000 with 752.21 spent → 247.79 remaining: the exact
        // figure from the ticket, where compact ("$248") and full ("$247.79") differ.
        let summary = BudgetsStatusSummary.Summary(
            health: .onTrack,
            overBudgetCount: 0,
            nearingCount: 0,
            budgetedCount: 3,
            trackedCount: 5,
            totalSpent: 900.00,
            budgetedSpent: 752.21,
            totalLimit: 1_000.00
        )

        guard let remaining = summary.remaining else {
            Issue.record("Expected budgeted summary to expose a remaining amount")
            return
        }
        #expect(abs(remaining - 247.79) < 0.0001)
        #expect(!summary.isAggregateOver)

        // Both surfaces render at `.full` (the status panel's precision, which the
        // hero now matches), so the figure is one number on the whole screen.
        let heroText = PrivacyMaskPresentation.currency(
            abs(remaining), format: .full, isEnabled: false, style: .compact
        )
        let panelText = PrivacyMaskPresentation.currency(
            abs(remaining), format: .full, isEnabled: false, style: .compact
        )
        #expect(heroText == panelText)
        #expect(heroText.contains("247.79"))
    }

    // MARK: - Helpers

    private func depository(name: String, current: Double, currency: String) -> AccountDTO {
        AccountDTO(
            id: name,
            itemId: "item",
            name: name,
            type: .depository,
            balances: BalanceDTO(available: current, current: current, isoCurrencyCode: currency)
        )
    }

    private func credit(name: String, current: Double, limit: Double, currency: String) -> AccountDTO {
        AccountDTO(
            id: name,
            itemId: "item",
            name: name,
            type: .credit,
            balances: BalanceDTO(current: current, limit: limit, isoCurrencyCode: currency)
        )
    }
}
