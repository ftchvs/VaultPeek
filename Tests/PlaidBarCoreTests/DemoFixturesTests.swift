import Foundation
@testable import PlaidBarCore
import Testing

/// Locks in the demo-fixture continuity contract: the 364-day spending
/// heatmap window has no dead zone, income recurs across the whole year, and
/// every demo account (including savings) has recent activity. All amounts
/// and merchants are synthetic.
@Suite("Demo Fixtures")
struct DemoFixturesTests {
    /// Fixed midday reference date so assertions never depend on the wall
    /// clock or midnight/DST boundaries.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    private var heatmapWindow: (start: Date, end: Date) {
        // Mirrors the dashboard heatmap lookback in MainPopover.
        let end = referenceDate
        let start = Calendar.current.date(byAdding: .day, value: -364, to: end)!
        return (start, end)
    }

    @Test("Heatmap window has no dead zone in either mode")
    func heatmapWindowHasNoDeadZone() {
        let transactions = DemoFixtures.transactions(now: referenceDate)
        let (start, end) = heatmapWindow

        for mode in [SpendingHeatmapMode.spending, .netCashflow] {
            let days = SpendingHeatmap.days(
                from: transactions,
                startDate: start,
                endDate: end,
                mode: mode
            )
            #expect(days.count == 365)

            var longestGap = 0
            var currentGap = 0
            for day in days {
                if day.transactionCount == 0 {
                    currentGap += 1
                    longestGap = max(longestGap, currentGap)
                } else {
                    currentGap = 0
                }
            }

            // A fully blank heatmap week column needs 7 aligned empty days;
            // capping gaps at 6 makes that impossible in any alignment.
            #expect(longestGap <= 6, "longest \(mode) gap was \(longestGap) days")
        }
    }

    @Test("Income recurs in every 30-day bucket across the year")
    func incomeCoversFullYear() {
        let calendar = Calendar.current
        let transactions = DemoFixtures.transactions(now: referenceDate)
        let reference = calendar.startOfDay(for: referenceDate)

        var bucketsWithIncome = Set<Int>()
        for transaction in transactions where transaction.category == .income {
            guard let date = Formatters.parseTransactionDate(transaction.date),
                  let daysAgo = calendar.dateComponents(
                      [.day],
                      from: calendar.startOfDay(for: date),
                      to: reference
                  ).day
            else { continue }
            bucketsWithIncome.insert(daysAgo / 30)
        }

        for bucket in 0..<12 {
            #expect(
                bucketsWithIncome.contains(bucket),
                "no income in days \(bucket * 30)...\(bucket * 30 + 29)"
            )
        }
    }

    @Test("Savings account has two-sided activity in the trailing 30 days")
    func savingsHasRecentTwoSidedActivity() {
        let transactions = DemoFixtures.transactions(now: referenceDate)
        let savings = transactions.filter { $0.accountId == "demo_savings" }
        #expect(!savings.isEmpty)

        // Mirrors the account-detail Changes block: both directions must be
        // non-zero so the savings fly-out never reads $0 in / $0 out.
        let insights = AccountDetailInsights.compute(
            transactions: savings,
            windowDays: 30,
            now: referenceDate
        )
        #expect(insights.incomeTotal > 0)
        #expect(insights.spendTotal > 0)
    }

    @Test("Transaction ids are unique and reference known demo accounts")
    func transactionIdsAndAccountsAreConsistent() {
        let transactions = DemoFixtures.transactions(now: referenceDate)
        let ids = transactions.map(\.id)
        #expect(Set(ids).count == ids.count)

        let accountIds = Set(DemoFixtures.accounts.map(\.id))
        for transaction in transactions {
            #expect(accountIds.contains(transaction.accountId))
        }
    }

    @Test("Fixture net worth matches the account balances")
    func netWorthMatchesAccountBalances() {
        let total = DemoFixtures.accounts.reduce(0.0) { sum, account in
            sum + (account.balances.current ?? account.balances.available ?? 0)
        }
        #expect(abs(total - DemoFixtures.netWorth) < 0.01)
    }

    @Test("Demo account balance histories cover every synthetic account")
    func accountBalanceHistoriesCoverEveryDemoAccount() {
        for account in DemoFixtures.accounts {
            let history = DemoFixtures.accountBalanceHistory(
                forAccountId: account.id,
                now: referenceDate
            )

            #expect(history.count == 60)
            #expect(history == history.sorted { $0.date < $1.date })
            #expect(history.last?.date == referenceDate)
            #expect(abs((history.last?.balance ?? 0) - (account.balances.current ?? account.balances.available ?? 0)) < 0.01)
        }
    }

    @Test("Demo account balance histories are deterministic and unknown ids stay empty")
    func accountBalanceHistoriesAreDeterministic() {
        let first = DemoFixtures.accountBalanceHistory(forAccountId: "demo_checking", now: referenceDate)
        let second = DemoFixtures.accountBalanceHistory(forAccountId: "demo_checking", now: referenceDate)

        #expect(first == second)
        #expect(DemoFixtures.accountBalanceHistory(forAccountId: "accountSecretIdentifier", now: referenceDate).isEmpty)
    }

    /// Demo-F2: the demo data contract is "accounts AND transactions together".
    /// `--demo` (and any code that hydrates from `DemoFixtures`) must never land
    /// in a half-populated state with accounts but no transactions, or vice
    /// versa — a dashboard with accounts but an empty transaction list reads as
    /// broken. Locks both halves non-empty together so a future fixture edit
    /// cannot silently strand one side.
    @Test("Demo fixtures populate accounts and transactions together")
    func demoFixturesPopulateAccountsAndTransactionsTogether() {
        let accounts = DemoFixtures.accounts
        let transactions = DemoFixtures.transactions(now: referenceDate)

        #expect(!accounts.isEmpty, "demo accounts must be populated")
        #expect(!transactions.isEmpty, "demo transactions must be populated")
        // The contract is the conjunction: neither side may be empty while the
        // other is non-empty.
        #expect(
            accounts.isEmpty == transactions.isEmpty,
            "demo accounts and transactions must be populated (or empty) together"
        )
    }
}
