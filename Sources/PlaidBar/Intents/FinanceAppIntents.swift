import AppIntents
import PlaidBarCore

// MARK: - Finance App Intents (AND-512, Epic D)
//
// These intents are the macOS 26 "Tahoe spine": Spotlight / Siri / Shortcuts can
// answer finance questions straight from the shared App Group snapshot
// (`FinanceSnapshot`) without launching the UI, hitting the local server, or
// touching Plaid. They are deliberately thin — every numeric/textual decision and
// the privacy/withholding rule lives in `FinanceIntentQueries` (PlaidBarCore), so
// it is unit-tested without the AppIntents runtime.
//
// Privacy (D3): when the snapshot is masked (App Lock / Privacy Mask active) the
// query returns `.withheld`, and the intent surfaces a value-free dialog instead
// of leaking the figure.

/// Reads the current shared snapshot, or `nil` when none has been written yet.
@MainActor
private func currentFinanceSnapshot() -> FinanceSnapshot? {
    AppGroupSnapshotStore.loadIfAvailable()
}

/// Maps a value-bearing ``FinanceIntentResolution`` to an AppIntents result, or
/// throws a user-facing error for the withheld / unavailable cases so Siri reads
/// the safe dialog without a number.
private func valueResult(
    from resolution: FinanceIntentResolution
) throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
    switch resolution {
    case let .value(value, spokenDialog):
        return .result(value: value, dialog: IntentDialog(stringLiteral: spokenDialog))
    case let .message(text):
        // A value intent received a non-numeric answer (e.g. "no credit cards").
        // Surface it as dialog with a zero value rather than failing.
        return .result(value: 0, dialog: IntentDialog(stringLiteral: text))
    case let .withheld(spokenDialog):
        throw FinanceIntentError.locked(spokenDialog)
    case let .unavailable(spokenDialog):
        throw FinanceIntentError.unavailable(spokenDialog)
    }
}

/// Maps a textual ``FinanceIntentResolution`` (bills list) to a dialog-only
/// result, throwing for withheld / unavailable.
private func messageResult(
    from resolution: FinanceIntentResolution
) throws -> some IntentResult & ProvidesDialog {
    switch resolution {
    case let .value(_, spokenDialog):
        return .result(dialog: IntentDialog(stringLiteral: spokenDialog))
    case let .message(text):
        return .result(dialog: IntentDialog(stringLiteral: text))
    case let .withheld(spokenDialog):
        throw FinanceIntentError.locked(spokenDialog)
    case let .unavailable(spokenDialog):
        throw FinanceIntentError.unavailable(spokenDialog)
    }
}

/// User-facing intent errors. `CustomLocalizedStringResourceConvertible` lets Siri
/// speak the safe message for the locked / unavailable states.
enum FinanceIntentError: Error, CustomLocalizedStringResourceConvertible {
    case locked(String)
    case unavailable(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .locked(message), let .unavailable(message):
            return LocalizedStringResource(stringLiteral: message)
        }
    }
}

// MARK: - Get Safe to Spend

struct GetSafeToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Safe to Spend"
    static let description = IntentDescription(
        "How much you can safely spend through the current window, from local VaultPeek data."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.safeToSpend(from: currentFinanceSnapshot()))
    }
}

// MARK: - Get Balance

struct GetBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Total Balance"
    static let description = IntentDescription(
        "Your total spendable balance across linked accounts, from local VaultPeek data."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.totalBalance(from: currentFinanceSnapshot()))
    }
}

// MARK: - Next Recurring Bills

struct NextRecurringBillsIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Recurring Bills"
    static let description = IntentDescription(
        "Your upcoming recurring bills, from local VaultPeek data."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try messageResult(from: FinanceIntentQueries.nextRecurringBills(from: currentFinanceSnapshot()))
    }
}

// MARK: - Get Credit Utilization

struct GetCreditUtilizationIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Credit Utilization"
    static let description = IntentDescription(
        "Your aggregate credit-card utilization percentage, from local VaultPeek data."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.creditUtilization(from: currentFinanceSnapshot()))
    }
}

// MARK: - App Shortcuts

/// Exposes the finance intents to Spotlight, Siri, and the Shortcuts app. Phrases
/// must include `\(.applicationName)` so Siri can disambiguate VaultPeek.
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
            intent: GetBalanceIntent(),
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
    }
}
