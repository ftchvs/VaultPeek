# Current-State Architecture — VaultPeek (PlaidBar)

**Audience:** Leadership evaluating a pivot from the menu-bar popover-primary model (AND-384) to a full native macOS 26 application where the primary experience lives in a dedicated window and the menu bar becomes a launcher/glance surface.

**Scope:** Factual, evidence-based current-state picture. This document reports *what is*, with `file:line` evidence. It does not advocate for or against the migration.

**Commit baseline:** branch `claude/fervent-thompson-649f21`, HEAD `2119292`. macOS deployment floor 26.0 (`Package.swift:28`).

---

## Executive summary

- **Lifecycle is a hybrid, not pure `MenuBarExtra`.** The SwiftUI scene graph is `MenuBarExtra(.window)` + `Settings` only (`PlaidBarApp.swift:80-332`). There is **no `Window`/`WindowGroup` scene anywhere** (verified: `grep WindowGroup` returns nothing in the SwiftUI sense). All "real" app windows are built imperatively in AppKit. The menu-bar item is driven by `MenuBarExtra` + the `MenuBarExtraAccess` package to reach the live `NSStatusItem` (`PlaidBarApp.swift:265-321`), with a refcounted `AppActivationPolicyCoordinator` flipping the app between `.accessory` and `.regular` (`AppActivationPolicyCoordinator.swift:27-49`).
- **Substantial real-window infrastructure already exists — this is the single most important finding.** Three independent AppKit `NSWindow` controllers are already built, shipped, and behaving like first-class app windows: the **detached full dashboard** (AND-384), the **Category Dashboard window** (AND-539), and the **Review Table window** (AND-532). All three use `NSWindow` (not `NSPanel`), behind-window `NSVisualEffectView` vibrancy, `NSHostingController`, frame autosave, lazy-singleton reuse, App-Lock key observation, and activation-policy elevation. A window-primary model would *extend a proven pattern*, not invent one.
- **The same `MainPopover` view already renders in two hosts** (popover and floating window) via a `DashboardPresentation` environment enum (`DashboardPresentation.swift:12-23`). The view never touches AppKit window lifecycle; the host injects detach/redock closures. This is direct evidence the UI is already partially host-agnostic.
- **Navigation is a flat filter-band, not a hierarchy.** No `NavigationStack`/`NavigationSplitView`/`TabView` anywhere in the app. Routing is a custom segmented control (`DashboardFilterBar`, `DashboardNavBand.swift:39`) plus `.sheet`/`.inspector` overlays. Filter and selected-account state live in **`@AppStorage` inside `MainPopover`** (`MainPopover.swift:14-15`), not in `AppState`.
- **`AppState` is a 4,213-LOC `@Observable @MainActor` god object** (`AppState.swift` + 2 extensions) holding ~67 stored properties spanning data, preferences, ~12 service instances, derived caches, and UI flags. It is **not `Sendable`**. It contains two hard single-surface flags — `isPopoverPresented` (`AppState.swift:117`) and `isDashboardDetached` (`AppState.swift:126`) — plus singular menu-bar computed properties. This is the principal coupling liability for a multi-window model.
- **The server / auth / Plaid boundary is a separate process and is completely independent of the UI.** A UI rearchitecture touches **zero** credential-handling code: server binds `127.0.0.1` only (`App.swift:153`), `/api/*` is bearer-gated (`App.swift:84-85`), access-token bytes live in Keychain with SQLite holding `keychain:<item_id>` refs (`PlaidTokenVault.swift:65-67`, `TokenStore.swift:63-68`). Verdict: survives untouched.
- **Glance surfaces (widget, Control Center controls, App Intents, Spotlight) live out-of-process** and read a display-only App Group snapshot (`GlanceSnapshot`/`FinanceSnapshot` in `PlaidBarCore`). They are app-architecture-agnostic; the only coupling is the `vaultpeek://dashboard` deep link and the `writeGlanceSnapshot()` call site.
- **Business logic is already heavily concentrated in `PlaidBarCore` (25,280 LOC across 153 files)** — DTOs, formatters, reducers, presentation models, energy policy, AI tiers. The app target is 23,769 LOC but ~half is SwiftUI views; the server is 6,593 LOC. The Core layer is `Sendable`/testable and survives any UI change.

---

## Process & lifecycle architecture

### Two processes, three+ executables

`Package.swift` declares four executables and two libraries (`Package.swift:30-36`):

