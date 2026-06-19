# macOS 26 Platform Research — Building a Full Native Windowed App

**Doc:** `docs/strategy/macos26-migration/04-platform-research.md`
**Audience:** VaultPeek migration architecture working group
**Status:** Research / decision input (not a commitment)
**Date:** 2026-06-19
**Author:** Platform research pass (Claude, macOS 26 / SwiftUI specialist)

---

## Purpose

VaultPeek (formerly PlaidBar) is today a local-first macOS **menu-bar popover** dashboard for Plaid data. This document is the authoritative, *current* (June 2026) best-practices survey of what a full native **macOS 26 windowed application** can do, so the migration architecture rests on real platform capability — not stale assumptions. Every claim below was verified against live Apple documentation (Context7 mirror of `developer.apple.com`), WWDC session material, and the public web; sources are listed per topic and aggregated at the end.

---

## ⚠️ Read first — the version-numbering trap (this changes roadmap math)

Apple switched to **year-based OS numbering** in 2025. There are **two distinct cycles** in scope, and conflating them will mis-target the build:

| Cycle | OS | Announced | Shipped | Status (June 2026) | Doc availability tag |
|---|---|---|---|---|---|
| **WWDC25** | **macOS 26 "Tahoe"** (iOS 26) | 9 Jun 2025 | **15 Sept 2025** | **Current shipping OS** — the correct floor for VaultPeek now | `macOS 26.0+` |
| **WWDC26** | **macOS 27** (iOS 27) | 8 Jun 2026 | ~Sept 2026 (betas now) | Just previewed; **betas only** | `macOS 27.0+ Beta` (docs label "2027 releases") |

**Consequences for the pivot:**

1. **Liquid Glass, `glassEffect`, `ToolbarSpacer`, `NSHostingSceneRepresentation`, App Intents interactive snippets (`SnippetIntent`), `supportedModes`, App Intents in Spotlight, the full `AXChartDescriptor` audio-graph stack, SwiftData `#Unique`/`#Index`/`@ModelActor`/History tracking — are ALL shippable on macOS 26 TODAY.** You do not need to wait.
2. **The shiny WWDC26 (macOS 27) additions — reorderable containers, `swipeActionsContainer`, `visibilityPriority`/`toolbarOverflowMenu`/`topBarPinnedTrailing`, sectioned `@Query`, `HistoryObserver`/`ResultsObserver`, `Tab(role: .prominent)` — are NOT in stable macOS 26.** Treat them as a fast-follow, gated behind `if #available(macOS 27, *)`, and re-confirm signatures against Xcode 27 headers at GA.
3. **Target macOS 26 as the deployment floor.** It carries everything VaultPeek's pivot needs.

