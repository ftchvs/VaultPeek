import PlaidBarCore
import SwiftUI

struct ReviewInboxView: View {
    /// When true, the view is hosted inside the right inspector column: it drops
    /// its own raised surface (the column already provides one), scrolls its rows
    /// to fit the column height, shows more rows, and renders an empty-state
    /// prompt instead of collapsing to nothing when the queue is clear.
    var embedded: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var selectedIndex = 0
    @State private var merchantDrafts: [String: String] = [:]
    @State private var actionConfirmation: ReviewActionConfirmation?
    /// Set when the user taps "Mark N reviewed"; holds the pre-computed blast
    /// radius so the confirmation dialog can state exactly how many and which
    /// rows resolve before anything is applied (AND-528).
    @State private var bulkReviewPlan: ReviewBulkActionPlan?
    /// Monotonic token so a queued auto-dismiss only clears the banner it was
    /// scheduled for — a newer action (which bumps the token) is never wiped by
    /// an older timer.
    @State private var confirmationGeneration = 0

    private var snapshot: TransactionReviewInboxSnapshot {
        appState.transactionReviewInboxSnapshot
    }

    private var items: [TransactionReviewItem] {
        Array(snapshot.items.prefix(embedded ? 20 : 6))
    }

    /// The blast radius of a bulk "Mark N reviewed" over the rows currently
    /// listed. No explicit selection: the radius is every unresolved row the user
    /// can see in this surface (the list is already truncated to the visible
    /// rows), so the action never resolves more than is on screen.
    private var listedBulkPlan: ReviewBulkActionPlan {
        ReviewBulkActionPlan.markReviewed(items: items)
    }

    private var headerPresentation: ReviewInboxPrivacyPresentation {
        ReviewInboxPrivacyPresentation.make(
            totalCount: snapshot.totalCount,
            highPriorityCount: snapshot.highPriorityCount,
            isPrivate: appState.shouldMaskFinancialValues
        )
    }