| Product | Type | Role |
|---|---|---|
| `PlaidBar` | executable | SwiftUI menu-bar app (UI layer) |
| `PlaidBarServer` | executable | Hummingbird 2 companion server (owns Plaid creds) |
| `PlaidBarWidgetExtension` | executable | WidgetKit bundle (widget + controls + intents) |
| `plaidbar-cli` | executable | source-built CLI over the same authed localhost server |
| `PlaidBarCore` | library | shared DTOs + pure utilities (`Sendable`) |
| `PlaidBarCache` | library | app-only SwiftData `@Model` + `@ModelActor` stores |

Data flow: `PlaidBar.app` → HTTP `127.0.0.1:8484` → `PlaidBarServer` → HTTPS → Plaid.

### Lifecycle verdict: HYBRID (`MenuBarExtra` + AppKit windows), NOT pure MenuBarExtra and NOT custom-NSStatusItem

The SwiftUI `App.body` contains exactly two scenes (`PlaidBarApp.swift:79-332`):

1. `MenuBarExtra { MainPopover() } label: { MenuBarLabel() }` with `.menuBarExtraStyle(.window)` (`PlaidBarApp.swift:80, 322`).
2. `Settings { SettingsView(...) }` (`PlaidBarApp.swift:324`).

There is **no `Window`/`WindowGroup` SwiftUI scene**. Every other window is an AppKit `NSWindow` created in a controller (`makeWindow()` in `CategoryDashboardWindowController.swift:109`, `ReviewTableWindowController.swift:107`, `DetachedDashboardWindowController.swift`).

The menu-bar status item is reached two ways simultaneously:
- SwiftUI owns the popover window via `MenuBarExtra(.window)`.
- The `MenuBarExtraAccess` package exposes the live `NSStatusItem` (`PlaidBarApp.swift:265`), onto which the app pins a **badge overlay** (`StatusItemBadgeController`) and a **right-click context menu** (`StatusItemContextMenuController`, `PlaidBarApp.swift:271-321`).

So it is a *hybrid*: declarative `MenuBarExtra` for the popover, AppKit surgery for the status item and for all real windows.

### Activation policy

`AppActivationPolicyCoordinator` (`AppActivationPolicyCoordinator.swift:17-50`) is a `@MainActor` singleton that **refcounts** `.regular` elevation. The app is `.accessory` (menu-bar-only) at rest; any detached window requests `.regular` (Dock + ⌘-Tab) on show and releases on close. Refcounting prevents two simultaneous windows from stranding the app in `.regular` (`AppActivationPolicyCoordinator.swift:8-13`). CLI flag `--regular-activation` forces `.regular` at launch for automation (`PlaidBarApp.swift:69-73`).

### Popover-window surgery

`PopoverWindowAnchor` (`PopoverWindowAnchor.swift`) does **not** create a window — it reaches the `MenuBarExtra(.window)` host `NSWindow` via `NSViewRepresentable` and pins its leading X-edge across width changes (`setFrameOrigin`, ~line 190) because SwiftUI re-centers the popover on the status item when the inspector opens. This is a known fragility (AND-514/SPIKE F2) of the popover host that **goes away** under a window-primary model.

---

## Inventory of EXISTING window / detached surfaces

This is the load-bearing section for the migration decision. **Four real windows already exist** (three app-built + the MenuBarExtra host), plus two status-item view surfaces.

