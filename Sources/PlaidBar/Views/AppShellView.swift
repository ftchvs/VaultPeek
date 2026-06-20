import PlaidBarCore
import SwiftUI

/// The window-first primary workspace shell (ADR-001, Epic 2 / AND-580, sidebar
/// step AND-595).
///
/// A `NavigationSplitView` whose sidebar lists the IA's **5 bands → 11
/// destinations** (`05-information-architecture.md` §2), driven by the
/// per-window `NavigationModel` / typed `Route` (`PlaidBarCore`). Selecting a row
/// sets the window's destination and routes the content column via
/// `DestinationContentView` (and, for 3-column destinations, a detail/inspector
/// column via `DestinationInspectorView`) — see
/// `Views/Destinations/DestinationRouter.swift`. The column count tracks each
/// destination's **2-col vs 3-col policy** (IA §3.1, pure
/// `RouteDestination.prefersThreeColumnLayout`): 2-column for Dashboard /
/// Planning / Insights, 3-column for Review / Transactions / Budgets / Goals /
/// Alerts / Accounts. Destinations whose real workspaces land in later epics
/// (4–7) show a labeled `ContentUnavailableView` placeholder in their own
/// per-destination view file. **Settings** is the native macOS `Settings` scene,
/// so its sidebar row triggers `openSettings()` rather than an in-split pane
/// (IA §5.10).
///
/// This is built **only** in the window-first surface — the menu-bar popover is
/// untouched. The window never opens unless `WindowFirstFeatureFlag` is ON
/// (default OFF), so with the flag off this view is never instantiated and there
/// is zero behavior change.
///
/// Liquid Glass on chrome is applied at the scene level via
/// `.containerBackground(.ultraThinMaterial, for: .window)` in `PlaidBarApp`
/// (with an explicit solid Reduce Transparency fallback), not here — per ADR-001
/// glass goes on chrome only, never on data.
///
/// **App Lock parity (ADR-001 Epic 10 / AND-588):** when content is LOCKED (not
/// merely masked), this shell paints the shared `AppLockedGateView` over the
/// entire window — identical to the popover and its detached host — so the
/// window-first surface can never show balances, account, or institution names
/// while App Lock is engaged. The gate sits above every other overlay (including
/// the ⌘K palette), and the palette is force-dismissed while locked.
struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    /// Reduce Motion gates the App-Lock gate's enter/exit transition so locking
    /// the window does not animate when the user has asked for less motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ⌘K command-palette state for this window. Owned by the scene
    /// (`PlaidBarApp`) so the ⌘K menu command and this overlay share one source
    /// of truth, and injected here. Defaults to a fresh model so the `#Preview`
    /// and any standalone use still work (AND-596).
    @State private var paletteModel: CommandPaletteModel
    /// Brings VaultPeek to the front (the summon-hotkey path); injected from the
    /// scene since summon is a scene-level concern. No-op by default.
    private let summon: () -> Void
    /// Focuses the current destination's search field (the ⌘F / find path);
    /// injected from the scene. No-op until per-destination search lands.
    private let focusSearch: () -> Void

    /// The window's unified `.searchable` query (AND-624). The shell owns one
    /// search field in the toolbar; it is threaded into the destination that
    /// supports search (currently the Dashboard, via `\.dashboardSearchQuery`).
    /// Window-scoped `@State` so each window searches independently, and reset on
    /// a destination switch so a stale query never leaks across surfaces.
    @State private var searchText = ""

    /// Whether the third (inspector) column is shown for a 3-column destination
    /// (AND-624). The shell now hosts the detail pane via the native
    /// `.inspector(isPresented:)` API with a toolbar toggle, instead of a fixed
    /// `NavigationSplitView` `detail:` column, so the user can collapse it. Per
    /// window, defaults open so a 3-column destination still lands on its full
    /// layout (IA §3.1: the inspector is content-gated, not hidden).
    @State private var isInspectorPresented = true

    /// `paletteModel` is optional so the default is constructed inside this
    /// `@MainActor` init body (a `@MainActor`-isolated default *argument* would be
    /// evaluated in the caller's nonisolated context and fail strict concurrency).
    /// The scene injects its shared model; the `#Preview` / standalone use gets a
    /// fresh one.
    @MainActor
    init(
        paletteModel: CommandPaletteModel? = nil,
        summon: @escaping () -> Void = {},
        focusSearch: @escaping () -> Void = {}
    ) {
        _paletteModel = State(initialValue: paletteModel ?? CommandPaletteModel())
        self.summon = summon
        self.focusSearch = focusSearch
    }

    var body: some View {
        // The per-window navigation model owns the selected destination (R-10).
        // Bind the sidebar selection to it; Settings is excluded from the
        // selectable set (it opens the native Settings scene instead), so the
        // binding maps a Settings tap to `openSettings()` and never parks the
        // split-view selection on a destination with no content column.
        let selection = Binding<RouteDestination?>(
            get: { appState.navigationModel.destination },
            set: { newValue in
                guard let newValue else { return }
                if newValue == .settings {
                    openSettings()
                } else {
                    appState.navigationModel.go(to: newValue)
                }
            }
        )

        let destination = appState.navigationModel.destination

        // Column policy per destination (IA §3.1, driven by the pure
        // `RouteDestination.prefersThreeColumnLayout` in PlaidBarCore). 3-column
        // destinations (Review, Transactions, Budgets, Goals, Alerts, Accounts)
        // get sidebar + content + a native **inspector**; 2-column destinations
        // (Dashboard, Planning, Insights) get sidebar + content only. Settings is
        // never routed here — it opens the native Settings scene.
        //
        // The shell is a two-column `NavigationSplitView` (sidebar + content); the
        // third column is the native `.inspector(isPresented:)` API (AND-624) with
        // a toolbar toggle, rather than a fixed `NavigationSplitView` `detail:`
        // column — so the detail pane can be collapsed at window scale per Apple's
        // *Inspectors* guidance, and the unified per-destination `.toolbar` carries
        // the title, primary actions, and the inspector toggle.
        NavigationSplitView {
            SidebarView(selection: selection)
        } detail: {
            DestinationContentView(destination: destination)
                .inspector(isPresented: inspectorBinding(for: destination)) {
                    // Content-gated, not existence-gated (IA §3.1): the inspector
                    // always exists for a 3-column destination and shows its
                    // "Select a …" prompt when nothing is selected.
                    DestinationInspectorView(destination: destination)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
                .toolbar { destinationToolbar(for: destination) }
                // The shell owns ONE unified `.searchable` field, applied only to
                // destinations that adopt it (currently the Dashboard). Destinations
                // with their own inline search (e.g. Transactions' filter bar) are
                // left untouched so there is never a competing second field — the
                // propagation pass migrates those to the shell field one at a time.
                .modifier(
                    ShellSearchable(
                        isEnabled: destinationSupportsSearch(destination),
                        text: $searchText,
                        prompt: searchPrompt(for: destination)
                    )
                )
        }
        // Reset the search query and restore the inspector when the destination
        // changes, so a query typed on one surface never leaks to another and a
        // collapsed inspector does not persist into a destination where it is the
        // primary detail view.
        .onChange(of: destination) { _, _ in
            searchText = ""
            isInspectorPresented = true
        }
        // The Dashboard reads the live query from the environment to filter its
        // account rows (the shell owns the field, the canvas owns the filtering).
        .environment(\.dashboardSearchQuery, destinationSupportsSearch(destination) ? searchText : "")
        // Deep-link hand-off (ADR-001 / AND-597). The primary scene is a
        // declarative `Window`, so a route can't be threaded through `openWindow`;
        // instead the opener stages it on `AppState.pendingRoute` and this view
        // consumes it into the window's `NavigationModel`. Both triggers are
        // needed: `onAppear` covers "this route opened the window" (the route was
        // staged *before* the window existed, so no change fires after mount), and
        // `onChange` covers "the window was already open" (a glance chip / App
        // Intent fired while the workspace was on screen). `consumePendingRoute`
        // is single-shot — it clears the slot — so the two never double-apply.
        .onAppear { appState.consumePendingRoute(into: appState.navigationModel) }
        .onChange(of: appState.pendingRoute) {
            appState.consumePendingRoute(into: appState.navigationModel)
        }
        // The ⌘K command palette is a window-level overlay (IA §3.3). It is only
        // ever reachable in this window-first surface — `AppShellView` is built
        // solely behind `WindowFirstFeatureFlag` — so the palette never exists in
        // the flag-OFF popover build.
        .overlay {
            if paletteModel.isPresented {
                CommandPalette(
                    model: paletteModel,
                    dispatcher: CommandDispatcher(
                        appState: appState,
                        navigationModel: appState.navigationModel,
                        openSettings: { openSettings() },
                        summon: summon,
                        focusSearch: focusSearch
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: paletteModel.isPresented)
        // Full App Lock gate (security parity with the popover + detached host —
        // ADR-001 Epic 10 / AND-588). When content is LOCKED (not merely masked)
        // the entire window must be hidden behind the shared `AppLockedGateView`:
        // account and institution names, the sidebar badges, and every
        // destination would otherwise leak even though balances are dotted
        // (AND-462). This overlay is declared *after* the palette overlay so it
        // renders on top of it, and the palette is force-dismissed while locked
        // so unlocking never reveals a stale ⌘K surface.
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
        .onChange(of: appState.isContentLocked) { _, isLocked in
            // A locked window must not keep the ⌘K palette mounted underneath the
            // gate; dismiss it so unlocking returns to the bare workspace.
            if isLocked { paletteModel.dismiss() }
        }
    }

    // MARK: - Unified per-destination toolbar (AND-624)

    /// The window's unified `.toolbar` for the current destination: shared primary
    /// actions (refresh, Privacy Mask toggle) on every destination, plus a native
    /// inspector toggle for the 3-column destinations. The destination *title* is
    /// carried by each destination's `.navigationTitle`, which the split view
    /// promotes into the toolbar — so the toolbar here adds actions, not a
    /// duplicate title.
    @ToolbarContentBuilder
    private func destinationToolbar(for destination: RouteDestination) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Privacy Mask toggle — shape carries the state (struck-through eye when
            // masked), never color alone (ACCESSIBILITY.md). Disabled under App Lock
            // (the gate already hides everything).
            Button {
                appState.togglePrivacyMask()
            } label: {
                Label(
                    appState.shouldMaskFinancialValues ? "Show values" : "Hide values",
                    systemImage: PrivacyMaskPresentation.toggleSymbolName(
                        isMasked: appState.shouldMaskFinancialValues
                    )
                )
            }
            .disabled(appState.isContentLocked)
            .help(appState.shouldMaskFinancialValues
                ? "Show financial values"
                : "Hide financial values (Privacy Mask)")

            // Refresh — the same dashboard refresh the popover triggers; the symbol
            // spins via the shared Reduce-Motion-aware `RefreshIcon`.
            Button {
                Task { await appState.refreshDashboard(force: true) }
            } label: {
                RefreshIcon(isLoading: appState.isLoading)
            }
            .disabled(appState.isLoading)
            .help("Refresh")

            // Inspector toggle — only for 3-column destinations, whose detail pane
            // is now the native collapsible `.inspector`. Native API placement so it
            // reads as the standard macOS inspector control.
            if destination.prefersThreeColumnLayout {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
        }
    }

    // MARK: - Inspector + search wiring (AND-624)

    /// The inspector-presented binding for a destination. 3-column destinations
    /// bind to the shell's `isInspectorPresented` state (toggleable); 2-column
    /// destinations have no inspector, so they bind to a constant `false` and the
    /// `.inspector` never mounts a pane.
    private func inspectorBinding(for destination: RouteDestination) -> Binding<Bool> {
        guard destination.prefersThreeColumnLayout else { return .constant(false) }
        return Binding(get: { isInspectorPresented }, set: { isInspectorPresented = $0 })
    }

    /// Whether a destination adopts the shell's unified `.searchable` field. Only
    /// the Dashboard does today (it filters its account rows via
    /// `\.dashboardSearchQuery`); destinations with their own inline search keep it
    /// until the propagation pass migrates them, so there is never a second field.
    private func destinationSupportsSearch(_ destination: RouteDestination) -> Bool {
        destination == .dashboard
    }

    /// The search-field prompt for a search-adopting destination.
    private func searchPrompt(for destination: RouteDestination) -> String {
        switch destination {
        case .dashboard: "Search accounts"
        default: "Search"
        }
    }
}

// MARK: - Conditional searchable

/// Applies `.searchable` only when the destination adopts the shell search field,
/// so destinations with their own inline search never get a competing second one.
/// A `ViewModifier` (rather than an inline `if`) keeps the view-type stable across
/// destination switches.
private struct ShellSearchable: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, placement: .toolbar, prompt: Text(prompt))
        } else {
            content
        }
    }
}