    var body: some View {
        if embedded || snapshot.totalCount > 0 || actionConfirmation != nil {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header

                if let actionConfirmation {
                    ReviewActionConfirmationBanner(confirmation: actionConfirmation)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                if appState.shouldMaskFinancialValues {
                    privateInboxPlaceholder
                } else if items.isEmpty {
                    emptyInboxPlaceholder
                } else {
                    rowsScroll {
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
                                animatingResolution { appState.approveReviewItem(item.id) }
                            },
                            onCategory: { category in
                                recordAction(.categorized(category), for: item)
                                animatingResolution { appState.updateReviewCategory(item.id, category: category) }
                            },
                            onRename: {
                                recordAction(.renamed, for: item)
                                animatingResolution { appState.renameReviewMerchant(item.id, merchantName: merchantDraft(for: item)) }
                            },
                            onTransfer: {
                                recordAction(.markedTransfer, for: item)
                                animatingResolution { appState.markReviewItemTransfer(item.id) }
                            },
                            onNotTransfer: {
                                recordAction(.markedSpend, for: item)
                                animatingResolution { appState.markReviewItemTransfer(item.id, isTransfer: false) }
                            },
                            onCategoryRule: { category in
                                recordAction(.ruleCreated, for: item)
                                animatingResolution { appState.createRule(from: item, category: category) }
                            },
                            onTransferRule: {
                                recordAction(.ruleCreated, for: item)
                                animatingResolution { appState.createRule(from: item, markTransfer: true) }
                            },
                            onIgnore: {
                                recordAction(.ignored, for: item)
                                animatingResolution { appState.ignoreReviewItem(item.id) }
                            }
                        )
                        // Resolved rows animate out (and the rest slide up) when
                        // the action removes them from the snapshot.
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                    }
                }
            }
            .padding(Spacing.sm)
            .modifier(ConditionalRaisedSurface(embedded: embedded))
            .focusable()
            .focused($isFocused)
            // Keep the container focusable for arrow-key row navigation, but
            // suppress the macOS system focus ring. Embedded as the full right
            // column the ring wraps the whole panel and reads as an accidental
            // "selected" state; the selected row already shows its own accent.
            .focusEffectDisabled()
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
                    withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) { actionConfirmation = nil }
                }
            }
            .onMoveCommand(perform: moveSelection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(headerPresentation.accessibilityLabel)
            .confirmationDialog(
                bulkReviewPlan.map { "Mark \($0.count) reviewed?" } ?? "Mark reviewed?",
                isPresented: bulkReviewConfirmationBinding,
                titleVisibility: .visible,
                presenting: bulkReviewPlan
            ) { plan in
                Button("Mark \(plan.count) Reviewed") { applyBulkReview(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                // State the blast radius in full so the user sees how many and
                // which rows resolve before confirming — never a bare count.
                Text(plan.blastRadiusDescription())
            }
        }
    }

    /// Drives the confirmation dialog: presented while a plan is staged, and
    /// clearing the plan when dismissed.
    private var bulkReviewConfirmationBinding: Binding<Bool> {
        Binding(
            get: { bulkReviewPlan != nil },
            set: { presented in if !presented { bulkReviewPlan = nil } }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Review Inbox")
                    .sectionTitle()

                Text(headerPresentation.subtitle)
                    .microText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let highPriorityBadge = headerPresentation.highPriorityBadge {
                Label(highPriorityBadge, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SemanticColors.warning)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(headerPresentation.highPriorityAccessibilityLabel ?? highPriorityBadge)
            }

            // Bulk "Mark N reviewed": staging a plan opens the blast-radius
            // confirmation. Hidden while masked (rows hidden) or when the inbox
            // has nothing to resolve. The N rides the label text + icon, never
            // color alone.
            if !appState.shouldMaskFinancialValues, !listedBulkPlan.isEmpty {
                Button {
                    bulkReviewPlan = listedBulkPlan
                } label: {
                    Label("Mark \(listedBulkPlan.count) reviewed", systemImage: "checklist")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Review all \(listedBulkPlan.count) listed transactions at once")
                .accessibilityLabel("Mark \(listedBulkPlan.count) listed transactions reviewed")
                .accessibilityHint("Shows which transactions will be marked reviewed before applying.")
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

    // Shown only in the embedded (right-column) layout when the queue is clear,
    // so the column reads as intentional space instead of collapsing to nothing.
    private var emptyInboxPlaceholder: some View {
        ContentUnavailableView {
            Label("Inbox Clear", systemImage: "checkmark.circle")
        } description: {
            Text("New or unusual transactions show up here to review, recategorize, or rename.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Review inbox clear. New or unusual transactions will appear here to review.")
    }

    // Rows scroll inside the fixed-height inspector column; in the standalone
    // layout they flow in the surrounding dashboard scroll view.
    @ViewBuilder
    private func rowsScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if embedded {
            ScrollView { VStack(spacing: 0) { content() } }
        } else {
            VStack(spacing: 0) { content() }
        }
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

    // Runs a review mutation inside an animation so the resulting snapshot
    // change (a resolved row leaving the inbox, the rest sliding up) animates
    // fluidly instead of snapping. Gated by Reduce Motion.
    private func animatingResolution(_ change: () -> Void) {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            change()
        }
    }

    /// Applies a confirmed bulk review: marks the plan's rows reviewed via the
    /// shared AppState path, animates the resolved rows out, announces the count
    /// and result to VoiceOver, and surfaces the same confirmation banner the
    /// single-row actions use. Clears the staged plan either way.
    private func applyBulkReview(_ plan: ReviewBulkActionPlan) {
        bulkReviewPlan = nil
        guard !plan.isEmpty else { return }
        recordBulkAction(count: plan.count)
        animatingResolution { appState.bulkMarkReviewed(ids: plan.affectedIDs) }
        // Announce the outcome with the count spelled out, so the result is not
        // conveyed only by rows silently vanishing from the list.
        let noun = plan.count == 1 ? "transaction" : "transactions"
        AccessibilityNotification.Announcement("Marked \(plan.count) \(noun) reviewed").post()
    }

    private func recordBulkAction(count: Int) {
        confirmationGeneration &+= 1
        let generation = confirmationGeneration
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            actionConfirmation = ReviewActionConfirmation(action: .bulkReviewed(count), merchantName: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard confirmationGeneration == generation else { return }
            withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) { actionConfirmation = nil }
        }
    }

    private func recordAction(_ action: ReviewActionConfirmation.Action, for item: TransactionReviewItem) {
        confirmationGeneration &+= 1
        let generation = confirmationGeneration
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            actionConfirmation = ReviewActionConfirmation(action: action, merchantName: item.effectiveMerchantName)
        }
        // Auto-dismiss so the banner never persists indefinitely. The generation
        // guard means a newer action's banner is not cleared by this older timer.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard confirmationGeneration == generation else { return }
            withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) { actionConfirmation = nil }
        }
    }
}

