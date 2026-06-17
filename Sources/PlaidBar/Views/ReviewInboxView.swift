import PlaidBarCore
import SwiftUI

struct ReviewInboxView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool
    @State private var selectedIndex = 0
    @State private var merchantDrafts: [String: String] = [:]
    @State private var actionConfirmation: ReviewActionConfirmation?
    /// Monotonic token so a queued auto-dismiss only clears the banner it was
    /// scheduled for — a newer action (which bumps the token) is never wiped by
    /// an older timer.
    @State private var confirmationGeneration = 0

    private var snapshot: TransactionReviewInboxSnapshot {
        appState.transactionReviewInboxSnapshot
    }

    private var items: [TransactionReviewItem] {
        Array(snapshot.items.prefix(6))
    }

    var body: some View {
        if snapshot.totalCount > 0 || actionConfirmation != nil {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header

                if let actionConfirmation {
                    ReviewActionConfirmationBanner(confirmation: actionConfirmation)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if appState.shouldMaskFinancialValues {
                    privateInboxPlaceholder
                } else {
                    VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        ReviewInboxRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            merchantDraft: merchantDraftBinding(for: item),
                            onSelect: { selectedIndex = index },
                            onApprove: {
                                recordAction(.approved, for: item)
                                appState.approveReviewItem(item.id)
                            },
                            onCategory: {
                                recordAction(.categorized($0), for: item)
                                appState.updateReviewCategory(item.id, category: $0)
                            },
                            onRename: {
                                recordAction(.renamed, for: item)
                                appState.renameReviewMerchant(item.id, merchantName: merchantDraft(for: item))
                            },
                            onTransfer: {
                                recordAction(.markedTransfer, for: item)
                                appState.markReviewItemTransfer(item.id)
                            },
                            onNotTransfer: {
                                recordAction(.markedSpend, for: item)
                                appState.markReviewItemTransfer(item.id, isTransfer: false)
                            },
                            onCategoryRule: {
                                recordAction(.ruleCreated, for: item)
                                appState.createRule(from: item, category: $0)
                            },
                            onTransferRule: {
                                recordAction(.ruleCreated, for: item)
                                appState.createRule(from: item, markTransfer: true)
                            },
                            onIgnore: {
                                recordAction(.ignored, for: item)
                                appState.ignoreReviewItem(item.id)
                            }
                        )
                    }
                    }
                }
            }
            .padding(Spacing.sm)
            .glassSurface(.raised)
            .focusable()
            .focused($isFocused)
            .onAppear {
                isFocused = true
                clampSelection()
            }
            .onChange(of: snapshot.totalCount) { _, newCount in
                clampSelection()
                // When the queue drains to empty, drop any lingering confirmation
                // banner so the inbox can collapse out of the popover instead of
                // sitting in an empty "0 items" state with a stuck banner.
                if newCount == 0 {
                    withAnimation(.snappy(duration: 0.18)) { actionConfirmation = nil }
                }
            }
            .onMoveCommand(perform: moveSelection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Review inbox. \(snapshot.totalCount) transaction\(snapshot.totalCount == 1 ? "" : "s") need attention.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Review Inbox")
                    .sectionTitle()

                Text("\(snapshot.totalCount) item\(snapshot.totalCount == 1 ? "" : "s") need attention")
                    .microText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if snapshot.highPriorityCount > 0 {
                Label("\(snapshot.highPriorityCount) high priority", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SemanticColors.warning)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("\(snapshot.highPriorityCount) high priority review item\(snapshot.highPriorityCount == 1 ? "" : "s")")
            }

            Button {
                appState.undoLastReviewAction()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo last review action")
            .accessibilityLabel("Undo last review action")
        }
    }

    private var privateInboxPlaceholder: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Review items, merchants, and amounts are hidden while Privacy Mask or App Lock is active.")
                .detailText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review inbox items hidden while VaultPeek is private")
    }

    private func merchantDraftBinding(for item: TransactionReviewItem) -> Binding<String> {
        Binding(
            get: { merchantDraft(for: item) },
            set: { merchantDrafts[item.id] = $0 }
        )
    }

    private func merchantDraft(for item: TransactionReviewItem) -> String {
        merchantDrafts[item.id] ?? item.effectiveMerchantName
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .down, .right:
            selectedIndex = min(selectedIndex + 1, max(items.count - 1, 0))
        case .up, .left:
            selectedIndex = max(selectedIndex - 1, 0)
        @unknown default:
            break
        }
    }

    private func clampSelection() {
        selectedIndex = min(max(selectedIndex, 0), max(items.count - 1, 0))
    }

    private func recordAction(_ action: ReviewActionConfirmation.Action, for item: TransactionReviewItem) {
        confirmationGeneration &+= 1
        let generation = confirmationGeneration
        withAnimation(.snappy(duration: 0.18)) {
            actionConfirmation = ReviewActionConfirmation(action: action, merchantName: item.effectiveMerchantName)
        }
        // Auto-dismiss so the banner never persists indefinitely. The generation
        // guard means a newer action's banner is not cleared by this older timer.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard confirmationGeneration == generation else { return }
            withAnimation(.snappy(duration: 0.18)) { actionConfirmation = nil }
        }
    }
}