Sources: [MacRumors — macOS Tahoe](https://www.macrumors.com/roundup/macos-26/) · [TechRadar — macOS Tahoe 26 announced](https://www.techradar.com/computing/mac-os/macos-tahoe-26-announced-at-wwdc-2025-with-a-new-look-and-new-numbering-scheme-these-are-the-best-features-for-your-new-mac-or-macbook) · [TechCrunch — WWDC 2026 recap](https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/)

---

## Topic 1 — Liquid Glass (the macOS 26 material/design language)

### What it is
Liquid Glass is Apple's unified design language introduced at WWDC25 and shipping in macOS 26. It is a translucent, dynamic material that refracts/reflects surrounding content (real-time lensing), carries specular highlights, adaptive shadows, and interactive behaviors. It spans iOS/iPadOS/macOS/watchOS/tvOS/visionOS 26.

### Current API / pattern (all `macOS 26.0+`)
- **Automatic adoption:** recompile against the macOS 26 SDK and stock SwiftUI controls (toolbars, sidebars, sheets, buttons) adopt Liquid Glass automatically. Toolbar items float on a shared glass surface that adapts to content beneath.
- **`glassEffect(_:in:)`** — apply glass to a custom view:
  ```swift
  func glassEffect(_ glass: Glass = .regular,
                   in shape: some Shape = DefaultGlassEffectShape()) -> some View
  // DefaultGlassEffectShape() is a Capsule.
  Text("Safe to spend").padding()
      .glassEffect(.regular.tint(.green).interactive(), in: .rect(cornerRadius: 12))
  ```
- **`Glass` variants:** `.regular` (default), `.clear` (more transparent — must add a dimming background for legibility), `.tint(_:)`, `.interactive()`.
- **Button styles:** `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `.buttonStyle(.glass(.clear))`.
- **`GlassEffectContainer(spacing:) { }`** — REQUIRED when you have multiple custom glass elements near each other. Glass cannot sample other glass, so the container fuses them into one morphable surface and prevents glass-on-glass artifacts.
- **Morphing / transitions:** `glassEffectID(_:in:)` + `@Namespace` for matched-geometry morphs; `glassEffectUnion(id:namespace:)` to merge geometries; `glassEffectTransition(.matchedGeometry / .materialize)`.
- **Toolbar grouping:** `ToolbarSpacer(.fixed/.flexible)` splits toolbar items into distinct glass groups; `sharedBackgroundVisibility(_:)` (on `ToolbarContent`) pulls an item out of the shared glass capsule into its own group (e.g., a custom net-worth pill).
- **Window-level translucency (SwiftUI-native):** `.containerBackground(.ultraThinMaterial, for: .window)` and `backgroundExtensionEffect()` to extend a detail background seamlessly under sidebar/inspector.

### When to use
Glass belongs to the **navigation/control layer that floats above content** — toolbars, sidebars, floating controls, KPI pills, badges. Use `GlassEffectContainer` whenever 2+ custom glass shapes coexist.

### macOS-specific caveats / pitfalls
- **Glass is for the navigation layer, NEVER the content itself.** Apple's explicit guidance: do not apply Liquid Glass to lists, tables, media, or large data surfaces. For a dense finance dashboard this is the dominant constraint — the transaction table, charts, and balance grids stay on solid/standard backgrounds; only the chrome is glass.
- **Avoid glass-on-glass.** Stacking glass layers looks cluttered and is technically unsupported (glass can't sample glass). Group with `GlassEffectContainer`.
- **Legibility:** `.clear` glass needs a dimming backing (`.background(.black.opacity(0.3))`) under text. Be judicious with tint so content shines through and stays legible.
- **Accessibility degradation (mandatory — see Topic 10):** stock glass auto-degrades to more opaque/contrasty when *Reduce Transparency* or *Increase Contrast* is on, but **any custom glass or hand-rolled `NSVisualEffectView` translucency you add must handle this yourself** via `@Environment(\.accessibilityReduceTransparency)`.

### UX opportunity vs popover
A real `Window` gets `.containerBackground(.ultraThinMaterial, for: .window)` — **supported, declarative, window-level translucency through public API.** This directly resolves VaultPeek's documented dead-end where behind-window popover translucency could *not* be achieved via `MenuBarExtra(.window)` host-window surgery. In a window, the glance/glass aesthetic the team wants is a one-liner, not a fight with AppKit internals.

Sources: [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) · [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) · [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) · [glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29) · [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) · [LogRocket — adopting Liquid Glass best practices](https://blog.logrocket.com/ux-design/adopting-liquid-glass-examples-best-practices/)

---

## Topic 2 — SwiftUI windowing on macOS

### What it is
The SwiftUI scene graph: a declarative set of `Scene`s (`WindowGroup`, `Window`, `Settings`, `MenuBarExtra`, `DocumentGroup`) in the `App` body, plus environment actions to open/close windows. A hybrid app declares a primary window AND a menu-bar glance AND settings in the same `body`.

### Current API / pattern
- **`WindowGroup`** (macOS 11+; `id`/value variants 13+) — group of identical windows; supports multiple simultaneous instances. `WindowGroup(_:for:) { $value in … }` gives one window per value (e.g., one per account).
- **`Window("Title", id:)`** (macOS 13+) — a single unique window. Cleaner than `WindowGroup` for "the one dashboard."
- **`Settings { }`** (macOS 13+) — standard Settings/Preferences scene (wires ⌘,).
- **`MenuBarExtra`** (macOS 13+) — `.menuBarExtraStyle(.menu)` (pull-down controls) vs `.window` (chromeless popover; what VaultPeek uses today). `MenuBarExtra(..., isInserted: $bool)` lets the user hide/show the item live.
- **Environment actions:** `\.openWindow` → `openWindow(id:)`/`openWindow(value:)`; `\.dismissWindow`; `\.openSettings()` (macOS 14+). `\.pushWindow` is effectively **visionOS-only** — do not bank on it for macOS.
- **Appearance:** `.windowStyle(.automatic/.titleBar/.hiddenTitleBar/.plain)` (`.hiddenTitleBar` = modern content-forward look), `.windowToolbarStyle(.unified/.unifiedCompact/.expanded)`.
- **Sizing/placement:** `.windowResizability(.contentSize/.contentMinSize/.automatic)` (use `.contentMinSize` for a resizable dashboard), `.defaultSize`, `.defaultPosition`, `.defaultWindowPlacement { content, context in … }` (anchor near the menu bar via `context.defaultDisplay.visibleRect`).
- **Behavior (macOS 15+):** `.windowLevel(.floating)` (always-on-top mini window), `.windowBackgroundDragBehavior(.enabled)` (drag chromeless windows by background), `.restorationBehavior(.automatic)` (reopen where left off), `.defaultLaunchBehavior(.suppressed)` (**launch menu-bar-only**, window appears on demand).
- **NEW WWDC26-relevant (macOS 26):** `NSHostingSceneRepresentation` lets an **AppKit (`NSApplicationDelegate`) lifecycle app host SwiftUI scenes** — including a dynamically-inserted `MenuBarExtra`. This is the blessed escape hatch for the exact menu-bar window-surgery problems VaultPeek hit before. (Caveat: its environment can open `Settings` and `WindowGroup` but not a plain `Window`.)

### Hybrid scene-graph skeleton (the load-bearing structure)
```swift
@main
struct VaultPeekApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        // 1) PRIMARY WINDOW — real, resizable dashboard, launch-suppressed.
        Window("VaultPeek", id: "main") {
            DashboardView().environment(model)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 600)
        .defaultLaunchBehavior(.suppressed)     // start menu-bar-only
        .restorationBehavior(.automatic)        // reopen where left off

        // 2) MENU-BAR GLANCE — compact, popover-style, user-removable.
        MenuBarExtra("VaultPeek", systemImage: "creditcard",
                     isInserted: $showMenuBarExtra) {
            GlanceView().environment(model)      // top-line balances + "Open Dashboard"
        }
        .menuBarExtraStyle(.window)

        // 3) SETTINGS.
        Settings { SettingsView().environment(model) }
    }
}
// GlanceView's CTA — the bridge from popover to window:
//   @Environment(\.openWindow) var openWindow
//   Button("Open Dashboard") { openWindow(id: "main") }
```

### When to use
Use a single `Window` for the dashboard if it's conceptually singular; use `WindowGroup(_:for:)` if you want multiple windows (one per institution/account). Keep the `MenuBarExtra` as the always-available glance.

### macOS-specific caveats
- `.defaultLaunchBehavior(.suppressed)` is macOS 15+. Pair it with activation-policy handling (Topic 9) so the suppressed window comes to the front correctly when opened.
- State restoration overrides `.defaultSize` with the last-used size (desirable for a dashboard).

### UX opportunity vs popover
A popover auto-dismisses on focus loss, is size-capped to the menu-bar anchor, is singular, and never restores. A window: **persists side-by-side with other apps, resizes to dense layouts, supports multiple instances, restores across launches, hosts a real toolbar/title-bar/full-screen, and can be pinned always-on-top.** See the ranked list at the end.

Sources: [Windows (SwiftUI)](https://developer.apple.com/documentation/swiftui/windows) · [WindowGroup](https://developer.apple.com/documentation/SwiftUI/WindowGroup) · [Window](https://developer.apple.com/documentation/swiftui/window) · [MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) · [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui) · [windowResizability(_:)](https://developer.apple.com/documentation/swiftui/scene/windowresizability%28_%3A%29) · [defaultLaunchBehavior(_:)](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior%28_%3A%29) · [NSHostingSceneRepresentation](https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation) · [WWDC26 — Use SwiftUI with AppKit and UIKit (272)](https://developer.apple.com/videos/play/wwdc2026/272/)

---

## Topic 3 — NavigationSplitView / NavigationStack / Sidebar / Inspector

### What it is
The canonical macOS "sidebar + content + detail" shell. `NavigationSplitView` lays out 2 or 3 columns where leading-column selection drives the next column; `NavigationStack` provides value-based push/pop *inside* a column; `inspector` adds a trailing detail-of-detail pane.

### Current API / pattern
- **`NavigationSplitView`** (2-col macOS 13+, 3-col + `preferredCompactColumn` macOS 14+):
  ```swift
  NavigationSplitView(columnVisibility: $vis) {
      sidebar
  } content: {
      list
  } detail: {
      detail
  }
  .navigationSplitViewStyle(.balanced)   // or .prominentDetail
  ```
- **`NavigationSplitViewVisibility`** (`.all`/`.doubleColumn`/`.detailOnly`/`.automatic`) for programmatic column collapse; **`NavigationSplitViewColumn`** (`.sidebar`/`.content`/`.detail`) with `preferredCompactColumn`.
- **Column widths:** `.navigationSplitViewColumnWidth(min:ideal:max:)`.
- **`NavigationStack(path: $path)`** + `.navigationDestination(for: T.self) { … }` — value-based, testable, restorable navigation. `path.append(_)` push, `path.removeLast()` pop, `path = []` pop-to-root.
- **Sidebar:** `List(selection: $sel) { Section { Label(_, systemImage:).tag(_).badge(_) } }.listStyle(.sidebar)`. `Label` (glyph + text) satisfies the never-color-alone rule; `.badge(_)` + `.badgeProminence(.increased)` for high-signal counts ("3 accounts need re-auth").
- **Inspector** (macOS 14+): `.inspector(isPresented:) { … }` trailing pane + `.inspectorColumnWidth(min:ideal:max:)` — the 4th region for transaction metadata / raw Plaid payload.
- **`Table`** (macOS 12+, selection/sort/customization broadened 14+): the densest transaction surface, natively keyboard-navigable (see Topic 7).

### Canonical shell skeleton (3-column + inspector)
```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    List(SidebarSection.allCases, selection: $section) { s in
        Label(s.title, systemImage: s.symbol).tag(s).badge(s.alertCount)
    }
    .listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
} content: {
    List(accounts(for: section), selection: $selectedAccountID) { AccountRow($0).tag($0.id) }
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
} detail: {
    NavigationStack(path: $path) {
        AccountDashboard(accountID: selectedAccountID)
            .navigationDestination(for: Transaction.self) { TransactionDetail($0) }
    }
    .inspector(isPresented: $showInspector) {
        InspectorPane(selectedAccountID: selectedAccountID)
            .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
    }
}
.navigationSplitViewStyle(.balanced)
```
`tabViewStyle(.sidebarAdaptable)` (macOS 15+) is the lighter alternative *only* if top-level sections are genuinely tab-like rather than hierarchical.

### When to use
3-column `NavigationSplitView` is the recommended VaultPeek shell: sidebar filters (Cash/Credit/Savings/Debt/Status — already the popover's mental model) → account/list content → dashboard detail with a drill-down `NavigationStack` and an inspector for metadata. `.prominentDetail` keeps the hero chart stable while the user toggles the sidebar.

### macOS-specific caveats
- Column resizing is supported on macOS; a fixed inspector width still lets the user collapse it (add `.interactiveDismissDisabled()` to prevent).
- Remove the auto sidebar toggle with `toolbar(removing: .sidebarToggle)` if you provide your own.

### UX opportunity vs popover
A popover is one transient surface; it **physically cannot show four coordinated regions** (sidebar + list + detail + inspector) simultaneously, cannot host a durable restorable navigation stack, and has no inspector analog. This multi-pane density IS the RepoBar/CodexBar north star.

Sources: [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) · [NavigationSplitViewVisibility](https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility) · [Migrating to new navigation types](https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types) · [inspector(isPresented:content:)](https://developer.apple.com/documentation/swiftui/view/inspector%28ispresented%3Acontent%3A%29) · [Table](https://developer.apple.com/documentation/swiftui/table)

---

## Topic 4 — App Intents + Shortcuts + Spotlight

### What it is
App Intents exposes your app's **actions** (verbs) and **content** (nouns) to Siri, the Shortcuts app, Spotlight, widgets, Control Center, and Apple Intelligence — often without opening the app. VaultPeek's "show spending / review transactions / show net worth" map to three `AppIntent`s + supporting `AppEntity`s.

### Current API / pattern
- **`AppIntent`** (iOS 16 / macOS 13 baseline): `static title`, `IntentDescription`, `@Parameter`, `static parameterSummary`, `func perform() async throws -> some IntentResult`. Composable returns: `ReturnsValue<T>`, `ProvidesDialog`, `OpensIntent`, `ShowsSnippetView`.
- **`AppShortcutsProvider` / `AppShortcut`** — zero-setup system shortcuts with `phrases` (must include `\(.applicationName)`), `shortTitle`, `systemImageName`. This is what auto-populates Spotlight/Shortcuts/Siri.
- **`AppEntity` / `EntityQuery`** (iOS 16 / macOS 13) — expose accounts/transactions. Conform to **`IndexedEntity`** (macOS 15) + `CSSearchableIndex.default().indexAppEntities(_:)` to push into Spotlight's semantic index; auto-generates "Find" actions in Shortcuts.
- **App Intents in Spotlight on Mac (macOS 26):** Spotlight can **run your intents directly from the search field**. Requirement: a complete `parameterSummary` covering all required-without-default params; intent must be discoverable with a real `perform()`.
- **`supportedModes` (macOS 26):** `IntentModes` = `.background`, `.foreground(.immediate/.dynamic/.deferred)`. Replaces deprecated `openAppWhenRun`/`ForegroundContinuableIntent`. "Show net worth" → `.background` (returns a number, no window); "review transactions" → `.foreground` (opens the app).
- **Interactive snippets — `SnippetIntent` (macOS 26):** return a **live SwiftUI view** that renders inline in Spotlight/Siri and stays interactive (`Button(intent:)` inside it runs other intents + `reload()`s). Effectively a **mini VaultPeek dashboard inside Spotlight**.
- **`AppIntentsPackage` (macOS 26):** App Intents now work inside Swift packages — so intent + entity definitions can live in **`PlaidBarCore`** and be shared across app, widget, and Siri/Spotlight. `ProgressReportingIntent` for long syncs.

### Code skeleton
```swift
struct ShowNetWorthIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Net Worth"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    func perform() async throws -> some ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        let nw = await NetWorthStore.shared.current()
        return .result(value: nw,
                       dialog: "Your net worth is \(nw.formatted(.currency(code: "USD"))).",
                       view: NetWorthSnippet(value: nw))
    }
}