// MARK: - Sidebar

/// The banded navigation sidebar: 5 IA bands → 11 destinations, each a
/// SF Symbol + label + optional textual count badge, with a footer carrying the
/// connection-health strip and the data-mode chip (IA §3.2).
private struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: RouteDestination?

    var body: some View {
        let badges = appState.sidebarBadgeModel

        List(selection: $selection) {
            // One Section per IA band, bands in their canonical order, each
            // listing its destinations in sidebar order. Driving both off
            // `RouteDestination` keeps the sidebar and the model in lockstep —
            // no second hand-maintained list of destinations.
            ForEach(RouteDestination.Band.allCases, id: \.self) { band in
                Section(band.title) {
                    ForEach(destinations(in: band), id: \.self) { destination in
                        SidebarRow(
                            destination: destination,
                            badge: badges.badge(for: destination)
                        )
                        .tag(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VaultPeek")
        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }

    /// The destinations in a band, in `allCases` (sidebar) order.
    private func destinations(in band: RouteDestination.Band) -> [RouteDestination] {
        RouteDestination.allCases.filter { $0.band == band }
    }
}

/// A single sidebar destination row: icon + label + optional trailing count
/// badge. The badge is a **number** (never a color-only dot — `ACCESSIBILITY.md`)
/// and is folded into the row's VoiceOver label so it is announced, not just
/// seen.
private struct SidebarRow: View {
    let destination: RouteDestination
    let badge: SidebarBadgeModel.Badge?

    var body: some View {
        Label {
            HStack(spacing: Spacing.sm) {
                Text(destination.title)
                if let badge {
                    Spacer(minLength: Spacing.sm)
                    Text(badge.text)
                        .dataText()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }
        } icon: {
            Image(systemName: destination.systemImage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// "Review, 4 items to review" — destination name plus the badge phrase when
    /// present (IA §8: the sidebar announces destination + badge).
    private var accessibilityLabel: String {
        guard let badge else { return destination.title }
        return "\(destination.title), \(badge.accessibilityText)"
    }
}

// MARK: - Sidebar footer

/// Persistent sidebar footer (IA §3.2): the connection-health strip plus the
/// data-mode chip (Demo / Sandbox / Production). Reuses the existing
/// `ConnectionHealthStripView` and `AppState.statusModeText` — no new signals.
private struct SidebarFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()
            ConnectionHealthStripView()
            DataModeChip(mode: appState.statusModeText)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

/// The Demo / Sandbox / Production data-mode chip shown in the sidebar footer.
/// Text-first (the mode word is the label), with a glyph for shape — meaning is
/// never carried by color alone.
private struct DataModeChip: View {
    let mode: String

    private var iconName: String {
        switch mode {
        case "Demo": "theatermasks"
        case "Sandbox": "testtube.2"
        case "Production": "checkmark.seal"
        default: "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(mode)
                .microText()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .glassSurface(.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Data mode: \(mode)")
    }
}

// MARK: - Content column
//
// The content / inspector columns are now routed per destination by
// `DestinationContentView` / `DestinationInspectorView` (see
// `Views/Destinations/DestinationRouter.swift`), each backed by a
// per-destination `…DestinationView` file so Epics 4–7 fill their own files in
// parallel without colliding here. Each still renders the same labeled
// placeholder it showed inline before (`DestinationPlaceholder`), preserving
// current behavior; the 2-col vs 3-col policy is applied in `body` above.

#Preview {
    AppShellView()
        .environment(AppState())
}
