import PlaidBarCore
import SwiftUI

/// **Review** destination (3-column — IA §3.1/§5.3, `[⌘2]`) — the flagship triage
/// surface (Epic 6, AND-584), the window-first re-host of the Copilot-style Review
/// Inbox (spec §3/§5, Option A).
///
/// The content column is the triage flow itself; the detail column (`Inspector`)
/// is a contextual triage guide. The detail column is **content-gated, not
/// existence-gated** (IA §3.1): when the inbox is clear the inspector shows the
/// "nothing to review" prompt rather than collapsing.
///
/// **What this re-hosts (no engine work — wiring + surfacing only):**
/// - **Triage mode** embeds the existing ``ReviewInboxView`` (`embedded:`), which
///   already ships date-sectioned rows (Today / Yesterday / This Week / Earlier),
///   single-key triage on the focused row (A approve · C recategorize · T transfer ·
///   R rule · M rename · I ignore — each undoable with ⌘Z, a calm confirmation
///   banner + haptic + auto-advance), the inline "Always categorize {merchant} as
///   {category}?" rule prompt (AND-531), the unreviewed-count badge (AND-533), and
///   the bulk "Mark N reviewed" with blast-radius confirmation (AND-528).
/// - **Table mode** embeds the existing ``ReviewTableWindow`` — the multi-select
///   bulk engine (AND-532) with per-row + multi-row blast-radius confirmation
///   (which merchants an action touches) and the masked dialog that respects
///   Privacy Mask.
///
/// Both bodies read the same ``AppState`` (the shell injects it) and route every
/// mutation through the existing review action paths, so the triage list, the
/// table, and the legacy popover inbox can never diverge in what an action means.
/// The triage/rule logic stays in PlaidBarCore (``TransactionReviewInbox``,
/// ``EffectiveCategoryResolver``); this destination owns only layout + the mode
/// toggle.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). With the flag off the popover is byte-identical —
/// this file is never instantiated.
struct ReviewDestinationView: View {
    @Environment(AppState.self) private var appState

    /// Triage ↔ Table presentation, persisted per-window so a power user who lives
    /// in the table stays there across re-opens of the same window. `@SceneStorage`
    /// keeps it window-scoped (each workspace window remembers its own mode) without
    /// touching shared `AppState`.
    @SceneStorage("review.workspace.mode") private var modeRaw = ReviewWorkspaceMode.triage.rawValue

    private var mode: ReviewWorkspaceMode {
        get { ReviewWorkspaceMode(rawValue: modeRaw) ?? .triage }
        nonmutating set { modeRaw = newValue.rawValue }
    }

    private var snapshot: TransactionReviewInboxSnapshot {
        appState.transactionReviewInboxSnapshot
    }

    /// The discrete unreviewed-count chip for the destination header (AND-533).
    /// Sourced from the same pure Core helper the inbox uses, so it returns nil at
    /// zero and while Privacy Mask / App Lock is active (the count never leaks — the
    /// AND-483 contract).
    private var unreviewedBadgeText: String? {
        ReviewInboxPrivacyPresentation.unreviewedBadge(
            count: snapshot.totalCount,
            isMasked: appState.shouldMaskFinancialValues
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.xl) {
            header

            switch mode {
            case .triage:
                // The existing inbox in its embedded (column-hosted) layout: it
                // drops its own raised surface to fit the column, scrolls its rows,
                // and shows a "Inbox Clear" empty state instead of collapsing. It
                // is re-hosted whole (the triage engine, single-key actions, inline
                // rule prompt, undo, and bulk path are all unchanged); only the
                // surrounding canvas is brought to desk-distance window density.
                ReviewInboxView(embedded: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .table:
                // The detached power-review Table, re-hosted inline. It already
                // owns its own header/empty/masked states and the multi-select
                // bulk engine + blast-radius confirmation, so it slots in whole.
                ReviewTableWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(WindowMetrics.canvasMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(RouteDestination.review.title)
    }

    /// The window-scale page header (desk distance — ``WindowMetrics`` /
    /// ``WindowTypography``): a `largeTitle` page identity with the live unreviewed
    /// chip, a `body`-scale subtitle, and the Triage | Table mode toggle. One step
    /// up from the popover inbox's caption-scale title so it reads as a workspace
    /// page, not a glance.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.lg) {
            VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                    Text("Review")
                        .windowLargeTitle()

                    // Unreviewed-count chip. Meaning rides the number + the
                    // VoiceOver label "N to review", never color alone
                    // (ACCESSIBILITY.md). Hidden at 0 and under Privacy Mask.
                    if let unreviewedBadgeText {
                        Text("\(snapshot.totalCount)")
                            .font(.headline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SemanticColors.brand)
                            .padding(.horizontal, WindowMetrics.sm)
                            .padding(.vertical, 4)
                            .background(SemanticColors.brand.opacity(0.12), in: Capsule())
                            .overlay { Capsule().stroke(SemanticColors.brand.opacity(0.20), lineWidth: 1) }
                            .accessibilityLabel(unreviewedBadgeText)
                    }
                }

                Text("Triage new and unusual transactions to zero.")
                    .windowBodyText()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: WindowMetrics.lg)

            modePicker
        }
    }