| # | Surface | Controller file | What it hosts | How invoked | Window class / chrome | Activation | Persistence | Lifecycle |
|---|---|---|---|---|---|---|---|---|
| 1 | **Detached full dashboard** (AND-384) | `DetachedDashboardWindowController.swift` + `DetachedDashboardCoordinator.swift` | `MainPopover()` (same view as popover) | Footer detach pin, context-menu "Open in Window", menu-bar click while detached, `vaultpeek://`, ⇧⌘V hotkey, `--detach` | `NSWindow` `[.titled,.closable,.miniaturizable,.resizable]`; `.normal` level (→`.floating` if "keep on top"); behind-window `NSVisualEffectView` `.underWindowBackground`; `NSHostingController<AnyView>` | `requestRegular()`/`releaseRegular()` | `setFrameAutosaveName` | Lazy singleton, reused, `isReleasedWhenClosed=false`, alpha-fade show/hide |
| 2 | **Category Dashboard window** (AND-539) | `CategoryDashboardWindowController.swift` + `Coordinator` + `Environment` | `CategoryDashboardWindow()` | `openCategoryDashboard` env action from `CategoryDashboardCard` "Open dashboard" | `NSWindow` titled/resizable; 640×640 default, 520×480 min; behind-window vibrancy; `NSHostingController` | `requestRegular()`/release | autosave `VaultPeekCategoryDashboard` | Lazy singleton, re-raise, `isReleasedWhenClosed=false`, hide via `windowShouldClose→false` |
| 3 | **Review Table window** (AND-532) | `ReviewTableWindowController.swift` + `Coordinator` + `Environment` | `ReviewTableWindow()` | `openReviewTable` env action from Review Inbox header | `NSWindow` titled/resizable; 760×560 default, 560×420 min; behind-window vibrancy; `NSHostingController` | `requestRegular()`/release | autosave `VaultPeekReviewTable` | Lazy singleton, re-raise, `isReleasedWhenClosed=false` |
| 4 | **Menu-bar popover host** | owned by `MenuBarExtra(.window)`; frame pinned by `PopoverWindowAnchor.swift` | `MainPopover()` | Status-item click | SwiftUI-owned `NSWindow`; frame-pinned imperatively | n/a | frame pinned (not autosaved) | Owned by MenuBarExtra |
| 5 | Status-item badge overlay | `StatusItemBadgeController.swift` | `NSView` subview on the status button (unreviewed count) | always-on | `NSView`, hit-testing disabled | n/a | n/a | re-attached idempotently |
| 6 | Status-item context menu | `StatusItemContextMenuController.swift` | `NSMenu` (Open/Refresh/Settings/Updates/About/Privacy Mask) | right-click / ⌥-click | `NSMenu` | n/a | n/a | transient |

**Shared, proven window pattern across #1–#3:** clear non-opaque `NSWindow` + behind-window `NSVisualEffectView` (AND-511 spike: real desktop read-through), `NSHostingController`, frame autosave, lazy-singleton reuse, `didBecomeKeyNotification` → App-Lock unlock prompt (AND-462), and `AppActivationPolicyCoordinator` elevation. Each surface has a 3-file coordinator/controller/environment split that already decouples views from AppKit lifecycle.

**Implication:** the codebase has already solved (and ships) the hard parts of native windowing on macOS 26 — vibrancy, activation policy, frame persistence, App Lock, deep-link/hotkey summoning. The detached dashboard literally hosts the same `MainPopover` view a window-primary model would promote.

---

## Navigation architecture today

- **No declarative navigation containers.** `grep` for `NavigationStack`/`NavigationSplitView`/`NavigationView`/`TabView`/`NavigationLink` across `Sources/PlaidBar/Views` and `App` returns **none**. The only routing primitives are `.sheet` (`MainPopover.swift:177`; `CategoryDashboardWindow.swift:59` budget editor) and a custom inspector morph (`MainPopover.swift:430`).
- **Routing = a flat filter band.** `DashboardFilterBar` (`DashboardNavBand.swift:39`) is a custom segmented control (deliberately not `Picker(.segmented)` so a `matchedGeometryEffect` selection pill can glide — AND-577, `DashboardNavBand.swift:23-49`). Filters are the Core enum `DashboardAccountFilterKind` (Cash/Credit/Savings/Debt/Investments/Status) reused directly (`DashboardNavBand.swift:11`).
- **UI navigation state lives in the view, not AppState.** `@AppStorage("dashboard.accountFilter")` and `@AppStorage("dashboard.selectedAccountId")` are declared in `MainPopover` (`MainPopover.swift:14-15`); `AppState` has zero references to `selectedAccountId`/`accountFilter` (verified: `grep -c` = 0). Account drill-in is single-selection via `selectedAccountId` (`MainPopover.swift:79-227`).
- **One view, many hosts.** `MainPopover` (2,712 LOC) reads `\.dashboardPresentation` to decide whether to show a detach pin (popover) or a re-dock control (window) (`MainPopover.swift:2478`, `DashboardPresentation.swift:12-23`). This is the existing seam a window-primary model would build on.

**Migration relevance:** a dedicated-window model with a sidebar would introduce `NavigationSplitView` (new construct for this codebase) and move filter/selection state out of `@AppStorage`-in-view into per-window state. The flat-band routing is shallow, so there is little hierarchy to untangle, but there is also little existing navigation scaffolding to reuse.

