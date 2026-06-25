import AppIntents
import Foundation

// MARK: - Finance App Intents package (AND-586, Epic 8)
//
// The macOS 26 `AppIntentsPackage` lets a *library* (here `PlaidBarCore`) export
// App Intents that the app, the widget extension, Siri, Spotlight, and Shortcuts
// all reuse — instead of every target redefining its own. Housing them in Core
// also keeps them `Sendable` and lets their decision logic stay unit-testable via
// `FinanceIntentQueries` / `RouteDeepLink`, which import no AppIntents runtime.
//
// Two kinds of intent live here:
//   1. Query intents (`GetSafeToSpendIntent`, `ShowSpendingIntent`,
//      `GetTotalBalanceIntent`, `GetCreditUtilizationIntent`,
//      `NextRecurringBillsIntent`) — answer from the shared `FinanceSnapshot`
//      without launching the UI. Privacy: a masked snapshot yields `.withheld`,
//      surfaced as a value-free error so Siri never speaks a number past the lock.
//   2. Navigation intents (`ShowSpendingIntent`, `ReviewTransactionsIntent`,
//      `OpenDashboardIntent`) — additionally deep-link into the window via an
//      `OpenURLIntent` carrying a `RouteDeepLink` URL, which the app's `onOpenURL`
//      parses back into a `Route` and feeds to `AppState.route(to:)`.
//
// These supersede the app-target `FinanceAppIntents.swift` definitions: the app's
// `AppShortcutsProvider` now points at these Core intents (single source of
// truth). The widget extension links Core and so reaches the same intents.

// MARK: - Snapshot access

/// Reads the current shared snapshot, or `nil` when none has been written yet.
/// `nonisolated` so it is callable from any intent actor context; the store is a
/// stateless enum performing a single atomic file read.
private func currentFinanceSnapshot() -> FinanceSnapshot? {
    AppGroupSnapshotStore.loadIfAvailable()
}

// MARK: - Result mapping

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
        // Throw `unavailable` rather than returning a fabricated 0: Shortcuts
        // automations would otherwise see a real-looking 0% / $0 and act on it.
        throw FinanceAppIntentError.unavailable(text)
    case let .withheld(spokenDialog):
        throw FinanceAppIntentError.locked(spokenDialog)
    case let .unavailable(spokenDialog):
        throw FinanceAppIntentError.unavailable(spokenDialog)
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
        throw FinanceAppIntentError.locked(spokenDialog)
    case let .unavailable(spokenDialog):
        throw FinanceAppIntentError.unavailable(spokenDialog)
    }
}

/// User-facing intent errors. `CustomLocalizedStringResourceConvertible` lets Siri
/// speak the safe message for the locked / unavailable states.
public enum FinanceAppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case locked(String)
    case unavailable(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .locked(message), let .unavailable(message):
            return LocalizedStringResource(stringLiteral: message)
        }
    }
}

/// Builds the `OpenURLIntent` that deep-links the window to a destination via the
/// shared `RouteDeepLink` contract. The URL is a compile-time-safe string; the
/// fallback only satisfies the non-optional initializer and is unreachable.
private func openRouteIntent(_ destination: RouteDestination) -> OpenURLIntent {
    OpenURLIntent(RouteDeepLink.url(for: destination) ?? URL(fileURLWithPath: "/"))
}

// MARK: - Query intents

/// "What's safe to spend" — answers from the snapshot without launching the UI.
public struct GetSafeToSpendIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Safe to Spend"
    public static let description = IntentDescription(
        "How much you can safely spend through the current window, from local VaultPeek data."
    )
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.safeToSpend(from: currentFinanceSnapshot()))
    }
}

/// "What's my balance" — total spendable balance across linked accounts.
public struct GetTotalBalanceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Total Balance"
    public static let description = IntentDescription(
        "Your total spendable balance across linked accounts, from local VaultPeek data."
    )
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.totalBalance(from: currentFinanceSnapshot()))
    }
}

/// "What are my next bills" — upcoming recurring obligations, spoken as a list.
public struct NextRecurringBillsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Recurring Bills"
    public static let description = IntentDescription(
        "Your upcoming recurring bills, from local VaultPeek data."
    )
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try messageResult(from: FinanceIntentQueries.nextRecurringBills(from: currentFinanceSnapshot()))
    }
}

/// "What's my credit utilization" — aggregate credit-card utilization percent.
public struct GetCreditUtilizationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Credit Utilization"
    public static let description = IntentDescription(
        "Your aggregate credit-card utilization percentage, from local VaultPeek data."
    )
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try valueResult(from: FinanceIntentQueries.creditUtilization(from: currentFinanceSnapshot()))
    }
}

// MARK: - Navigation intents

/// "Show spending" — speaks this period's spend + top categories AND opens the
/// window on the Budgets destination so the user can dig in. Returns the period
/// total so a Shortcut can chain on the number.
public struct ShowSpendingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Spending"
    public static let description = IntentDescription(
        "Show how much you've spent this period and open VaultPeek to your budgets."
    )
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & OpensIntent {
        let resolution = FinanceIntentQueries.showSpending(from: currentFinanceSnapshot())
        switch resolution {
        case let .value(value, spokenDialog):
            return .result(
                value: value,
                opensIntent: openRouteIntent(.budgets),
                dialog: IntentDialog(stringLiteral: spokenDialog)
            )
        case let .message(text):
            throw FinanceAppIntentError.unavailable(text)
        case let .withheld(spokenDialog):
            throw FinanceAppIntentError.locked(spokenDialog)
        case let .unavailable(spokenDialog):
            throw FinanceAppIntentError.unavailable(spokenDialog)
        }
    }
}

/// "Review transactions" — opens the window straight to the Review inbox. Pure
/// navigation; no figure is read, so it works even while masked.
public struct ReviewTransactionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Review Transactions"
    public static let description = IntentDescription(
        "Open VaultPeek to review and categorize recent transactions."
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: openRouteIntent(.review))
    }
}

/// "Open VaultPeek" — opens the window on the Dashboard. The neutral entry point
/// also used by the glance widget / Control Center deep links.
public struct OpenDashboardIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Dashboard"
    public static let description = IntentDescription("Open VaultPeek to your dashboard.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: openRouteIntent(.dashboard))
    }
}

// MARK: - AppIntentsPackage

/// The `AppIntentsPackage` that exports this library's intents so the app and the
/// widget extension can both declare `static var includedPackages` pointing here,
/// extracting the metadata once from Core instead of redefining intents per target
/// (AND-586). The app target adds its UI-bound `SnippetIntent` on top of this.
public struct PlaidBarCoreAppIntentsPackage: AppIntentsPackage {}