private struct ReviewActionConfirmation: Equatable {
    enum Action: Equatable {
        case approved
        case ignored
        case categorized(SpendingCategory)
        case renamed
        case markedTransfer
        case markedSpend
        case ruleCreated

        var message: String {
            switch self {
            case .approved:
                "Approved"
            case .ignored:
                "Ignored"
            case let .categorized(category):
                "Categorized as \(category.displayName)"
            case .renamed:
                "Merchant name updated"
            case .markedTransfer:
                "Marked as transfer"
            case .markedSpend:
                "Marked as spend"
            case .ruleCreated:
                "Rule created"
            }
        }
    }

    let action: Action
    let merchantName: String

    var accessibilityLabel: String {
        "Review action completed: \(action.message) for \(merchantName)"
    }
}

private struct ReviewActionConfirmationBanner: View {
    let confirmation: ReviewActionConfirmation

    var body: some View {
        Label {
            Text("\(confirmation.action.message): \(confirmation.merchantName)")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .foregroundStyle(SemanticColors.positive)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SemanticColors.positive.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(SemanticColors.positive.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confirmation.accessibilityLabel)
    }
}

private struct ReviewInboxRow: View {
    let item: TransactionReviewItem
    let isSelected: Bool
    @Binding var merchantDraft: String
    let onSelect: () -> Void
    let onApprove: () -> Void
    let onCategory: (SpendingCategory) -> Void
    let onRename: () -> Void
    let onTransfer: () -> Void
    let onNotTransfer: () -> Void
    let onCategoryRule: (SpendingCategory) -> Void
    let onTransferRule: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(action: onSelect) {
                rowSummary
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Selects this transaction review row. Approve and ignore actions are also available below this summary.")

            compactActionStrip

            if isSelected {
                selectedControls
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        // Flattened: no per-row card. Selection reads as a subtle inline
        // emphasis (tinted wash + leading accent) inside the single raised
        // surface, with Dividers separating rows.
        .background(alignment: .leading) {
            if isSelected {
                SemanticColors.warning.opacity(0.08)
                Rectangle()
                    .fill(SemanticColors.warning.opacity(0.55))
                    .frame(width: 2)
            }
        }
    }

    private var rowSummary: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: leadingSymbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(leadingTint)
                .frame(width: Sizing.glyphMedium, height: Sizing.glyphMedium)
                .background(leadingTint.opacity(0.12), in: RoundedRectangle(cornerRadius: SurfaceTokens.panelCornerRadius))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(item.effectiveMerchantName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: Spacing.xs)

                    Text(Formatters.currency(item.transaction.displayAmount, format: .compact))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }

                HStack(spacing: Spacing.xs) {
                    Text(item.effectiveCategory?.displayName ?? "Uncategorized")
                        .microText()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(Formatters.displayTransactionDate(item.transaction.date))
                        .microText()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                reasonChips
            }
        }
    }

    private var reasonChips: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(item.reasonCodes, id: \.self) { reason in
                Label(reason.displayName, systemImage: symbolName(for: reason))
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(tint(for: reason))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint(for: reason).opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule().stroke(tint(for: reason).opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    private var compactActionStrip: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                onApprove()
            } label: {
                Label("Approve", systemImage: "checkmark")
            }
            .help("Approve transaction")
            .accessibilityLabel("Approve transaction")
            .accessibilityHint("Marks \(item.effectiveMerchantName) as reviewed and shows a confirmation.")

            Button {
                onSelect()
            } label: {
                Label(isSelected ? "Editing" : "Review", systemImage: isSelected ? "checkmark.circle" : "chevron.down")
            }
            .help(isSelected ? "Review controls are expanded" : "Show category, transfer, rule, and rename controls")
            .accessibilityLabel(isSelected ? "Review controls expanded" : "Show full review controls")

            Spacer(minLength: Spacing.xs)

            Button {
                onIgnore()
            } label: {
                Label("Ignore", systemImage: "eye.slash")
            }
            .help("Ignore unless materially changed")
            .accessibilityLabel("Ignore transaction")
            .accessibilityHint("Marks \(item.effectiveMerchantName) reviewed unless it changes materially and shows a confirmation.")
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private var selectedControls: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Button {
                    onApprove()
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .keyboardShortcut("a", modifiers: [])
                .help("Approve transaction")

                categoryPicker

                Button {
                    transferAction()
                } label: {
                    Label(item.isTransfer ? "Not transfer" : "Transfer", systemImage: "arrow.left.arrow.right")
                }
                .keyboardShortcut("t", modifiers: [])
                .help(item.isTransfer ? "Mark as spend" : "Mark transfer and exclude from budgets")

                ruleMenu

                Button {
                    onIgnore()
                } label: {
                    Label("Ignore", systemImage: "eye.slash")
                }
                .keyboardShortcut("i", modifiers: [])
                .help("Ignore unless materially changed")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            HStack(spacing: Spacing.xs) {
                TextField("Merchant name", text: $merchantDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit(onRename)
                    .accessibilityLabel("Normalized merchant name")

                Button {
                    onRename()
                } label: {
                    Label("Rename", systemImage: "textformat")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .keyboardShortcut("m", modifiers: [])
                .help("Save merchant rename")
            }
        }
    }

    private var categoryPicker: some View {
        Menu {
            ForEach(SpendingCategory.allCases, id: \.self) { category in
                Button {
                    onCategory(category)
                } label: {
                    Label(category.displayName, systemImage: category.iconName)
                }
            }
        } label: {
            Label("Category", systemImage: "tag")
        }
        .keyboardShortcut("c", modifiers: [])
        .help("Change local category")
    }

    private var ruleMenu: some View {
        Menu {
            if item.reasonCodes.contains(.possibleTransfer) || item.isTransfer {
                Button {
                    onTransferRule()
                } label: {
                    Label("Always mark transfer", systemImage: "arrow.left.arrow.right")
                }
            }

            Menu {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    Button {
                        onCategoryRule(category)
                    } label: {
                        Label(category.displayName, systemImage: category.iconName)
                    }
                }
            } label: {
                Label("Always categorize as", systemImage: "tag")
            }
        } label: {
            Label("Rule", systemImage: "wand.and.stars")
        }
        .keyboardShortcut("r", modifiers: [])
        .help("Create a deterministic local rule for this merchant")
    }

    private func transferAction() {
        item.isTransfer ? onNotTransfer() : onTransfer()
    }

    private var leadingSymbolName: String {
        item.reasonCodes.first.map(symbolName(for:)) ?? "tray"
    }

    private var leadingTint: Color {
        item.reasonCodes.contains(where: \.isHighPriority) ? SemanticColors.warning : .secondary
    }

    private var accessibilitySummary: String {
        let reasons = item.reasonCodes.map(\.displayName).joined(separator: ", ")
        let category = item.effectiveCategory?.displayName ?? "Uncategorized"
        let amount = Formatters.currency(item.transaction.displayAmount, format: .full)
        return "\(item.effectiveMerchantName), \(amount), \(category), reasons: \(reasons)"
    }

    private func symbolName(for reason: TransactionReviewReason) -> String {
        switch reason {
        case .uncategorized: "tag"
        case .newMerchant: "person.crop.circle.badge.questionmark"
        case .unusualAmount: "chart.line.uptrend.xyaxis"
        case .possibleTransfer: "arrow.left.arrow.right"
        case .recurringChanged: "calendar.badge.exclamationmark"
        case .pendingChanged: "clock.badge.exclamationmark"
        }
    }

    private func tint(for reason: TransactionReviewReason) -> Color {
        reason.isHighPriority ? SemanticColors.warning : .secondary
    }
}