struct VaultPeekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowNetWorthIntent(),
                    phrases: ["What's my net worth in \(.applicationName)"],
                    shortTitle: "Net Worth", systemImageName: "chart.line.uptrend.xyaxis")
    }
}
```

### When to use
Read-only actions (net worth, spending total) → background intents returning a value/snippet, runnable from Spotlight/Siri with no window. Navigational actions (review transactions) → foreground intents that open the windowed app.

### macOS-specific caveats
- An accessory/menu-bar app **can** register intents, but the deep-link "open full UI" path needs a real window to foreground into — which is an argument *for* the pivot.
- Apple Intelligence semantic-index features require Apple-silicon Macs. WWDC26 formally **deprecated SiriKit** in favor of App Intents (2–3 year migration window) — so investing in App Intents is the durable bet.

### UX opportunity vs popover
A popover only exists while open and lives nowhere in the system. App Intents put VaultPeek in **Spotlight (typed actions + interactive snippet dashboards), Siri (voice), the Shortcuts app (user automations), and system search (indexed transactions)** — distribution surfaces a popover cannot reach.

Sources: [AppIntent](https://developer.apple.com/documentation/appintents/appintent) · [AppShortcut](https://developer.apple.com/documentation/appintents/appshortcut) · [SnippetIntent](https://developer.apple.com/documentation/appintents/snippetintent) · [Displaying static and interactive snippets](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets) · [Making app entities available in Spotlight](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight) · [Develop for Shortcuts and Spotlight with App Intents (WWDC25 260)](https://developer.apple.com/videos/play/wwdc2025/260/)

---

## Topic 5 — WidgetKit on macOS 26

### What it is
Glanceable, timeline-driven views rendered in **Notification Center and on the desktop** (macOS Sonoma+) and mirrored from iPhone via Continuity.

### Current API / pattern
- **Families on macOS:** `.systemSmall`, `.systemMedium`, `.systemLarge` (declare via `.supportedFamilies([...])`).
- **Configuration:** `StaticConfiguration` + `TimelineProvider` (fixed) or **`AppIntentConfiguration` + `AppIntentTimelineProvider`** driven by a `WidgetConfigurationIntent` (user-configurable, e.g., "which account?"). (AppIntent config: iOS 17 / macOS 14.)
- **Interactive widgets (iOS 17 / macOS 14):** `Button(intent:)` and `Toggle(intent:, isOn:)` (intent conforms to `SetValueIntent`) run an App Intent in the background and refresh the widget — same intents reused from Topic 4.
- **App→widget data sharing:** App Group — `UserDefaults(suiteName:)` for small values, or a **shared SwiftData container** (`ModelConfiguration(groupContainer: .identifier("group.com.vaultpeek.shared"))`, widget side `allowsSave: false`). Call `WidgetCenter.shared.reloadTimelines(ofKind:)` after a sync.
- **What's new (macOS 26 / WWDC25):** push-updated widgets (`WidgetPushHandler`, mostly moot for a local-first app), automatic Liquid Glass rendering of desktop/Notification-Center widgets (design for legibility on glass), RelevanceKit.

### `ControlWidget` — the one macOS caveat to verify
`ControlWidget` (Control Center / Lock Screen / Action button — `ControlWidgetButton`, `ControlWidgetToggle`) was introduced at **WWDC24 for iOS/iPadOS 18 and is documented iOS-only.** macOS 26 shipped a redesigned, third-party-extensible Control Center, but **authoritative confirmation that the `ControlWidget` WidgetKit API targets macOS could not be found.** **Action:** verify the `ControlWidget` `@available` annotation in Xcode 26 before roadmapping a macOS Control Center control. Everything else in this topic is confirmed for macOS.

### Security note
Putting balances in a shared App Group container widens VaultPeek's surface beyond the current Keychain/SQLite split. **Keep tokens out of the group; store only display-ready, non-sensitive read-model values; and respect the App-Lock / privacy-mask state in widget rendering** (the existing "glance snapshot not redacted on mask" risk carries straight into a widget reading SwiftData directly).

### UX opportunity vs popover
Persistent, always-visible desktop/Notification-Center widgets (net worth, spending), configurable per-account and interactive — a popover only exists while open and has no presence on the desktop or in Control Center.

Sources: [What's new in widgets (WWDC25 278)](https://developer.apple.com/videos/play/wwdc2025/278/) · [WidgetPushHandler](https://developer.apple.com/documentation/widgetkit/widgetpushhandler) · [Extend your app's controls across the system (WWDC24 10157)](https://developer.apple.com/videos/play/wwdc2024/10157/) · [Meet WidgetKit (WWDC20 10028)](https://developer.apple.com/videos/play/wwdc2020/10028/)

---

## Topic 6 — SwiftData in macOS 26

### What it is
Apple's persistence framework (`@Model` classes over SQLite). VaultPeek already uses it for a disposable read-model cache and list virtualization, and stores potentially large transaction history.

### Current API / pattern (all available on macOS 26 today)
- **Modeling:** `@Model` (14+), `@Attribute(.unique)` (14+, upsert on collision), **`#Unique<T>([\.a, \.b])`** compound uniqueness (15+ — correct for transaction de-dup on `(accountID, plaidTransactionID)`), **`#Index<T>([\.date], [\.accountID, \.date])`** (15+ — index columns you filter/sort on; the single highest-leverage perf lever for large history).
- **Container/context:** `ModelContainer`/`ModelContext` (14+), `@Environment(\.modelContext)`. `ModelConfiguration(_:schema:isStoredInMemoryOnly:allowsSave:groupContainer:cloudKitDatabase:)`. **Set `cloudKitDatabase: .none`** explicitly (local-first). In-memory config = the existing disposable cache + tests.
- **Concurrency (critical for the strict-concurrency CI gate):** `@ModelActor` for off-main work (sync reduction, large upserts). **`PersistentModel` instances are NOT `Sendable`; `PersistentIdentifier` IS.** Hand off IDs across actors (`fetchIdentifiers` → `mainContext.model(for: id)`), never models. IDs are temporary until `save()`.
- **History tracking (15+, shipped WWDC24 — available now):** `HistoryDescriptor<T>`, `DefaultHistoryToken`, `context.fetchHistory(_:)`, `HistoryChange` (`.insert/.update/.delete`). Persist the last token; on launch, reduce "changes since token" into the read-model. Handle `SwiftDataError.historyTokenExpired`.
- **Large-dataset performance:** `FetchDescriptor.fetchLimit/fetchOffset` (paged fetch — already in use), `propertiesToFetch` (only render columns), `includePendingChanges = false`, `fetch(_:batchSize:)` → lazy `FetchResultsCollection` (backs a virtualized table), `enumerate(_:batchSize:)` (memory-bounded migration/recategorization), `fetchCount`, `fetchIdentifiers`, `DataStoreBatchDeleteRequest` (bulk purge). Avoid Swift-only closures in predicates (throws `.unsupportedPredicate`); set `context.undoManager = nil` during large imports.
- **App+widget sharing:** `ModelConfiguration(groupContainer: .identifier(...))`, widget side `allowsSave: false` + History tracking for cross-process change detection.

