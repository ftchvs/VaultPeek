import PlaidBarCore
import SwiftUI

/// The detached multi-select **review Table** surface (AND-532) — the power-review
/// counterpart to the popover's Review Inbox (spec §3/§5, Option A). It lists every
/// review-inbox row in a resizable, sortable, multi-select `Table` so a user can
/// triage many transactions at once, with:
///
/// - **Per-row context menu (sub 555):** Recategorize, Create rule, Mark transfer —
///   each wired to the *existing* `AppState` review action path (`updateReviewCategory`,
///   `createRule`, `markReviewItemTransfer`), so the table and the inbox can never
///   diverge in what an action means.
/// - **Bulk recategorize (sub 556):** apply one chosen category to every selected
///   row at once. The blast radius (which ids, which category) is decided by the
///   pure ``ReviewBulkRecategorizePlan`` and surfaced to the user before applying;
///   the application loops the *same* `updateReviewCategory` path per id (state
///   blast radius), inside one undo-friendly animation.
///
/// It reads the same ``TransactionReviewInboxSnapshot`` `AppState` already builds —
/// no recompute. Rows are the pure, unit-tested ``ReviewTableRow`` in PlaidBarCore;
/// this view owns only the table layout, the menus, and the open-window intent.
///
/// Privacy (SECURITY.md / ACCESSIBILITY.md): under Privacy Mask / App Lock the
/// window withholds merchant + amount figures (it shows a placeholder instead of
/// the rows), and the category pill rides on glyph + text, never color alone.
struct ReviewTableWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Multi-select row ids. `Set<String>` is the `Table` selection contract and
    /// the same id space the AppState review actions key off.
    @State private var selection: Set<String> = []
    /// Active table sort, stored as the small `Sendable` ``ReviewTableSort`` enum
    /// from PlaidBarCore. A `[KeyPathComparator]` is NOT `Sendable`, so it cannot
    /// live in `@State` under strict concurrency (the same constraint
    /// CategoryDashboardWindow documents); the sort is applied by the pure,
    /// unit-tested ``ReviewTableSort/sorted(_:)`` comparator instead, and chosen via
    /// a `Picker` rather than `Table`'s `sortOrder:` binding.
    @State private var sort: ReviewTableSort = .amountDescending
    /// Staged bulk-recategorize plan — set when the user picks a category for the
    /// selection; drives the blast-radius confirmation before anything is applied.
    @State private var pendingBulkPlan: ReviewBulkRecategorizePlan?

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    private var snapshot: TransactionReviewInboxSnapshot {
        appState.transactionReviewInboxSnapshot
    }

    /// All listed rows, sorted by the active table order (pure Core comparator).
    private var rows: [ReviewTableRow] {
        sort.sorted(ReviewTableRow.rows(from: snapshot.items))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            if isMasked {
                maskedPlaceholder
            } else if snapshot.totalCount == 0 {
                emptyState
            } else {
                bulkActionBar
                table
            }
        }
        .padding(Spacing.lg)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            pendingBulkPlan.map { "Set \($0.count) to \($0.category.displayName)?" } ?? "Recategorize?",
            isPresented: bulkConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingBulkPlan
        ) { plan in
            Button("Set \(plan.count) to \(plan.category.displayName)") { applyBulkRecategorize(plan) }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(plan.blastRadiusDescription())
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Review Transactions")
                    .font(.title2.weight(.bold))
                Text("Multi-select to recategorize, create a rule, or mark a transfer in bulk.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            if !isMasked, snapshot.totalCount > 0 {
                Picker("Sort", selection: $sort) {
                    ForEach(ReviewTableSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Sort transactions")
            }
        }
    }

    // MARK: - Bulk action bar (sub 556)

    /// A bar that appears above the table once rows are selected: it states the
    /// selection count (text, never color alone) and offers a category menu that
    /// stages the blast-radius confirmation for a bulk recategorize.
    @ViewBuilder
    private var bulkActionBar: some View {
        let selectedCount = selectionInListedRows.count
        HStack(spacing: Spacing.sm) {
            if selectedCount == 0 {
                Label("Select rows to recategorize in bulk", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "\(selectedCount) selected",
                    systemImage: "checkmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

                bulkRecategorizeMenu

                Button {
                    bulkMarkTransfer()
                } label: {
                    Label("Mark transfer", systemImage: "arrow.left.arrow.right")
                }
                .controlSize(.small)
                .help("Mark all \(selectedCount) selected transactions as transfers and exclude them from budgets")

                Button(role: .cancel) {
                    selection.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .help("Clear the selection")
            }

            Spacer(minLength: Spacing.sm)

            Button {
                appState.undoLastReviewAction()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo last review action")
        }
        .padding(.bottom, Spacing.xxs)
    }

    /// Category picker that stages a bulk-recategorize plan for the current
    /// selection. Picking a category opens the blast-radius confirmation (it does
    /// not apply directly), so the user always sees how many + which rows move.
    private var bulkRecategorizeMenu: some View {
        Menu {
            ForEach(SpendingCategory.allCases, id: \.self) { category in
                Button {
                    stageBulkRecategorize(to: category)
                } label: {
                    Label(category.displayName, systemImage: category.iconName)
                }
            }
        } label: {
            Label("Recategorize", systemImage: "tag")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help("Apply one category to all selected transactions")
        .accessibilityLabel("Recategorize selected transactions")
    }

    // MARK: - Table

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Merchant") { row in
                merchantCell(row)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Amount") { row in
                Text(row.amountText(isMasked: isMasked))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Date") { row in
                Text(row.dateText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 88, ideal: 104)

            TableColumn("Category") { row in
                categoryCell(row)
            }
            .width(min: 140, ideal: 170)

            TableColumn("Reason") { row in
                Text(row.reasonSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(row.reasonSummary)
            }
            .width(min: 140, ideal: 180)
        }
        .contextMenu(forSelectionType: ReviewTableRow.ID.self) { ids in
            contextMenu(for: ids)
        }
        .frame(minHeight: 240)
        .accessibilityLabel("Review transactions table")
    }

    private func merchantCell(_ row: ReviewTableRow) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(row.merchantText(isMasked: isMasked))
                .lineLimit(1)
            if row.isNLSuggested {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(SemanticColors.brand)
                    .help("Category suggested on device")
                    .accessibilityLabel("Category suggested on device")
            }
            if row.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Marked as transfer")
                    .accessibilityLabel("Transfer")
            }
        }
    }

    /// The category pill cell — glyph + text + a redundant accent (never color
    /// alone). Mirrors the inbox row's pill so the two surfaces match.
    private func categoryCell(_ row: ReviewTableRow) -> some View {
        let accent = row.category.map(CategoryAccentTokens.color(for:)) ?? .secondary
        return Label(row.categoryTitle, systemImage: row.categoryGlyph)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(accent)
            .lineLimit(1)
            .accessibilityLabel("Category: \(row.categoryTitle)")
    }

    // MARK: - Context menu (sub 555)

    /// Per-row / multi-row context menu wired to the existing review action path.
    /// When the user right-clicks a row that is not in the current selection,
    /// SwiftUI passes just that row's id; when they right-click within a multi-row
    /// selection, it passes the whole set — so the same menu serves single and bulk.
    @ViewBuilder
    private func contextMenu(for ids: Set<ReviewTableRow.ID>) -> some View {
        if ids.isEmpty {
            Text("No transaction selected")
        } else {
            let scoped = scopedRows(ids)
            Menu("Recategorize") {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Button {
                        recategorize(rows: scoped, to: category)
                    } label: {
                        Label(category.displayName, systemImage: category.iconName)
                    }
                }
            }

            Menu("Create rule") {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Button {
                        createCategoryRules(rows: scoped, category: category)
                    } label: {
                        Label("Always \(category.displayName)", systemImage: category.iconName)
                    }
                }
                Divider()
                Button {
                    createTransferRules(rows: scoped)
                } label: {
                    Label("Always mark transfer", systemImage: "arrow.left.arrow.right")
                }
            }

            Button {
                markTransfer(rows: scoped)
            } label: {
                Label(
                    ids.count == 1 ? "Mark transfer" : "Mark \(scoped.count) transfers",
                    systemImage: "arrow.left.arrow.right"
                )
            }

            Divider()

            Button {
                approve(rows: scoped)
            } label: {
                Label(
                    ids.count == 1 ? "Mark reviewed" : "Mark \(scoped.count) reviewed",
                    systemImage: "checkmark"
                )
            }
        }
    }

    // MARK: - Actions (all via the existing AppState review path)

    /// Stage a bulk recategorize over the current multi-selection (sub 556) — does
    /// not apply; opens the blast-radius confirmation first.
    private func stageBulkRecategorize(to category: SpendingCategory) {
        let plan = ReviewBulkRecategorizePlan.make(
            rows: rows,
            selection: selection,
            category: category
        )
        guard !plan.isEmpty else { return }
        pendingBulkPlan = plan
    }

    /// Apply a confirmed bulk recategorize: route every affected id through the SAME
    /// per-row `updateReviewCategory` path the inbox uses, inside one animation, then
    /// announce the count + category (never a silent change) and clear the selection.
    private func applyBulkRecategorize(_ plan: ReviewBulkRecategorizePlan) {
        pendingBulkPlan = nil
        guard !plan.isEmpty else { return }
        animatingResolution {
            appState.withBatchedReviewUndo {
                for id in plan.affectedIDs {
                    appState.updateReviewCategory(id, category: plan.category)
                }
            }
        }
        selection.subtract(plan.affectedIDs)
        let noun = plan.count == 1 ? "transaction" : "transactions"
        AccessibilityNotification.Announcement(
            "Set \(plan.count) \(noun) to \(plan.category.displayName)"
        ).post()
    }

    /// Recategorize a scoped set of rows (single from a context-menu, or many).
    /// The whole scope is one undo unit — for a single row that is exactly one
    /// snapshot, matching the inbox's per-row behavior.
    private func recategorize(rows scoped: [ReviewTableRow], to category: SpendingCategory) {
        animatingResolution {
            appState.withBatchedReviewUndo {
                for row in scoped {
                    appState.updateReviewCategory(row.id, category: category)
                }
            }
        }
        selection.subtract(scoped.map(\.id))
    }

    private func markTransfer(rows scoped: [ReviewTableRow]) {
        animatingResolution {
            appState.withBatchedReviewUndo {
                for row in scoped {
                    appState.markReviewItemTransfer(row.id)
                }
            }
        }
        selection.subtract(scoped.map(\.id))
    }

    private func bulkMarkTransfer() {
        markTransfer(rows: scopedRows(selection))
    }

    private func approve(rows scoped: [ReviewTableRow]) {
        let ids = scoped.map(\.id)
        animatingResolution {
            if ids.count == 1, let id = ids.first {
                appState.approveReviewItem(id)
            } else {
                appState.bulkMarkReviewed(ids: ids)
            }
        }
        selection.subtract(ids)
    }

    /// Create a per-merchant "always categorize as" rule for each scoped row,
    /// reusing the existing `createRule(from:category:)` path.
    private func createCategoryRules(rows scoped: [ReviewTableRow], category: SpendingCategory) {
        animatingResolution {
            appState.withBatchedReviewUndo {
                for row in scoped {
                    if let item = item(for: row.id) {
                        appState.createRule(from: item, category: category)
                    }
                }
            }
        }
        selection.subtract(scoped.map(\.id))
    }

    /// Create a per-merchant "always mark transfer" rule for each scoped row.
    private func createTransferRules(rows scoped: [ReviewTableRow]) {
        animatingResolution {
            appState.withBatchedReviewUndo {
                for row in scoped {
                    if let item = item(for: row.id) {
                        appState.createRule(from: item, markTransfer: true)
                    }
                }
            }
        }
        selection.subtract(scoped.map(\.id))
    }

    // MARK: - Helpers

    /// The rows referenced by an id set, in current table order (so actions resolve
    /// in the order the user sees, and a stale id is dropped).
    private func scopedRows(_ ids: Set<String>) -> [ReviewTableRow] {
        rows.filter { ids.contains($0.id) }
    }

    /// The selection narrowed to ids that are actually still listed.
    private var selectionInListedRows: Set<String> {
        let listed = Set(rows.map(\.id))
        return selection.intersection(listed)
    }

    /// The full inbox item behind a row id — needed by `createRule`, which takes the
    /// whole `TransactionReviewItem` (to read the original/merchant name + reasons).
    private func item(for id: String) -> TransactionReviewItem? {
        snapshot.items.first { $0.id == id }
    }

    private var bulkConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkPlan != nil },
            set: { presented in if !presented { pendingBulkPlan = nil } }
        )
    }

    private func animatingResolution(_ change: () -> Void) {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            change()
        }
    }

    // MARK: - Placeholders

    private var maskedPlaceholder: some View {
        ContentUnavailableView {
            Label("Transactions hidden", systemImage: "eye.slash")
        } description: {
            Text("Merchants and amounts are hidden while Privacy Mask or App Lock is active.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Review transactions hidden while VaultPeek is private")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Inbox Clear", systemImage: "checkmark.circle")
        } description: {
            Text("New or unusual transactions show up here to review, recategorize, or rename.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Review inbox clear. New or unusual transactions will appear here.")
    }
}
