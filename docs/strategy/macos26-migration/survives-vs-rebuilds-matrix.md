# Survives vs Rebuilds Matrix

Source: [01-current-state-architecture.md](01-current-state-architecture.md) (architecture audit) + synthesis.
Effort key: **S** ≤2d · **M** ~1wk · **L** ~2–3wk · **XL** >3wk. Verdicts:
**Survives** (use as-is) · **Adapts** (modify/wrap) · **Rebuilds** (net-new).

## Summary

| Bucket | ~Weight | Risk |
|--------|--------|------|
| Survives as-is | ~55% | None — out of migration scope |
| Adapts | ~30% | Low–Medium |
| Rebuilds (net-new) | ~15% | Medium (concentrated in navigation + AppState) |

The migration **never crosses the security boundary** and **never touches
`PlaidBarCore`** (~45% of LOC). The two most expensive things to get wrong are out
of scope by construction.

---

## What Survives (as-is)

| Subsystem | Verdict | Effort | Notes |
|-----------|---------|--------|-------|
| Server process (`PlaidBarServer`) | Survives | — | Separate process behind localhost HTTP; a UI pivot cannot reach it |
| Plaid client + token vault + `APITokenMiddleware` | Survives | — | Security boundary; explicitly out of scope |
| Keychain storage / SQLite item store / sync cursors | Survives | — | No schema change required |
| **`PlaidBarCore` (~25K LOC, ~45% of source)** | Survives | — | Sendable, TDD'd; summaries, formatters, recurring detection, sync reduction, presentation mapping. New logic adds here |
| Background services (RefreshService, SyncService, energy-aware scheduling, NotificationService, LaunchService) | Survives | S | Window model changes *callers*, not the services |
| JSON read-model cache / SwiftData disposable cache (read path) | Survives | S | Cold-render cache pattern carries over |
| Widget extension (`PlaidBarWidgetExtension`) | Survives | S | Expands in Epic 8; foundation unchanged |
| Local AI tiers (NaturalLanguage → Foundation Models, `@Generable` insights) | Survives | — | Service layer; UI surfaces consume it |
| Design tokens / Typography / 8pt grid (`Theme/`) | Survives | — | Reused by the shell |
| ~30 view components (AccountDetailFlyout, ReviewInboxView, CategoryTreeView, CategoryStatusBar, BudgetEditorSheet, SafeToSpendCard, all `Charts/`, WeeklyReviewCard, LocalAIInsightReceipt, SettingsView) | Survives | S | Re-hosted into destinations; internals intact |

## What Adapts (modify / wrap)

| Subsystem | Verdict | Effort | Notes |
|-----------|---------|--------|-------|
| Existing window controllers (Detached dashboard, Category Dashboard, Review Table) | Adapts | M | Imperative AppKit → declarative scenes / destinations; the *hard* windowing (vibrancy, autosave, activation) is already solved and reused |
| `MenuBarExtra` item + `MenuBarExtraAccess` + badge/context-menu controllers | Adapts | M | Reduced to glance-only; status item logic mostly retained |
| `DashboardPresentation` host-switching enum | Adapts | S | Already exists to render host-agnostically — extend, don't invent |
| `AppActivationPolicyCoordinator` (.accessory↔.regular refcount) | Adapts | M | Window-primary *simplifies* this; retire obsolete refcounting carefully (R-01) |
| SwiftData read-model cache (write/coordination path) | Adapts | M | Per-window contexts; App-Group sharing for widget |
| `MainPopover` (2,712 LOC, 4 hosts today) | Adapts | L | Decompose into destination views; reuse subviews |
| Demo/Sandbox/Production mode plumbing | Adapts | S | Surfaced in shell footer + Settings |

## What Rebuilds (net-new)

| Subsystem | Verdict | Effort | Notes |
|-----------|---------|--------|-------|
| **Navigation hierarchy** (sidebar, `NavigationSplitView` 2/3-col, `NavigationStack`, typed `Route`, deep-linking) | Rebuilds | L | None exists today — flat `@AppStorage` filter band only. The core build cost |
| **Command palette (⌘K)** + `CommandMenu`/`CommandGroup` keyboard map | Rebuilds | M | No centralized command structure today |
| **`AppState` UI-state decomposition** | Rebuilds | L | 4,213 LOC god object, ~67 props, not Sendable, single-surface flags (`isPopoverPresented`, `isDashboardDetached`); split into per-window `@Observable` navigation/selection models. Highest-uncertainty item (R-02) |
| Menu-bar **popover → glance** reduction | Rebuilds | M | Ships LAST (Epic 9, guardrail); glance view is small but the removal is gated on parity |
| **Goals** destination + Core logic | Rebuilds | M | The one genuinely new feature; finance math lands in `PlaidBarCore` |
| `PopoverWindowAnchor` (host-window surgery) | Rebuilds→Delete | S | Fragile workaround; disappears under a real window model |
| Onboarding/first-run in a windowed model | Rebuilds | S | Re-host existing FirstRunSnapshotView into the shell |

---

## Reading the percentages

These are *judgment* weights by subsystem importance, not LOC. By raw LOC the
"survives" share is higher still (Core alone is ~45%). The point is directional and
robust: **the migration is bounded to the app target's presentation layer, and the
genuinely net-new work is one navigation shell plus an `AppState` split.**
