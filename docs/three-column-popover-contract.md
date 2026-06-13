# Three-Column Popover Design Contract

Status: **Active contract** (AND-368). Governs the three-column popover work in
AND-367, AND-369, AND-370, AND-371, AND-372, AND-373, AND-374, AND-376 and the
visual QA in AND-375. This document is the single source of truth for the target
anatomy, geometry, anchoring, fallback, and accessibility behavior of the
VaultPeek main popover. Where this contract and `DESIGN.md` disagree about the
popover, this contract wins until `DESIGN.md` is updated to match (AND-367).

> No real account identifiers, balances, institution names, Plaid payloads,
> tokens, local SQLite data, logs, or private screenshots appear in this
> document or in any artifact produced under it. All examples use demo fixtures.

## 1. Why this changes

Today the main popover is a **swap** layout (shipped in AND-337): a single
left panel that toggles between `WealthSummaryFlyout` (when nothing is selected)
and `AccountDetailFlyout` (when an account row is selected), with the dashboard
to its right. Selecting an account therefore **hides** the portfolio context the
left panel was showing.

The target is a **three-column** layout where portfolio context is *permanent*:

```
┌──────────────────┬───────────────────────────┬────────────────────┐
│  Left            │  Center                    │  Right             │
│  Wealth Summary  │  Dashboard                 │  Account Inspector │
│  (always)        │  (always)                  │  (when selected)   │
│                  │                            │                    │
│  net worth,      │  change receipt, attention,│  selected account  │
│  metric grid,    │  heatmap, filters,         │  detail: status,   │
│  balance mix,    │  account rows, summary     │  balances, changes,│
│  cashflow,       │  context, footer status    │  review, top cats, │
│  credit, sync    │                            │  recent, actions   │
└──────────────────┴───────────────────────────┴────────────────────┘
   320pt              480pt                        320pt (additive)
```

The Wealth Summary rail stays put while you inspect an account; the inspector
opens to the **right** of the dashboard, not in place of the left rail.

## 2. Anatomy and ownership

| Column | View | Visibility | Owns |
|--------|------|-----------|------|
| **Left — Wealth Summary** | `WealthSummaryFlyout` | Always (post-setup) | The one net-worth hero number, portfolio metric grid, balance mix, cashflow, credit utilization summary, attention rollup, sync health pill |
| **Center — Dashboard** | dashboard column in `MainPopover` | Always (post-setup) | Latest local changes (change receipt), attention/recovery, 365-day heatmap, segmented finance filters, account rows, balance/summary context, footer status line |
| **Right — Account Inspector** | `AccountDetailFlyout`, adapted | Only when an account row is selected | The selected account's detail: connection status, balances, 30-day changes, to-review, top categories, recent activity, account actions |

**Hard rules:**

1. **`AccountDetailFlyout` no longer replaces `WealthSummaryFlyout`.** They are
   different columns that can be on screen at the same time. The left rail is
   never swapped out to show account detail.
2. **The net-worth hero number lives in exactly one place: the left Wealth
   Summary.** The center dashboard does not render a second net-worth hero
   (AND-376). One hero per surface, as in `DESIGN.md` § Typography.
3. **Single drill-in only — preserve AND-312.** The account inspector is the
   *only* detail surface. Do not reintroduce the removed tab tree
   (`AccountsView` / `TransactionsView` / `SpendingView` / `CreditView` /
   `StatusView`). New detail belongs in the inspector, not a tab container.
4. **Setup renders alone.** First-run / setup-recovery renders at dashboard
   width with no left or right side panels.

## 3. Geometry contract

Three layout states, three widths. Column widths are tokens, not magic numbers;
implementations must read them from a single `Layout` source.

