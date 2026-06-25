import AppIntents
import PlaidBarCore

// MARK: - App Intents registration (AND-586, Epic 8)
//
// The finance App Intents themselves — "safe to spend", "show spending", "review
// transactions", "total balance", "next bills", "credit utilization" — now live
// in `PlaidBarCore` (`FinanceAppIntentsPackage.swift`) as an `AppIntentsPackage`,
// so the app, the widget extension, Siri, Spotlight, and Shortcuts all reuse one
// `Sendable` source of truth instead of each target redefining them (AND-586).
//
// AppIntents metadata extraction runs against the *main app target*. This file is
// the app's hook:
//   1. `PlaidBarAppIntentsPackage.includedPackages` pulls Core's package in so the
//      extractor records every shared Core intent against the VaultPeek app.
//   2. `PlaidBarShortcutsProvider` is the single `AppShortcutsProvider` — it lives
//      here (not Core) so it can list both the Core query/navigation intents and
//      the app-only `FinanceDashboardSnippetIntent` (a SwiftUI `SnippetIntent`
//      that can't live in the UI-free Core package).

/// The app's `AppIntentsPackage`. Declaring `includedPackages` here makes the
/// AppIntents extractor walk into Core's package, so the shared finance intents are
/// registered against the app without being duplicated in this target.
struct PlaidBarAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [PlaidBarCoreAppIntentsPackage.self]
    }
}

/// Exposes the finance intents to Spotlight, Siri, and the Shortcuts app. Phrases
/// must include `\(.applicationName)` so Siri can disambiguate VaultPeek. The
/// intents are Core types; the snippet entry is the app-only `SnippetIntent`.
struct PlaidBarShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetSafeToSpendIntent(),
            phrases: [
                "What's safe to spend in \(.applicationName)",
                "How much can I spend in \(.applicationName)",
            ],
            shortTitle: "Safe to Spend",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: ShowSpendingIntent(),
            phrases: [
                "Show my spending in \(.applicationName)",
                "How much have I spent in \(.applicationName)",
            ],
            shortTitle: "Show Spending",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: ReviewTransactionsIntent(),
            phrases: [
                "Review transactions in \(.applicationName)",
                "Open my review inbox in \(.applicationName)",
            ],
            shortTitle: "Review Transactions",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: GetTotalBalanceIntent(),
            phrases: [
                "What's my balance in \(.applicationName)",
                "Show my total balance in \(.applicationName)",
            ],
            shortTitle: "Total Balance",
            systemImageName: "banknote"
        )
        AppShortcut(
            intent: NextRecurringBillsIntent(),
            phrases: [
                "What are my next bills in \(.applicationName)",
                "Show upcoming bills in \(.applicationName)",
            ],
            shortTitle: "Next Bills",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: GetCreditUtilizationIntent(),
            phrases: [
                "What's my credit utilization in \(.applicationName)",
                "Show credit usage in \(.applicationName)",
            ],
            shortTitle: "Credit Utilization",
            systemImageName: "creditcard"
        )
        // Focused rich snippets (AND-637). The package's minimum deployment is
        // macOS 26, so these `@available(macOS 26.0, *)` SnippetIntents are always
        // available here — no #available gate is needed at this call site.
        AppShortcut(
            intent: SafeToSpendSnippetIntent(),
            phrases: [
                "Show my safe to spend snippet in \(.applicationName)",
            ],
            shortTitle: "Safe to Spend Snippet",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: NextBillsSnippetIntent(),
            phrases: [
                "Show my next bills snippet in \(.applicationName)",
            ],
            shortTitle: "Next Bills Snippet",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: CreditUtilizationSnippetIntent(),
            phrases: [
                "Show my credit utilization snippet in \(.applicationName)",
            ],
            shortTitle: "Credit Utilization Snippet",
            systemImageName: "creditcard"
        )
    }
}