    /// Triage | Table mode toggle. The two modes carry a glyph **and** a label, so
    /// the selected mode is never conveyed by color/selection-tint alone
    /// (ACCESSIBILITY.md). A segmented control keeps both affordances always
    /// visible — the spec's "Triage | Table mode toggle".
    private var modePicker: some View {
        Picker("Review mode", selection: modeBinding) {
            ForEach(ReviewWorkspaceMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
        .fixedSize()
        .accessibilityLabel("Review mode")
        .accessibilityHint("Switch between single-item triage and the multi-select table.")
        .help("Triage one item at a time, or open the multi-select table for bulk actions")
    }

    private var modeBinding: Binding<ReviewWorkspaceMode> {
        Binding(get: { mode }, set: { mode = $0 })
    }

    /// The detail-column (inspector) pane for Review — a contextual triage guide.
    ///
    /// The content column already merges the list **and** the inline triage detail
    /// (each inbox row expands in place to its full triage controls), so the third
    /// column is the reference surface: the single-key shortcut cheat-sheet and the
    /// reason-code legend that explains *why* each transaction surfaced. It reads
    /// only ``AppState`` (no cross-column selection state to thread through the
    /// shell), and is content-gated — when the inbox is clear it shows the
    /// "nothing to review" prompt rather than a stale guide.
    struct Inspector: View {
        @Environment(AppState.self) private var appState

        private var snapshot: TransactionReviewInboxSnapshot {
            appState.transactionReviewInboxSnapshot
        }

        /// The reason codes present in the live queue, most-urgent first, so the
        /// legend explains exactly what the user is looking at rather than every
        /// possible reason. Empty when masked or clear (the guide is hidden then).
        private var activeReasons: [TransactionReviewReason] {
            guard !appState.shouldMaskFinancialValues else { return [] }
            let present = Set(snapshot.items.flatMap(\.reasonCodes))
            return TransactionReviewReason.allCases
                .filter(present.contains)
                .sorted { $0.priority < $1.priority }
        }

        var body: some View {
            if appState.shouldMaskFinancialValues {
                maskedPrompt
            } else if snapshot.totalCount == 0 {
                clearPrompt
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: WindowMetrics.lg) {
                        summaryCard
                        shortcutGuide
                        if !activeReasons.isEmpty {
                            reasonLegend
                        }
                    }
                    .padding(WindowMetrics.canvasMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Review guide")
            }
        }

        // MARK: - Cards (window-scale ``WindowSection`` surfaces)

        /// Live at-a-glance counts: how many remain and how many are high-priority.
        /// Counts ride text (never color alone); the high-priority figure pairs a
        /// warning glyph with its label.
        private var summaryCard: some View {
            WindowSection("In your queue", systemImage: "tray.full") {
                VStack(alignment: .leading, spacing: WindowMetrics.sm) {
                    Label(
                        "\(snapshot.totalCount) to review",
                        systemImage: "tray.full"
                    )
                    .windowBodyText()
                    .foregroundStyle(.primary)
                    .accessibilityLabel("\(snapshot.totalCount) transactions to review")

                    if snapshot.highPriorityCount > 0 {
                        Label(
                            "\(snapshot.highPriorityCount) high priority",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .windowBodyText()
                        .foregroundStyle(SemanticColors.warning)
                        .accessibilityLabel("\(snapshot.highPriorityCount) high priority transactions")
                    }
                }
            }
        }

        /// The single-key triage cheat-sheet. The shortcuts work on the focused row
        /// in Triage mode; surfacing them here makes the keyboard flow discoverable
        /// (a native-macOS advantage the spec keeps). Each row is a glyph + key + an
        /// action label, so meaning never rides on a key cap alone.
        private var shortcutGuide: some View {
            WindowSection("Keyboard triage", systemImage: "keyboard") {
                VStack(alignment: .leading, spacing: WindowMetrics.sm) {
                    ForEach(ReviewShortcutGuide.shortcuts) { shortcut in
                        shortcutRow(shortcut)
                    }
                }
            }
        }

        private func shortcutRow(_ shortcut: ReviewShortcutGuide.Shortcut) -> some View {
            HStack(spacing: WindowMetrics.sm) {
                Image(systemName: shortcut.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text(shortcut.key)
                    .font(.callout.weight(.bold).monospaced())
                    .frame(minWidth: 26)
                    .padding(.horizontal, WindowMetrics.xs)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)

                Text(shortcut.action)
                    .windowBodyText()
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(shortcut.action). Press \(shortcut.key).")
        }

        /// Explains the reason codes that actually appear in the current queue —
        /// each as glyph + name + a plain-language "what it means" line. Sorted
        /// most-urgent first; high-priority reasons pair a warning tint with the
        /// "High priority" text so the urgency is never color-only.
        private var reasonLegend: some View {
            WindowSection("Why these surfaced", systemImage: "questionmark.circle") {
                VStack(alignment: .leading, spacing: WindowMetrics.md) {
                    ForEach(activeReasons, id: \.self) { reason in
                        reasonRow(reason)
                    }
                }
            }
        }

        private func reasonRow(_ reason: TransactionReviewReason) -> some View {
            let tint: Color = reason.isHighPriority ? SemanticColors.warning : .secondary
            return HStack(alignment: .top, spacing: WindowMetrics.sm) {
                Image(systemName: ReviewReasonGuide.systemImage(for: reason))
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: WindowMetrics.xs) {
                    HStack(spacing: WindowMetrics.xs) {
                        Text(reason.displayName)
                            .windowBodyText()
                            .fontWeight(.semibold)
                        if reason.isHighPriority {
                            Text("High priority")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SemanticColors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SemanticColors.warning.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(ReviewReasonGuide.explanation(for: reason))
                        .windowSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(reason.displayName)\(reason.isHighPriority ? ", high priority" : ""). \(ReviewReasonGuide.explanation(for: reason))"
            )
        }

        // MARK: - Empty / masked

        private var clearPrompt: some View {
            ContentUnavailableView {
                Label("Nothing to review", systemImage: "checkmark.circle")
            } description: {
                Text("New or unusual transactions show up here to triage. The guide returns when something needs review.")
            }
            .accessibilityLabel("Nothing to review. New or unusual transactions will appear here.")
        }

        private var maskedPrompt: some View {
            ContentUnavailableView {
                Label("Guide hidden", systemImage: "eye.slash")
            } description: {
                Text("The review guide is hidden while Privacy Mask or App Lock is active.")
            }
            .accessibilityLabel("Review guide hidden while VaultPeek is private")
        }
    }
}

/// The Triage ↔ Table presentation of the Review workspace (Epic 6). A small,
/// `Sendable`, `RawRepresentable` enum so it can live in `@SceneStorage`.
private enum ReviewWorkspaceMode: String, CaseIterable, Identifiable {
    /// Single-item triage: the embedded ``ReviewInboxView`` with date sections,
    /// single-key actions, inline rule prompt, and undo.
    case triage
    /// Multi-select power review: the embedded ``ReviewTableWindow`` bulk engine
    /// with blast-radius confirmation.
    case table

    var id: String { rawValue }

    var label: String {
        switch self {
        case .triage: "Triage"
        case .table: "Table"
        }
    }

    var systemImage: String {
        switch self {
        case .triage: "checklist"
        case .table: "tablecells"
        }
    }
}

/// The single-key triage cheat-sheet shown in the Review inspector. Pure display
/// data — it documents the keyboard shortcuts the embedded ``ReviewInboxView``
/// already binds on the focused row; it does not itself dispatch actions (so it
/// never fires while the user is typing in a field elsewhere).
private enum ReviewShortcutGuide {
    struct Shortcut: Identifiable {
        let key: String
        let action: String
        let systemImage: String
        var id: String { key }
    }

    static let shortcuts: [Shortcut] = [
        Shortcut(key: "A", action: "Approve", systemImage: "checkmark"),
        Shortcut(key: "C", action: "Recategorize", systemImage: "tag"),
        Shortcut(key: "T", action: "Mark transfer", systemImage: "arrow.left.arrow.right"),
        Shortcut(key: "R", action: "Create rule", systemImage: "wand.and.stars"),
        Shortcut(key: "M", action: "Rename merchant", systemImage: "textformat"),
        Shortcut(key: "I", action: "Ignore", systemImage: "eye.slash"),
        Shortcut(key: "⌘Z", action: "Undo last action", systemImage: "arrow.uturn.backward"),
    ]
}

/// Plain-language explanations + glyphs for each review reason code, for the
/// inspector legend. The glyphs mirror the inbox row's leading glyph so the two
/// surfaces read consistently; the copy explains *why* a transaction surfaced.
private enum ReviewReasonGuide {
    static func systemImage(for reason: TransactionReviewReason) -> String {
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

    static func explanation(for reason: TransactionReviewReason) -> String {
        switch reason {
        case .uncategorized:
            "No category yet. Recategorize so it counts toward the right budget."
        case .newMerchant:
            "First time you've seen this merchant. Confirm it's expected."
        case .unusualAmount:
            "Larger or more unusual than this merchant's usual charges."
        case .possibleTransfer:
            "Looks like a transfer or card payment. Mark transfer to exclude it from budgets."
        case .recurringChanged:
            "A recurring charge changed amount or timing."
        case .pendingChanged:
            "This pending charge changed before it posted."
        case .changedSinceReview:
            "Changed since you last reviewed it, so it reopened."
        }
    }
}

#Preview("Content") {
    ReviewDestinationView()
}

#Preview("Inspector") {
    ReviewDestinationView.Inspector()
}