| State | Condition | Columns | Width (pt) |
|-------|-----------|---------|-----------|
| **Setup** | `!isSetupComplete && !recoveryDashboard` | Center only | `dashboard` = 480 |
| **Two-column** | post-setup, no account selected | Left + Center | `summaryRail` + 1 + `dashboard` = 320 + 1 + 480 = **801** |
| **Three-column** | post-setup, an account selected | Left + Center + Right | `summaryRail` + 1 + `dashboard` + 1 + `inspector` = 320 + 1 + 480 + 1 + 320 = **1122** (ideal; clamped — see §5) |

Notes:

- `summaryRail = 320`, `dashboard = 480`, `inspector = 320`, dividers = 1pt.
- The two-column width (801) equals today's expanded popover width, so the
  default (no-selection) state does **not** change size when this work lands.
- Heights stay screen-bounded: each side column caps its internal scroll to the
  same screen-bounded height the dashboard scroll column already uses, so tall
  content scrolls *inside* a column instead of growing the whole popover.

## 4. Anchoring contract (AND-370)

The menu-bar popover is anchored to its status item. The current implementation
pins the popover's **trailing edge** so the (single) left panel grows leftward.
The three-column model needs a different anchor because there is now growth on
the **right** (the inspector) on top of a permanent left rail.

Behavioral contract — the implementation may use any NSWindow/NSPopover
mechanism that satisfies all of these without fragile run-loop timing:

1. **No horizontal jump of the Wealth Summary** when the right inspector opens
   or closes. The left + center block is the stable anchor; the inspector is
   additive on the trailing side.
2. **Persisted selection opens directly into three-column geometry** — if an
   account was selected when the popover last closed, reopening lands in the
   correct three-column layout without a visible resize animation from
   two-column to three-column.
3. **Stay within the visible screen** where practical (see §5 for what happens
   when the ideal width does not fit).
4. **Close/deselect returns to two-column geometry** without losing the natural
   menu-bar anchor — the popover does not drift away from its status item.
5. **MainActor / strict-concurrency clean** across the resize path; any
   `NSViewRepresentable` window code is correctly isolated.

## 5. Screen-constrained fallback contract (AND-374)

The ideal three-column width (1122pt) does not fit on every display, especially
near a screen edge or on narrow laptops. The fallback is **mandatory**, not
optional, and is layered from least to most disruptive:

| Tier | Trigger | Behavior |
|------|---------|----------|
| **0 — Ideal** | `1122 + 2·margin ≤ visibleFrame.width` | Full three columns side by side. |
| **1 — Cap + flexible center** *(implemented, AND-405)* | 1122 does not fit, but the rail + a `minDashboardWidth` center + the inspector do (≈ ≥ 1002pt usable, covering scaled displays down to ~1024pt) | `PopoverGeometry.fittedWidth` caps the popover to `visibleFrame.width − 2·margin`; the rail and inspector keep their fixed 320pt and the **center dashboard flexes** (down to `minDashboardWidth` = 340pt) and scrolls internally, so the trailing inspector and its ✕/recovery controls stay on-screen. **The left Wealth Summary stays visible.** |
| **2 — Overlay inspector (last resort)** | even a `minDashboardWidth` center cannot fit alongside the rail + inspector (extreme accessibility zoom, ≲ 1002pt usable) | The inspector overlays the trailing region of the center column as a layer above it; the left Wealth Summary remains visible. This last-resort path **must** be documented in code and be fully keyboard- and VoiceOver-reachable. *(Not yet implemented; the residual case is documented here and in `docs/qa-matrix.md`.)* |

Constraints that hold in every tier:

- The **left Wealth Summary remains visible** in the primary fallback path
  (Tiers 0–1).
- Internal scrolling must **not** clip close buttons, row highlights, account
  balances, utilization text, or recovery actions.
- `margin` accounts for the menu bar, footer chrome, and a Dock-safe inset; it
  is a named constant, not an inline literal.
- Any tier that hides or overlays content documents it and keeps that content
  reachable by keyboard and VoiceOver.

## 6. Selection, keyboard, focus, accessibility contract (AND-373)

Selection model:

