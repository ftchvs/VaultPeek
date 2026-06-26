import AppKit
import PlaidBarCore
import SwiftUI

struct MainPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Whether this dashboard is hosted in the menu-bar popover or a floating
    /// desktop window (AND-384). Detached, the host window owns width/height, so
    /// the popover's fixed-width frame and screen-edge anchor are skipped.
    @Environment(\.dashboardPresentation) private var dashboardPresentation
    // Dashboard filter + account selection moved out of view-level `@AppStorage`
    // into the per-window `NavigationModel` behind the `AppState` façade (AND-594).
    // These computed accessors keep the rest of this view byte-identical while the
    // state and its persistence now live in one routable model. Persistence is
    // unchanged: the model writes the same `dashboard.accountFilter` /
    // `dashboard.selectedAccountId` keys, so a relaunch restores the same filter
    // and selection the popover always did.
    @AppStorage(PopoverTransparencySetting.storageKey) private var popoverTransparency = PopoverTransparencySetting.defaultValue

    /// The persisted filter raw value, delegated to the navigation model. Kept as
    /// a raw `String` so the existing `.onChange(of: selectedFilterRawValue)` and
    /// `filterBinding` call sites are unchanged.
    private var selectedFilterRawValue: String {
        get { appState.dashboardFilter.rawValue }
        nonmutating set {
            appState.dashboardFilter = DashboardAccountFilter(rawValue: newValue) ?? .all
        }
    }

    /// The persisted selected-account id (""=none), delegated to the navigation
    /// model. `nonmutating set` mirrors `@AppStorage`'s settable-from-`let`-view
    /// semantics so the assignment sites below (`= ""`, `= $0.id`) are unchanged.
    private var selectedAccountId: String {
        get { appState.dashboardSelectedAccountID }
        nonmutating set { appState.dashboardSelectedAccountID = newValue }
    }
    @State private var isShowingAccountSetup = false
    @State private var shouldShowSetupRecoveryDashboard = false
    @State private var dashboardContentHeight: CGFloat = 0
    @State private var activeScreenVisibleWidth: CGFloat?
    @State private var isRecurringInspectorOpen = false
    /// Income → Category flow drill-in (AND-500), mirroring the recurring
    /// inspector pattern. Mutually exclusive with account/recurring inspectors.
    @State private var isFlowInspectorOpen = false
    /// True after the first render. Gates the inspector's trailing slide-in so a
    /// popover opened with a persisted selection appears directly in three-column
    /// geometry (no slide on restore); in-session selections still slide (AND-405).
    @State private var hasAppeared = false
    /// Namespace for Liquid Glass morphing (AND-511): the trailing inspector
    /// column carries a stable `glassEffectID` in this namespace so its glass
    /// surface morphs in/out of the shared `GlassEffectContainer` around the
    /// columns instead of hard-cutting when an account/drill-in is selected.
    @Namespace private var glassNamespace

    private enum Layout {
        // Column widths and the screen-edge margin are owned by the shared,
        // unit-tested PopoverGeometry so the SwiftUI frames, the popover width
        // math, and the AppKit window anchor stay in lockstep (AND-375).
        static let dashboardWidth = PopoverGeometry.dashboardWidth
        static let flyoutWidth = PopoverGeometry.railWidth
        static let dashboardMinHeight: CGFloat = 460
        /// Vertical breathing room kept below the popover: menu bar,
        /// footer chrome, and a Dock-safe margin.
        static let screenHeightInset: CGFloat = 120
        /// Gap kept between the widened three-column popover and the screen's
        /// visible edges when it is clamped on-screen (AND-374 fallback).
        static let screenEdgeMargin = PopoverGeometry.screenEdgeMargin

        static let contentHorizontalPadding: CGFloat = 12
        static let contentTopPadding: CGFloat = 8
        static let contentBottomPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = Spacing.sm
        static let groupSpacing: CGFloat = Spacing.lg
    }

    /// RepoBar-style vertical sizing: the dashboard grows with its content
    /// up to the available screen height instead of stopping at a fixed
    /// budget. Short content hugs; long content fills the screen and
    /// scrolls. Falls back to the height-budget model when no screen is
    /// available (headless renders).
    private var dashboardScrollHeight: CGFloat {
        let fallback = CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
        let screenCap = NSScreen.main.map { $0.visibleFrame.height - Layout.screenHeightInset } ?? fallback
        let contentCap = dashboardContentHeight > 0 ? dashboardContentHeight : screenCap
        return max(Layout.dashboardMinHeight, min(screenCap, contentCap))
    }

    /// Max height for the side columns (rail / inspector). In the popover this is
    /// the screen-bounded scroll height so tall content scrolls inside a column;
    /// in the detached window (AND-384) the columns fill the resizable panel.
    private var columnMaxHeight: CGFloat {
        dashboardPresentation.isDetached ? .infinity : dashboardScrollHeight
    }

    private var selectedFilter: DashboardAccountFilter {
        DashboardAccountFilter(rawValue: selectedFilterRawValue) ?? .all
    }

    private var selectedAccount: AccountDTO? {
        guard !isRecurringInspectorOpen, !isFlowInspectorOpen else { return nil }
        let accounts = filteredAccounts
        // A selection survives only while the account is still visible; a filter
        // change or a removed/synced-away account deselects it (AND-373/375).
        guard let id = DashboardAccountSelection.resolvedSelectedId(
            selectedAccountId,
            visibleAccountIds: accounts.map(\.id)
        ) else { return nil }
        return accounts.first { $0.id == id }
    }

    /// The trailing inspector COLUMN is present whenever setup is complete — the
    /// three-column workspace is stable and never collapses to two columns on
    /// deselect ("3 columns always open"). It drives the popover width, the
    /// leading-edge anchor, and the detached resize floor, so the layout opens
    /// directly in three-column geometry and stays there. Only the column's
    /// CONTENT varies (selected-account inspector, a brief loading placeholder for
    /// a still-resolving persisted selection, or an empty-selection prompt) —
    /// never the column's existence.
    private var isInspectorColumnVisible: Bool {
        !shouldShowSetupScreen
    }

    /// Whether a specific account's inspector is showing (a row is selected).
    /// Distinct from the column's existence: drives Esc-to-deselect precedence
    /// (AND-373) and which content the always-present inspector column renders.
    private var isAccountInspectorOpen: Bool {
        !selectedAccountId.isEmpty && !shouldShowSetupScreen
    }

    /// The width available for the popover on the active screen, or effectively
    /// unbounded when there is no screen (headless renders) so the full geometry
    /// is used.
    private var availableScreenWidth: CGFloat {
        PopoverGeometry.availableWidth(
            activeScreenWidth: activeScreenVisibleWidth,
            fallbackScreenWidth: NSScreen.main?.visibleFrame.width
        )
    }

    /// Two-column base width: Wealth Summary rail + divider + dashboard. This is
    /// the popover's width with no account selected and the stable block whose
    /// leading edge the window anchor pins (AND-369/370).
    private var twoColumnWidth: CGFloat {
        PopoverGeometry.width(for: .twoColumn)
    }

    private func deselectAccount() {
        selectedAccountId = ""
    }

    private func openRecurringInspector() {
        selectedAccountId = ""
        isFlowInspectorOpen = false
        isRecurringInspectorOpen = true
    }

    private func closeRecurringInspector() {
        isRecurringInspectorOpen = false
    }

    private func openFlowInspector() {
        selectedAccountId = ""
        isRecurringInspectorOpen = false
        isFlowInspectorOpen = true
    }

    private func closeFlowInspector() {
        isFlowInspectorOpen = false
    }

    private var filteredAccounts: [AccountDTO] {
        appState.accounts.filter { selectedFilter.includes($0, appState: appState) }
    }

    var body: some View {
        chromedPopover
            // Full App Lock gate: when content is LOCKED (not merely masked) the
            // dashboard must be hidden entirely — account and institution names
            // would otherwise leak even though balances are dotted (AND-462). The
            // overlay sits above the chrome on both the popover and the detached
            // host (both render this same view). Privacy Mask (`.masked`) is
            // unaffected: it only dots values and leaves content visible.
            .overlay {
                if appState.isContentLocked {
                    AppLockedGateView(
                        message: appState.lockedSurfaceCopy,
                        reduceMotion: reduceMotion,
                        onUnlock: { Task { await appState.unlockApp() } }
                    )
                    .transition(.opacity)
                }
            }
            .animation(
                MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion),
                value: appState.isContentLocked
            )
            .sheet(
                isPresented: $isShowingAccountSetup,
                onDismiss: {
                    if !appState.isSetupComplete {
                        shouldShowSetupRecoveryDashboard = true
                    }
                }
            ) {
                SetupView {
                    shouldShowSetupRecoveryDashboard = false
                    isShowingAccountSetup = false
                }
                .environment(appState)
            }
            .task {
                await appState.loadInitialData()
            }
            .onAppear { hasAppeared = true }
            // Also self-heals the first-open edge where a persisted selection
            // doesn't survive the active filter: at mount accounts are empty, so
            // this fires once when they first populate and clears a now-invalid
            // id, collapsing the reserved three-column back to two (AND-405).
            .onChange(of: filteredAccounts.map(\.id)) { _, ids in
                guard !selectedAccountId.isEmpty, !ids.contains(selectedAccountId) else { return }
                selectedAccountId = ""
            }
            .onChange(of: selectedFilterRawValue) { _, _ in
                selectedAccountId = ""
            }
            .onChange(of: appState.isSetupComplete) { _, isComplete in
                if isComplete {
                    shouldShowSetupRecoveryDashboard = false
                }
            }
            .onChange(of: appState.weeklyReviewNavigation) { _, target in
                guard let target else { return }
                handleWeeklyReviewNavigation(target)
                appState.weeklyReviewNavigation = nil
            }
    }

    private func handleWeeklyReviewNavigation(_ target: WeeklyReviewNavigationTarget) {
        switch target {
        case .recurring:
            openRecurringInspector()
        case .reviewInbox, .safeToSpend:
            // The review inbox and safe-to-spend cards are inline sections in
            // this same popover; closing any open inspector returns the user to
            // the dashboard column where those sections are visible.
            closeRecurringInspector()
            selectedAccountId = ""
        }
    }

    // The visual chrome is kept on its own opaque property so neither it nor the
    // lifecycle chain in `body` overflows the single-expression type-checker.
    private var chromedPopover: some View {
        sizedColumns
            .foregroundStyle(AppearanceTextColors.primary)
            .environment(\.colorScheme, effectiveColorScheme)
            .background {
                // The detached desktop window supplies its own behind-window
                // vibrancy backdrop (a translucent NSVisualEffectView), so the
                // dashboard renders a clear root there and lets the desktop show
                // through. The menu-bar popover keeps the in-content material
                // backdrop (its host window is not vibrant on its own).
                if dashboardPresentation.isDetached {
                    Color.clear
                } else {
                    PopoverMaterialBackground(transparencySetting: transparencySetting)
                }
            }
            // The screen-edge anchor and width reader only apply to the menu-bar
            // popover window (which AppKit re-centers under the status item). The
            // detached desktop window owns its own resizable geometry, so they
            // are skipped there (AND-384) and the popover behavior (AND-370/374)
            // is unchanged.
            .modifier(PopoverWindowGeometryModifier(
                isDetached: dashboardPresentation.isDetached,
                isInspectorOpen: isInspectorColumnVisible,
                collapsedWidth: twoColumnWidth,
                screenEdgeMargin: Layout.screenEdgeMargin,
                activeScreenVisibleWidth: $activeScreenVisibleWidth
            ))
            .animation(
                MotionTokens.animation(MotionTokens.content, reduceMotion: reduceMotion),
                value: selectedAccount?.id
            )
            // Esc closes the trailing inspector first; with no inspector open the
            // handler is nil so the key event falls through and closes the
            // popover (AND-373).
            .onExitCommand(perform: exitCommandHandler)
            .animation(
                MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion),
                value: appState.error != nil
            )
    }

    /// Width handling differs by host (AND-384): the menu-bar popover pins to the
    /// computed `popoverWidth` (screen-anchored, fixed); the floating window fills
    /// its resizable frame down to a usable minimum so the user can size it.
    @ViewBuilder
    private var sizedColumns: some View {
        if dashboardPresentation.isDetached {
            popoverColumns
                .frame(
                    minWidth: shouldShowSetupScreen
                        ? PopoverGeometry.width(for: .setup)
                        // The inspector column is always present, so the resize
                        // floor always includes it — the window can never be sized
                        // narrower than the full three-column layout (AND-384/405).
                        : PopoverGeometry.detachedMinContentWidth(isInspectorOpen: isInspectorColumnVisible),
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
        } else {
            popoverColumns
                .frame(width: popoverWidth)
        }
    }

    /// Esc handler: dismiss the inspector when open, otherwise `nil` so the key
    /// event falls through and closes the popover (AND-373). Hoisted out of the
    /// view chain as an explicitly-typed value to keep the type-checker fast.
    private var exitCommandHandler: (() -> Void)? {
        guard !isRecurringInspectorOpen else { return { closeRecurringInspector() } }
        guard !isFlowInspectorOpen else { return { closeFlowInspector() } }
        guard isAccountInspectorOpen else { return nil }
        return { deselectAccount() }
    }

    // Split into per-column helpers so the type-checker can resolve the body in
    // reasonable time — the full three-column HStack plus modifiers overflows
    // the single-expression solver.
    private var popoverColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            if !shouldShowSetupScreen {
                wealthSummaryRail

                Divider()
                    .opacity(0.35)
            }

            // The center flexes: the rail and inspector keep their fixed widths,
            // so when the popover is capped on a narrow/scaled display the center
            // absorbs the difference (down to a floor) and the trailing inspector
            // + its close control stay on-screen (AND-405).
            dashboardColumn
                .frame(minWidth: PopoverGeometry.minDashboardWidth, maxWidth: .infinity)

            accountInspectorColumn
        }
        // One GlassEffectContainer spans the columns so the trailing inspector's
        // glass surface morphs (via its glassEffectID) when it shows/hides on a
        // drill-in, instead of hard-cutting (AND-511). The merge radius is small
        // (SurfaceTokens.glassMergeRadius), so the rail and inspector glass do
        // not fuse across the wide center — only the morph is shared.
        .glassGroup()
    }

    // LEFT: the Wealth Summary rail is mounted unconditionally once setup is
    // complete and is never swapped out by account selection (three-column
    // contract, AND-367/369). A stable id keeps SwiftUI from remounting/flashing
    // it when the trailing inspector opens or closes.
    private var wealthSummaryRail: some View {
        WealthSummaryFlyout(
            onAddAccount: openAccountSetup,
            onOpenSubscriptions: openRecurringInspector,
            onOpenFlow: openFlowInspector
        )
            .environment(appState)
            .id("wealth-summary-rail")
            .frame(width: Layout.flyoutWidth)
            // Cap the rail to the same screen-bounded height as the dashboard
            // scroll column so tall content scrolls inside the rail instead of
            // growing the whole popover past the screen-bounded height. In the
            // detached window the panel owns the height, so the rail fills it.
            .frame(maxHeight: columnMaxHeight)
            .leftPanelSurface()
            .transition(.move(edge: .leading).combined(with: .opacity))
    }

    // RIGHT: the account inspector column is always present once setup is complete
    // (three-column-always contract): the left rail and center dashboard stay put
    // and the column's CONTENT — not its existence — changes with selection, so
    // deselecting reverts to an empty-selection prompt instead of collapsing the
    // workspace to two columns.
    @ViewBuilder
    private var accountInspectorColumn: some View {
        if isInspectorColumnVisible {
            Divider()
                .opacity(0.35)

            Group {
                if let selectedAccount {
                    AccountInspector(
                        account: selectedAccount,
                        isStatusFilter: selectedFilter == .status,
                        onClose: deselectAccount
                    )
                    .environment(appState)
                } else if isRecurringInspectorOpen {
                    RecurringPaymentsView(
                        presentation: RecurringPaymentsSurfacePresentation.make(
                            from: appState.recurringTransactions,
                            asOf: Date()
                        ),
                        loadState: appState.loadState(for: .recurring),
                        onClose: closeRecurringInspector
                    )
                } else if isFlowInspectorOpen {
                    IncomeCategoryFlowInspector(
                        presentation: IncomeCategoryFlowPresentation.make(
                            // Scope to the same trailing 30-day window as the
                            // "30D cashflow" card this drill-in launches from, so
                            // the inspector totals reconcile with that card rather
                            // than spanning the full multi-month transaction cache.
                            from: IncomeCategoryFlow.transactions(
                                in: IncomeCategoryFlow.defaultWindowDays,
                                from: appState.transactions,
                                asOf: Date()
                            )
                        ),
                        loadState: appState.loadState(for: .transactions),
                        isPrivacyMasked: appState.shouldMaskFinancialValues,
                        onClose: closeFlowInspector
                    )
                } else if !selectedAccountId.isEmpty {
                    // A persisted selection is still resolving (accounts not loaded
                    // yet); a brief placeholder holds the column until it fills in.
                    inspectorLoadingPlaceholder
                } else {
                    // Nothing selected: the right column hosts the Review Inbox by
                    // default. Selecting an account swaps to its inspector and
                    // deselecting returns here. The embedded inbox renders its own
                    // "Inbox Clear" prompt when the queue is empty, so the column
                    // never collapses.
                    ReviewInboxView(embedded: true)
                        .environment(appState)
                }
            }
            .frame(width: Layout.flyoutWidth)
            .frame(maxHeight: columnMaxHeight)
            // Liquid Glass morph (AND-511): the surface treatment and the
            // morph id are applied by ONE modifier so `.glassEffectID` lands
            // immediately after the `.glassEffect` on the SAME view, inside the
            // columns' shared GlassEffectContainer (`.glassGroup()`). Applying
            // `.glassEffectID` to the composed result of `leftPanelSurface()`
            // (as before) bound it to a wrapper view, not to the glass-bearing
            // view buried in the modifier, so the show/hide morph silently
            // no-op'd. A stable id across content swaps lets the inspector's
            // glass fluidly morph as drill-ins open/close instead of hard-cutting.
            .modifier(InspectorGlassMorphSurface(
                morphID: Self.inspectorMorphID,
                namespace: glassNamespace
            ))
            // The column is stable once setup completes, so this transition only
            // plays when the whole column first appears at setup completion — not
            // on every selection. Content swaps inside the column animate via the
            // glass morph above plus the `MotionTokens.content` animation keyed on
            // the selection, so there is no competing trailing-slide on drill-ins
            // (AND-405/511). On removal (setup re-entered) it slides out.
            .transition(.asymmetric(
                insertion: inspectorInsertionTransition,
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }

    /// Stable Liquid Glass morph identity for the inspector column. A single id
    /// held across every content swap (account / recurring / flow / inbox / empty)
    /// is what lets the system fluidly morph the one glass surface rather than
    /// tearing it down and rebuilding it per selection (AND-511).
    private static let inspectorMorphID = "account-inspector-column"

    private var inspectorInsertionTransition: AnyTransition {
        hasAppeared ? .move(edge: .trailing).combined(with: .opacity) : .identity
    }

    private var inspectorLoadingPlaceholder: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading account details")
    }

    private var popoverWidth: CGFloat {
        // Cap the content to the available screen width so the popover never
        // renders off-screen; the center dashboard flexes to absorb the cap so
        // the rail and the trailing inspector + close control stay visible on
        // narrow/scaled displays (AND-405). Setup renders at the dashboard width.
        guard !shouldShowSetupScreen else { return PopoverGeometry.width(for: .setup) }
        return PopoverGeometry.fittedWidth(
            for: isInspectorColumnVisible ? .threeColumn : .twoColumn,
            availableWidth: availableScreenWidth
        )
    }

    private var transparencySetting: PopoverTransparencySetting {
        PopoverTransparencySetting(value: popoverTransparency)
    }

    private var effectiveColorScheme: ColorScheme {
        guard let mode = CommandLineOptions.value(for: "--appearance") else { return colorScheme }
        switch mode.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return colorScheme
        }
    }

    private var dashboardColumn: some View {
        VStack(spacing: 0) {
            // The error banner outranks everything below it — including the
            // setup screen, which previously swallowed errors entirely.
            if let error = appState.error {
                ErrorBanner(error: error)
                    .environment(appState)
            }

            if shouldShowSetupScreen {
                SetupView()
            } else {
                ScrollView {
                    // 16pt between concept groups, 8pt between siblings
                    // within a group — spacing is the hierarchy.
                    VStack(alignment: .leading, spacing: Layout.groupSpacing) {
                        // The rail owns the net-worth hero and its trend, so the
                        // center leads with the latest-changes receipt instead of
                        // repeating either (AND-372).
                        DashboardChangeReceiptStrip()
                            .environment(appState)

                        BalanceTimeMachineView()
                            .environment(appState)

                        WeeklyReviewCard()
                            .environment(appState)

                        // The Copilot-style Category Dashboard surface (AND-539):
                        // donut + top group rollups inline, with an "Open dashboard"
                        // affordance that launches the full detached window. Reads
                        // the override-aware rollup `AppState` caches — no recompute.
                        CategoryDashboardCard()
                            .environment(appState)

                        // Review Inbox moved to the right inspector column
                        // (accountInspectorColumn) so the center stays one compact
                        // instrument and the inbox is not shown twice.

                        if let presentation = appState.firstRunSnapshotPresentation {
                            FirstRunSnapshotView(
                                presentation: presentation,
                                isMasked: appState.shouldMaskFinancialValues,
                                onDismiss: appState.dismissFirstRunSnapshot
                            )
                        }

                        if shouldElevateStatusReadinessPanel {
                            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                                ConnectionHealthStripView()
                                    .environment(appState)

                                AttentionQueueView(title: "Attention", onAddAccount: openAccountSetup)
                                    .environment(appState)

                                DashboardStatusReadinessPanel(
                                    openSettings: { openSettings() },
                                    onAddAccount: openAccountSetup
                                )
                                .environment(appState)
                            }
                        }

                        DashboardOverviewStack(
                            transactions: appState.transactions,
                            accounts: filteredAccounts,
                            filter: selectedFilter,
                            filterSelection: filterBinding,
                            selectedAccountId: selectedAccount?.id,
                            onSelectAccount: {
                                isRecurringInspectorOpen = false
                                isFlowInspectorOpen = false
                                selectedAccountId = $0.id
                            },
                            onDeselectAccount: { selectedAccountId = "" },
                            onAddAccount: openAccountSetup
                        )
                        .environment(appState)

                        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                            // The left rail owns the portfolio totals (assets,
                            // debt, balance mix, 30-day cashflow), so the center
                            // drops those duplicates (AND-372) and keeps only what
                            // the rail does NOT show: the 7-day spend velocity and
                            // the local-only insight receipt.
                            RecentSpendChip()
                                .environment(appState)

                            LocalInsightsCard()
                                .environment(appState)
                        }
                        .loadingRedaction(appState.loadState(for: .summaryCards))

                        if shouldShowLowerStatusReadinessPanel {
                            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                                ConnectionHealthStripView()
                                    .environment(appState)

                                AttentionQueueView(title: "Attention", onAddAccount: openAccountSetup)
                                    .environment(appState)

                                DashboardStatusReadinessPanel(
                                    openSettings: { openSettings() },
                                    onAddAccount: openAccountSetup
                                )
                                .environment(appState)
                            }
                        }
                    }
                    .padding(.horizontal, Layout.contentHorizontalPadding)
                    .padding(.top, Layout.contentTopPadding)
                    .padding(.bottom, Layout.contentBottomPadding)
                    // The dashboard's coexisting glass surfaces (heatmap, status
                    // readiness panel, insights card + chips, overview cards)
                    // share one GlassEffectContainer sampling region. Native
                    // Liquid Glass is the unconditional macOS-26 baseline
                    // (AND-511) — no version passthrough. Merge radius =
                    // SurfaceTokens.glassMergeRadius (small), so only adjacent
                    // glass fuses — distant cards in this tall column stay distinct.
                    .glassGroup()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        dashboardContentHeight = height
                    }
                }
                .scrollContentBackground(.hidden)
                // Glass-aware scroll edge effect (AND-511): the soft edge style
                // lets content fade under the popover's top/bottom glass chrome as
                // it scrolls, so the scroll column reads as one continuous glass
                // surface rather than content abruptly clipping at a hard edge.
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .frame(maxWidth: .infinity)
                .modifier(DashboardScrollHeightModifier(
                    isDetached: dashboardPresentation.isDetached,
                    fixedHeight: dashboardScrollHeight
                ))

                Divider()

                DashboardFooter(
                    settingsActivation: .shared,
                    openSettings: openSettings,
                    onAddAccount: openAccountSetup,
                    onOpenSubscriptions: openRecurringInspector
                )
                .environment(appState)
            }
        }
    }

    private var shouldShowSetupScreen: Bool {
        !appState.isSetupComplete && !shouldShowSetupRecoveryDashboard
    }

    private var shouldShowStatusReadinessPanel: Bool {
        selectedFilter == .status || shouldElevateStatusReadinessPanel
    }

    private var shouldElevateStatusReadinessPanel: Bool {
        // `.loading` stays quiet like `.healthy`: the boot handshake must not
        // hoist an attention panel over the dashboard before any verdict.
        let level = appState.dashboardStatusReadiness.level
        return !appState.isSetupComplete || level == .warning || level == .blocked
    }

    private var shouldShowLowerStatusReadinessPanel: Bool {
        shouldShowStatusReadinessPanel && !shouldElevateStatusReadinessPanel
    }

    private var filterBinding: Binding<DashboardAccountFilter> {
        Binding(
            get: { selectedFilter },
            set: { selectedFilterRawValue = $0.rawValue }
        )
    }

    private func openAccountSetup() {
        isShowingAccountSetup = true
    }
}

