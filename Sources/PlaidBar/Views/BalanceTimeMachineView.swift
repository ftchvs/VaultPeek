import PlaidBarCore
import SwiftUI

/// Balance Time Machine (AND-490): a compact "what the bank said" list of the
/// latest per-account bank-reported balances, plus a "history changed" badge when
/// a sync restated prior-day numbers. Presentation-only — the ledger and diff
/// logic live in `AccountBalanceLedger` / `SyncHistoryDiff` (Core). User-facing
/// text shows account display names only, never accountId / itemId.
struct BalanceTimeMachineView: View {
    @Environment(AppState.self) private var appState

    private var latestEntries: [AccountBalanceLedger.LedgerEntry] {
        appState.accountBalanceLedger.latestEntriesByAccount()
    }

    private var diffRows: [SyncHistoryDiff.Row] {
        appState.syncHistoryDiffRows
    }

    private func displayName(for accountId: String) -> String {
        appState.accounts.first { $0.id == accountId }?.name ?? "Account"
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
                        Text(Formatters.currency(entry.current ?? entry.available ?? 0))
                            .microText()
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Formatters.displayDate(entry.date))
                            .microText()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(displayName(for: entry.accountId)) reported \(Formatters.currency(entry.current ?? entry.available ?? 0)) as of \(Formatters.displayDate(entry.date))."
                    )
                }

                ForEach(diffRows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(row.summary)
                            .microText()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .help(row.accessibilityText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityText)
                }
            }
            .padding(Spacing.sm)
            .glassSurface(.inset)
        }
    }
}
