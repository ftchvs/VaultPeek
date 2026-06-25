import PlaidBarCore
import SwiftUI

/// The Transaction Workspace's sortable, keyboard-navigable `Table` (AND-582).
///
/// Single-selection (the inspector follows the selected row). `Table` gives arrow
/// navigation, Return/double-click activation, and type-to-search over the visible
/// cell text for free; the selection binding into ``NavigationModel`` means moving
/// the highlight updates the inspector live. Rows are the pure
/// ``TransactionWorkspace/Row`` view-models (already filtered + sorted by Core), so
/// this view owns only layout, the per-row context menu, and the selection.
///
/// Sorting is driven by the parent's ``TransactionWorkspace/Sort`` picker (not
/// `Table`'s `sortOrder:`) because `[KeyPathComparator]` is not `Sendable` and
/// cannot live in strict-concurrency `@State` — the same constraint
/// `ReviewTableWindow` documents.
///
/// Every status/category cue pairs color with a glyph + text, never color alone
/// (ACCESSIBILITY.md); amounts/merchants are withheld under Privacy Mask.
struct TransactionsTable: View {
    let rows: [TransactionWorkspace.Row]
    @Binding var selection: String?
    let isMasked: Bool
    /// Whether the paged source has more pages to load (AND-567). When true, the
    /// last row's appearance triggers `onReachEnd` to page on demand.
    var hasMorePages: Bool = false
    var onReachEnd: () -> Void = {}
    let onRecategorize: (String, SpendingCategory) -> Void
    let onMarkTransfer: (String, Bool) -> Void
    let onApprove: (String) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Merchant") { row in
                merchantCell(row)
                    // Page-on-demand: when the last loaded row is rendered and more
                    // pages remain, ask the source for the next page. `Table` itself
                    // virtualizes row rendering, so this fires only as the user
                    // scrolls near the end of the loaded window.
                    .onAppear {
                        if hasMorePages, row.id == rows.last?.id {
                            onReachEnd()
                        }
                    }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Date") { row in
                Text(Formatters.displayTransactionDate(row.transaction.date))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Category") { row in
                categoryCell(row)
            }
            .width(min: 150, ideal: 180)

            TableColumn("Status") { row in
                statusCell(row)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Amount") { row in
                Text(amountText(row))
                    .windowDataText()
                    .foregroundStyle(amountColor(row))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        }
        .accessibilityLabel("Transactions table")
    }

    // MARK: - Cells

    private func merchantCell(_ row: TransactionWorkspace.Row) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(isMasked ? "•••••" : row.merchantName)
                .lineLimit(1)
            if row.transaction.pending {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(SemanticColors.pending)
                    .help("Pending")
                    .accessibilityLabel("Pending")
            }
            if row.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Transfer — excluded from budgets")
                    .accessibilityLabel("Transfer")
            }
            if row.hasNote {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Has a note")
                    .accessibilityLabel("Has a note")
            }
        }
    }

    /// Category pill — glyph + text + a redundant accent (never color alone).
    /// Mirrors the inbox/review-table pill so the surfaces match.
    private func categoryCell(_ row: TransactionWorkspace.Row) -> some View {
        let category = row.effectiveCategory ?? row.suggestedCategory
        let accent = category.map(CategoryAccentTokens.color(for:)) ?? .secondary
        return HStack(spacing: Spacing.xxs) {
            Label(categoryTitle(row), systemImage: category?.iconName ?? "tag")
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(accent)
                .lineLimit(1)
            if row.isCategorySuggested {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(SemanticColors.brand)
                    .help("Category suggested on device")
                    .accessibilityLabel("suggested")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category: \(categoryTitle(row))\(row.isCategorySuggested ? ", suggested" : "")")
    }

    /// Review status — glyph + text, never color alone.
    private func statusCell(_ row: TransactionWorkspace.Row) -> some View {
        Label(row.status.displayName, systemImage: row.status.glyphName)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(statusColor(row.status))
            .lineLimit(1)
            .accessibilityLabel("Status: \(row.status.displayName)")
    }

    // MARK: - Context menu (single-row, via the existing review path)

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
            Menu("Recategorize") {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Button {
                        onRecategorize(id, category)
                    } label: {
                        Label(category.displayName, systemImage: category.iconName)
                    }
                }
            }

            if row.isTransfer {
                Button {
                    onMarkTransfer(id, false)
                } label: {
                    Label("Mark not transfer", systemImage: "arrow.uturn.left")
                }
            } else {
                Button {
                    onMarkTransfer(id, true)
                } label: {
                    Label("Mark transfer", systemImage: "arrow.left.arrow.right")
                }
            }

            Divider()

            if row.status != .reviewed {
                Button {
                    onApprove(id)
                } label: {
                    Label("Mark reviewed", systemImage: "checkmark")
                }
            }
        } else {
            Text("No transaction selected")
        }
    }

    // MARK: - Formatting helpers

    private func amountText(_ row: TransactionWorkspace.Row) -> String {
        if isMasked { return "••••" }
        let prefix = row.transaction.isIncome ? "+" : ""
        return "\(prefix)\(Formatters.currency(row.transaction.displayAmount, format: .full))"
    }

    private func amountColor(_ row: TransactionWorkspace.Row) -> Color {
        if isMasked { return .secondary }
        return row.transaction.isIncome ? SemanticColors.positive : AppearanceTextColors.primary
    }

    private func categoryTitle(_ row: TransactionWorkspace.Row) -> String {
        (row.effectiveCategory ?? row.suggestedCategory)?.displayName ?? "Uncategorized"
    }

    private func statusColor(_ status: TransactionReviewStatus) -> Color {
        switch status {
        case .needsReview: SemanticColors.warning
        case .reviewed: SemanticColors.positive
        case .ignored: .secondary
        }
    }
}