/// The inspector column's left-panel glass surface, with the Liquid Glass morph
/// id bound on the SAME view as the glass effect (AND-511).
///
/// This mirrors the visual of `leftPanelSurface()` (the shared `.leftPanel`
/// `SurfaceRank`: fill + `.glassEffect(.regular)` + stroke + shadow) but applies
/// `.glassEffectID` *immediately after* the `.glassEffect`, on the same `content`,
/// so the morph identity actually binds. The previous code applied
/// `.glassEffectID` to the composed output of `leftPanelSurface()`, which is a
/// wrapper view — not the glass-bearing view inside the modifier — so the
/// show/hide morph silently no-op'd. The merge radius of the enclosing
/// `GlassEffectContainer` (`SurfaceTokens.glassMergeRadius`, small) keeps this
/// panel's glass from fusing with the rail across the wide center column.
private struct InspectorGlassMorphSurface: ViewModifier {
    let morphID: String
    let namespace: Namespace.ID

    @AppStorage(PopoverTransparencySetting.storageKey)
    private var popoverTransparency = PopoverTransparencySetting.defaultValue

    private let rank = SurfaceRank.leftPanel
    private var cornerRadius: CGFloat { SurfaceTokens.panelCornerRadius }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let multiplier = PopoverTransparencySetting(value: popoverTransparency).surfaceDepthMultiplier

