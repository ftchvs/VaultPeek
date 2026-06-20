import PlaidBarCore
import SwiftUI

/// The Transaction Workspace detail-column inspector (AND-582).
///
/// Reads the selected transaction id from the shared ``NavigationModel`` and
/// resolves it (override-aware) against `AppState`. Content-gated: shows the
/// "Select a transaction" prompt when nothing is selected (IA §3.1). All edits —
/// recategorize, add/clear note, mark / un-mark transfer, "always categorize"
/// rule, mark reviewed — route through the existing `AppState` review path, so the
/// inspector, the table, and the Review Inbox stay in lockstep and every edit is
/// undoable and reflected in dependent surfaces (budgets, category dashboard).
///
/// Under Privacy Mask / App Lock the inspector withholds merchant + amount.
struct TransactionInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Local draft of the note so typing doesn't write per-keystroke to the
    /// persisted store; committed on submit / focus-loss. Re-seeded when the
    /// selected row changes.
    @State private var noteDraft = ""
    @FocusState private var noteFocused: Bool

    private var navigationModel: NavigationModel { appState.navigationModel }
    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    /// The selected row, resolved through the pure Core builder so its category /
    /// transfer / status match the table exactly. `nil` when nothing is selected or
    /// the selection no longer exists.
    private var selectedRow: TransactionWorkspace.Row? {
        let id = navigationModel.selectedTransactionID
        guard !id.isEmpty else { return nil }
        return TransactionWorkspace.rows(
            transactions: appState.transactions,
            metadata: appState.transactionReviewMetadata,
            rules: appState.transactionRules
        ).first { $0.id == id }
    }

    var body: some View {
        Group {
            if let row = selectedRow {
                if isMasked {
                    maskedPlaceholder
                } else {
                    detail(for: row)
                }
            } else {
                emptyPrompt
            }
        }
        .onChange(of: navigationModel.selectedTransactionID) { _, _ in
            noteDraft = selectedRow?.note ?? ""
        }
        .onAppear { noteDraft = selectedRow?.note ?? "" }
    }

    // MARK: - Detail

    private func detail(for row: TransactionWorkspace.Row) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header(row)
                amountSection(row)
                categorySection(row)
                noteSection(row)
                actionsSection(row)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func header(_ row: TransactionWorkspace.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                MerchantLogoView(
                    logoURL: row.transaction.logoURL,
                    fallbackTint: row.transaction.isIncome ? SemanticColors.positive : Color.secondary.opacity(0.55)
                )
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(row.merchantName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(Formatters.displayTransactionDate(row.transaction.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            statusBadges(row)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusBadges(_ row: TransactionWorkspace.Row) -> some View {
        HStack(spacing: Spacing.xs) {
            badge(statusTitle(row.status), systemImage: statusGlyph(row.status), tint: statusColor(row.status))
            if row.transaction.pending {
                badge("Pending", systemImage: "clock", tint: SemanticColors.pending)
            }
            if row.isTransfer {
                badge("Transfer", systemImage: "arrow.left.arrow.right", tint: .secondary)
            }
        }
    }

    private func badge(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }

    private func amountSection(_ row: TransactionWorkspace.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(row.transaction.isIncome ? "Received" : "Spent")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amountText(row))
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.transaction.isIncome ? SemanticColors.positive : AppearanceTextColors.primary)
            if row.transaction.name != row.merchantName {
                Text("Statement: \(row.transaction.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if row.excludedFromBudgets {
                Label("Excluded from budgets", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func categorySection(_ row: TransactionWorkspace.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("Category")
            Picker("Category", selection: categoryBinding(row)) {
                Text("Uncategorized").tag(SpendingCategory?.none)
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.iconName)
                        .tag(SpendingCategory?.some(category))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if row.isCategorySuggested, let suggested = row.suggestedCategory {
                Label("Suggested on device: \(suggested.displayName)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(SemanticColors.brand)
            }
        }
    }

    private func noteSection(_ row: TransactionWorkspace.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("Note")
            TextEditor(text: $noteDraft)
                .frame(minHeight: 60, maxHeight: 120)
                .focused($noteFocused)
                .padding(Spacing.xxs)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .accessibilityLabel("Transaction note")
                .onChange(of: noteFocused) { _, focused in
                    // Commit on focus-loss so the persisted store isn't written per
                    // keystroke. (The note is display-only; it never marks reviewed.)
                    if !focused { commitNote(row.id) }
                }
            HStack {
                Spacer()
                Button("Save note") { commitNote(row.id) }
                    .controlSize(.small)
                    .disabled(noteDraft == (row.note ?? ""))
            }
        }
    }

    private func actionsSection(_ row: TransactionWorkspace.Row) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Actions")

            if row.isTransfer {
                Button {
                    edit { appState.markReviewItemTransfer(row.id, isTransfer: false) }
                } label: {
                    Label("Mark not a transfer", systemImage: "arrow.uturn.left")
                }
                .help("Restore this row to spend and clear its budget exclusion")
            } else {
                Button {
                    edit { appState.markReviewItemTransfer(row.id, isTransfer: true) }
                } label: {
                    Label("Mark as transfer", systemImage: "arrow.left.arrow.right")
                }
                .help("Exclude this row from budgets as an account transfer")
            }

            // Inline rule affordance: "always categorize this merchant" reusing the
            // existing createRule path. Offered only when there's an effective
            // category to bind the rule to.
            if let category = row.effectiveCategory {
                Button {
                    edit { appState.createRule(from: reviewItem(for: row), category: category) }
                } label: {
                    Label("Always categorize “\(row.merchantName)” as \(category.displayName)", systemImage: "wand.and.stars")
                }
                .help("Create a rule so future transactions from this merchant categorize automatically")
            }

            if row.status != .reviewed {
                Button {
                    edit { appState.approveReviewItem(row.id) }
                } label: {
                    Label("Mark reviewed", systemImage: "checkmark.circle")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Bindings + edits

    private func categoryBinding(_ row: TransactionWorkspace.Row) -> Binding<SpendingCategory?> {
        Binding(
            get: { row.effectiveCategory },
            set: { newValue in
                guard let newValue, newValue != row.effectiveCategory else { return }
                edit { appState.updateReviewCategory(row.id, category: newValue) }
            }
        )
    }

    private func commitNote(_ id: String) {
        appState.updateReviewNote(id, note: noteDraft)
    }

    /// Build a `TransactionReviewItem` from the resolved row so the existing
    /// `createRule(from:)` path can read merchant + category + transfer state. The
    /// rule matcher keys on the effective merchant name, exactly as the inbox does.
    private func reviewItem(for row: TransactionWorkspace.Row) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: row.transaction,
            status: row.status,
            reasonCodes: [],
            effectiveCategory: row.effectiveCategory,
            effectiveMerchantName: row.merchantName,
            isTransfer: row.isTransfer,
            excludedFromBudgets: row.excludedFromBudgets,
            matchedRuleIds: []
        )
    }

    private func edit(_ change: () -> Void) {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            change()
        }
    }

    // MARK: - Subviews

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var emptyPrompt: some View {
        ContentUnavailableView {
            Label(
                RouteDestination.transactions.detailColumnEmptyPrompt ?? "Select a transaction",
                systemImage: RouteDestination.transactions.systemImage
            )
        } description: {
            Text("Choose a transaction from the list to see its details and edit it here.")
        }
    }

    private var maskedPlaceholder: some View {
        ContentUnavailableView {
            Label("Transaction hidden", systemImage: "eye.slash")
        } description: {
            Text("Details are hidden while Privacy Mask or App Lock is active.")
        }
    }

    // MARK: - Formatting

    private func amountText(_ row: TransactionWorkspace.Row) -> String {
        let prefix = row.transaction.isIncome ? "+" : ""
        return "\(prefix)\(Formatters.currency(row.transaction.displayAmount, format: .full))"
    }

    private func statusTitle(_ status: TransactionReviewStatus) -> String {
        switch status {
        case .needsReview: "Needs review"
        case .reviewed: "Reviewed"
        case .ignored: "Ignored"
        }
    }

    private func statusGlyph(_ status: TransactionReviewStatus) -> String {
        switch status {
        case .needsReview: "exclamationmark.circle"
        case .reviewed: "checkmark.circle"
        case .ignored: "minus.circle"
        }
    }

    private func statusColor(_ status: TransactionReviewStatus) -> Color {
        switch status {
        case .needsReview: SemanticColors.warning
        case .reviewed: SemanticColors.positive
        case .ignored: .secondary
        }
    }
}