- Clicking an account row **selects** it: the row shows the native accent
  selection highlight **and** the right inspector opens for that account.
- The selected-row highlight stays synchronized with the open inspector — they
  are two views of one selection state.
- Re-clicking the selected row, clicking the inspector's ✕, changing the filter,
  or pressing Esc **deselects**: the right inspector closes and the layout
  returns to two-column. Deselect closes **only** the right inspector and must
  not remount or flash the left Wealth Summary.

Keyboard:

- **Esc closes the right inspector first**, then (on a subsequent Esc, when no
  inspector is open) falls through to the system popover dismiss. A single Esc
  never both closes the inspector and dismisses the popover.
- Keyboard users can open and close the inspector without losing context.
- **Focus after close returns to the previously selected row**, so keyboard
  navigation continues from where the user was — not the top of the list, not a
  dismissed popover.

Accessibility (these are non-negotiable, per `ACCESSIBILITY.md`):

- **No meaning by color alone** anywhere in the three columns — selected state,
  finance risk, credit utilization, sync state, recovery/error, and chart/heatmap
  meaning each carry a text or icon cue in addition to any color.
- VoiceOver reports selected vs unselected row state and announces the
  right-inspector action clearly (e.g. an explicit "Shows account detail" hint
  rather than relying on the highlight).
- The inspector's close affordance has a text/VoiceOver label and is reachable in
  the focus order.
- Reduced Motion is respected: column insertion/removal uses opacity rather than
  slide/spring when `accessibilityReduceMotion` is on, gated through
  `MotionTokens.animation(_:reduceMotion:)`.

## 7. Center dashboard rebalance (AND-372, AND-376)

Because the left rail now permanently owns portfolio context, the center column
stops repeating it:

- **Remove the center net-worth hero** (the large `Net Worth $…` block in
  `DashboardHeader`) whenever the Wealth Summary rail is visible — which, in the
  three-column model, is always post-setup (AND-376). The center column begins
  with the latest-local-changes receipt.
- Trim or collapse other center content that merely restates the left rail
  (high-level summary cards, balance mix, local-insight chrome) **only where it
  adds no distinct value**; keep anything the left rail does not already show.
- The center column must still communicate, at all times: latest local changes,
  attention/recovery and error actions, the activity heatmap, the finance
  filters, the account rows, the selected-account state, and the footer status
  line.
- Removing center content must **not** remove any finance-risk, utilization,
  sync, error, or chart-meaning cue. Those either stay in the center or are
  already present in the left rail.
- Structure follows the existing `glassSurface` ranks; no cards-inside-cards.

## 8. Mapping to issues

| Issue | Scope under this contract |
|-------|---------------------------|
| **AND-367** | The epic. Deliver the three-column model end to end; update `DESIGN.md` and `docs/wealth-summary-visual-polish.md` to describe three-column (not swap/stacked). |
| **AND-369** | Refactor `MainPopover` shell into left summary / center dashboard / right inspector per §2–§3, including stable left-rail identity (no remount/flash). |
| **AND-371** | Adapt `AccountDetailFlyout` to read as a *trailing* inspector per §2 and §6; keep insight math/tests unchanged. |
| **AND-370** | Replace the trailing-edge anchor with the three-column anchor per §4. |
| **AND-373** | Implement selection / keyboard / focus / accessibility per §6. |
| **AND-374** | Implement the screen-constrained fallback per §5. |
| **AND-376** | Remove the duplicate center net-worth hero per §7. |
| **AND-372** | Rebalance the rest of the center column per §7. |
| **AND-375** | Visual QA + tests proving §2–§7 hold in two- and three-column states, light/dark, and a constrained-width case. |

## 9. Out of scope / preserved invariants

- No new network calls, no Plaid/credential surface changes — this is a layout
  and presentation contract only.
- Demo and BYO behavior unchanged; the popover renders from existing AppState.
- Local-first and privacy boundaries unchanged.
- The removed tab tree (AND-312) stays removed.