        content
            .background(rank.fill, in: shape)
            // `.glassEffect` and `.glassEffectID` are adjacent on this same view,
            // inside the columns' GlassEffectContainer — the binding the morph
            // requires (AND-511).
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .glassEffectID(morphID, in: namespace)
            .overlay {
                shape
                    .stroke(rank.stroke(multiplier: multiplier), lineWidth: 1)
                    .overlay {
                        shape
                            .inset(by: 1)
                            .stroke(rank.innerStroke(multiplier: multiplier), lineWidth: 0.5)
                    }
            }
            .shadow(
                color: Color.black.opacity((rank.depth.shadow?.opacity ?? 0) * multiplier),
                radius: rank.depth.shadow?.radius ?? 0,
                x: rank.depth.shadow?.x ?? 0,
                y: rank.depth.shadow?.y ?? 0
            )
    }
}

// `AppLockedGateView` — the full-surface App Lock gate — was moved to its own
// file (`Views/AppLockedGateView.swift`) so the window-first shell (`AppShellView`)
// can reuse the *same* gate for App Lock parity (Epic 10 / AND-588). The
// popover's `.overlay { if appState.isContentLocked { AppLockedGateView(...) } }`
// usage above is unchanged — same view, same behavior, just relocated to module
// scope.

private struct DashboardChangeReceiptStrip: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var receipt: DashboardChangeReceipt? {
        DashboardChangeReceipt.evaluate(
            history: appState.balanceHistory,
            transactions: appState.transactions,
            itemStatuses: appState.itemStatuses
        )
    }

    var body: some View {
        if let receipt {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(receipt.title.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(PrivacyMaskPresentation.maskCurrencyTokens(
                    in: receipt.summary,
                    isEnabled: appState.shouldMaskFinancialValues
                ))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    ForEach(receipt.rows) { row in
                        let value = PrivacyMaskPresentation.maskCurrencyTokens(
                            in: row.value,
                            isEnabled: appState.shouldMaskFinancialValues
                        )
                        Text(value)
                            .font(.caption2.weight(.semibold))
                            .rollingTabularNumber(value, reduceMotion: reduceMotion)
                            .lineLimit(1)
                            .help(row.accessibilityText)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(receipt.accessibilitySummary)
            .help(receipt.accessibilitySummary)
        }
    }
}

private struct RecentSpendChip: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 7-day spend velocity — the one summary metric the left rail does not
        // show (its cashflow section is 30-day). The rail owns cash, credit, and
        // the balance mix, so the center keeps only this short-window signal.
        // Renders nothing when there is no recent spend, so the center has no
        // empty stub.
        if appState.recentSpend > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("7-DAY SPEND")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                Text(PrivacyMaskPresentation.currency(
                    appState.recentSpend,
                    format: .compact,
                    isEnabled: appState.shouldMaskFinancialValues
                ))
                    .font(.caption.weight(.semibold))
                    .rollingTabularNumber(
                        PrivacyMaskPresentation.currency(
                            appState.recentSpend,
                            format: .compact,
                            isEnabled: appState.shouldMaskFinancialValues
                        ),
                        reduceMotion: reduceMotion
                    )
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("7 day spend: \(PrivacyMaskPresentation.currency(appState.recentSpend, format: .full, isEnabled: appState.shouldMaskFinancialValues))")
        }
    }
}

