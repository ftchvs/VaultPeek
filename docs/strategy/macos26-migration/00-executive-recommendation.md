# Executive Recommendation — VaultPeek macOS 26 Window-First Architecture

**Date:** 2026-06-19
**Author:** Architecture evaluation (5-agent parallel research + synthesis)
**Decision owner:** Felipe Chaves
**Status:** Proposed — awaiting ratification
**Supersedes:** the *product-model* half of AND-384 ("popover-primary, polish only")

---

## 1. Recommendation

**Adopt a window-first *hybrid*: promote a dedicated native macOS 26 window to the
primary VaultPeek experience, and reduce the menu bar to a first-class glance +
launcher. Keep the menu-bar glance sacred — read + route only.**

**Confidence: High.** This recommendation is reinforced independently by four of
five research agents and, crucially, by the codebase itself.

### The decisive finding

VaultPeek is **already a multi-window application in everything but doctrine.**

- **Three+ real `NSWindow` surfaces already ship today:** the detached dashboard
  (AND-384, #357), the Category Dashboard window (AND-539), and the multi-select
  Review Table window (AND-532) — all real `NSWindow`s (not panels), with
  behind-window `NSVisualEffectView` vibrancy, frame autosave, lazy-singleton
  reuse, App-Lock observation, and `.accessory↔.regular` activation elevation.
- **The macOS 26 *platform* migration already landed** (AND-508–515, merged
  2026-06-18): Liquid Glass, App Intents, WidgetKit, SwiftData read-model cache,
  Dynamic Type, deploy floor — plus Foundation Models AI tiers since.
- A `DashboardPresentation` environment enum *already* makes the main view render
  host-agnostically in both popover and window.

What is therefore **missing** is small and well-bounded:

1. A coherent **navigation shell** — there is no `NavigationSplitView`/`NavigationStack`
   anywhere today; routing is a flat `@AppStorage` filter band.
2. A **declarative primary `Window` scene** — today windows are imperative AppKit
   controllers bolted onto a `MenuBarExtra + Settings` scene graph.
3. **Governance docs that match the code** — the decision log still says
   "popover-primary"; the binary ships windows. This divergence is itself a risk.

**Conclusion:** This is a *consolidation and formalization* of work that already
exists, plus one net-new navigation layer — **not** a risky rewrite. That
reframing is the single most important output of this evaluation.

---

## 2. Was the menu bar a real choice or the fastest path?

**Both — and the product has outgrown the container.** (Full evidence: [02](02-product-strategy.md), [03](03-archaeology.md).)

- The menu-bar form factor was the **founding thesis** ("RepoBar/CodexBar for
  personal finance"), never an examined decision — the burden of proof was only
  ever placed on *deviating* from it. The *glance* value is genuine and enduring.
- But every **session workflow** that has since shipped — transaction review
  triage, bulk recategorization, category budgets, weekly review, reconciliation —
  has either escaped into an `NSWindow` or is structurally hostile to an
  auto-dismissing popover. The popover ceiling has been breached repeatedly.
- Reference precedent is unambiguous: Fantastical, Bartender, MoneyMoney all run a
  **primary window + a menu-bar entry**. Hybrid is the mature form for exactly
  this product shape.

---

## 3. Survives vs Rebuilds (summary)

Full table: [survives-vs-rebuilds-matrix.md](survives-vs-rebuilds-matrix.md).

| Bucket | ~Weight | What |
|--------|--------|------|
| **Survives as-is** | **~55%** | Server/Plaid/auth/Keychain boundary (separate process — untouched by a UI pivot); **all of `PlaidBarCore` (~25K LOC, ~45% of source, Sendable/tested)**; server SQLite; JSON/read-model caches; background services; widgets; AI tiers; ~30 view components & design tokens |
| **Adapts** | **~30%** | Existing window controllers → declarative scenes; SwiftData read-model cache; menu-bar item → glance-only; host-switching via `DashboardPresentation`; `AppState` decomposition |
| **Rebuilds (net-new)** | **~15%** | Navigation hierarchy (sidebar, `NavigationSplitView`, command palette, typed routing); `AppState` per-window UI-state split; popover reduced to glance; **Goals** (the one genuinely new feature) |

**Risk level: MEDIUM.** All rework is isolated to the app target. The migration
**never touches the security boundary or `PlaidBarCore`** — the two things most
expensive to get wrong are out of scope.

---

## 4. Engineering effort estimate

Judgment estimate, single developer accelerated by the agent loop. Ranges reflect
uncertainty in the `AppState` decomposition (the one genuine unknown).

| Phase | Scope | Estimate |
|-------|-------|----------|
| **P1** | App shell + navigation foundation (sidebar, split-view, routing, ⌘K skeleton) | 2–3 wk |
| **P2** | Window lifecycle: declarative `Window` scene, retire imperative controllers, dual-run flag | 2 wk |
| **P3** | Destination workspaces: Transactions, Budgets/Planning, Review Inbox consolidation, **Goals** | 4–6 wk |
| **P4** | Insights & Intelligence; Widgets/App Intents expansion | 2–3 wk |
| **P5** | Menu-bar simplification + Liquid Glass polish + a11y hardening | 2 wk |
| | **Total** | **~12–16 engineer-weeks** (≈3–4 months solo; materially compressible with the autonomous loop) |

This is low for a "migration" precisely because ~55% survives untouched and the
hard platform/windowing primitives already ship.

---

## 5. Recommended implementation sequence

```
[Gate 0] Ratify ADR-001 + update doctrine (decision log, roadmap, CLAUDE.md, GOAL.md)
   │
   ▼
Epic 1  macOS 26 Application Shell ──► Epic 2  Navigation Architecture ──► Epic 3  Window Lifecycle Migration
                                                                                │
                          ┌─────────────────────────────┬─────────────────────┘   (P3 workspaces parallelizable
                          ▼                              ▼                            once shell+nav land)
                  Epic 4 Transaction Workspace   Epic 5 Planning & Budgeting   Epic 6 Review Inbox
                          └───────────────┬──────────────┴──────────────┬──────────────┘
                                          ▼                              ▼
                                  Epic 7 Insights & Intelligence   Epic 8 Widgets & App Intents
                                          └──────────────┬───────────────┘
                                                         ▼
                                  Epic 9 Menu Bar Simplification  ← SHIPS LAST (guardrail)
                                                         ▼
                                  Epic 10 Liquid Glass Polish     ← continuous, finalized last
```

**Epic 9 (menu-bar simplification) ships LAST, deliberately.** Reducing the
popover before the window reaches parity would strand users. Dual-run the popover
and window behind a feature flag until parity is proven.

---

## 6. Non-negotiable guardrails

These protect against the failure mode where this migration quietly destroys
VaultPeek's only moat.

1. **Keep the glance sacred.** The menu-bar surface stays read + route only —
   status, sync, 2–4 glance metrics, attention chips that deep-link into the
   window, "Open VaultPeek." It must never host triage, editing, settings,
   tables, or any unfinishable workflow.
2. **Parity before removal.** Do not delete the popover workflows until the window
   reaches functional parity. Ship behind a flag; dual-run.
3. **Update doctrine in lockstep.** The #1 history-derived risk is the next agent
   "reverting" this work citing stale "popover-primary" docs. ADR + decision log +
   roadmap + CLAUDE.md + GOAL.md must change together (Gate 0).
4. **macOS 26 "Tahoe" is the floor.** Do **not** conflate it with macOS 27 /
   WWDC26 (betas only as of June 2026): reorderable containers, toolbar-overflow
   APIs, sectioned `@Query`, `ResultsObserver`/`HistoryObserver` must be gated
   behind `if #available(macOS 27, *)`.
5. **Liquid Glass on chrome only.** Never on lists, tables, charts, or dense data;
   never glass-on-glass. Every custom-translucency surface needs a
   `reduceTransparency` solid fallback; every chart needs an `AXChartDescriptor`.
6. **Touch nothing across the security boundary.** No change to the server, Plaid
   client, Keychain vault, or the localhost auth boundary is in scope.

---

## 7. The honest counter-case

A real minority reading deserves to be on the record (raised independently by the
product and archaeology agents):

> *The autonomous build loop **overshot** the popover doctrine. VaultPeek's own
> constitution (AND-384, the v1.0 "Menu Bar First" rule) says to treat "large
> canvas / persistent workspace" with skepticism — yet windows crept in
> feature-by-feature without a ratified decision. The disciplined move is to
> **delete two of the three windows** and recommit to glance-first, not to bless
> the drift.*

**Why we reject it as the primary path (but preserve it as the explicit
"do-not-migrate" option in the ADR):**

- The shipped session workflows (review triage, budgeting, reconciliation) are
  *genuinely* multi-step and structurally hostile to an ephemeral popover. Deleting
  the windows deletes the workflows, not just the chrome.
- Reference precedent (Fantastical, Bartender, MoneyMoney) shows hybrid — not
  glance-only — is the mature form for a resident finance/utility app.
- The expensive part (windowing, vibrancy, activation policy, host-agnostic view)
  is *already built and merged*. The cost asymmetry favors ratify-and-consolidate
  over rip-out-and-revert.

**The condition under which the counter-case wins:** if VaultPeek's strategic
identity is re-scoped to "ambient glance only, zero session workflows" (i.e., the
review/budget/planning features are themselves deprecated). That is a product-scope
decision, not an architecture one — and it is the question the decision owner must
answer at Gate 0.

---

## 8. What the decision owner must decide at Gate 0

1. **Ratify or reject** window-first hybrid (ADR-001).
2. Confirm the **session-workflow scope** stays in-product (if yes → migrate; if
   the product is re-scoped to glance-only → the counter-case path).
3. Approve the **doctrine update** (decision log / roadmap / CLAUDE.md / GOAL.md).
4. Approve **macOS 26 as the hard floor** (drops any pre-Tahoe support).

Everything downstream (Epics 1–10) is sequenced to begin only after Gate 0.
