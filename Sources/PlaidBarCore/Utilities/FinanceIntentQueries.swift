import Foundation

/// The outcome of answering a finance App Intent from the shared snapshot.
///
/// App Intents in the app target are thin shells: they load the snapshot and ask
/// one of the ``FinanceIntentQueries`` helpers for a `Resolution`, then translate
/// it into an AppIntents `IntentResult`. Keeping the decision logic here makes the
/// masked/withheld/unavailable behavior (AND-512, D3) fully unit-testable without
/// the AppIntents runtime.
public enum FinanceIntentResolution: Sendable, Equatable {
    /// A numeric answer is available. `value` is the raw figure (for a
    /// `ReturnsValue` intent); `spokenDialog` is the natural-language sentence
    /// for Siri/Spotlight.
    case value(Double, spokenDialog: String)
    /// A non-numeric textual answer (e.g. a bills list, or "no upcoming bills").
    case message(String)
    /// Privacy Mask / App Lock is active — withhold the figure. `spokenDialog`
    /// is a safe, value-free sentence.
    case withheld(spokenDialog: String)
    /// No snapshot has been produced yet (first run / post-reset). Prompts setup.
    case unavailable(spokenDialog: String)
}

/// Pure helpers that turn a ``FinanceSnapshot`` (or its absence) into a
/// ``FinanceIntentResolution`` for each finance App Intent. No AppIntents import,
/// no `Date()` side effects beyond formatting, fully testable.
public enum FinanceIntentQueries {
    static let lockedDialog = "Your finances are locked. Unlock VaultPeek to see this."
    static let unavailableDialog = "VaultPeek hasn't synced yet. Open VaultPeek to get started."

    /// Guard shared by every query: returns a non-`value` resolution when the
    /// snapshot is missing or masked, otherwise `nil` to proceed.
    private static func gate(_ snapshot: FinanceSnapshot?) -> FinanceIntentResolution? {
        guard let snapshot else {
            return .unavailable(spokenDialog: unavailableDialog)
        }
        if snapshot.isMasked {
            return .withheld(spokenDialog: lockedDialog)
        }
        if snapshot.isEmpty {
            return .unavailable(spokenDialog: unavailableDialog)
        }
        return nil
    }

    // MARK: - Safe to spend

    public static func safeToSpend(from snapshot: FinanceSnapshot?) -> FinanceIntentResolution {
        if let blocked = gate(snapshot) { return blocked }
        guard let snapshot else { return .unavailable(spokenDialog: unavailableDialog) }
        let amount = snapshot.safeToSpend
        let formatted = Formatters.currency(amount, format: .full, currencyCode: snapshot.isoCurrencyCode)
        let dialog: String = amount < 0
            ? "You're over budget by \(Formatters.currency(abs(amount), format: .full, currencyCode: snapshot.isoCurrencyCode))."
            : "You have \(formatted) safe to spend."
        return .value(amount, spokenDialog: dialog)
    }

    // MARK: - Total balance

    public static func totalBalance(from snapshot: FinanceSnapshot?) -> FinanceIntentResolution {
        if let blocked = gate(snapshot) { return blocked }
        guard let snapshot else { return .unavailable(spokenDialog: unavailableDialog) }
        let amount = snapshot.totalBalance
        let formatted = Formatters.currency(amount, format: .full, currencyCode: snapshot.isoCurrencyCode)
        return .value(amount, spokenDialog: "Your total balance is \(formatted).")
    }

    // MARK: - Next recurring bills

    /// How many upcoming bills to read aloud before summarizing the remainder.
    public static let maxSpokenBills = 3

    public static func nextRecurringBills(from snapshot: FinanceSnapshot?) -> FinanceIntentResolution {
        if let blocked = gate(snapshot) { return blocked }
        guard let snapshot else { return .unavailable(spokenDialog: unavailableDialog) }

        let bills = snapshot.nextRecurringBills
        guard !bills.isEmpty else {
            return .message("No upcoming bills in your tracked window.")
        }

        let spoken = bills.prefix(maxSpokenBills).map { bill in
            "\(bill.merchantName) for \(Formatters.currency(bill.amount, format: .full, currencyCode: snapshot.isoCurrencyCode)) on \(Formatters.displayTransactionDate(bill.nextExpectedDate))"
        }
        var sentence = "Coming up: " + listSentence(spoken) + "."
        let remainder = bills.count - min(bills.count, maxSpokenBills)
        if remainder > 0 {
            sentence += " Plus \(remainder) more."
        }
        return .message(sentence)
    }

    // MARK: - Credit utilization

    public static func creditUtilization(from snapshot: FinanceSnapshot?) -> FinanceIntentResolution {
        if let blocked = gate(snapshot) { return blocked }
        guard let snapshot else { return .unavailable(spokenDialog: unavailableDialog) }

        guard let percent = snapshot.creditUtilization else {
            return .message("No credit cards with a known limit are linked.")
        }
        let formatted = Formatters.percent(percent)
        return .value(percent, spokenDialog: "Your credit utilization is \(formatted).")
    }

    // MARK: - Formatting helpers

    /// Joins items into a spoken list: "a", "a and b", "a, b, and c".
    private static func listSentence(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items[items.count - 1])"
        }
    }
}