/// In the standalone (center) layout the inbox owns a raised surface; in the
/// embedded (right-column) layout the column already provides one, so adding a
/// second would nest cards (the flattening AND-474 removed).
private struct ConditionalRaisedSurface: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content.glassSurface(.raised)
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
        case bulkReviewed(Int)

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
            case let .bulkReviewed(count):
                "Marked \(count) reviewed"
            }
        }
    }

    let action: Action
    /// The single merchant a row-level action resolved. Nil for batch actions
    /// (bulk review), where the subject is a count, not one merchant.
    let merchantName: String?

    var bannerText: String {
        if let merchantName {
            return "\(action.message): \(merchantName)"
        }
        return action.message
    }

    var accessibilityLabel: String {
        if let merchantName {
            return "Review action completed: \(action.message) for \(merchantName)"
        }
        return "Review action completed: \(action.message)"
    }
}

private struct ReviewActionConfirmationBanner: View {
    let confirmation: ReviewActionConfirmation

    var body: some View {
        Label {
            Text(confirmation.bannerText)
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

            // Collapsed rows show the compact Approve / Review / Ignore strip;
            // the selected row expands to the full controls instead of stacking
            // both (which previously duplicated Approve and Ignore).
            if isSelected {
                selectedControls
            } else {
                compactActionStrip
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        // Flattened: no per-row card. Selection reads as a subtle inline
        // emphasis (tinted wash + leading accent) inside the single raised
        // surface, with Dividers separating rows.
        // Wash fills the row; the 2pt accent is a separate leading overlay so it
        // sits flush on the left edge (the prior single multi-view background
        // could place the bar mid-row).
        .background {
            if isSelected { SemanticColors.warning.opacity(0.08) }
        }
        .overlay(alignment: .leading) {
            if isSelected {
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

                    if item.isNLSuggestedCategory {
                        suggestedBadge
                    }

                    Text(Formatters.displayTransactionDate(item.transaction.date))
                        .microText()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                reasonChips
            }
        }
    }

    // On-device NL inference badge (AND-507). Pairs a sparkles icon AND the
    // word "Suggested" with the tint, so meaning is never carried by color
    // alone (accessibility rule). Shown only when the category was backfilled
    // by the zero-setup NL tier rather than the user or Plaid.
    private var suggestedBadge: some View {
        Label("Suggested", systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(SemanticColors.brand)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SemanticColors.brand.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(SemanticColors.brand.opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("Category suggested on device")
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
            // Five controls don't fit the 320pt inspector column with text, so
            // show icons only; each keeps its Label text for VoiceOver plus a
            // .help tooltip and a keyboard shortcut.
            .labelStyle(.iconOnly)

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
        // The row Button's label overrides the child "Suggested" badge, so fold
        // the on-device provenance into the spoken category — otherwise VoiceOver
        // announces an NL suggestion identically to a Plaid/user category even
        // though the visual UI shows the "Suggested" badge.
        let baseCategory = item.effectiveCategory?.displayName ?? "Uncategorized"
        let category = item.isNLSuggestedCategory ? "\(baseCategory) (suggested on device)" : baseCategory
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
        case .changedSinceReview: "arrow.triangle.2.circlepath"
        }
    }

    private func tint(for reason: TransactionReviewReason) -> Color {
        reason.isHighPriority ? SemanticColors.warning : .secondary
    }
}
