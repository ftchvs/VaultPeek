import PlaidBarCore
import SwiftUI

/// Balance Time Machine (AND-490): a compact "what the bank said" list of the
/// latest per-account bank-reported balances, plus a "history changed" badge when
/// a sync restated prior-day numbers. Presentation-only — the ledger and diff
/// logic live in `AccountBalanceLedger` / `SyncHistoryDiff` (Core). User-facing
/// text shows account display names only, never accountId / itemId.
struct BalanceTimeMachineView: View {
    @Environment(AppState.self) private var appState

    /// Latest per-account ledger rows, intersected with currently-linked
    /// accounts. After an institution is disconnected, `removeAccount` prunes the
    /// account but not the ledger, so an un-filtered list would keep showing the
    /// removed account's last balance under the fallback "Account" name.
    private var latestEntries: [AccountBalanceLedger.LedgerEntry] {
        let activeIds = Set(appState.accounts.map(\.id))
        return appState.accountBalanceLedger
            .latestEntriesByAccount()
            .filter { activeIds.contains($0.accountId) }
    }

    private var diffRows: [SyncHistoryDiff.Row] {
        appState.syncHistoryDiffRows
    }

    private var privacyMaskEnabled: Bool {
        appState.shouldMaskFinancialValues
    }

    private func displayName(for accountId: String) -> String {
        appState.accounts.first { $0.id == accountId }?.name ?? "Account"
    }

    /// Bank-reported balance for a row, masked to `••••` when Privacy Mask / the
    /// app-lock display mode hides financial values.
    private func balanceText(for entry: AccountBalanceLedger.LedgerEntry) -> String {
        PrivacyMaskPresentation.currency(
            entry.current ?? entry.available ?? 0,
            isEnabled: privacyMaskEnabled
        )
    }

    /// History-changed rows carry a signed currency delta baked into their
    /// summary / accessibility prose (Core-produced). Mask those amounts when
    /// Privacy Mask is on so the strip never leaks figures the rest of the UI
    /// hides. No-op when masking is off.
    private func maskedDelta(_ text: String) -> String {
        SyncHistoryDiff.maskCurrencyTokens(in: text, isEnabled: privacyMaskEnabled)
    }

    var body: some View {
        let entries = latestEntries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("What the bank said")
                        .sectionTitle()
                        .foregroundStyle(.secondary)
                }

                ForEach(entries) { entry in
                    HStack(spacing: 6) {
                        Text(displayName(for: entry.accountId))
                            .microText()
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(balanceText(for: entry))
                            .microText()
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Formatters.displayDate(entry.date))
                            .microText()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(displayName(for: entry.accountId)) reported \(balanceText(for: entry)) as of \(Formatters.displayDate(entry.date))."
                    )
                }

                ForEach(diffRows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(maskedDelta(row.summary))
                            .microText()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .help(maskedDelta(row.accessibilityText))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(maskedDelta(row.accessibilityText))
                }
            }
            .padding(Spacing.sm)
            .glassSurface(.inset)
        }
    }
}