// MARK: - 365 Day Heatmap

private struct BalanceActivityHeatmap: View {
    @Environment(AppState.self) private var appState
    let transactions: [TransactionDTO]
    var loadState: DashboardLoadState?

    // Heatmap metric moved out of view-level `@AppStorage` into the per-window
    // `NavigationModel` behind the `AppState` façade (AND-594). Persistence is
    // unchanged: the model writes the same `dashboard.heatmapMode` key.
    private var modeRawValue: String {
        get { appState.dashboardHeatmapMode.rawValue }
        nonmutating set {
            appState.dashboardHeatmapMode = SpendingHeatmapMode(rawValue: newValue) ?? .spending
        }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Day key (yyyy-MM-dd) of the selected cell, or nil when none is selected.
    /// Persists until another cell is chosen or focus moves (AND-380).
    @State private var selectedDay: String?
    /// Mirrors keyboard focus so arrow keys can move it across the grid.
    @FocusState private var focusedDay: String?

    private let calendar = Calendar.current
    private let spacing: CGFloat = 2
    private let monthLabelHeight: CGFloat = 10
    private let monthLabelWidth: CGFloat = 22
    /// Caption row reserves this height so showing/hiding the focused-day
    /// summary never shifts the layout below the grid.
    private let captionRowHeight: CGFloat = 14

    private var mode: SpendingHeatmapMode {
        SpendingHeatmapMode(rawValue: modeRawValue) ?? .spending
    }

    private func currentLayout() -> SpendingHeatmapLayout {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -364, to: end) ?? end
        return SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: mode,
            calendar: calendar
        )
    }

    var body: some View {
        // Derive the layout once per render. The previous computed-property form
        // re-aggregated every transaction on each property access (~8x per body).
        let layout = currentLayout()

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(layout.mode.summaryTitle)
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Heatmap metric", selection: modeBinding) {
                    Text(SpendingHeatmapMode.spending.shortLabel).tag(SpendingHeatmapMode.spending)
                    Text(SpendingHeatmapMode.netCashflow.shortLabel).tag(SpendingHeatmapMode.netCashflow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 116)

                Text(isInitialLoad ? "—" : totalLabel(for: layout))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isInitialLoad ? AppearanceTextColors.secondary : totalTint(for: layout))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                let weeks = max(layout.weekColumns.count, 1)
                let cell = max(5, min(8, floor((proxy.size.width - (CGFloat(weeks - 1) * spacing)) / CGFloat(weeks))))

                ZStack(alignment: .topLeading) {
                    ForEach(layout.monthMarkers) { marker in
                        Text(marker.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: monthLabelWidth, height: monthLabelHeight, alignment: .leading)
                            .offset(x: CGFloat(marker.weekIndex) * (cell + spacing), y: 0)
                    }

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(layout.weekColumns.enumerated()), id: \.offset) { columnIndex, week in
                            VStack(spacing: spacing) {
                                ForEach(Array(week.enumerated()), id: \.offset) { rowIndex, day in
                                    if let day {
                                        BalanceHeatmapCell(
                                            day: day,
                                            peakValue: layout.peakValue,
                                            mode: layout.mode,
                                            size: cell,
                                            isPrivacyMasked: appState.shouldMaskFinancialValues,
                                            isSelected: selectedDay == day.date,
                                            focusBinding: $focusedDay,
                                            reduceMotion: reduceMotion,
                                            onSelect: { toggleSelection(day.date) },
                                            onMove: { direction in
                                                moveFocus(direction, from: (columnIndex, rowIndex), in: layout)
                                            }
                                        )
                                    } else {
                                        RoundedRectangle(cornerRadius: Radius.cell)
                                            .fill(.clear)
                                            .frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                    .offset(y: monthLabelHeight + 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: monthLabelHeight + 3 + 7 * 8 + 6 * spacing)
            // First sync in flight: the empty grid dims so it reads as a
            // placeholder, not as a year of zero activity.
            .opacity(isInitialLoad ? 0.45 : 1)

            // Fixed-height caption: the focused day when a cell is selected,
            // otherwise a hint — so selecting never shifts the layout (AND-380).
            focusedDayCaption(for: layout)
                .frame(height: captionRowHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                if layout.mode == .spending {
                    Text("Less")
                        .microText()
                        .foregroundStyle(.secondary)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: Radius.cell)
                            .fill(BalanceHeatmapCell.fillColor(
                                intensity: intensity,
                                value: intensity,
                                mode: layout.mode
                            ))
                            .frame(width: 8, height: 8)
                    }

                    Text("More")
                        .microText()
                        .foregroundStyle(.secondary)
                } else {
                    NetLegendKey(label: "Income", tint: SemanticColors.positive)
                    NetLegendKey(label: "Outflow", tint: SemanticColors.negative)
                }

                Spacer()

                Text(isInitialLoad ? "Loading activity" : "\(layout.activeDayCount) active days")
                    .microText()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.raised)
        // Drop a selection that no longer maps to a day in the current range
        // (e.g. after a sync rolls the window forward), so the caption never
        // shows a stale date and the ring never points at a vanished cell.
        // Keyed on the last day — correct for the fixed end-at-today 365-day
        // window (the end always advances); broaden the key (e.g. days.count)
        // if the window ever becomes configurable from the front.
        .onChange(of: layout.days.last?.date) {
            if let selectedDay, !layout.days.contains(where: { $0.date == selectedDay }) {
                self.selectedDay = nil
            }
        }
        // Keep selection following keyboard focus so VoiceOver/arrow users hear
        // the same day the caption shows. Intentional consequence: tabbing back
        // into the grid re-selects the last-focused cell (focus implies
        // selection here).
        .onChange(of: focusedDay) { _, current in
            if let current { selectedDay = current }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isInitialLoad
                ? (loadState?.loadingAccessibilityLabel ?? "Loading activity heatmap.")
                : "\(layout.mode.summaryTitle) heatmap for the last 365 days with \(layout.activeDayCount) active days. \(layout.mode.semanticDescription). Select a day to see its detail."
        )
        // VoiceOver audio graph over the active days. Suppressed during the first
        // sync (placeholder grid) and honors Privacy Mask (AND-569).
        .audioGraph(
            isInitialLoad
                ? ChartAudioGraph.Descriptor(
                    title: layout.mode.summaryTitle,
                    summary: "Loading activity heatmap.",
                    xAxis: .init(title: "Active day", lowerBound: 0, upperBound: 0),
                    yAxis: .init(title: layout.mode.shortLabel, lowerBound: 0, upperBound: 0),
                    seriesName: layout.mode.shortLabel,
                    isContinuous: false,
                    points: []
                )
                : ChartAudioGraph.heatmap(layout, isPrivacyMasked: appState.shouldMaskFinancialValues)
        )
    }

    @ViewBuilder
    private func focusedDayCaption(for layout: SpendingHeatmapLayout) -> some View {
        if let summary = SpendingHeatmap.focusedDaySummary(for: selectedDay, in: layout), !isInitialLoad {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(summary.captionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.accessibilityLabel)
        } else {
            Text("Select a day for its detail")
                .microText()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func toggleSelection(_ day: String) {
        withAnimation(MotionTokens.animation(MotionTokens.micro, reduceMotion: reduceMotion)) {
            selectedDay = (selectedDay == day) ? nil : day
        }
        // Deselect correctness depends on the activated cell already holding
        // focus: re-tapping a selected cell clears `selectedDay`, and this
        // assignment is then a no-op (focus was already on `day`), so
        // `.onChange(of: focusedDay)` does not fire and the selection stays
        // cleared. Keep this LAST — focusing a different cell before clearing
        // would resurrect the selection via the focus→selection sync below.
        focusedDay = day
    }

    /// Arrow-key navigation across the padded week grid. Columns are weeks,
    /// rows are weekdays; movement skips nil padding cells and stays in bounds
    /// (no wraparound — predictable for keyboard users).
    private func moveFocus(
        _ direction: MoveCommandDirection,
        from origin: (column: Int, row: Int),
        in layout: SpendingHeatmapLayout
    ) {
        let columns = layout.weekColumns
        guard !columns.isEmpty else { return }

        var column = origin.column
        var row = origin.row
        for _ in 0 ..< (columns.count * 7) {
            switch direction {
            case .up: row -= 1
            case .down: row += 1
            case .left: column -= 1
            case .right: column += 1
            @unknown default: return
            }
            guard column >= 0, column < columns.count, row >= 0, row < 7 else { return }
            if let day = columns[column][row] {
                focusedDay = day.date
                return
            }
        }
    }

    private var isInitialLoad: Bool {
        loadState?.isInitialLoad ?? false
    }

    private var modeBinding: Binding<SpendingHeatmapMode> {
        Binding(
            get: { mode },
            set: { modeRawValue = $0.rawValue }
        )
    }

    private func totalLabel(for layout: SpendingHeatmapLayout) -> String {
        guard !appState.shouldMaskFinancialValues else {
            return PrivacyMaskPresentation.compactValue
        }
        guard layout.mode == .netCashflow else {
            return Formatters.currency(layout.totalValue, format: .compact)
        }
        return cashflowText(for: layout.totalValue)
    }

    private func totalTint(for layout: SpendingHeatmapLayout) -> Color {
        guard layout.mode == .netCashflow else { return AppearanceTextColors.primary }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(layout.totalValue)
        if displayAmount > 0 { return SemanticColors.positive }
        if displayAmount < 0 { return SemanticColors.negative }
        return AppearanceTextColors.secondary
    }

    private func cashflowText(for value: Double) -> String {
        guard !appState.shouldMaskFinancialValues else {
            return PrivacyMaskPresentation.compactValue
        }
        let displayAmount = SpendingHeatmap.displayCashflowAmount(value)
        let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
        return "\(prefix)\(Formatters.currency(abs(displayAmount), format: .compact))"
    }
}

private struct NetLegendKey: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(tint.opacity(0.72))
                .frame(width: 8, height: 8)
            Text(label)
                .microText()
                .foregroundStyle(.secondary)
        }
    }
}