---

## AppState assessment

**Size:** 4,213 LOC total — `AppState.swift` (3,972) + `AppState+ReadModelCache.swift` (139) + `AppState+TransactionCache.swift` (102).

**Shape:** `@Observable @MainActor final class AppState` (`AppState.swift:9-11`). Correctly `@Observable` (not `ObservableObject`); `@MainActor`-isolated. **Not `Sendable`.** Injected via SwiftUI `@Environment(AppState.self)`.

**~67 stored properties**, grouped:
- Server/data state (~20): `accounts`, `liabilities`, `transactions`, `itemStatuses`, `balanceHistory`, `accountBalanceLedger`, `categoryBudgets`, server readiness fields (`AppState.swift:63-177`).
- UI/presentation flags (~8) — includes the single-surface flags below (`AppState.swift:103-178`).
- Preferences (~30): menu-bar mode/icon, thresholds, refresh policy, notification toggles, watchlist, App Lock, launch-at-login, summon hotkey, local-AI prefs (`AppState.swift:193-489`).
- Caches & services (~18): `serverClient`, `localDataCache`, `readModelCacheStore`, `transactionCacheStore`, `merchantLogoStore`, `appLockService`, `reviewStorageWriter`, `localAIInsightsService`, `notificationService`, `foundationModelsProbe`, `glanceSnapshotWriteDebouncer`, plus `refreshTask`/`localAISummaryRefreshTask` and `_cached*` derived caches (`AppState.swift:497-548, 1310-1607`).

**Single-surface coupling (the migration-critical part):**

| Property | Line | Why it blocks multi-window |
|---|---|---|
| `isPopoverPresented` | `AppState.swift:117` | Tracks whether *the* popover is open; per-window presentation would need per-window state. The whole `MenuBarExtra` is bound to `$appState.isPopoverPresented` (`PlaidBarApp.swift:265`). |
| `isDashboardDetached` | `AppState.swift:126` | A single persisted boolean ("docked vs floating"). In a multi-window world this must become a window registry. |
| `menuBarText` / `menuBarStatusPresentation` / `menuBarSignalGlyph` | `AppState.swift:953-1009` | Singular computed values; fine for one menu bar, but they couple "current display" into the shared store. |
| App Lock state (`isAppLocked`, `lastUnlockMessage`) | `AppState.swift:397-403` | App-wide today; multi-window must decide per-window vs global unlock. |