### NOT in macOS 26 (WWDC26 / `macOS 27.0+ Beta` — plan but gate)
Sectioned `@Query` (`sectionBy:`), `@Attribute(.codable)`, `ResultsObserver<Model, SectionID>` (Query-style live fetch outside SwiftUI via Observation — clean fit for VaultPeek's `@Observable` services layer), `HistoryObserver` (reactive history). These are "2027 releases" — do not design the near-term pivot around them.

### macOS-specific caveats
- All large-history performance is solvable on macOS 26; nothing here requires waiting for macOS 27.
- The `PersistentIdentifier`-not-models rule is the key Swift 6 constraint given VaultPeek's `-strict-concurrency=complete -warnings-as-errors` gate.

### UX opportunity vs popover
Not a UX surface per se, but SwiftData is what makes the **windowed dense table + charts over large history performant** (indexed, paged, lazy) — a capability a small popover never needed and never exercised. It also enables the **shared store the widget reads**.

Sources: [SwiftData framework](https://developer.apple.com/documentation/swiftdata) · [FetchDescriptor](https://developer.apple.com/documentation/swiftdata/fetchdescriptor) · [@Index](https://developer.apple.com/documentation/swiftdata/index%28_%3A%29-7d4z0) · [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor) · [Track model changes with SwiftData history (WWDC24 10075)](https://developer.apple.com/videos/play/wwdc2024/10075/) · [What's new in SwiftData (WWDC26 274)](https://developer.apple.com/videos/play/wwdc2026/274/)

---

## Topic 7 — Command navigation / keyboard-first

### What it is
A real app menu bar of commands, global keyboard shortcuts, focus management, and a command-palette pattern — the keyboard-first power-user surface a popover cannot host.

### Current API / pattern
- **`.commands { }`** (Scene modifier): `CommandMenu("Accounts") { … }` (top-level menu), `CommandGroup(before:/after:/replacing: CommandGroupPlacement, …)` to inject/replace standard items (`.newItem`, `.sidebar`, `.toolbar`, `.appInfo`, …). `commandsRemoved()`, `commandsReplaced { }`.
- **`.keyboardShortcut(_:modifiers:)`** (macOS 11+): `KeyEquivalent` (`"k"`, `.return`, `.escape`, arrows…), `EventModifiers` (`.command/.option/.shift/.control`). `KeyboardShortcut.defaultAction`/`.cancelAction`.
- **Command palette (Cmd-K):** no built-in; compose a `sheet`/overlay with a `@FocusState`-focused `TextField` + filtered `List`, `.onKeyPress(.upArrow/.downArrow/.return)` for arrow selection, wired from a `CommandGroup` button with `.keyboardShortcut("k", modifiers: .command)`.
- **Focus:** `@FocusState` (Bool or `Hashable?`), `.focusable()`, `.focused($field, equals:)`, `.onKeyPress(keys:phases:action:)` (macOS 14+, return `.handled`/`.ignored`), `onExitCommand`/`onDeleteCommand`.
- **Context-aware commands:** `.focusedSceneValue(\.selectedTransaction, txn)` + `@FocusedValue(\.selectedTransaction)` in `.commands` → menu items enable/disable based on the focused pane. This is the glue that makes shortcuts act on whatever has focus.
- **`Table` keyboard nav** (macOS 12+/14+): `Table(data, selection: $set, sortOrder: $order) { TableColumn(_, value:) … }` — arrow keys move selection, Shift+arrow extends, type-to-select, header click sorts via `KeyPathComparator`, `columnCustomization` + `.customizationID` for user-tunable columns (persist via `@SceneStorage`).

### When to use
A finance power-user wants keyboard everything: ⌘R refresh, ⌘N new link, ⌘K palette, arrow-key table navigation, ⌘F search. All require window+menu-bar presence.

### macOS-specific caveats
Shortcut resolution: key window → main window → command groups (first match wins). Define a clear, non-conflicting shortcut map.

### UX opportunity vs popover
A `MenuBarExtra` popover surfaces **no app menu** and no global command system. A window unlocks the full macOS menu bar, discoverable shortcuts, a Cmd-K palette, context-aware commands, and a keyboard-navigable dense `Table` — the densest possible transaction view.

Sources: [Menus and commands](https://developer.apple.com/documentation/swiftui/menus-and-commands) · [keyboardShortcut(_:modifiers:)](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut%28_%3Amodifiers%3A%29) · [FocusState](https://developer.apple.com/documentation/swiftui/focusstate) · [onKeyPress(keys:phases:action:)](https://developer.apple.com/documentation/swiftui/view/onkeypress%28keys%3Aphases%3Aaction%3A%29) · [Table](https://developer.apple.com/documentation/swiftui/table)

---

## Topic 8 — macOS 26 container / layout / scene APIs new this cycle

### Shipping NOW (macOS 26 / WWDC25) — adopt today
- **`ToolbarSpacer(.fixed/.flexible)`** — split toolbar into distinct glass groups (Mail-style leading/trailing groups).
- **`sharedBackgroundVisibility(_:)`** (`ToolbarContent`) — pull an item out of the shared glass capsule.
- **`toolbarMinimizeBehavior(_:for:)`** — auto-collapse bars on scroll to reclaim space.
- **`backgroundExtensionEffect()`** — extend a detail background under sidebar/inspector for continuous glass.
- **`containerBackground(_:for: .window/.navigation/.navigationSplitView)`** — declarative window/sidebar/detail backgrounds.
- **`tabViewStyle(.sidebarAdaptable)`** + `tabViewSidebarBottomBar` (macOS 15+) — TabView that renders as an adaptive sidebar with a pinned footer (alternative shell).
- **`glassEffect` family** (Topic 1).

### ANNOUNCED — WWDC26 / macOS 27 (ships fall 2026; gate behind `if #available(macOS 27, *)`)
- **Reorderable containers** (headline): `.reorderable()` on a `ForEach` + `.reorderContainer(for:_:)` on List/LazyVGrid/LazyVStack/custom layouts, applying a `ReorderDifference`. Drag-to-rearrange anywhere (pin/reorder accounts).
- **Toolbar:** `visibilityPriority(_:)`, `ToolbarOverflowMenu { }`, `ToolbarItem(placement: .topBarPinnedTrailing)`.
- **Others:** `swipeActionsContainer()` (swipe on any scroll view), `navigationTransition(.crossFade)`, `Tab(role: .prominent)`, item-binding `confirmationDialog`/`alert`, `appearsActive` environment value (style inactive windows — useful for a secondary dashboard window), `@State` becomes a macro with lazy init (back-ported to macOS 14 — audit existing `@State` class storage), `@ContentBuilder` (Xcode 27 build-time wins).

### Caveat
The WWDC26 toolbar/reorder symbol pages did not render bodies on direct fetch — confirm exact `@available` lines and enum spellings against Xcode 27 headers before writing code against them. The macOS 26 (WWDC25) APIs above are fully confirmed.

### UX opportunity vs popover
Adaptive, overflow-aware toolbars and reorderable lists are meaningless in a fixed popover — they exist to scale with a resizable window and a persistent multi-pane layout.

Sources: [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer) · [toolbarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/toolbarminimizebehavior) · [backgroundExtensionEffect()](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect%28%29) · [What's new in SwiftUI (WWDC26 269)](https://developer.apple.com/videos/play/wwdc2026/269/) · [Reordering items in lists, stacks, grids, and custom layouts](https://developer.apple.com/documentation/SwiftUI/Reordering-items-in-lists-stacks-grids-and-custom-layouts) · [What is new in SwiftUI after WWDC26 — Majid](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/)

---

## Topic 9 — Menu-bar app coexistence & activation policy

### What it is
How a primary-window app keeps a lightweight `MenuBarExtra` glance, and the activation-policy dance required so a real window can come to the front from an otherwise dock-less utility. **This is the single riskiest part of the pivot.**

### Current API / pattern
- **`NSApplication.ActivationPolicy`:** `.accessory` (no Dock icon, no app menus, **cannot reliably make a window key**) vs `.regular` (Dock + app menus + key windows). A clean menu-bar utility runs `.accessory` at rest.
- **`LSUIElement` (Info.plist "Application is agent"):** static `.accessory`. **Recommendation: prefer runtime policy switching over the static plist flag** (no `LSUIElement`; set `.accessory` programmatically at launch) for cleaner accessory↔regular transitions.
- **Open-window sequence:**
  ```swift
  @MainActor func openMainWindow(_ openWindow: OpenWindowAction) {
      NSApp.setActivationPolicy(.regular)       // gain Dock + key-window ability
      NSApp.activate(ignoringOtherApps: true)   // bring app forward
      openWindow(id: "main")
  }
  // On last real window close → NSApp.setActivationPolicy(.accessory)
  ```
- **AppKit-lifecycle hybrid (macOS 26):** `NSHostingSceneRepresentation` hosts SwiftUI scenes inside an `NSApplicationDelegate`, giving precise control over policy/termination while authoring UI in SwiftUI. Use a `WindowGroup` (not `Window`) so `environment.openWindow(id:)` works.

### macOS-specific caveats (the risk surface — budget engineering time)
1. **No Dock icon ⇒ no key window.** `makeKeyAndOrderFront` is a no-op while `.accessory`; switch to `.regular` first. Root cause of "window opens behind everything."
2. Switching `.accessory → .regular` doesn't immediately light up your own app menus — test ⌘, and Quit after switching.
3. **Opening `Settings` from accessory context is the most fragile path** and has a **reported macOS 26 regression** around `openSettings()`. Mitigation: the WWDC26-blessed `NSHostingSceneRepresentation.environment.openSettings()` route. **Validate the Settings-open path on macOS 26 hardware specifically.**
4. The policy-switch → activate → order-front sequence is timing-racy (often needs 100–200 ms sleeps). Wrap it in one well-tested helper; don't scatter it.

### UX opportunity vs popover
This is the *enabling* mechanism, not a feature: it's what lets VaultPeek **keep the lightweight glance AND gain a real workspace** — the hybrid that defines the pivot.

Sources: [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui) · [NSHostingSceneRepresentation](https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation) · [Keep your macOS app's menu bar item running after quitting (Pol Piella)](https://www.polpiella.dev/keep-menu-bar-running-after-quitting-app) · [Showing Settings from macOS Menu Bar Items (Steinberger)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)

---

## Topic 10 — Accessibility on macOS 26

For a windowed finance dashboard with charts, three of these are **mandatory, not nice-to-have.**

### Accessibility Nutrition Labels (App Store)
Standardized accessibility disclosures on the App Store product page, configured in App Store Connect, **rendering on macOS 26+ product pages.** Currently voluntary, trending mandatory; Guideline 2.3 governs accuracy (over-claiming = review risk). **The rule:** to claim a feature, *every common task* (primary functionality + onboarding + login + purchase + settings) must be completable with it. For VaultPeek: linking an account, viewing balances, filtering transactions, and **reading charts** must all pass under each claimed feature.

### Audio Graphs / `AXChartDescriptor` — MANDATORY
A Swift Chart is opaque to VoiceOver; audio graphs are the only way a blind user perceives a balance trend or spending breakdown — and a non-audible chart **blocks the VoiceOver Nutrition Label claim.** This is the biggest a11y task of the pivot.
```swift
struct BalanceTrendDescriptor: AXChartDescriptorRepresentable {  // macOS 12.0+
    let points: [BalancePoint]
    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(title: "Date", range: minDay...maxDay,
                                            gridlinePositions: []) { dateLabel($0) }
        let y = AXNumericDataAxisDescriptor(title: "Balance", range: minBal...maxBal,
                                            gridlinePositions: []) { currency($0) }
        let series = AXDataSeriesDescriptor(name: "Account balance", isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.day, y: $0.balance) })
        return AXChartDescriptor(title: "Account balance over time",
            summary: "Balance rose from \(currency(first)) to \(currency(last)) over 90 days.",
            xAxis: x, yAxis: y, series: [series])
    }
    func updateChartDescriptor(_ d: AXChartDescriptor) { /* refresh on data change */ }
}
Chart(points) { /* marks */ }
    .accessibilityChartDescriptor(BalanceTrendDescriptor(points: points))
```
The `summary` field (the spoken insight) is the highest-value piece. Verify exact `AXChartDescriptor`/`AXNumericDataAxisDescriptor` initializer parameter order in Xcode Quick Help (the raw doc page 404'd; the SwiftUI bridge is confirmed).

### Reduce Transparency × Liquid Glass — MANDATORY (VaultPeek uses translucency)
```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
// background:
reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial)
```
Stock glass auto-degrades under Reduce Transparency / Increase Contrast, but **custom glass and any hand-rolled `NSVisualEffectView` translucency (the detached-window design) is your responsibility.** Test with both Reduce Transparency and Increase Contrast on. Related: `accessibilityDifferentiateWithoutColor` (drive the never-color-alone rule), `accessibilityReduceMotion` (gate the matchedGeometryEffect reflow + haptics), `accessibilityPrefersCrossFadeTransitions` (macOS 26.4+).

### Never color alone (already a VaultPeek hard rule)
Positive/negative balance, utilization risk, sync errors, chart series must never be hue-only. Pair color with SF Symbols (arrow.up/down, exclamationmark.triangle), +/− signs, text, or chart shape/pattern. This overlaps the "Differentiate Without Color Alone" Nutrition Label.

### Dynamic Type — caveat
`@Environment(\.dynamicTypeSize)` **does not scale text on macOS**, and "Larger Text" is **not** a Mac Nutrition Label. Lower priority while Mac-only — but use semantic fonts (`.font(.body)`) and `@ScaledMetric` for layout resilience, and it becomes **mandatory** if an iOS/iPad companion is added.

### VoiceOver core (macOS 11/12+)
`accessibilityLabel/Value/Hint`, `accessibilityElement(children:)` (combine a stat card into one stop), `accessibilityRepresentation { }` (custom gauge → `Slider`/`ProgressView`), `accessibilityInputLabels` (Voice Control / Full Keyboard Access).

### UX opportunity vs popover
A windowed chart-heavy app *raises* the accessibility bar — but also makes it achievable: a window has the room for properly-labeled multi-pane content and audible charts. The point is that **shipping charts in a window without audio graphs would be an accessibility regression**, so the pivot must budget for it.

Sources: [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/) · [Evaluate your app for Accessibility Nutrition Labels (WWDC25 224)](https://developer.apple.com/videos/play/wwdc2025/224/) · [accessibilityChartDescriptor(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor%28_%3A%29) · [AXChartDescriptorRepresentable](https://developer.apple.com/documentation/swiftui/axchartdescriptorrepresentable) · [Bring accessibility to charts (WWDC21 10122)](https://developer.apple.com/videos/play/wwdc2021/10122/) · [accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)

---

## Recommended architecture patterns — the canonical macOS 26 VaultPeek shell

**Scene graph:** primary `Window` (dashboard) + `MenuBarExtra` (glance) + `Settings` + a Widget extension (App Group) + App Intents (in `PlaidBarCore` via `AppIntentsPackage`).

```swift
// ───────── App target ─────────
@main
struct VaultPeekApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        // Primary windowed dashboard: 3-column shell, launch-suppressed, glass chrome.
        Window("VaultPeek", id: "main") {
            VaultPeekShell()                         // NavigationSplitView (Topic 3)
                .environment(model)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.suppressed)          // menu-bar-only on launch
        .restorationBehavior(.automatic)
        .commands {                                  // real menu bar + shortcuts (Topic 7)
            CommandMenu("Accounts") {
                Button("Refresh All") { model.refresh() }.keyboardShortcut("r")
                Button("Command Palette…") { model.showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra("VaultPeek", systemImage: "creditcard",
                     isInserted: $showMenuBarExtra) {
            GlanceView().environment(model)          // .window style popover glance
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(model) }
    }
}

// ───────── PlaidBarCore (shared, via AppIntentsPackage) ─────────
//   ShowNetWorthIntent / ShowSpendingIntent / ReviewTransactionsIntent
//   + AccountEntity / TransactionEntity (IndexedEntity) + VaultPeekShortcuts
//   reused by app, widget, Siri, and Spotlight.

// ───────── Widget extension ─────────
//   AppIntentConfiguration widget (net worth / spending), interactive via Button(intent:),
//   reads the shared SwiftData store: ModelConfiguration(groupContainer: .identifier(...),
//   allowsSave: false), redacting under privacy-mask.
```

Activation policy (Topic 9) is handled in a single `@MainActor` helper that flips `.accessory ↔ .regular` around `openWindow(id: "main")`. SwiftData (Topic 6) backs the dense table with indexed, paged, lazy fetches. Liquid Glass (Topic 1) stays on the chrome only; the data surfaces stay solid. Every chart carries an `AXChartDescriptor` and every translucent surface honors Reduce Transparency (Topic 10).

**Architectural fit with the existing codebase:** the two-process security boundary (UI ↔ local server) is unaffected — the window is still a pure HTTP client. Intents/entities/summaries belong in `PlaidBarCore` (keeps them `Sendable`/testable and shareable to the widget), exactly matching the project's "put shared logic in Core" rule.

---

## UX opportunities unavailable in popover architecture (ranked)

1. **Persistence + side-by-side use.** A window stays open beside the browser/spreadsheet; a popover auto-dismisses on focus loss. ("Glance and go" → "live workspace.")
2. **Multi-pane density (sidebar + list + detail + inspector).** Four coordinated regions at once — the RepoBar/CodexBar north star. Impossible in one transient popover.
3. **Spotlight / Siri / Shortcuts reach via App Intents + interactive snippets.** Typed actions and a mini-dashboard *inside Spotlight*; voice; user automations; indexed transactions. A popover lives nowhere in the system.
4. **Desktop & Notification Center widgets.** Always-visible net-worth/spending glances, per-account configurable, interactive — present even when the app is closed.
5. **Keyboard-first power use.** Full app menu bar, discoverable shortcuts, ⌘K command palette, context-aware commands (`focusedSceneValue`), and a keyboard-navigable dense `Table`.
6. **Resizability + state restoration.** Tune column widths, grow to show large charts/tables, reopen exactly where you left off. Popovers are fixed-size and ephemeral.
7. **Multiple simultaneous windows.** One per institution/account/time-range, compared side by side (`WindowGroup(_:for:)`).
8. **Always-on-top utility mode.** `windowLevel(.floating)` pinned mini "safe-to-spend" ticker.
9. **Supported, declarative translucency.** `containerBackground(.ultraThinMaterial, for: .window)` — resolves the prior behind-window-popover translucency dead-end.
10. **Deep linking to specific surfaces.** A notification or the glance opens straight to an account window (`openWindow(value:)`).

---

## Adoption risks & minimum OS targets

### Recommended floor: **macOS 26.0**
Everything the pivot needs is available there: Liquid Glass + `glassEffect`, the full windowing/scene/MenuBarExtra surface, `NavigationSplitView`/inspector/`Table`, App Intents (interactive snippets, supportedModes, Spotlight actions, `AppIntentsPackage`), WidgetKit interactive widgets + App-Group SwiftData sharing, SwiftData `#Unique`/`#Index`/`@ModelActor`/History tracking, and the `AXChartDescriptor` audio-graph stack.

### Requires macOS 26 (degrades or absent below)
- Liquid Glass (`glassEffect`, `GlassEffectContainer`, `ToolbarSpacer`, `containerBackground(_:for:.window)`), App Intents interactive snippets/`supportedModes`/Spotlight-run actions, `NSHostingSceneRepresentation`. On macOS 25 these simply aren't present — if a lower floor is ever required, gate behind `#available` and fall back to standard materials/controls.

### Requires macOS 27 (WWDC26 — NOT yet shippable; gate behind `if #available(macOS 27, *)`)
Reorderable containers, `swipeActionsContainer`, toolbar `visibilityPriority`/`ToolbarOverflowMenu`/`.topBarPinnedTrailing`, sectioned `@Query`, `ResultsObserver`/`HistoryObserver`, `Tab(role: .prominent)`, `appearsActive`. Plan as fast-follow; confirm signatures at GA.

### Top risks
1. **Activation policy (highest).** The `.accessory ↔ .regular` dance and the **reported macOS 26 `openSettings()` regression** are timing-racy and version-specific. Mitigation: one tested helper + `NSHostingSceneRepresentation` for Settings; validate on macOS 26 hardware early.
2. **Accessibility debt becomes mandatory.** Shipping charts in a window without audio graphs is a regression and blocks the VoiceOver Nutrition Label. Budget `AXChartDescriptor` work + Reduce-Transparency fallbacks for the custom glass.
3. **Widget data-sharing widens the security surface.** Shared App Group SwiftData must hold only non-sensitive display values and respect the privacy mask (the existing "glance snapshot not redacted on mask" gap carries over).
4. **`ControlWidget` on macOS unconfirmed.** Verify the `@available` annotation in Xcode 26 before roadmapping a Control Center control.
5. **WWDC26 signatures unstable.** The macOS 27 toolbar/reorder/SwiftData APIs are corroborated across session writeups but some symbol pages didn't render bodies — re-confirm against Xcode 27 headers before coding.

---

## Sources

**Apple — SwiftUI / windowing / navigation**
- https://developer.apple.com/documentation/swiftui/windows
- https://developer.apple.com/documentation/SwiftUI/WindowGroup · https://developer.apple.com/documentation/swiftui/window · https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui
- https://developer.apple.com/documentation/swiftui/scene/windowresizability%28_%3A%29 · https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior%28_%3A%29
- https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation
- https://developer.apple.com/documentation/swiftui/navigationsplitview · https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility
- https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types · https://developer.apple.com/documentation/swiftui/view/inspector%28ispresented%3Acontent%3A%29
- https://developer.apple.com/documentation/swiftui/table
- https://developer.apple.com/documentation/swiftui/menus-and-commands · https://developer.apple.com/documentation/swiftui/view/keyboardshortcut%28_%3Amodifiers%3A%29 · https://developer.apple.com/documentation/swiftui/focusstate · https://developer.apple.com/documentation/swiftui/view/onkeypress%28keys%3Aphases%3Aaction%3A%29

**Apple — Liquid Glass**
- https://developer.apple.com/documentation/technologyoverviews/liquid-glass · https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views · https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29 · https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/swiftui/toolbarspacer · https://developer.apple.com/documentation/swiftui/toolbarminimizebehavior · https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect%28%29

**Apple — App Intents / WidgetKit**
- https://developer.apple.com/documentation/appintents/appintent · https://developer.apple.com/documentation/appintents/appshortcut · https://developer.apple.com/documentation/appintents/snippetintent
- https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets · https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight
- https://developer.apple.com/videos/play/wwdc2025/260/ (Shortcuts & Spotlight) · https://developer.apple.com/videos/play/wwdc2025/278/ (widgets)
- https://developer.apple.com/documentation/widgetkit/widgetpushhandler · https://developer.apple.com/videos/play/wwdc2024/10157/ (controls) · https://developer.apple.com/videos/play/wwdc2020/10028/ (WidgetKit)

**Apple — SwiftData**
- https://developer.apple.com/documentation/swiftdata · https://developer.apple.com/documentation/swiftdata/fetchdescriptor · https://developer.apple.com/documentation/swiftdata/index%28_%3A%29-7d4z0 · https://developer.apple.com/documentation/swiftdata/modelactor
- https://developer.apple.com/videos/play/wwdc2024/10075/ (history) · https://developer.apple.com/videos/play/wwdc2026/274/ (what's new, WWDC26)

**Apple — Accessibility**
- https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/ · https://developer.apple.com/videos/play/wwdc2025/224/
- https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor%28_%3A%29 · https://developer.apple.com/documentation/swiftui/axchartdescriptorrepresentable · https://developer.apple.com/videos/play/wwdc2021/10122/
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency

**Apple — WWDC26 / version**
- https://developer.apple.com/wwdc26/guides/swiftui/ · https://developer.apple.com/videos/play/wwdc2026/269/ · https://developer.apple.com/videos/play/wwdc2026/272/
- https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes

**Secondary (corroboration / community)**
- https://www.macrumors.com/roundup/macos-26/ · https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/
- https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/ · https://swiftwithmajid.com/2025/07/01/glassifying-toolbars-in-swiftui/
- https://blog.logrocket.com/ux-design/adopting-liquid-glass-examples-best-practices/ · https://www.polpiella.dev/keep-menu-bar-running-after-quitting-app · https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items

---

## Verification flags (for the architecture working group)

- **macOS 27 / WWDC26 signatures** (reorderable containers, toolbar overflow APIs, sectioned `@Query`, `ResultsObserver`/`HistoryObserver`) are corroborated across WWDC26 session writeups but some symbol pages did not render bodies on fetch — confirm `@available` lines against Xcode 27 headers before coding.
- **`ControlWidget` on macOS** is documented iOS-18-only; macOS support is unconfirmed — verify in Xcode 26.
- **`openSettings()` from accessory context** has a reported macOS 26 regression — validate the Settings-open path on macOS 26 hardware early; prefer the `NSHostingSceneRepresentation` route.
- **`AXChartDescriptor` initializer parameter order** — the raw doc page 404'd; confirm in Xcode Quick Help (the SwiftUI `accessibilityChartDescriptor` bridge is confirmed).