private struct BalanceHeatmapCell: View {
    let day: SpendingHeatmapDay
    let peakValue: Double
    let mode: SpendingHeatmapMode
    let size: CGFloat
    /// Unlike the window grids, the popover heatmap renders its interactive cells
    /// even while Privacy Mask is on, so the per-cell help/label MUST mask the
    /// amount here (it would otherwise leak the day's value on hover / to
    /// VoiceOver). Same single Core label source (AND-671).
    var isPrivacyMasked: Bool = false
    var isSelected: Bool = false
    var focusBinding: FocusState<String?>.Binding
    var reduceMotion: Bool = false
    var onSelect: () -> Void = {}
    var onMove: (MoveCommandDirection) -> Void = { _ in }

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: Radius.cell)
                .fill(Self.fillColor(intensity: intensity, value: day.value, mode: mode))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .focused(focusBinding, equals: day.date)
        // Non-color highlight: a ring/stroke that reads in both appearances and
        // does not depend on the fill hue (AND-380).
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.cell)
                    .strokeBorder(AppearanceTextColors.primary, lineWidth: 1.5)
                    .frame(width: size + 2, height: size + 2)
            }
        }
        // Space/Return select via the Button; arrows move focus across the grid.
        .onMoveCommand(perform: onMove)
        .animation(MotionTokens.animation(MotionTokens.micro, reduceMotion: reduceMotion), value: isSelected)
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var intensity: Double {
        SpendingHeatmap.cellIntensity(for: day, peakValue: peakValue)
    }

    private var helpText: String {
        SpendingHeatmap.cellLabel(for: day, mode: mode, isPrivacyMasked: isPrivacyMasked)
    }

    static func fillColor(intensity: Double, value: Double, mode: SpendingHeatmapMode) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.06) }

        // Spend mode uses a neutral intensity ramp: green means money-in
        // everywhere else in the app, so green-for-heavy-spending would
        // invert the token semantics. Net mode keeps the green/red pairing
        // with its explicit Income/Outflow legend.
        guard mode == .netCashflow else {
            return Color.primary.opacity(0.14 + (0.6 * intensity))
        }

        let base: Color = value < 0 ? SemanticColors.positive : SemanticColors.negative
        return base.opacity(0.18 + (0.72 * intensity))
    }
}

// MARK: - Local Insights

private struct LocalInsightsCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    private var availability: LocalAIAvailability {
        primarySummary?.availability ?? appState.localAIAvailability
    }

    private var primarySummary: LocalAIActivitySummary? {
        // The menu-bar glance stays on the 30-day window by design, but reads
        // through the shared accessor so it can never diverge from how the window
        // surfaces resolve a summary (fallbacks included).
        appState.summary(for: .lastMonth)
    }

    private var receipt: LocalAIInsightReceipt {
        LocalAIInsightReceipt.make(
            summary: primarySummary,
            availability: availability,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(receipt.title)
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                LocalAIStatusPill(
                    availability: availability,
                    isChecking: appState.isCheckingLocalAIAvailability,
                    modelName: appState.localAIModelName,
                    onRetry: { Task { await appState.checkLocalAIAvailability() } },
                    onOpenSettings: { openSettings() }
                )
            }

            Text(receipt.headline)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            HStack(spacing: 6) {
                ForEach(receipt.evidenceChips) { chip in
                    LocalInsightEvidenceChip(chip: chip)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(receiptDetailLines.enumerated()), id: \.offset) { _, detail in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.secondary.opacity(0.58))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(detail)
                            .microText()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(footerText)
                    .microText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button {
                    openSettings()
                } label: {
                    Label("Where your data lives", systemImage: "externaldrive.badge.questionmark")
                        .labelStyle(.titleAndIcon)
                        .microText()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Settings to see where VaultPeek stores your data on this Mac.")
                .accessibilityLabel("Where your data lives")
                .accessibilityHint("Opens Settings to the local data section")
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(receipt.accessibilitySummary)
    }

    private var receiptDetailLines: [String] {
        var lines = [receipt.confidence]
        if let unavailableState = receipt.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: receipt.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    private var footerText: String {
        "\(receipt.localOnlyBadge). \(receipt.reversibleActionCopy)"
    }
}

private struct LocalAIStatusPill: View {
    let availability: LocalAIAvailability
    let isChecking: Bool
    let modelName: String
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            statusCapsule

            actionButton
        }
        .help(LocalAIAvailabilityPresentation.helpText(for: availability))
    }

    private var statusCapsule: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: LocalAIAvailabilityPresentation.iconName(for: availability.state))
                .font(.caption2.weight(.medium))
            Text(LocalAIAvailabilityPresentation.popoverLabel(for: availability))
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(.quinary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LocalAIAvailabilityPresentation.popoverLabel(for: availability))
    }

    @ViewBuilder
    private var actionButton: some View {
        switch LocalAIAvailabilityPresentation.remediationCategory(for: availability) {
        case .noInstalledModel:
            Button {
                LocalAIRemediationActions.copyPullCommand(modelName: modelName)
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy the Ollama model install command")
            .accessibilityLabel("Copy Ollama model command")
        case .runtimeUnavailable, .modelError:
            Button {
                onRetry()
            } label: {
                Label(isChecking ? "Checking" : "Retry", systemImage: isChecking ? "hourglass" : "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isChecking)
            .help("Check Ollama again")
            .accessibilityLabel("Retry Ollama connection")
        case .unsupportedConfiguration:
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open Local AI settings")
            .accessibilityLabel("Open Local AI settings")
        case .none, .disabled, .checking:
            EmptyView()
        }
    }

    private var tint: Color {
        switch availability.state {
        case .available: SemanticColors.positive
        case .disabled: AppearanceTextColors.secondary
        case .unavailable: SemanticColors.warning
        case .checking: AppearanceTextColors.secondary
        }
    }
}

private struct LocalInsightEvidenceChip: View {
    let chip: LocalAIInsightReceipt.EvidenceChip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: chip.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentTint)
                Text(chip.label)
                    .lineLimit(1)
            }
            .microText()
            .foregroundStyle(.secondary)

            Text(chip.value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        .glassSurface(.inset, cornerRadius: Radius.control)
        .help("\(chip.label): \(chip.value)")
    }

    private var accentTint: Color {
        guard let category = chip.accentCategory else { return AppearanceTextColors.secondary }
        return CategoryAccentTokens.color(for: category)
    }
}

