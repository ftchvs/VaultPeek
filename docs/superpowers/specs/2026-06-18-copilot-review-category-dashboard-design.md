# Copilot-style Review Inbox + Category Dashboard — Delivery Design

**Date:** 2026-06-18 · **Product:** VaultPeek (PlaidBar) · **Reference:** [Copilot.money](https://www.copilot.money) transaction-review workflow + category dashboard
**Linear:** Project *VaultPeek* (`20069ff6-…`), team *Andeslab*. Epics **AND-518 … AND-524**, issues **AND-525 … AND-559**, all related to the completed epic [AND-398](https://linear.app/andeslab/issue/AND-398).
**Scope decision (ratified):** **Option A + v2 backlog stub** — ship the full v1 as display-only rollups over the existing taxonomy (no schema migration); file Option B (custom/nested categories, rollover, rebalance) as a clearly-deferred v2 epic.

---

## 1. Executive summary

VaultPeek already has the *hard parts built and tested*: a pure `TransactionReviewInbox.evaluate` engine (7 reason codes, pending→posted reconciliation, 28 tests), an on-device `NLMerchantCategorizer`, a `CategoryBudgetPlanner` (refund netting, status bands, 15 tests), a **server-persisted budget store with full CRUD** (`BudgetRoutes` + `BudgetStore` + `category_budgets` SQLite), and a live `ReviewInboxView` mounted as the popover right-inspector (`MainPopover.swift:414`). So Copilot parity is **wiring + surfacing + one correctness fix**, not engine work.

**The load-bearing bug:** user category overrides, `excludedFromBudgets`, and rules **do not flow into spend math** — `CategoryBudgetPlanner.netSpendByCategory` reads raw `transaction.category ?? .other` (`CategoryBudgetPlanner.swift:182-195`) and never consults `TransactionReviewMetadata`. Recategorizing in the inbox changes nothing downstream. Fixing this (Epic 1) is the foundation.

**The structural gaps vs Copilot:** no global category dashboard (only per-account slices + an income Sankey); a budget editor UI with **zero callers** (`AppState.setCategoryBudget`/`removeCategoryBudget` are dead — the live half of [AND-444](https://linear.app/andeslab/issue/AND-444)); no bulk "Mark N reviewed", date sections, menu-bar count badge; and demo mode zeroes review/budget state so nothing is demoable.

## 2. The category-model decision

`SpendingCategory` is a closed 16-case enum whose `rawValue` is a primary key in three stores (server `category_budgets` row id, `CategoryBudgetDTO.id`, app-local review/rules JSON), bound 1:1 to Plaid PFCv2 `primary`.

| Option | What ships | Cost | Verdict |
|---|---|---|---|
| **A** | Donut, status bars, **fixed** 2-level group tree, current-month single limits, exclude-from-budget — display-only rollups. No migration. | S–M | **✅ Chosen for v1** |
| **B** | Custom/renamed categories, user groups, per-month budgets, rollover, rebalance — needs `Category`/`Budget` tables + migrations + Plaid `detailed` mapping; breaks `switch` exhaustiveness. | L | ❌ Deferred → Epic 7 (AND-524) |
| C | Enum + nullable `userCategoryId` overlay | M–L | ❌ Two-source-of-truth |

The **one non-negotiable regardless of A/B**: make spend math override-aware (resolve `userCategory`/`isTransferOverride`/`excludedFromBudgets`/rules *before* aggregation) — a pure-function fix in PlaidBarCore.

## 3. Target experience (v1)

Two surfaces on the existing **popover-primary + detached-window** split (popover = Copilot's dashboard card; window = Copilot's full tab).

- **Review Inbox** ("triage to zero"): bulk "Mark N reviewed" + blast radius, date-group sections, colored icon+text category pill, inline rule prompt, menu-bar count badge; detached window gets a multi-select `Table`. Keyboard speed-review (`a/i/c/t/r/m`, arrows, ⌘Z) already ships — a native-macOS advantage, kept.
- **Category Dashboard** ("where money went vs. plan"): a new center-column card (donut + top groups) → detached full window (monthly-history `BarMark` + dashed `RuleMark` budget line + flat SPENT/BUDGET/LEFT `Table`). Built as Option-A rollups.

**Cut from v1 (YAGNI):** splits, rollover, rebalance, custom/renamed categories, per-month budgets, server-synced review, swipe gestures. All in Epic 7.

## 4. Architecture (Option A — additive, no migration)

- **New (PlaidBarCore):** `CategoryGroup` enum + `SpendingCategory.group`; `CategoryDashboardBuilder` (pure rollup, `asOf:`/`Calendar` injected, `Sendable`); a shared `EffectiveCategoryResolver` extracted from the inbox logic. **The resolver has two modes:** the inbox keeps its *display* mode (user override → rules → Plaid → on-device NL suggestion → uncategorized, `resolveCategory:380-404`); budget/dashboard **aggregation uses a persisted-only mode** (user override → rules → raw Plaid → `.other`) with **NL display suggestions excluded** — so an unreviewed NL-guessed category never moves budget/category totals, and recategorizing/approving in the inbox stays the *one* place downstream numbers change. The resolver must also carry review metadata stored under a charge's `pendingTransactionId` into its posted replacement (mirror `TransactionReview.swift:207-222`), not only `resolveCategory:380-404` — otherwise a category/transfer decision made while a charge is pending vanishes from totals when it re-posts under a new id.
- **Changed (the fix):** `CategoryBudgetPlanner.netSpendByCategory` gains optional `metadata`/`rules` params (default nil → existing tests pass); skips excluded/transfer rows; resolves the **persisted-only** effective category. `AppState.categoryBudgetPresentation:1251` passes live metadata/rules — **and the budget-presentation cache must be invalidated when `transactionReviewMetadata` or `transactionRules` change**, not only on `transactions`/`categoryBudgets` change (today `AppState.swift:69-82,144-145` clears only the *inbox* cache on review/rule edits), or an approve/recategorize/new-rule leaves the dashboard stale until an unrelated refresh — re-creating the very "review changes no number" symptom this epic fixes.
- **Unchanged:** `TransactionDTO`, `SpendingCategory` rawValues, `CategoryBudgetDTO` PK, server schema. **Zero migration.** Review state stays app-local JSON (local-first). No new server work — budget CRUD already exists.
- **Views:** `CategoryDashboardCard`, dashboard window, `BudgetEditorSheet`, `ReviewBulkActionBar`, `CategoryPill`, `CategoryStatusBar`, `CategoryTreeView`, `CategoryDonutChart`. Menu-bar badge via **custom `NSStatusItem`** (per the documented MenuBarExtra-glass constraint). Demo: add `DemoFixtures.demoBudgets()/demoReviewMetadata()/demoTransactionRules()`; stop zeroing in `loadDemoData:3471-3473`.

## 5. Epic / issue / sub-issue tree (as filed)

| Epic | Issues (AND-) |
|---|---|
| **AND-518** Override-aware spend math | **525** extract `EffectiveCategoryResolver` → **526** override-aware planner (sub **554** wire AppState) → **527** exports follow-up |
| **AND-519** Review Inbox parity | **528** bulk mark-reviewed · **529** date sections · **530** colored pill · **531** inline rule prompt · **532** detached `Table` (subs **555** context menu, **556** bulk recategorize) |
| **AND-520** Menu-bar count signal | **533** inbox badge · **534** `NSStatusItem` badge |
| **AND-521** Category Dashboard | **535** group map · **536** builder · **537** donut · **538** status bars + tree (subs **557** leaf bar, **558** group rollup, **559** recurring ghost) · **539** dashboard card + window |
| **AND-522** Budget editing | **540** `BudgetEditorSheet` · **541** set/edit affordances · **542** suggested budgets |
| **AND-523** Demo fixtures + QA | **543** fixtures · **544** demo tests · **545** screenshots + QA matrix |
| **AND-524** [DEFERRED v2] | **546** Option-B tables · **547** custom categories/groups · **548** per-month + rollover · **549** rebalance · **550** splits · **551** rules manager · **552** server-synced review · **553** confidence-sorted inbox |

Each issue carries testable acceptance criteria, technical requirements (files/types/endpoints), design + accessibility notes, size (S/M/L), and labels.

## 6. Dependencies & sequencing

```
Phase 0 (foundation):  AND-525 → AND-526 → AND-554 ;  AND-535 (parallel) ;  AND-543 (parallel)
Phase 1 (inbox, parallel): AND-528, 529, 530, 531, 532(+555/556), 533, 534
Phase 2 (dashboard):   AND-536 (needs 526+535) → 537, 538 → AND-539
Phase 3 (budget edit): AND-540 (needs 526) → 541 (needs 539+540), 542 (needs 540)
Phase 4 (QA):          AND-544 (needs 543+526) ; AND-545 (needs 539+540+528)
```

**Critical path:** AND-525 → 526 → 536 → 538 → 539 → 541. `blockedBy` links are wired in Linear.

## 7. Risks, edge cases, future

- **Risks:** scope creep into a budgeting suite (Option A hard-caps v1); override-awareness regression (additive nil-default params keep tests green); `BudgetStore.allBudgets` silently drops unmapped category rows (`BudgetStore.swift:25-28`) — v1 never changes rawValues, guarded; menu-bar badge / glass constraints (custom `NSStatusItem`, no glass-on-glass); macOS-26 API availability (`.sectionActions` gated by `#available`).
- **Edge cases:** pending→posted — raw de-dupe is *not* sufficient; aggregation must carry review metadata saved under `pendingTransactionId` into the posted row (see §4), or a pending-phase category/transfer decision disappears when the charge re-posts under a new id; transfers/credit-card payments (exclude via override); **NL-suggested category is display-only and excluded from aggregation** — NL-suggested spend stays under raw Plaid/`.other` in the rollup until the user approves it (approval persists it as `userCategory`, at which point it counts); over-at-leaf-but-under-at-group (independent status); multi-account aggregation vs account-filter; empty/first-run (suggestions only, no false "over"); refunds (signed-amount netting).
- **Future (Epic 7 / AND-524):** Option-B category tables, custom categories, rollover, rebalance, splits, rules manager, server-synced review, confidence-sorted inbox.

---

*Synthesized from a parallel discovery workflow (6 audit/research agents + synthesis) and a Linear backlog dedup pass. Every file:line citation verified against the worktree. The defining theme: VaultPeek already has the engines — this plan wires and polishes them, fixes the one correctness gap, adds the missing global category surface as display-only rollups, and deliberately stops short of the budgeting suite the launch cutline forbids.*
