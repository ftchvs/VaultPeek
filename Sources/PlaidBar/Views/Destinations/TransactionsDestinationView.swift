import PlaidBarCore
import SwiftUI

/// **Transactions** destination (3-column — IA §3.1/§5.2, AND-582 / Epic 4).
///
/// The ledger: a sortable, keyboard-navigable `Table` (content column) → a
/// transaction inspector (detail column). The shell renders this content column
/// plus ``Inspector`` in the detail column, which is content-gated and shows
/// "Select a transaction" when nothing is selected (IA §3.1).
///
/// ## Reused engines (nothing rebuilt)
/// - **Filter / search / sort math** is the pure, unit-tested
///   ``TransactionWorkspace`` (PlaidBarCore): build override-aware rows → filter
///   (AND of every facet) → search → sort. Filter + sort + selection live in
///   ``NavigationModel`` (the prompt's "filter/search state lives in
///   NavigationModel"), so the table and the inspector share one source of truth
///   and the window restores its last query.
/// - **Override-aware spend attributes** (effective category, transfer, exclusion)
///   come from ``EffectiveCategoryResolver`` — no spend re-derivation here.
/// - **Edits** (recategorize, mark / un-mark transfer, create rule, add note)
///   route through the existing `AppState` review path (`updateReviewCategory`,
///   `markReviewItemTransfer`, `createRule`, `updateReviewNote`), so the workspace
///   and the Review Inbox can never diverge in what an action means, and every
///   edit is undoable (⌘Z) and reflected in dependent surfaces.
///
/// ## Privacy
/// Under Privacy Mask / App Lock the table withholds merchant + amount figures
/// (a placeholder replaces the rows), and every status/category cue rides on
/// glyph + text, never color alone (ACCESSIBILITY.md / SECURITY.md).
///
/// Window-first surface only: built solely behind `WindowFirstFeatureFlag`
/// (default OFF), so with the flag off none of this is instantiated and the
/// popover is byte-identical.
struct TransactionsDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Focuses the search field for the ⌘F / find affordance.
    @FocusState private var isSearchFocused: Bool

    /// Large-history paging engine (AND-567), reused verbatim: page 0 loads on
    /// appear, the next page loads as the table nears the end of the loaded rows.
    /// When the disposable SwiftData cache is unavailable/disabled the source stays
    /// on the in-memory `appState.transactions` fallback, so a small history (or a
    /// cache-less environment) renders exactly today's rows — no regression. The
    /// source's `rows` are the *input* to the pure ``TransactionWorkspace`` pipeline
    /// (filter → search → sort), so a 10k+-row history materializes a page at a time
    /// rather than all at once.
    @State private var pagedSource: PagedTransactionSource

    @MainActor
    init() {
        // A placeholder source until `.task` rebuilds it against the live AppState
        // store/cache. `inMemory([])` stays on the fallback path with no rows; the
        // real source is built in `body`'s `.task` once `appState` is available.
        _pagedSource = State(initialValue: .inMemory([]))
    }

    private var navigationModel: NavigationModel { appState.navigationModel }
    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    /// The transactions feeding the pipeline: the paged source's current rows
    /// (paged from cache, or the in-memory fallback when paging is unavailable).
    private var sourceTransactions: [TransactionDTO] { pagedSource.rows }

    /// The fully composed rows: page → build → filter → search → sort (pure Core).
    private var rows: [TransactionWorkspace.Row] {
        TransactionWorkspace.resolve(
            transactions: sourceTransactions,
            metadata: appState.transactionReviewMetadata,
            rules: appState.transactionRules,
            filter: navigationModel.transactionFilter,
            sort: navigationModel.transactionSort,
            now: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TransactionsFilterBar(
                filter: filterBinding,
                sort: sortBinding,
                accounts: appState.accounts,
                resultCount: rows.count,
                isSearchFocused: $isSearchFocused
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            Divider().opacity(0.4)

            content
        }
        .navigationTitle(RouteDestination.transactions.title)
        // Build the paged source against the live AppState cache once, then load the
        // first page. Best-effort: any failure leaves it on the in-memory fallback.
        .task {
            pagedSource = appState.makePagedTransactionSource(fallback: appState.transactions)
            await pagedSource.loadFirstPageIfNeeded()
        }
        // Keep the fallback rows fresh when a refresh replaces the in-memory array,
        // so the list reflects new data even before/without a cache page.
        .onChange(of: appState.transactions) { _, latest in
            pagedSource.updateFallback(latest)
        }
        // While a filter or search is active, drain remaining pages so the facet
        // applies to the WHOLE history, not just the pages scrolled so far —
        // otherwise filtering a partially-paged 10k history would silently omit
        // matches in unloaded pages. Re-runs whenever the active filter changes;
        // the source's in-flight guard keeps this from over-fetching.
        .task(id: navigationModel.transactionFilter) {
            guard navigationModel.transactionFilter.isActive else { return }
            while pagedSource.hasMore {
                await pagedSource.loadNextPageIfNeeded()
            }
        }
        // Self-heal: if the selected row falls out of the filtered set, clear it so
        // the inspector returns to its prompt instead of pointing at a hidden row.
        .onChange(of: rows.map(\.id)) { _, ids in
            navigationModel.reconcileTransactionSelection(visibleTransactionIDs: ids)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if appState.isBootLoadInFlight {
            TransactionsLoadingSkeleton()
        } else if let error = appState.error, appState.transactions.isEmpty {
            errorState(error)
        } else if isMasked {
            maskedPlaceholder
        } else if appState.transactions.isEmpty {
            emptyState
        } else if rows.isEmpty {
            filteredEmptyState
        } else {
            table
        }
    }

    private var table: some View {
        TransactionsTable(
            rows: rows,
            selection: selectionBinding,
            isMasked: isMasked,
            hasMorePages: pagedSource.hasMore,
            onReachEnd: {
                // The table is near the end of the currently-loaded page — fetch the
                // next page from the cache (no-op outside the paged path / when one
                // is already in flight, guarded inside the source).
                if pagedSource.hasMore {
                    Task { await pagedSource.loadNextPageIfNeeded() }
                }
            },
            onRecategorize: { id, category in
                animate { appState.updateReviewCategory(id, category: category) }
            },
            onMarkTransfer: { id, isTransfer in
                animate { appState.markReviewItemTransfer(id, isTransfer: isTransfer) }
            },
            onApprove: { id in
                animate { appState.approveReviewItem(id) }
            }
        )
    }

    // MARK: - Bindings to the shared NavigationModel state

    private var filterBinding: Binding<TransactionWorkspace.Filter> {
        Binding(
            get: { navigationModel.transactionFilter },
            set: { navigationModel.transactionFilter = $0 }
        )
    }

    private var sortBinding: Binding<TransactionWorkspace.Sort> {
        Binding(
            get: { navigationModel.transactionSort },
            set: { navigationModel.transactionSort = $0 }
        )
    }

    /// The `Table`'s single-selection binding, bridged to the model's `""` sentinel.
    private var selectionBinding: Binding<String?> {
        Binding(
            get: {
                let id = navigationModel.selectedTransactionID
                return id.isEmpty ? nil : id
            },
            set: { navigationModel.selectedTransactionID = $0 ?? "" }
        )
    }

    private func animate(_ change: () -> Void) {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            change()
        }
    }

    // MARK: - Empty / loading / error states

    private var maskedPlaceholder: some View {
        ContentUnavailableView {
            Label("Transactions hidden", systemImage: "eye.slash")
        } description: {
            Text("Merchants and amounts are hidden while Privacy Mask or App Lock is active.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Transactions hidden while VaultPeek is private")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No transactions yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Connected accounts will show their transaction history here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No transactions match the current filters or search.")
        } actions: {
            Button("Clear filters") {
                animate {
                    navigationModel.transactionFilter = navigationModel.transactionFilter.cleared()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn’t load transactions", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Could not load transactions. \(message)")
    }

    /// The detail-column (inspector) pane for Transactions — the selected row's full
    /// detail + inline edit. Content-gated: shows "Select a transaction" when
    /// nothing is selected (IA §3.1). A separate `View` because the shell mounts the
    /// content and inspector columns independently; both read the shared selection
    /// from `AppState.navigationModel`.
    struct Inspector: View {
        @Environment(AppState.self) private var appState

        var body: some View {
            TransactionInspectorView()
                .environment(appState)
        }
    }
}

#Preview("Content") {
    TransactionsDestinationView()
        .environment(AppState())
        .frame(width: 640, height: 480)
}

#Preview("Inspector") {
    TransactionsDestinationView.Inspector()
        .environment(AppState())
        .frame(width: 320, height: 480)
}