private struct DashboardStatusReadinessPanel: View {
    @Environment(AppState.self) private var appState
    let openSettings: () -> Void
    let onAddAccount: () -> Void

    private var readiness: DashboardStatusReadiness {
        appState.dashboardStatusReadiness
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness.title)
                        .font(.callout.weight(.semibold))
                    Text(readiness.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            if !appState.isSetupComplete {
                SetupRecoverySummary(state: appState.firstRunCompletionState)
            }

            StatusMetricGrid()
                .environment(appState)

            if readiness.primaryAction != nil || !readiness.secondaryActions.isEmpty {
                HStack(spacing: 8) {
                    if let primaryAction = readiness.primaryAction {
                        if readinessNeedsAttention {
                            Button {
                                perform(primaryAction)
                            } label: {
                                Label(
                                    primaryActionLabel(for: primaryAction),
                                    systemImage: readiness.primaryActionIconName ?? primaryAction.canonicalIconName
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(tint)
                            .disabled(appState.isLoading)
                        } else {
                            Button {
                                perform(primaryAction)
                            } label: {
                                Label(
                                    primaryActionLabel(for: primaryAction),
                                    systemImage: readiness.primaryActionIconName ?? primaryAction.canonicalIconName
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(appState.isLoading)
                        }
                    }

                    // Modeled recovery fallbacks (e.g. in-app Settings when the
                    // primary action opens System Settings). Routed through the
                    // same perform(_:) so the panel matches the readiness
                    // presentation contract (#322).
                    ForEach(readiness.secondaryActions, id: \.self) { action in
                        Button {
                            perform(action)
                        } label: {
                            Label(action.canonicalTitle, systemImage: action.canonicalIconName)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appState.isLoading)
                        .accessibilityLabel(action.canonicalTitle)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .glassSurface(readinessNeedsAttention ? .emphasized(tint) : .raised)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch readiness.level {
        case .healthy: "checkmark.circle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        // Warning/negative tints are reserved for actionable verdicts —
        // an in-flight first load renders neutral.
        switch readiness.level {
        case .healthy, .loading: AppearanceTextColors.secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }

    private var readinessNeedsAttention: Bool {
        readiness.level == .warning || readiness.level == .blocked
    }

    private func perform(_ action: RecoveryAction) {
        RecoveryActionDispatcher(
            appState: appState,
            openSettings: openSettings,
            onAddAccount: onAddAccount
        )
        .perform(action)
    }

    private func primaryActionLabel(for action: RecoveryAction) -> String {
        if action == .reconnect,
           let title = ItemRecoveryTarget.actionTitle(from: appState.itemStatuses)
        {
            return title
        }
        return readiness.primaryActionTitle ?? action.canonicalTitle
    }
}

private struct SetupRecoverySummary: View {
    let state: FirstRunCompletionState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text("Setup recovery")
                    .microText()
                    .foregroundStyle(.secondary)
                Text(state.title)
                    .font(.caption.weight(.semibold))
                Text(state.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch state.step {
        case .ready:
            "checkmark.circle.fill"
        case .blocked:
            "exclamationmark.triangle.fill"
        case .openPlaidLink:
            "link.circle"
        case .loadAccounts:
            "building.columns"
        case .syncTransactions:
            "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch state.step {
        case .ready:
            .secondary
        case .blocked:
            SemanticColors.negative
        case .openPlaidLink, .loadAccounts, .syncTransactions:
            SemanticColors.brand
        }
    }
}

private struct StatusMetricGrid: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            StatusMetricPill(title: "Mode", value: appState.statusModeText)
            StatusMetricPill(title: "Server", value: appState.statusServerText)
            StatusMetricPill(title: "Items", value: "\(appState.statusItemCount) linked")
            StatusMetricPill(title: "Synced", value: syncedItemsText)
            StatusMetricPill(title: "Credentials", value: appState.serverCredentialsText)
            StatusMetricPill(title: "Last Sync", value: appState.lastSyncRelative ?? "Never")
            StatusMetricPill(title: "Data Path", value: appState.activeStorageDirectoryDisplayText)
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 112), spacing: 6),
            GridItem(.flexible(minimum: 112), spacing: 6),
            GridItem(.flexible(minimum: 112), spacing: 6),
        ]
    }

    private var syncedItemsText: String {
        "\(appState.serverSyncedItemCount ?? 0) of \(appState.statusItemCount)"
    }
}

private struct StatusMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .microText()
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Overview Flow

private struct DashboardOverviewStack: View {
    @Environment(AppState.self) private var appState
    let transactions: [TransactionDTO]
    let accounts: [AccountDTO]
    let filter: DashboardAccountFilter
    @Binding var filterSelection: DashboardAccountFilter
    let selectedAccountId: String?
    let onSelectAccount: (AccountDTO) -> Void
    let onDeselectAccount: () -> Void
    let onAddAccount: () -> Void

    private var fallbackState: DashboardOverviewFallbackState? {
        DashboardOverviewFallbackState.evaluate(
            isSetupComplete: appState.isSetupComplete,
            isDemoMode: appState.isDemoMode,
            accountCount: appState.accounts.count,
            transactionCount: appState.transactions.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.stack) {
            if let fallbackState {
                DashboardOverviewFallbackBanner(presentation: fallbackState, onAction: onAddAccount)
            } else {
                BalanceActivityHeatmap(
                    transactions: transactions,
                    loadState: appState.loadState(for: .activityHeatmap)
                )
            }

            VStack(alignment: .leading, spacing: LayoutSpacing.controls) {
                DashboardFilterBar(
                    selection: $filterSelection,
                    hasSelectedAccount: selectedAccountId != nil
                )

                AccountsSection(
                    accounts: accounts,
                    filter: filter,
                    selectedAccountId: selectedAccountId,
                    onSelect: onSelectAccount,
                    onDeselect: onDeselectAccount,
                    onAddAccount: onAddAccount
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Overview with activity heatmap, account filters, account rows, and selected account details."
        )
    }

    private enum LayoutSpacing {
        static let stack: CGFloat = 6
        static let controls: CGFloat = 5
    }
}

private struct DashboardOverviewFallbackBanner: View {
    let presentation: DashboardOverviewFallbackState
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SemanticColors.brandSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        SemanticColors.brandSecondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Radius.panel)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.callout.weight(.semibold))
                    Text(presentation.detail)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.title). \(presentation.detail)")

            Button(action: onAction) {
                Label(presentation.actionTitle, systemImage: presentation.actionIconName)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.emphasized(SemanticColors.brandSecondary))
    }
}

// MARK: - Account List

private struct AccountsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accounts: [AccountDTO]
    let filter: DashboardAccountFilter
    let selectedAccountId: String?
    let onSelect: (AccountDTO) -> Void
    let onDeselect: () -> Void
    let onAddAccount: () -> Void
    /// Tracks which account row holds keyboard focus so opening and closing the
    /// trailing inspector keeps the user's place in the list (AND-373).
    @FocusState private var focusedAccountId: String?

    private var accountsLoadState: DashboardLoadState {
        appState.loadState(for: .accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Accounts")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(accounts.count)")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                    .opacity(accountsLoadState.showsSkeleton ? 0 : 1)
            }
            .padding(.horizontal, Spacing.compactRowHorizontalPadding)
            .padding(.bottom, Spacing.xs)

            if accounts.isEmpty {
                if accountsLoadState.showsSkeleton {
                    // First fetch in flight: redacted placeholder rows
                    // instead of offline/empty copy.
                    DashboardAccountRowSkeletonList(loadState: accountsLoadState)
                } else {
                    DashboardEmptyAccountState(filter: filter, onAddAccount: onAddAccount)
                        .environment(appState)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        AccountRowWithDrilldown(
                            account: account,
                            isStatusFilter: filter == .status,
                            isSelected: selectedAccountId == account.id,
                            focusBinding: $focusedAccountId,
                            onSelect: {
                                if selectedAccountId == account.id {
                                    onDeselect()
                                } else {
                                    onSelect(account)
                                }
                            }
                        )
                        .environment(appState)
                        .scrollEdgeDepth(reduceMotion: reduceMotion)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            }
        }
        // Keep focus on the selected row while the inspector is open and return
        // it to that row when the inspector closes, so keyboard users do not
        // lose context on Esc/close (AND-373). onChange does not fire on mount,
        // so a popover reopened with a persisted selection neither re-announces
        // nor re-homes focus.
        .onChange(of: selectedAccountId) { previous, current in
            if let current, let account = accounts.first(where: { $0.id == current }) {
                focusedAccountId = current
                // Announce only on a genuine selection change (not on mount/
                // restore), so VoiceOver hears the inspector open exactly once.
                AccessibilityNotification.Announcement(
                    "\(AccountPresentation.displayName(for: account)) details opened in account inspector"
                ).post()
            } else if let previous, accounts.contains(where: { $0.id == previous }) {
                // Return focus only when the row still exists (Esc/✕/re-click).
                // If the selection was cleared because the row left the list
                // (filter change or account removed), leave focus alone rather
                // than pointing @FocusState at a vanished id (AND-373).
                focusedAccountId = previous
            }
        }
    }
}

