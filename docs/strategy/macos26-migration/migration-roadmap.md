# Migration Roadmap & Sequencing

Phased plan for the window-first hybrid ([ADR-001](ADR-001-window-first-architecture.md)).
Each epic maps to a Linear epic (team **Andeslab / AND**, project **"VaultPeek
macOS 26 — Window-First Architecture"**). Effort key: S ≤2d · M ~1wk · L ~2–3wk · XL >3wk.

---

## Gate 0 — Decision & doctrine (blocks everything)

Not an epic — a ratification gate owned by Felipe.

- Ratify ADR-001 (or choose the counter-case / status quo).
- Confirm session-workflow scope stays in-product.
- Update doctrine **in lockstep**: `docs/mvp-launch-decision-log.md`,
  `docs/post-mvp-roadmap.md`, `docs/v1.0-roadmap.md`, `CLAUDE.md`, `GOAL.md`,
  `PRD.md` — replace "popover-primary" with "window-first hybrid" and link ADR-001.
- Approve macOS 26 "Tahoe" as the hard minimum OS.

**Exit criteria:** ADR-001 status → Accepted; doctrine PR merged. No code epic
starts before this.

---

## Phase 1 — Foundation

### Epic 1 — macOS 26 Application Shell  *(M–L)*
Declarative `Window("VaultPeek", id: "main")` scene + `AppShellView`
(`NavigationSplitView`), `MenuBarExtra(style:.window)` retained, `Settings` scene,
`.defaultLaunchBehavior(.suppressed)` + `.restorationBehavior(.automatic)`,
`.containerBackground(.ultraThinMaterial, for:.window)`, single tested
`@MainActor` activation-policy helper. **Feature-flagged on; popover still default.**
Blocks: 2, 3. Blocked by: Gate 0.

### Epic 2 — Navigation Architecture Refactor  *(L)*
Typed `Route` enum, single `@Observable NavigationModel` replacing scattered
`@AppStorage`; sidebar (4 groups: Overview / Workflows / Insights / Money /
System) with text-count badges; 2-col vs 3-col policy per destination;
`⌘K` command palette (`CommandRegistry`) + `CommandMenu`/`CommandGroup` global
keymap; deep-linking + selection restoration. Blocks: 4–9. Blocked by: 1.

### Epic 3 — Window Lifecycle Migration  *(L)*
Migrate imperative AppKit controllers (detached dashboard, Category Dashboard,
Review Table) to the declarative scene + destinations; retire
`AppActivationPolicyCoordinator` refcounting (R-01) and `PopoverWindowAnchor`;
per-window state via `NavigationModel` (not view `@AppStorage`); frame autosave /
restoration. Blocks: 4, 5, 6. Blocked by: 1, 2.

---

## Phase 2 — Workspaces *(parallelizable once Phase 1 lands)*

### Epic 4 — Transaction Workspace  *(L)*
Dense, keyboard-navigable `Table`; filters + search; inspector (3-col); reuse
existing transaction components; large-history virtualization + paged fetch
(already shipped) wired to the table. Blocked by: 2, 3.

### Epic 5 — Planning & Budgeting Workspace  *(L)*
Budgets (category tree, `BudgetEditorSheet`, status bars), Planning canvas,
safe-to-spend; override-aware spend math (reuse Core). 2-col Planning, 3-col
Budgets. Blocked by: 2, 3.

### Epic 6 — Review Inbox  *(M–L)*
Consolidate the detached Review Table into a first-class destination: date-sectioned
list ↔ triage detail; single-key actions (A/C/T/R/M/I) with undo + haptics +
auto-advance; inline "always categorize…" rule prompt; Triage|Table mode with the
existing bulk engine + blast-radius confirmation. Blocked by: 2, 3.

### Epic 7 — Insights & Intelligence  *(M)*
Insights destination surfacing Foundation Models `@Generable` streaming insights +
weekly review + LocalAIInsightReceipt; trend/donut/heatmap charts with
`AXChartDescriptor` audio graphs. Blocked by: 2. Related: 4, 5.

---

## Phase 3 — Reach, simplification, polish

### Epic 8 — Widgets & App Intents  *(M)*
Expand WidgetKit families + interactive widgets; `AppIntentsPackage` in
`PlaidBarCore` (reused by app/widget/Siri/Spotlight); `SnippetIntent` mini-dashboard
in Spotlight; investigate `ControlWidget` (verify macOS availability). App-Group
shared SwiftData store. Blocked by: 2. Related: 1.

### Epic 9 — Menu Bar Simplification  *(M)*  — **SHIPS LAST**
Reduce the popover to glance-only (status, sync, 2–4 metrics, attention chips,
"Open VaultPeek"); remove migrated workflows from the popover; flip the default
from popover to window; remove the dual-run flag. **Gated on a window-parity
sign-off.** Blocked by: 4, 5, 6, 7 (parity).

### Epic 10 — Liquid Glass Polish  *(M, continuous)*
Apply Liquid Glass to chrome only (sidebar/toolbar/nav), never data; group with
`GlassEffectContainer`; `reduceTransparency` solid fallbacks; motion polish
(matched-geometry reflow already shipped); final a11y pass (Dynamic Type, audio
graphs, Privacy Mask gating uniform across windows). Runs alongside 1–9; finalized
last. Blocked by: 1 (starts), 9 (finalizes).

---

## Critical path

`Gate 0 → Epic 1 → Epic 2 → Epic 3 → (Epics 4/5/6 parallel) → Epic 7 → Epic 9`.
Epics 8 and 10 run alongside and do not gate the critical path (10 finalizes after 9).

## Dual-run / reversibility

Epics 1–8 are reversible by flipping the feature flag (window hidden, popover
default). Epic 9 removes the popover path and is therefore **gated on parity** —
the point of no easy return.