Notably, account-filter/selection state is **not** in AppState (it's in the view via `@AppStorage`), which slightly *reduces* AppState's single-surface coupling — but also means there is no per-window UI-state container to inherit.

**Coupling depth:** AppState instantiates and owns ~12 services and mixes networking, persistence, SwiftData caches, biometric lock, AI, notifications, energy scheduling, and UI flags in one type. Roughly 60% is legitimate app-wide state; ~40% is view-model-style derivation (`netBalance`, `categoryBudgetPresentation`, `transactionReviewInboxSnapshot`, `recurringTransactions`, `localAIActivitySummaries`, all cached via `_cached*` with `didSet` invalidation). Business logic is largely *delegated* to Core (`MenuBarSummary`, `CategoryBudgetPlanner`, `CategoryDashboardBuilder`, `RecurringDetector`, `TransactionReviewInbox`) but the orchestration and caching live here.

**Verdict:** AppState is the central refactor target for a window-primary pivot. The data/services half is reusable as a shared app-wide store; the UI-flag/derivation half (popover presented, detached, menu-bar display, derived caches) assumes one surface and would need to split into per-window view models with a shared single background-refresh coordinator.

---

## Data layer & SwiftData strategy

Three storage tiers:

**Tier 1 — App-side SwiftData read-model cache (`PlaidBarCache` target, AND-566/567).** Two `@Model` types: `CachedDashboardReadModel` (single-row, `@Attribute(.unique) cacheKey`, JSON `payload`) and `CachedTransaction` (composite `@Attribute(.unique) uniqueKey` for `#Unique`-style upsert on re-sync). Accessed via two `@ModelActor` stores (`ReadModelCacheStore`, `TransactionCacheStore`) with on-disk containers in `~/.vaultpeek/` at `0o700/0o600`. Purpose: instant cold-render before the first HTTP refresh, plus paged transaction virtualization. **Disposable** — rebuilt on refresh, wiped on reset. Every op is `try?`-guarded in AppState, so SwiftData unavailability degrades cleanly. *Survives UI rearchitecture: PARTLY* — the data and stores are UI-agnostic, but the store *instances* are AppState properties (`AppState.swift:509,516`) and the hydrate/persist seams live in `AppState+*Cache.swift`; per-window AppState instances would need a shared container or scoped reopen.

**Tier 2 — App-side JSON/local cache (`PlaidBarCore`).** `LocalDataStore`/`LocalDataCacheService` (actor) persist `accounts.json`, `transactions.json`, review metadata, rules under `~/.vaultpeek/`, scoped by environment + path. Authoritative warm path; SwiftData is a second cache layered on top. *Survives: YES* — pure path-scoped file I/O.

**Tier 3 — Server-side Fluent/SQLite.** `ItemModel` (`items`) and `SyncCursorModel` (`sync_cursors`) with migrations `CreateItems`, `CreateSyncCursors`, `AddProviderToItems`, `AddOriginToItems` (`Database.swift`). Per-environment `plaidbar-<env>.sqlite`. *Survives: YES* — separate process, behind HTTP.

**Core domain models:** `Sources/PlaidBarCore/Models/` holds ~70 files / ~194 type decls, all `Codable`/`Sendable` structs (`TransactionDTO`, `AccountDTO`, `BalanceDTO`, `DashboardReadModel`, etc.). *Survives: YES* — UI-agnostic.

---

## Sync, background services, Plaid/auth boundary

**No separate `RefreshService`/`SyncService` types exist** (despite the CLAUDE.md mention — that is design intent). The background loop lives **inside AppState**: a single `refreshTask` (`AppState.swift:526`) ticks `refreshDashboard()` + `evaluateNotifications()`, sleeping a base 15-min interval (`Constants` `backgroundRefreshInterval`) scaled ×4 under energy pressure.

- **`ServerClient`** — `actor` (`ServerClient.swift:4`); HTTP to `/api/*` with bearer auth from `~/.vaultpeek/auth-token`; UI-agnostic. *Survives: YES.*
- **`ServerProcessService`** — `@MainActor` singleton; launches/supervises the bundled server, detects external servers via `/health`, SIGTERM on app exit. *Survives: YES.*
- **`NotificationService`** — `@MainActor`; trigger evaluation + LRU dedup in UserDefaults. *Survives: YES.*
- **`LaunchService`** — `SMAppService` wrapper. *Survives: YES.*
- **`SummonHotkeyMonitor`** — `@MainActor`; Carbon `⇧⌘V` global hotkey. *Survives: YES* (callback injected; would just retarget the window).
- **`PagedTransactionSource`** / **`MerchantLogoStore`** / **`HapticFeedback`** — `@Observable @MainActor` view-layer; fetch/policy logic is Core-side. *Survives: PARTLY.*
- **Energy-aware scheduling** — `EnergyAwareRefreshPolicy` (Core) reads Low Power Mode + thermal state; `AutomaticRefreshPolicy` (`.twiceDaily` default / `.manualOnly`); observers restart the loop on power/thermal change (`AppState.swift:2548-2587`). UI-agnostic.

**Plaid/auth security boundary — survives UI rearchitecture UNTOUCHED (verified):**
- Server binds `127.0.0.1` only (`App.swift:150-156`); no override.
- `/health`, `/oauth/callback`, `/webhook/*` open; everything under `/api` behind `APITokenMiddleware` (`App.swift:79-85,139,145`) with constant-time token compare + localhost-origin CSRF defense (`APITokenMiddleware.swift:16-32,82-95`).
- Access-token bytes in macOS Keychain; SQLite stores `keychain:<item_id>` references (`PlaidTokenVault.swift:65-67`; `TokenStore.swift:63-68`).
- `PlaidClient` is a server-only `actor` holding `client_secret`/`client_id` from `ServerConfig` (`PlaidClient.swift:45-71,114-121`); **no `PlaidClient`/`ServerConfig` in app code**.
- `/api/status` is a readiness contract that explicitly excludes tokens/IDs/balances/transactions (`StatusRoutes.swift:34-87`; `ServerStatus.swift:5`).

**Verdict:** the server/auth/Plaid layer is a black box behind localhost HTTP. A popover→window pivot touches none of it.

---

## Widget & AI tiers

**Glance surfaces (out-of-process):**
- Widget extension (`PlaidBarWidgetExtension`) hosts `PlaidBarGlanceWidget` (small/medium), Control Center controls (`RefreshBalancesIntent`, `SetPrivacyMaskIntent`, Safe-to-Spend + Credit-Utilization value displays), via `PlaidBarWidgetBundle.swift`.
- App-side App Intents: `FinanceAppIntents` (Get Safe-to-Spend / Get Balance, privacy-gated), `FocusPrivacyFilterIntent` (mask while Focus active), Spotlight indexing via `AccountSpotlightIndexer` (salted-hash IDs, last-4 only).
- Data crosses the boundary as **display-only** App Group snapshots: `GlanceSnapshot` and `FinanceSnapshot` in `PlaidBarCore` (group `group.com.ftchvs.PlaidBar`), written debounced (400 ms) by `GlanceSnapshotWriteDebouncer` (actor, Core). Extension → app commands are tiny JSON files consumed on `didBecomeActive`. No tokens/balances/IDs ever cross.
- *Survives UI rearchitecture: YES* — only coupling is the `vaultpeek://dashboard` deep link and the `writeGlanceSnapshot()`/`writeFinanceSnapshot()` call sites, which move location but not contract.

**Local AI tiers** (all UI-decoupled; produce Core presentation models):
1. Apple Foundation Models (on-device, `#available(macOS 26)`), probed via `FoundationModelsAvailabilityProbe` (`SystemLanguageModel.default.availability`).
2. Ollama local runtime (localhost-enforced, model auto-discovery).
3. Apple NaturalLanguage categorizer (always-on, merchant hints only).
4. Deterministic heuristic fallback.

Resolved by `LocalAITierResolver` (Core). **Off by default** — no transaction data routes anywhere without explicit opt-in (`LocalAIInsightsService.swift:356-387`). Output is a display-safe `LocalAIInsightReceipt` (redacted evidence, reversible-action language; `LocalAIInsights.swift:176-457`). *Survives: YES.*

---

## Business-logic distribution (Core vs app vs server)

LOC by target (`*.swift`):

| Target | Files | LOC | Notes |
|---|---|---:|---|
| **PlaidBarCore** | 153 | **25,280** | Models (70 files, 11,503) + Utilities (82 files, 13,774). `Sendable`, testable, UI-free. **The center of gravity.** |
| **PlaidBar (app)** | 83 | **23,769** | Views 11,979 (40 files) · App/lifecycle/windows 6,459 (17) · Settings 1,961 (1) · Services 2,264 (16) · Theme/Intents/Controls/Spotlight/Models ~1,106 |
| **PlaidBarServer** | 35 | **6,593** | Routes 2,407 · Config 1,165 · Storage 1,048 · Plaid 840 · Auth 663 |
| **PlaidBarWidgetExtension** | 2 | 502 | thin shells over Core |
| **PlaidBarCache** | 6 | 526 | SwiftData `@Model` + `@ModelActor` |
| **PlaidBarCLI** | 1 | 325 | CLI over localhost server |
| **Tests** | 146 | 34,175 | Swift Testing; tests outweigh source |

**Distribution read:** roughly **45% of source LOC is in Core** (UI-agnostic, survives). Of the app's 23.8K LOC, ~12K is SwiftUI views and ~6.5K is lifecycle/window/AppState plumbing — the part most exposed to a UI pivot. Two files dominate the app risk surface: `AppState.swift` (3,972) and `MainPopover.swift` (2,712). Server logic (6.6K) is fully insulated. The strong Core concentration is the single biggest asset for a migration: the model, reducers, presentation logic, energy policy, and AI tiers do not move.

---

## Technical-debt assessment (ranked)

| # | Severity | Debt | Evidence |
|---|---|---|---|
| 1 | **High** | **`AppState` god object (4,213 LOC, ~67 props, ~12 services, not `Sendable`).** Mixes data, prefs, caches, AI, notifications, energy, and UI flags. Single-surface flags (`isPopoverPresented`, `isDashboardDetached`) and singular menu-bar computeds embed "one surface" assumptions. | `AppState.swift:9-11,117,126,953-1009,497-548` |
| 2 | **High** | **`MainPopover` is a 2,712-LOC view** doing layout, filter routing, drill-in, inspector morphs, sheets, heatmap, and per-surface presentation switching in one file. Reused across 4 hosts, amplifying change risk. | `MainPopover.swift` (whole) |
| 3 | **Medium** | **Popover-host window surgery is inherently fragile.** `PopoverWindowAnchor` reaches into the SwiftUI-owned `MenuBarExtra` window to pin its frame because SwiftUI re-centers it; this is a workaround (AND-514/SPIKE F2), not a supported API. | `PopoverWindowAnchor.swift` |
| 4 | **Medium** | **UI navigation state in `@AppStorage` inside the view** (`dashboard.accountFilter`, `dashboard.selectedAccountId`). Global UserDefaults keys cannot represent per-window selection; multi-window would alias state across windows. | `MainPopover.swift:14-15` |
| 5 | **Medium** | **Window controllers duplicate a ~3-file boilerplate** (controller + coordinator + environment) per surface with near-identical `NSWindow`/`NSVisualEffectView`/autosave/App-Lock code. No shared base class. | `DetachedDashboard*`, `CategoryDashboardWindow*`, `ReviewTableWindow*` |
| 6 | **Low** | **Background sync embedded in AppState** rather than an extractable `SyncService`/`RefreshService` (contradicts CLAUDE.md intent). Works at current scale; couples loop to UI state. | `AppState.swift:526,2149-2193,1906-1976` |
| 7 | **Low** | **Derived `_cached*` view-model caches with `didSet` invalidation in AppState** add invalidation complexity that would multiply with per-window filtering. | `AppState.swift:1310-1607` |

---

## Migration complexity assessment (per subsystem)

Rating each subsystem **Survives-as-is / Adapts / Rebuilds**, with effort **S/M/L/XL**, for a pivot to a window-primary macOS 26 app (menu bar → launcher/glance).

| Subsystem | Verdict | Effort | One-line reason |
|---|---|---|---|
| Server / Plaid / auth / Keychain | **Survives-as-is** | — | Separate process behind localhost HTTP; UI pivot touches zero credential code. |
| `PlaidBarCore` (DTOs, reducers, presentation, energy, AI tiers) | **Survives-as-is** | S | UI-agnostic, `Sendable`, already 45% of LOC. |
| Server-side SQLite / Fluent | **Survives-as-is** | — | Behind the HTTP boundary. |
| JSON local cache (Tier 2) | **Survives-as-is** | S | Path-scoped file I/O. |
| Glance surfaces (widget, controls, intents, Spotlight) | **Survives-as-is** | S | Out-of-process; only deep link + write-site move. |
| Background services (ServerClient, ServerProcessService, Notification, Launch, hotkey) | **Survives-as-is** | S | UI-agnostic; hotkey/deep-link just retarget the window. |
| Existing AppKit window controllers (#1–#3) | **Adapts** | M | Pattern is exactly what a window-primary model needs; refactor toward a shared `Window`/`WindowGroup` scene or a base controller; dedupe boilerplate. |
| SwiftData read-model cache (Tier 1) | **Adapts** | M | Move store instances off AppState into a shared app-level container so multiple windows share one on-disk store. |
| `DashboardPresentation` / `MainPopover` host-switching | **Adapts** | M | Already two-host-aware; extend to window-primary; split the 2,712-LOC view. |
| Menu-bar item (status/badge/context menu) | **Adapts** | M | Demote popover to optional glance; keep `MenuBarExtra` label + context menu as launcher; remove popover-host surgery. |
| Navigation / routing | **Rebuilds** | L | No `NavigationStack`/`SplitView` exists; a windowed app likely needs a sidebar + detail split, a new construct here. |
| `AppState` (UI-flag + derivation half) | **Rebuilds** | L–XL | Split into a shared app-wide data/service store + per-window view models; replace `isPopoverPresented`/`isDashboardDetached` with a window registry; relocate `@AppStorage` filter/selection to per-window state. |
| Activation policy | **Adapts** | S | `AppActivationPolicyCoordinator` already refcounts `.accessory`↔`.regular`; window-primary likely defaults `.regular` with the coordinator demoting to `.accessory` only for glance-only mode. |

**Overall:** the *infrastructure* needed for a window-primary app (real `NSWindow`s, vibrancy, activation policy, frame persistence, App Lock, deep-link summoning, a host-agnostic dashboard view, a Core-heavy model layer, an insulated server) **already exists and ships today.** The concentrated risk is `AppState`'s single-surface coupling and the absence of any navigation hierarchy — both real, both squarely in the app target, neither touching the security boundary or Core.