private struct AccountRowWithDrilldown: View {
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let isStatusFilter: Bool
    let isSelected: Bool
    let focusBinding: FocusState<String?>.Binding
    let onSelect: () -> Void

    var body: some View {
        // Selection opens the AccountInspector on the trailing side of the
        // dashboard (mounted by MainPopover), not an inline panel below. The
        // left rail stays in place; only the right inspector toggles.
        Button(action: onSelect) {
            DashboardAccountRow(
                account: account,
                isStatusFilter: isStatusFilter,
                isSelected: isSelected,
                privacyMaskEnabled: appState.shouldMaskFinancialValues
            )
        }
        .buttonStyle(.plain)
        .focused(focusBinding, equals: account.id)
        .hoverHighlight()
        .help(drillInPath.pointerHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accountAccessibilityLabel)
        .accessibilityHint(drillInPath.accessibilityHint)
        .accessibilityAction(named: drillInPath.accessibilityActionName, onSelect)
    }

    private var accountAccessibilityLabel: String {
        let label = AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: AccountPresentation.rowAmountText(
                for: account,
                privacyMaskEnabled: appState.shouldMaskFinancialValues
            ),
            connectionLabel: connectionPresentation.rowLabel,
            pendingCount: pendingCount,
            isSelected: isSelected,
            utilizationThreshold: appState.creditUtilizationThreshold,
            privacyMaskEnabled: appState.shouldMaskFinancialValues,
            liability: appState.liabilities.first { $0.accountId == account.id }
        )
        guard let demoTrend else { return label }
        return "\(label). \(accountTrendAccessibility(demoTrend))"
    }

    private var demoTrend: BalanceTrend? {
        demoAccountTrend(for: account, appState: appState)
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).count(where: \.pending)
    }

    private var drillInPath: DashboardAccountDrillInPath {
        DashboardAccountDrillInPath.presentation(for: account, isSelected: isSelected)
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }
}

private struct DashboardEmptyAccountState: View {
    @Environment(AppState.self) private var appState
    let filter: DashboardAccountFilter
    let onAddAccount: () -> Void

