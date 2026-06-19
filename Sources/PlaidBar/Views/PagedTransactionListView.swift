import PlaidBarCore
import SwiftUI

/// A virtualized, page-on-demand transaction list (AND-567).
///
/// Renders rows in a `LazyVStack` so a multi-thousand-row history materializes
/// only the visible rows, never the whole array. When the last loaded row appears,
/// it asks the ``PagedTransactionSource`` for the next page (infinite scroll). The
/// source owns the fallback contract: if the disposable cache is unavailable or
/// disabled it stays on the in-memory array, so this view renders exactly today's
/// rows — just lazily — with no regression.
///
/// The view does **not** wrap its own `ScrollView` by default, so it composes
/// inside an existing scroll container (the account inspector's scroll). Pass
/// `ownsScroll: true` for a standalone surface that should provide its own scroll.
///
/// Rows reuse the existing ``TransactionMiniRow`` so the visual system,
/// accessibility, and privacy-masking behavior match the rest of the app.
struct PagedTransactionListView: View {
    @State private var source: PagedTransactionSource
    private let ownsScroll: Bool

    init(source: PagedTransactionSource, ownsScroll: Bool = false) {
        _source = State(initialValue: source)
        self.ownsScroll = ownsScroll
    }

    var body: some View {
        Group {
            if ownsScroll {
                ScrollView { rows }
            } else {
                rows
            }
        }
        .task {
            await source.loadFirstPageIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transaction history")
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.rowVertical) {
            ForEach(source.rows) { transaction in
                TransactionMiniRow(transaction: transaction)
                    .onAppear {
                        // Trigger the next page when the last loaded row scrolls into
                        // view. Guarded inside the source so re-appearances and
                        // in-flight fetches never double-load.
                        if transaction.id == source.rows.last?.id, source.hasMore {
                            Task { await source.loadNextPageIfNeeded() }
                        }
                    }
            }

            if source.hasMore {
                loadingMoreFooter
            }
        }
    }

    /// A lightweight footer shown while more pages remain. Text + symbol, never
    /// color-only (ACCESSIBILITY.md).
    private var loadingMoreFooter: some View {
        HStack(spacing: Spacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text("Loading more…")
                .microText()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.xs)
        .accessibilityLabel("Loading more transactions")
        .onAppear {
            // Belt-and-braces: if the footer itself appears (very short pages), keep
            // paging forward.
            Task { await source.loadNextPageIfNeeded() }
        }
    }
}
