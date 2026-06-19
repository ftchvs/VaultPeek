# ADR-001: VaultPeek Window-First Hybrid Architecture

- **Status:** Accepted — ratified by Felipe Chaves at Gate 0 ([AND-578](https://linear.app/andeslab/issue/AND-578)) on 2026-06-19. Session-workflow scope confirmed in-product; macOS 26 floor approved.
- **Date:** 2026-06-19
- **Supersedes:** the product-model decision in AND-384 ("popover-primary, polish
  only; NOT desktop-first / Window scene") and the v1.0 roadmap "Menu Bar First"
  guardrail, **to the extent they forbid a primary window**.
- **Preserves:** the security, concurrency, and local-first decisions of AND-384
  and all prior ADR-equivalent decisions (see §"What we explicitly preserve").
- **Related:** [00-executive-recommendation.md](00-executive-recommendation.md),
  [survives-vs-rebuilds-matrix.md](survives-vs-rebuilds-matrix.md)

---

## Context

AND-384 (2026-06-14) decided VaultPeek would stay **popover-primary** and treat any
"large canvas / persistent workspace" with skepticism — explicitly declining a
desktop-first `Window` scene. That decision was correct *for the MVP*: it minimized
surface area and shipped fast.

Since then, three facts changed the ground under that decision:

1. **The product grew session workflows.** Transaction review triage, multi-select
   bulk recategorization, category budgets, weekly review, and reconciliation all
   shipped. These are multi-step, dwell-time workflows — not glance-and-dismiss.

2. **The code already went multi-window.** Three real `NSWindow` surfaces ship
   today (detached dashboard AND-384, Category Dashboard AND-539, Review Table
   AND-532), each with vibrancy, frame autosave, activation elevation, and App-Lock
   observation. A `DashboardPresentation` enum already renders the main view
   host-agnostically. **The doctrine says popover-first; the binary ships windows.**

3. **The macOS 26 platform layer already landed.** AND-508–515 adopted Liquid
   Glass, App Intents, WidgetKit, SwiftData, and Dynamic Type. The platform
   migration is done; only the *product-model* migration was deliberately declined.

This ADR resolves the doctrine-vs-code divergence and formalizes the architecture
the product has been drifting toward.

---

## Decision

**VaultPeek adopts a window-first hybrid architecture on a macOS 26 floor:**

- A **dedicated primary `Window` scene** becomes the main experience: a
  `NavigationSplitView` shell (sidebar → content → optional detail/inspector) with
  destinations Dashboard, Transactions, Budgets, Planning, Goals, Review Inbox,
  Insights, Alerts, Accounts, Settings. Keyboard-first, command-palette (⌘K)
  navigable, Liquid-Glass-polished on chrome only.
- The **`MenuBarExtra` glance is retained as a first-class, reduced surface**:
  status, sync state, 2–4 glance metrics, attention chips that deep-link into the
  window, and "Open VaultPeek." **Read + route only.**
- The existing **imperative AppKit window controllers are migrated to declarative
  scenes** and their workflows fold back into sidebar destinations.
- **`PlaidBarCore`, the server, the Plaid client, the Keychain vault, and the
  localhost auth boundary are unchanged.**

The menu bar becomes an **entry point into** the primary experience, not the
primary experience itself.

---

## Options considered

### Option A — Keep popover-primary (status quo doctrine) — REJECTED
Honor AND-384 literally; treat the shipped windows as exceptions; do not build a
navigation shell.
- **Pro:** zero migration cost; preserves the purest glance identity.
- **Con:** the doctrine already does not match the code; session workflows remain
  cramped in an auto-dismissing popover; the divergence keeps regenerating risk
  (next agent "reverts" or re-adds windows ad hoc). Does not scale to the roadmap.

### Option B — Window-only (delete the menu-bar surface) — REJECTED
Become a conventional `.regular` dock app; drop the glance.
- **Pro:** simplest mental model; full dock/Stage Manager citizenship.
- **Con:** forfeits VaultPeek's **only uncontested moat** — the "local-first +
  glanceable" quadrant (`pricing-and-launch.md`). The ambient glance is the
  differentiator vs. Copilot/Monarch. Throwing it away to win a crowded quadrant is
  strategically backwards.

### Option C — Window-first hybrid — **CHOSEN**
Primary window + retained glance. See Decision above.
- **Pro:** matches the code; unlocks the session workflows; preserves the moat;
  ~55% of the system survives untouched; precedent-aligned (Fantastical/Bartender/
  MoneyMoney).
- **Con:** requires discipline to keep the glance from re-bloating; doctrine must
  be rewritten; introduces a net-new navigation layer (the one real build cost).

### Option D — "Do not migrate; delete the drift" (the counter-case) — REJECTED, conditionally
Delete two of the three windows; recommit to glance-only; deprecate session
workflows.
- **Pro:** maximal doctrinal purity; smallest maintenance surface.
- **Con:** deletes shipped, working, multi-step workflows users value; discards
  already-merged windowing investment; mistakes "the build loop overshot" for "the
  product should be smaller."
- **Wins only if** the product is deliberately re-scoped to ambient-glance-only
  with no session workflows — a product-scope call for the decision owner, not an
  architecture call. Recorded here so the choice is explicit, not implicit.

---

## What we explicitly preserve (do NOT touch)

These were correct and remain correct; the migration must not regress them.

1. **Two-process security boundary.** UI talks only to `127.0.0.1`; the server owns
   Plaid `client_secret` / `access_token`; SQLite holds only `keychain:<item_id>`
   references; tokens live in the Keychain vault (now `ThisDeviceOnly`, AND-572).
   *The single decision in the repo with a written rationale — form-factor independent.*
2. **Core-centric, `Sendable`, TDD'd logic in `PlaidBarCore`.** Strict-concurrency
   (`-strict-concurrency=complete -warnings-as-errors`) is the CI gate. New finance
   logic (e.g., Goals) lands in Core as pure Sendable types.
3. **Local-first, no hosted backend, no telemetry** (ratified 2026-06-14).
4. **Single drill-in, no tab tree** (AND-312); recovery-first UX; accessibility
   rules (never encode meaning via color alone; Privacy Mask; redacted glance
   snapshots; audio graphs).

---

## Consequences

**Positive**
- Doctrine and code reconverge; future agents stop oscillating.
- Session workflows get the canvas they need (3-column density = the original
  RepoBar/CodexBar north star, physically impossible in one popover).
- Spotlight/Siri/Shortcuts/widgets reach expands via App Intents.
- ~55% of the system (Core + server + boundary) is provably out of scope.

**Negative / costs**
- A net-new navigation shell and `AppState` UI-state decomposition (the only real
  build risk — see [risk-register.md](risk-register.md) R-02).
- Activation-policy logic must be retired cleanly (the most-patched area in repo
  history — R-01).
- The menu-bar glance must be actively defended from re-bloat forever (guardrail 1).

**Migration approach**
- **Dual-run behind a feature flag.** The window and the existing popover coexist
  until the window reaches parity. The popover/legacy windows are removed only in
  Epic 9, last.
- **Reversibility:** until Epic 9, reverting is flipping the flag. After Epic 9,
  reverting requires restoring the popover host — so Epic 9 is gated on a parity
  sign-off.

---

## Ratification

This ADR takes effect only when the decision owner completes **Gate 0**
(see [00-executive-recommendation.md §8](00-executive-recommendation.md#8-what-the-decision-owner-must-decide-at-gate-0)):
ratify, confirm session-workflow scope, approve the doctrine update, and approve
the macOS 26 floor. Until then: **Proposed**.