    private var presentation: DashboardAccountEmptyState {
        DashboardAccountEmptyState.evaluate(
            filter: filter,
            isDemoMode: appState.usesDemoConnectionPresentation,
            isInitialLoad: appState.loadState(for: .accounts).isInitialLoad,
            serverConnected: appState.serverConnected,
            credentialsConfigured: appState.serverCredentialsConfigured,
            linkedItemCount: appState.statusItemCount,
            accountCount: appState.accounts.count,
            degradedItemCount: appState.needsLoginItemCount + appState.erroredItemCount,
            degradedItemRecoveryTitle: ItemRecoveryTarget.actionTitle(from: appState.itemStatuses),
            degradedItemRecoveryDetail: ItemRecoveryTarget.recoveryDetail(from: appState.itemStatuses)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(message)
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Loading is passive: no recovery actions until the first fetch
            // delivers a verdict the user can act on.
            if !presentation.isLoading {
                HStack(spacing: 8) {
                    if showsAddAccount {
                        Button(action: onAddAccount) {
                            Label("Add Account", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        performRecoveryAction()
                    } label: {
                        Label(actionTitle, systemImage: actionIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(emphasizedTint.map { SurfaceRank.emphasized($0) } ?? .raised)
    }

    private var title: String {
        presentation.title
    }

    private var message: String {
        presentation.detail
    }

    private var icon: String {
        presentation.iconName
    }

    private var tint: Color {
        switch presentation.tone {
        case .brand:
            SemanticColors.brand
        case .healthy, .loading:
            .secondary
        case .offline, .secondary:
            .secondary
        case .warning:
            SemanticColors.warning
        }
    }

    private var emphasizedTint: Color? {
        switch presentation.tone {
        case .brand, .warning:
            tint
        case .healthy, .loading, .offline, .secondary:
            nil
        }
    }

    private var showsAddAccount: Bool {
        presentation.showsAddAccount
    }

    private var actionTitle: String {
        presentation.actionTitle
    }

    private var actionIcon: String {
        presentation.actionIconName
    }

    private func performRecoveryAction() {
        switch presentation.action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .reconnect:
            guard let itemId = ItemRecoveryTarget.itemId(from: appState.itemStatuses) else {
                Task { await appState.refreshDashboard() }
                return
            }
            Task { await appState.reconnectItem(itemId: itemId) }
        case .sync:
            Task { await appState.refreshDashboard() }
        }
    }
}

private struct DashboardAccountRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: AccountDTO
    let isStatusFilter: Bool
    let isSelected: Bool
    let privacyMaskEnabled: Bool

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            Image(systemName: AccountPresentation.iconName(for: account))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Sizing.iconChip, height: Sizing.iconChip)
                .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(alignment: .bottomTrailing) {
                    // Decorative reinforcement only: the row subtitle carries
                    // the connection state in text, so the tinted dot is
                    // hidden from VoiceOver instead of being color-only.
                    Circle()
                        .fill(statusTint)
                        .frame(width: Sizing.statusDot, height: Sizing.statusDot)
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text(account.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .detailText()
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.compactRowContentSpacing)

            // Inline per-account sparkline (AND-379), ahead of the chevron.
            // Decorative: the row announces the balance and the trailing delta
            // carries direction in text, so this is hidden from VoiceOver and
            // never the sole cue. Rows with insufficient history render nothing
            // and keep identical height and rhythm.
            if let accountSparkline {
                AccountRowSparkline(series: accountSparkline)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                // Amounts are data, not verdicts: keep them neutral. Risk is
                // carried by the utilization line below — icon + tint + text,
                // and only once the user's own threshold is crossed.
                Text(amountText)
                    .dataText()
                    .rollingTabularNumber(amountText, reduceMotion: reduceMotion)
                    .foregroundStyle(AppearanceTextColors.primary)
                    .lineLimit(1)

                if let utilization = account.balances.utilizationPercent {
                    // Mirrors the filter-bar rule: tint the icon, never the
                    // text — orange caption text fails 4.5:1 contrast.
                    HStack(spacing: Spacing.xxs) {
                        if utilizationNeedsAttention {
                            Image(systemName: SemanticColors.utilizationIcon(
                                for: utilization,
                                threshold: appState.creditUtilizationThreshold
                            ))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SemanticColors.utilization(
                                for: utilization,
                                threshold: appState.creditUtilizationThreshold
                            ))
                        }
                        Text(trailingDetailText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(utilizationNeedsAttention ? AnyShapeStyle(AppearanceTextColors.primary) :
                                AnyShapeStyle(.secondary))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text(trailingDetailText)
                        .microText()
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            // The account inspector opens on the trailing side of the
            // dashboard; chevron.forward flips correctly under RTL. The selected
            // row swaps in a filled chevron so selection is carried by shape,
            // not color alone (AND-373).
            Image(systemName: isSelected ? "chevron.forward.circle.fill" : "chevron.forward")
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowVerticalPadding)
        .background(
            isSelected ? Color.accentColor.opacity(SurfaceTokens.selectedFillOpacity) : .clear,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
        .overlay(alignment: .bottom) {
            if !isSelected {
                Divider()
                    .opacity(0.4)
            }
        }
        .contentShape(Rectangle())
    }

    private var utilizationNeedsAttention: Bool {
        guard let utilization = account.balances.utilizationPercent else { return false }
        return utilization >= appState.creditUtilizationThreshold
    }

    private var subtitle: String {
        AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: isStatusFilter ? connectionPresentation.statusFilterSubtitle : statusText,
            pendingCount: pendingCount,
            privacyMaskEnabled: privacyMaskEnabled)

    }

    private var amountText: String {
        AccountPresentation.rowAmountText(for: account, privacyMaskEnabled: privacyMaskEnabled)
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).filter(\.pending).count
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }

    private var statusText: String {
        connectionPresentation.rowLabel
    }

    private var trailingDetailText: String {
        AccountPresentation.dashboardTrailingDetailText(
            for: account,
            connectionLabel: statusText,
            privacyMaskEnabled: privacyMaskEnabled,
            liability: appState.liabilities.first { $0.accountId == account.id }
        )
    }

    private var statusTint: Color {
        accountConnectionTint(for: connectionPresentation.level)
    }

    private var accountSparkline: AccountSparkline.Series? {
        accountSparklineSeries(for: account, appState: appState)
    }
}

@MainActor
private func accountSparklineSeries(for account: AccountDTO, appState: AppState) -> AccountSparkline.Series? {
    AccountSparkline.evaluate(history: accountBalanceHistory(for: account, appState: appState))
}

@MainActor
private func demoAccountTrend(for account: AccountDTO, appState: AppState) -> BalanceTrend? {
    BalanceTrend.evaluate(history: accountBalanceHistory(for: account, appState: appState))
}

/// Per-account balance history source. Real builds do not record per-account
/// history yet (`AppState.balanceHistory` is aggregate net worth only), so the
/// row sparkline is sourced from deterministic demo fixtures in demo mode and
/// is intentionally absent otherwise — degrading to no line rather than a
/// misleading one.
@MainActor
private func accountBalanceHistory(for account: AccountDTO, appState: AppState) -> [BalanceSnapshot] {
    guard appState.usesDemoConnectionPresentation else { return [] }
    return DemoFixtures.accountBalanceHistory(forAccountId: account.id)
}

private func accountTrendAccessibility(_ trend: BalanceTrend) -> String {
    let change: String
    switch trend.direction {
    case .up:
        change = "up \(Formatters.currency(abs(trend.delta), format: .full))"
    case .down:
        change = "down \(Formatters.currency(abs(trend.delta), format: .full))"
    case .flat:
        change = "unchanged"
    }
    return "Demo account balance trend \(change) over the last \(trend.spanDays) day\(trend.spanDays == 1 ? "" : "s")"
}

// MARK: - Footer

private struct DashboardFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dashboardPresentation) private var dashboardPresentation
    /// Direct-manipulation haptics preference (AND-576). Drives the quick
    /// Privacy Mask toggle's tactile confirmation; off-state is a no-op. The
    /// pure mapping lives in Core.
    @AppStorage(HapticFeedbackPreference.storageKey) private var hapticRaw = HapticFeedbackPreference.defaultValue.rawValue
    let settingsActivation: SettingsWindowActivationRestorer
    let openSettings: OpenSettingsAction
    let onAddAccount: () -> Void
    let onOpenSubscriptions: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onAddAccount) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Add Account")
            .accessibilityLabel("Add Account")
            .keyboardShortcut("n", modifiers: .command)

            // The one place sync/mode status lives on a healthy dashboard.
            Text(statusLineText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Status: \(statusLineText)")

            Spacer()

            Button(action: onOpenSubscriptions) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Recurring payments")
            .accessibilityLabel("Open recurring payments")

            detachControl

            // Quick Privacy Mask toggle — engage/clear masking in one click
            // without opening Settings. State is read from the underlying
            // preference (not the locked-inclusive `shouldMaskFinancialValues`)
            // so the glyph reflects exactly what the button controls; meaning is
            // carried by the eye/eye.slash SHAPE, never color.
            Button {
                // Tactile confirmation for the in-popover mask/reveal flip
                // (AND-576) — a binary direct manipulation. No-op when the
                // preference is off or the trackpad lacks a haptic engine, so
                // behavior matches today.
                HapticFeedback.play(
                    .toggle,
                    enabled: (HapticFeedbackPreference(rawValue: hapticRaw) ?? .on).isEnabled
                )
                appState.togglePrivacyMask()
            } label: {
                Image(systemName: PrivacyMaskPresentation.toggleSymbolName(
                    isMasked: appState.appLockPreferences.privacyMaskEnabled
                ))
                .foregroundStyle(.secondary)
                .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help(PrivacyMaskPresentation.toggleActionLabel(isMasked: appState.appLockPreferences.privacyMaskEnabled))
            .accessibilityLabel(PrivacyMaskPresentation.toggleActionLabel(isMasked: appState.appLockPreferences.privacyMaskEnabled))
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button {
                Task { await appState.refreshDashboard() }
            } label: {
                RefreshIcon(isLoading: appState.isLoading)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    /// Detach / re-dock affordance (AND-384). In popover mode it pops the
    /// dashboard out into a floating desktop window the user can drag anywhere;
    /// in the floating window it docks back to the menu-bar popover. The glyph
    /// (macwindow vs. pin.slash) and label carry the meaning, never color.
    @ViewBuilder
    private var detachControl: some View {
        switch dashboardPresentation {
        case let .popover(detach):
            Button(action: detach) {
                Image(systemName: "macwindow")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Open dashboard in a floating window")
            .accessibilityLabel("Detach dashboard into a floating window")
        case let .detached(redock):
            Button(action: redock) {
                Image(systemName: "pin.slash")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Dock dashboard back to the menu bar")
            .accessibilityLabel("Dock dashboard back to the menu bar")
        }
    }

    private var statusLineText: String {
        var parts = [appState.statusModeText]
        parts.append(appState.statusSyncText)
        if appState.statusItemCount > 0 {
            parts.append("\(appState.statusItemCount) linked")
        }
        return parts.joined(separator: " · ")
    }

    private func openSettingsWindow() {
        settingsActivation.open(openSettings: openSettings)
    }
}

@MainActor
final class SettingsWindowActivationRestorer {
    static let shared = SettingsWindowActivationRestorer()

    private var closeObserver: NSObjectProtocol?
    private var discoveryObserver: NSObjectProtocol?
    /// True while Settings holds a `.regular` request with the shared coordinator,
    /// so opening Settings twice does not double-count and closing releases once.
    private var holdsRegularRequest = false

    func open(openSettings: OpenSettingsAction) {
        let app = NSApplication.shared
        removeDiscoveryObserver()
        // Elevate via the shared, refcounted coordinator (not a private save) so
        // Settings and the detached dashboard cannot strand the app in `.regular`.
        if !holdsRegularRequest {
            holdsRegularRequest = true
            AppActivationPolicyCoordinator.shared.requestRegular()
        }

        openSettings()
        app.activate(ignoringOtherApps: true)

        if focusCurrentSettingsWindow() { return }

        discoveryObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let observedWindow = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard
                    let self,
                    let settingsWindow = observedWindow,
                    Self.isSettingsWindowCandidate(settingsWindow)
                else { return }

                self.focus(settingsWindow)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, discoveryObserver != nil else { return }
            _ = focusCurrentSettingsWindow()
        }
    }

    private func focusCurrentSettingsWindow() -> Bool {
        guard let settingsWindow = NSApplication.shared.windows.first(where: Self.isSettingsWindowCandidate) else {
            return false
        }

        focus(settingsWindow)
        return true
    }

    private func focus(_ settingsWindow: NSWindow) {
        removeDiscoveryObserver()
        removeCloseObserver()

        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreActivationPolicy()
            }
        }
    }

    private func restoreActivationPolicy() {
        if holdsRegularRequest {
            holdsRegularRequest = false
            AppActivationPolicyCoordinator.shared.releaseRegular()
        }
        removeCloseObserver()
        removeDiscoveryObserver()
    }

    private static func isSettingsWindowCandidate(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.canBecomeKey, !window.isMiniaturized, window.level == .normal else {
            return false
        }

        if window.title.localizedCaseInsensitiveContains("settings") {
            return true
        }

        return window.styleMask.contains(.titled)
            && window.sheetParent == nil
            && window.frame.width >= 580
            && window.frame.height >= 500
    }

    private func removeCloseObserver() {
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
    }

    private func removeDiscoveryObserver() {
        guard let discoveryObserver else { return }
        NotificationCenter.default.removeObserver(discoveryObserver)
        self.discoveryObserver = nil
    }
}

/// Applies the menu-bar popover's AppKit window geometry — the leading-edge
/// anchor (AND-370/374) and the active-screen width reader (AND-405) — only when
/// the dashboard is hosted in the popover. In the detached desktop window
/// (AND-384) the host `NSPanel` owns its resizable geometry, so these are no-ops
/// there and the popover behavior is untouched.
private struct PopoverWindowGeometryModifier: ViewModifier {
    let isDetached: Bool
    let isInspectorOpen: Bool
    let collapsedWidth: CGFloat
    let screenEdgeMargin: CGFloat
    @Binding var activeScreenVisibleWidth: CGFloat?

    func body(content: Content) -> some View {
        if isDetached {
            content
        } else {
            content
                .background {
                    PopoverLeadingEdgeAnchor(
                        isInspectorOpen: isInspectorOpen,
                        collapsedWidth: collapsedWidth,
                        screenEdgeMargin: screenEdgeMargin
                    )
                }
                .background {
                    PopoverScreenWidthReader(visibleWidth: $activeScreenVisibleWidth)
                }
        }
    }
}

/// Heights for the center scroll column differ by host (AND-384). The menu-bar
/// popover pins the scroll view to a fixed, screen-bounded height so the popover
/// window sizes to it; the detached desktop window fills its resizable frame
/// (with a sensible floor) so dragging the window taller shows more content.
private struct DashboardScrollHeightModifier: ViewModifier {
    let isDetached: Bool
    let fixedHeight: CGFloat

    func body(content: Content) -> some View {
        if isDetached {
            content.frame(maxHeight: .infinity)
        } else {
            content.frame(height: fixedHeight)
        }
    }
}

private struct ErrorBanner: View {
    @Environment(AppState.self) private var appState
    let error: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticColors.negative)
                .accessibilityHidden(true)
            // Sanitized errors are capped at 220 characters upstream, so an
            // uncapped line count stays bounded while never truncating the
            // actionable part of the message.
            Text(error)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                appState.error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(SemanticColors.negative.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(error)")
        .task(id: error) {
            // Keyed by the error text so each distinct error is announced,
            // not just the first one mounted; the task also yields once so
            // the banner is in the hierarchy before VoiceOver speaks.
            await Task.yield()
            AccessibilityNotification.Announcement("Error: \(error)").post()
        }
    }
}
