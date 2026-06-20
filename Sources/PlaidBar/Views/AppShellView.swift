import PlaidBarCore
import SwiftUI

/// The window-first primary workspace shell (ADR-001, Epic 2 / AND-580, sidebar
/// step AND-595).
///
/// A `NavigationSplitView` whose sidebar lists the IA's **5 bands → 11
/// destinations** (`05-information-architecture.md` §2), driven by the
/// per-window `NavigationModel` / typed `Route` (`PlaidBarCore`). Selecting a row
/// sets the window's destination and routes the content column; destinations
/// whose real workspaces land in later epics (4–7) show a labeled
/// `ContentUnavailableView` placeholder. **Settings** is the native macOS
/// `Settings` scene, so its sidebar row triggers `openSettings()` rather than an
/// in-split pane (IA §5.10).
///
/// This is built **only** in the window-first surface — the menu-bar popover is
/// untouched. The window never opens unless `WindowFirstFeatureFlag` is ON
/// (default OFF), so with the flag off this view is never instantiated and there
/// is zero behavior change.
///
/// Liquid Glass on chrome is applied at the scene level via
/// `.containerBackground(.ultraThinMaterial, for: .window)` in `PlaidBarApp`, not
/// here — per ADR-001 glass goes on chrome only, never on data.
struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
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

        NavigationSplitView {
            SidebarView(selection: selection)
        } detail: {
            ShellContentColumn(destination: appState.navigationModel.destination)
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

/// The detail (content) column. For now every destination shows a labeled
/// `ContentUnavailableView` placeholder — the real workspaces are decomposed from
/// the popover in Epics 4–7 (AND-595 is scope-limited to the sidebar). Settings
/// is never routed here: its sidebar row opens the native Settings scene instead.
private struct ShellContentColumn: View {
    let destination: RouteDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            Text(placeholderDescription)
        }
        .navigationTitle(destination.title)
    }

    /// Honest "under construction" copy naming the destination, so the shell is
    /// demoable (via `--window-first on`) without pretending the workspaces exist.
    private var placeholderDescription: String {
        "The \(destination.title) workspace is coming soon."
    }
}

#Preview {
    AppShellView()
        .environment(AppState())
}
