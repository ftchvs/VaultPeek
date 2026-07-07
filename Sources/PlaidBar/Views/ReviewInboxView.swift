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
    /// Opens the detached multi-select review Table window for power review (AND-532).
    /// Injected by the app scene; a no-op in previews / headless renders.
    @Environment(\.openReviewTable) private var openReviewTable
    /// Whether direct-manipulation haptics fire (AND-576). Read here so the
    /// review actions — the highest-value direct manipulations in the app — give
    /// a tactile confirmation on Force Touch trackpads when enabled. Off-state is
    /// a no-op (behavior equals today). The pure mapping lives in Core.
    @AppStorage(HapticFeedbackPreference.storageKey) private var hapticRaw = HapticFeedbackPreference.defaultValue.rawValue
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
    /// The inline "always categorize <merchant> as <category>?" offer staged the
    /// moment the user recategorizes a row (AND-531). One at a time, dismissible;
    /// a newer correction replaces an older offer. Accepting routes through the
    /// existing `AppState.createRule` path. Nil when no offer is pending. The pure
    /// `InlineCategoryRulePrompt` decides whether an offer is even worth showing
    /// (suppressed for a blank merchant or a duplicate rule), so this stays
    /// non-nagging.
    @State private var rulePrompt: InlineCategoryRulePrompt?
    /// The row the staged `rulePrompt` was offered for, captured so an Accept can
    /// route through the existing `AppState.createRule(from:category:)` path even
    /// after the recategorization removed the row from the live snapshot.
    @State private var rulePromptItem: TransactionReviewItem?

    private var snapshot: TransactionReviewInboxSnapshot {
        appState.transactionReviewInboxSnapshot
    }

    private var items: [TransactionReviewItem] {
        Array(snapshot.items.prefix(embedded ? 20 : 6))
    }

    /// The listed rows bucketed into recency sections (Today / Yesterday / This
    /// Week / Earlier) by the pure Core helper (AND-529). `asOf` is the live now
    /// captured at render; the Core helper owns the bucketing so it stays
    /// deterministic and testable. Empty sections are omitted.
    private var sections: [ReviewInboxDateSections.Section] {
        ReviewInboxDateSections.sections(items: items, asOf: Date())
    }

    /// Rows in section-render order — the flattened order the keyboard selection
    /// index walks, so arrow keys move down a section then into the next, matching
    /// what the user sees (the priority-sorted `items` order can differ).
    private var orderedItems: [TransactionReviewItem] {
        sections.flatMap(\.items)
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
                    ReviewActionConfirmationBanner(
                        confirmation: actionConfirmation,
                        isPrivate: appState.shouldMaskFinancialValues
                    )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                // Inline "always categorize …?" offer (AND-531). Suppressed while
                // masked — the offer names the merchant, a value the Privacy Mask
                // hides — so it appears only when rows themselves are visible.
                if !appState.shouldMaskFinancialValues, let rulePrompt {
                    InlineCategoryRulePromptBanner(
                        prompt: rulePrompt,
                        onCreate: { acceptRulePrompt(rulePrompt) },
                        onDismiss: { dismissRulePrompt() }
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                if appState.shouldMaskFinancialValues {
                    privateInboxPlaceholder
                } else if items.isEmpty {
                    emptyInboxPlaceholder
                } else {
                    rowsScroll {
                        sectionedRows
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
            // Drive the live on-device Foundation Models categorization tier
            // (AND-565). A no-op unless Apple Intelligence is `.available`, so the
            // no-FM device makes no model call. Re-runs when the queue changes so
            // newly-arrived uncategorized rows get a suggestion. Results are
            // display-only suggestions surfaced via the "Suggested" badge; they
            // never auto-apply.
            .task(id: snapshot.totalCount) {
                await appState.refreshFoundationModelsCategorySuggestions()
            }
            .onChange(of: snapshot.totalCount) { _, newCount in
                clampSelection()
                // When the queue drains to empty, drop any lingering confirmation
                // banner so the inbox can collapse out of the popover instead of
                // sitting in an empty "0 items" state with a stuck banner.
                if newCount == 0 {
                    withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                        actionConfirmation = nil
                        rulePrompt = nil
                        rulePromptItem = nil
                    }
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
            // Privacy Mask / App Lock can engage while the bulk confirmation is
            // staged. The cached plan's dialog title/message include exact counts
            // and blast-radius details, so drop it as soon as masking begins.
            .onChange(of: appState.shouldMaskFinancialValues) { _, masked in
                if masked { bulkReviewPlan = nil }
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

    /// The listed rows rendered as date-grouped sections (AND-529): each section
    /// gets a header (label + count + per-section "approve all") and its rows. The
    /// running `globalIndex` keeps the single keyboard selection index consistent
    /// across sections (it walks `orderedItems`, the flattened section order).
    @ViewBuilder
    private var sectionedRows: some View {
        let sections = sections
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(sectionStartOffsets(sections).enumerated()), id: \.element.section.id) { sectionIndex, entry in
                if sectionIndex > 0 {
                    Divider().padding(.vertical, Spacing.xxs)
                }
                sectionHeader(entry.section)

                VStack(spacing: 0) {
                    ForEach(Array(entry.section.items.enumerated()), id: \.element.id) { rowIndex, item in
                        if rowIndex > 0 {
                            Divider()
                        }
                        reviewRow(item: item, globalIndex: entry.startOffset + rowIndex)
                    }
                }
            }
        }
    }

    /// Pairs each section with its starting offset in `orderedItems`, so a row's
    /// global selection index is `startOffset + rowIndex`.
    private func sectionStartOffsets(
        _ sections: [ReviewInboxDateSections.Section]
    ) -> [(section: ReviewInboxDateSections.Section, startOffset: Int)] {
        var offset = 0
        return sections.map { section in
            let entry = (section: section, startOffset: offset)
            offset += section.items.count
            return entry
        }
    }

    /// A date-group header: the section label, its row count, and a per-section
    /// "approve all in section" affordance. The count rides the text (never color
    /// alone); the affordance stages the same blast-radius confirmation the global
    /// bulk bar uses, scoped to this section's rows, and applies via the shared
    /// bulk-review path. No sensitive figures appear — labels and counts only.
    @ViewBuilder
    private func sectionHeader(_ section: ReviewInboxDateSections.Section) -> some View {
        let plan = ReviewBulkActionPlan.markReviewed(items: section.items)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(section.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(section.count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(section.count) \(section.count == 1 ? "transaction" : "transactions")")

            Spacer(minLength: Spacing.xs)

            // Per-section approve: only when the section has unresolved rows. Stages
            // the section-scoped plan so the existing confirmation dialog states the
            // exact count + which merchants before anything resolves.
            if !plan.isEmpty {
                Button {
                    bulkReviewPlan = plan
                } label: {
                    Label("Approve \(plan.count)", systemImage: "checkmark.circle")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Approve all \(plan.count) transactions in \(section.label)")
                .accessibilityLabel("Approve all \(plan.count) transactions in \(section.label)")
                .accessibilityHint("Shows which transactions will be marked reviewed before applying.")
            }
        }
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// One review row wired to the shared single-action AppState paths. Factored
    /// out so the sectioned layout (AND-529) and the selection index can drive it
    /// without duplicating the per-row action wiring.
    private func reviewRow(item: TransactionReviewItem, globalIndex: Int) -> some View {
        ReviewInboxRow(
            item: item,
            foundationModelsSuggestion: appState.foundationModelsCategorySuggestion(for: item.id),
            isSelected: globalIndex == selectedIndex,
            merchantDraft: merchantDraftBinding(for: item),
            onSelect: { selectedIndex = globalIndex },
            onApprove: {
                recordAction(.approved, for: item)
                animatingResolution { appState.approveReviewItem(item.id) }
            },
            onCategory: { category in
                recordAction(.categorized(category), for: item)
                animatingResolution { appState.updateReviewCategory(item.id, category: category) }
                // Offer to promote this one-off correction into a durable rule
                // (AND-531). The pure model suppresses the offer for a blank
                // merchant or a rule that already exists, so this never nags.
                stageRulePrompt(for: item, category: category)
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
        // Resolved rows animate out (and the rest slide up) when the action
        // removes them from the snapshot.
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
    }

    /// The discrete Copilot-style unreviewed-count chip sat next to the title
    /// (AND-533). Sourced from the pure Core helper, which returns nil when the
    /// queue is empty or while Privacy Mask / App Lock is active (so the count
    /// never leaks — the AND-483 contract). Nil here hides the chip entirely.
    private var unreviewedBadgeText: String? {
        ReviewInboxPrivacyPresentation.unreviewedBadge(
            count: snapshot.totalCount,
            isMasked: appState.shouldMaskFinancialValues
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("Review Inbox")
                        .sectionTitle()

                    // Discrete at-a-glance unreviewed-count chip (AND-533). The
                    // meaning rides the number itself plus the VoiceOver label
                    // "N to review" — never color alone (ACCESSIBILITY.md). Hidden
                    // at 0 and under Privacy Mask (Core helper returns nil), so no
                    // count leaks (AND-483). This is additive: the subtitle below
                    // and the high-priority badge are unchanged.
                    if let unreviewedBadgeText {
                        Text("\(snapshot.totalCount)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SemanticColors.brand)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(SemanticColors.brand.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule().stroke(SemanticColors.brand.opacity(0.20), lineWidth: 1)
                            }
                            .accessibilityLabel(unreviewedBadgeText)
                    }
                }

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

            // Confidence-aware sort control (AND-553). Re-orders the listed rows
            // between the historical "most urgent" order and "low confidence
            // first", which floats Plaid's LOW/UNKNOWN categorizations to the top.
            // The current order rides the menu label text + glyph (never color
            // alone). Shown only with rows to order; the pure ordering lives in
            // Core (`ReviewInboxSorting`) so the control just flips a stored enum.
            if !appState.shouldMaskFinancialValues, snapshot.totalCount > 0 {
                sortControl
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

            // Power-review entry point (AND-532): opens the detached multi-select
            // review Table window. Shown only when there is something to review, so
            // it never clutters a clear inbox.
            if snapshot.totalCount > 0 {
                Button {
                    openReviewTable()
                } label: {
                    Label("Open review table", systemImage: "tablecells")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Open the multi-select review table in a window")
                .accessibilityLabel("Open review table in a window")
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

    /// The confidence-aware sort control (AND-553). A compact menu that flips the
    /// stored `appState.reviewInboxSortOrder`; each option carries its title + a
    /// glyph so the choice never reads by color alone (ACCESSIBILITY.md). Changing
    /// it invalidates the cached snapshot so the rows immediately re-order.
    private var sortControl: some View {
        @Bindable var state = appState
        return Menu {
            Picker("Sort", selection: $state.reviewInboxSortOrder) {
                ForEach(ReviewInboxSortOrder.allCases) { order in
                    Label(order.title, systemImage: order.glyphName).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Sort: \(appState.reviewInboxSortOrder.title)", systemImage: "arrow.up.arrow.down")
                .font(.caption2.weight(.semibold))
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.mini)
        .fixedSize()
        .help("Sort the review queue: \(ReviewInboxSortOrder.allCases.map(\.title).joined(separator: " or "))")
        .accessibilityLabel("Sort review queue, currently \(appState.reviewInboxSortOrder.title)")
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

    /// Resolved haptic preference (default on). Off makes every `play` a no-op,
    /// so behavior with haptics disabled equals today.
    private var hapticsEnabled: Bool {
        (HapticFeedbackPreference(rawValue: hapticRaw) ?? .on).isEnabled
    }

    private func recordBulkAction(count: Int) {
        // Bulk "mark N reviewed" is a committed positive resolution — same
        // tactile confirmation as a single-row approve (AND-576). No-op when the
        // preference is off or the hardware lacks a haptic engine.
        HapticFeedback.play(.reviewResolved, enabled: hapticsEnabled)
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
        // Every committed single-row review action is a direct manipulation that
        // resolves or recategorizes a row — give a tactile confirmation on Force
        // Touch trackpads (AND-576). Ignore reads as a softer "removed" click;
        // all other resolutions share the positive confirmation. No-op when the
        // preference is off, matching today's behavior exactly.
        HapticFeedback.play(action.hapticInteraction, enabled: hapticsEnabled)
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

    /// Stages the inline "always categorize <merchant> as <category>?" offer for a
    /// just-recategorized row (AND-531). The pure `InlineCategoryRulePrompt.make`
    /// decides whether an offer is even worth showing — it returns nil for a blank
    /// merchant or a category rule that already exists — so a no-op or duplicate
    /// correction never produces a prompt. A newer correction replaces any older
    /// pending offer (one prompt at a time, non-nagging).
    private func stageRulePrompt(for item: TransactionReviewItem, category: SpendingCategory) {
        let prompt = InlineCategoryRulePrompt.make(
            transactionID: item.id,
            merchantName: item.effectiveMerchantName,
            category: category,
            existingRules: appState.transactionRules
        )
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            rulePrompt = prompt
            rulePromptItem = prompt == nil ? nil : item
        }
    }

    /// Accepts the inline offer: creates the merchant→category rule through the
    /// EXISTING `AppState.createRule(from:category:)` path (so the rule flows into
    /// the override-aware spend math like any other rule), announces it, and clears
    /// the offer. Routing through the captured row keeps the matcher/merchant/
    /// exclusion context identical to a rule made from the row's Rule menu.
    private func acceptRulePrompt(_ prompt: InlineCategoryRulePrompt) {
        defer { clearRulePrompt() }
        guard let item = rulePromptItem, item.id == prompt.transactionID else { return }
        appState.createRule(from: item, category: prompt.category)
        AccessibilityNotification.Announcement(
            "Created rule: always categorize \(prompt.merchantName) as \(prompt.category.displayName)"
        ).post()
    }

    /// Dismisses the inline offer without creating a rule. The one-off correction
    /// already applied stands; only the durable-rule offer is declined.
    private func dismissRulePrompt() {
        clearRulePrompt()
    }

    private func clearRulePrompt() {
        withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
            rulePrompt = nil
            rulePromptItem = nil
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
            content.solidDataSurface(cornerRadius: Radius.panel, fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.controlFillOpacity)))
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

        /// The haptic interaction kind this action plays (AND-576). Ignore is the
        /// one "removed" gesture that gets the softer level-change click; every
        /// other committed resolution shares the positive confirmation. The pure
        /// `HapticFeedbackPolicy` maps these kinds to concrete patterns.
        var hapticInteraction: HapticInteraction {
            switch self {
            case .ignored: .reviewIgnored
            case .approved, .categorized, .renamed, .markedTransfer, .markedSpend, .ruleCreated, .bulkReviewed:
                .reviewResolved
            }
        }
    }

    let action: Action
    /// The single merchant a row-level action resolved. Nil for batch actions
    /// (bulk review), where the subject is a count, not one merchant. The
    /// banner's user-facing copy and accessibility label are produced by
    /// `ReviewActionConfirmationPrivacyPresentation`, which handles both the
    /// nil-merchant (bulk) case and Privacy Mask redaction.
    let merchantName: String?
}

private struct ReviewActionConfirmationBanner: View {
    let confirmation: ReviewActionConfirmation
    let isPrivate: Bool

    private var presentation: ReviewActionConfirmationPrivacyPresentation {
        ReviewActionConfirmationPrivacyPresentation.make(
            actionMessage: confirmation.action.message,
            merchantName: confirmation.merchantName,
            isPrivate: isPrivate
        )
    }

    var body: some View {
        Label {
            Text(presentation.message)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .foregroundStyle(SemanticColors.positive)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emphasizedDataSurface(tint: SemanticColors.positive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// The inline, dismissible "always categorize <merchant> as <category>?" offer
/// shown the moment the user recategorizes a review row (AND-531).
///
/// Turning a one-off correction into a durable `TransactionRule` is the whole
/// value of Copilot-style review — but the offer must never nag, so it is a
/// single inline banner (one at a time), it is dismissible, and accepting routes
/// through the same `AppState.createRule` path the row's Rule menu uses. The
/// banner names the merchant and category as text (never color alone — the
/// "Create rule" affordance always carries its label + glyph), matching the
/// ACCESSIBILITY rule. Privacy: the parent suppresses this banner entirely while
/// Privacy Mask / App Lock is active, so the merchant name never renders masked.
private struct InlineCategoryRulePromptBanner: View {
    let prompt: InlineCategoryRulePrompt
    let onCreate: () -> Void
    let onDismiss: () -> Void

    private var message: String {
        "Always categorize \(prompt.merchantName) as \(prompt.category.displayName)?"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "wand.and.stars")
            }
            .foregroundStyle(SemanticColors.brand)

            Spacer(minLength: Spacing.xs)

            Button(action: onCreate) {
                Label("Create rule", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .help("Always categorize \(prompt.merchantName) as \(prompt.category.displayName) from now on")
            .accessibilityHint("Creates a rule so future transactions from this merchant are categorized automatically.")

            Button(action: onDismiss) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Dismiss without creating a rule")
            .accessibilityLabel("Dismiss rule suggestion")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emphasizedDataSurface(tint: SemanticColors.brand)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}

private struct ReviewInboxRow: View {
    let item: TransactionReviewItem
    /// On-device Foundation Models category *suggestion* for this row, when an
    /// `.available` FM device produced one (AND-565). Display-only: it badges the
    /// row but never auto-applies — the user still approves through the existing
    /// review flow. `nil` on every non-FM device and for rows the model skipped,
    /// so the row renders exactly as before there.
    var foundationModelsSuggestion: MerchantCategorySuggestion?
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
                    // Colored icon+text category pill (AND-530). Color is a
                    // redundant layer only: the pill always shows the category
                    // name as text + a glyph, so meaning never rides on color
                    // (ACCESSIBILITY.md). The pure CategoryPillModel owns the
                    // category→{title, glyph, accent} mapping.
                    CategoryPill(model: CategoryPillModel.make(category: displayCategory))

                    if isShowingSuggestion {
                        suggestedBadge
                    }

                    // Flags a row that the opt-in auto-review pass cleared and that
                    // later reopened (AND-553) — pairs a glyph AND the word
                    // "Auto-reviewed" so the provenance never rides on color alone.
                    if item.wasAutoReviewed {
                        autoReviewedBadge
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

    // Auto-review provenance badge (AND-553). Shown on a row that the opt-in
    // high-confidence pass cleared and that later reopened, so the user can see it
    // was resolved automatically. Glyph + text carry the meaning together.
    private var autoReviewedBadge: some View {
        Label("Auto-reviewed", systemImage: "checkmark.seal")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("Automatically reviewed")
    }

    private var reasonChips: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(item.reasonCodes, id: \.self) { reason in
                Label(reason.displayName, systemImage: reason.glyphName)
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
        item.reasonCodes.first.map(\.glyphName) ?? "tray"
    }

    private var leadingTint: Color {
        item.reasonCodes.contains(where: \.isHighPriority) ? SemanticColors.warning : .secondary
    }

    /// The category the row displays. Prefers the persisted/Plaid/NL effective
    /// category; only when none exists does it fall back to a display-only
    /// Foundation Models *suggestion* so an `.available` FM device fills the pill
    /// instead of showing "Uncategorized". This is display-only — it never
    /// persists and never bypasses the review/override flow (AND-565).
    private var displayCategory: SpendingCategory? {
        item.effectiveCategory ?? foundationModelsSuggestion?.category
    }

    /// Whether the displayed category is an on-device *suggestion* (NL backfill or
    /// a Foundation Models fill of an otherwise-uncategorized row) and so should
    /// carry the "Suggested" badge. A real Plaid/user category never badges, even
    /// if FM also produced a (now-unused) suggestion.
    private var isShowingSuggestion: Bool {
        item.isNLSuggestedCategory
            || (item.effectiveCategory == nil && foundationModelsSuggestion != nil)
    }

    private var accessibilitySummary: String {
        let reasons = item.reasonCodes.map(\.displayName).joined(separator: ", ")
        // The row Button's label overrides the child "Suggested" badge, so fold
        // the on-device provenance into the spoken category — otherwise VoiceOver
        // announces a suggestion identically to a Plaid/user category even though
        // the visual UI shows the "Suggested" badge.
        let baseCategory = displayCategory?.displayName ?? "Uncategorized"
        let category = isShowingSuggestion ? "\(baseCategory) (suggested on device)" : baseCategory
        let amount = Formatters.currency(item.transaction.displayAmount, format: .full)
        let autoReviewed = item.wasAutoReviewed ? ", automatically reviewed" : ""
        return "\(item.effectiveMerchantName), \(amount), \(category), reasons: \(reasons)\(autoReviewed)"
    }

    private func tint(for reason: TransactionReviewReason) -> Color {
        reason.isHighPriority ? SemanticColors.warning : .secondary
    }
}

/// A colored icon+text category pill for a review row (AND-530).
///
/// Renders the category glyph + name in a tinted capsule. The accent is a
/// **redundant** layer only — the title text and the glyph always carry the
/// meaning, so the pill never conveys the category by color alone
/// (ACCESSIBILITY.md). The category→{title, glyph, accent} mapping lives in the
/// pure, unit-tested `CategoryPillModel` in PlaidBarCore; this view is a thin
/// renderer that resolves the accent through the app's `CategoryAccentTokens`
/// (falling back to a neutral secondary tint for the uncategorized case).
///
/// Privacy: the pill carries only a category label and glyph — never a merchant,
/// amount, or other sensitive figure — and the inbox never renders rows at all
/// while masked (it shows `privateInboxPlaceholder` instead), so nothing leaks.
private struct CategoryPill: View {
    let model: CategoryPillModel

    private var accent: Color {
        model.category.map(CategoryAccentTokens.color(for:)) ?? .secondary
    }

    var body: some View {
        Label(model.title, systemImage: model.glyph)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(accent)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accent.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(accent.opacity(0.18), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Category: \(model.title)")
    }
}
