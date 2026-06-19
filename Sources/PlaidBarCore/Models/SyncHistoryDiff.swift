import Foundation

/// Deterministic diff over two `AccountBalanceLedger` snapshots (AND-490). When
/// a sync changes an already-recorded prior-day balance for an account (Plaid
/// modified/removed rewriting history), it emits display-safe rows describing how
/// many prior days changed and the net signed delta. User-facing strings carry
/// only the account display name — never accountId / itemId — matching
/// DashboardChangeReceipt's privacy contract. Pure and Sendable.
public enum SyncHistoryDiff {
    public struct Row: Sendable, Equatable, Identifiable {
        /// Stable, non-PII identity for SwiftUI. Derived from a hash of the
        /// account id, but never surfaced in user-facing text.
        public let id: String
        public let accountDisplayName: String
        public let changedDayCount: Int
        public let netDelta: Double
        public let summary: String
        public let accessibilityText: String

        public init(
            id: String,
            accountDisplayName: String,
            changedDayCount: Int,
            netDelta: Double,
            summary: String,
            accessibilityText: String
        ) {
            self.id = id
            self.accountDisplayName = accountDisplayName
            self.changedDayCount = changedDayCount
            self.netDelta = netDelta
            self.summary = summary
            self.accessibilityText = accessibilityText
        }
    }

    /// Compares `previousLedger` against `nextLedger`. Only prior-day rewrites
    /// count: a purely-additive newer day (a new date not present in the prior
    /// ledger) is not "history changed" and produces no row. The current sync day
    /// (`now`) is excluded entirely: `AccountBalanceLedger.appending` replaces
    /// today's entry in place, so an ordinary same-day balance movement must not
    /// be reported as a "prior day restated" rewrite. `displayName` resolves an
    /// accountId to a privacy-safe display name; when it returns nil, a neutral
    /// "An account" label is used (never the id).
    public static func evaluate(
        previousLedger: AccountBalanceLedger,
        nextLedger: AccountBalanceLedger,
        now: Date = Date(),
        displayName: (String) -> String?
    ) -> [Row] {
        let currentDayKey = AccountBalanceLedger.dayKey(now)

        // Index prior entries by (accountId, dayKey) -> current balance, skipping
        // the current sync day so today's in-place replacement isn't a "rewrite".
        // Use updateValue so an explicit nil prior balance (institutions that
        // previously reported `current == nil`) is preserved as a stored key
        // rather than removed by the subscript — otherwise a later nil→value
        // restatement would look like a brand-new day and be suppressed.
        var priorByKey: [String: Double?] = [:]
        for entry in previousLedger.entries where AccountBalanceLedger.dayKey(entry.date) != currentDayKey {
            priorByKey.updateValue(entry.current, forKey: key(entry.accountId, entry.date))
        }

        // Accumulate per-account rewrite stats.
        struct Accumulator {
            var changedDays = 0
            var netDelta = 0.0
        }
        var perAccount: [String: Accumulator] = [:]
        var accountOrder: [String] = []

        for entry in nextLedger.entries where AccountBalanceLedger.dayKey(entry.date) != currentDayKey {
            let entryKey = key(entry.accountId, entry.date)
            // Only a day that already existed in the prior ledger can be a
            // "history changed" rewrite; a brand-new day is additive, not a diff.
            guard let priorCurrent = priorByKey[entryKey] else { continue }
            guard priorCurrent != entry.current else { continue }

            let delta = (entry.current ?? 0) - (priorCurrent ?? 0)
            if perAccount[entry.accountId] == nil {
                perAccount[entry.accountId] = Accumulator()
                accountOrder.append(entry.accountId)
            }
            perAccount[entry.accountId]?.changedDays += 1
            perAccount[entry.accountId]?.netDelta += delta
        }

        return accountOrder.sorted().compactMap { accountId in
            guard let stats = perAccount[accountId], stats.changedDays > 0 else { return nil }
            let name = displayName(accountId) ?? "An account"
            let deltaText = signedCurrency(stats.netDelta)
            let dayWord = stats.changedDays == 1 ? "day" : "days"
            let summary = "\(name): \(stats.changedDays) prior \(dayWord) restated (\(deltaText))"
            let accessibilityText = "\(name) had \(stats.changedDays) prior \(dayWord) restated by your bank, a net change of \(deltaText)."
            return Row(
                id: StableHash.hexPadded(accountId),
                accountDisplayName: name,
                changedDayCount: stats.changedDays,
                netDelta: stats.netDelta,
                summary: summary,
                accessibilityText: accessibilityText
            )
        }
    }

    /// Replaces every signed currency token baked into a row's summary /
    /// accessibility prose (e.g. "Chase: 1 prior day restated (+$30.00)") with
    /// the Privacy Mask placeholder, leaving the surrounding text intact. These
    /// strings interleave currency with prose, so the per-value `currency(_:)`
    /// mask can't be applied — the call site uses this when masking is on.
    /// No-op when `isEnabled` is false.
    public static func maskCurrencyTokens(in text: String, isEnabled: Bool) -> String {
        guard isEnabled else { return text }
        // Optional leading sign, currency symbol, then a grouped/decimal number:
        // covers "$30.00", "+$1,234.56", "-$0.50".
        let pattern = "[+-]?\\$[0-9][0-9,]*(?:\\.[0-9]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: PrivacyMaskPresentation.compactValue)
        )
    }

    private static func key(_ accountId: String, _ date: Date) -> String {
        "\(accountId)|\(AccountBalanceLedger.dayKey(date))"
    }

    private static func signedCurrency(_ amount: Double) -> String {
        let formatted = Formatters.currency(abs(amount))
        if amount > 0 { return "+\(formatted)" }
        if amount < 0 { return "-\(formatted)" }
        return formatted
    }
}
