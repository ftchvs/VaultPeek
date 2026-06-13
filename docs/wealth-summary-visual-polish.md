# Design Note: Always-Open Wealth Summary + Visual Polish

Status: planned (not implemented). Tracked in Linear under the PlaidBar project,
Andeslab team. This note is the durable, repo-side source of truth; Linear
tracks status.

## Why

Today the left panel (`AccountDetailFlyout`) only appears when an account is
selected — see the conditional in `Sources/PlaidBar/Views/MainPopover.swift:58`.
With nothing selected, the popover is dashboard-only, so there is no persistent,
high-signal view of the user's overall financial position. This work makes the
left panel always present, gives it a new **Wealth Summary** default surface,
adds user-controlled transparency, and raises overall visual craft — without
turning PlaidBar into a budgeting suite or breaking its local-first, accessible,
strict-concurrency constraints.

## The six pieces

Filed as six related Linear issues (separate, not an epic), sequenced so the
panel lands first and the visual set composes on top of it.

| Linear | Piece | Priority | Depends on |
|--------|-------|----------|------------|
| AND-337 | Always-open left panel + Wealth Summary surface | High | — |
| AND-338 | Transparency slider (Settings → Appearance) | Medium | composes with AND-337 |
| AND-339 | Motion & micro-interaction polish | Medium | AND-337 |
| AND-340 | Depth & glass layering | Medium | AND-337, AND-338 |
| AND-341 | Richer data viz (sparklines, net-worth hero, animated mix) | Medium | AND-337, AND-339 |
| AND-342 | Texture & accents (gradient/mesh, category accents) | Low | AND-337, AND-338 |

### AND-337 — Always-open left panel + Wealth Summary

Render the left column unconditionally in `MainPopover.body`
(`MainPopover.swift:57-78`): when an account is selected show the existing
`AccountDetailFlyout`; otherwise show a new `WealthSummaryFlyout`. The account
detail's close affordance deselects back to the summary rather than collapsing
the panel. Reuse `Layout.flyoutWidth = 320` and the existing
`PopoverTrailingEdgeAnchor` width math.

Wealth Summary sections (draft): net-worth hero + trend delta, balance mix
(cash / credit / savings / debt / loans), 30-day cashflow (spend vs income,
net), and a finance-health read (utilization, accounts needing attention, sync
staleness). All derivation lives in `PlaidBarCore` (Sendable, unit-tested);
views only render.

Layout decision: **swap** (summary ⇄ detail), not stacked. Whether "always
open" should later become user-toggleable is out of scope.

> **Superseded (AND-367, shipped):** the swap model was replaced by a
> **three-column** popover — a *permanent* Wealth Summary rail (left), the center
> dashboard, and the account inspector on the **right** — so inspecting an account
> no longer hides portfolio context. The Wealth Summary sections above still
> describe the rail's content; only the swap/placement decision is obsolete. See
> `DESIGN.md` (RepoBar-Style Finance Overview) and
> `docs/three-column-popover-contract.md`.

### AND-338 — Transparency slider

Popover transparency is hardcoded to `.ultraThinMaterial`
(`MainPopover.swift:82`). Add a continuous 0–100% slider in a new **Appearance**
section of `SettingsView`, backed by `@AppStorage`, with live preview. Drive the
popover background from the value; centralize default/bounds in `SurfaceTokens`
(`Theme/DesignTokens.swift`) rather than parallel magic numbers. Enforce a
legibility floor so text never drops below contrast thresholds at max
transparency.

### AND-339 — Motion & micro-interactions

Animated number transitions on hero/summary values, spring drill-in on the
summary ⇄ detail swap, hover/press feedback on rows/chips/buttons, and chart
draw-in for `Views/Charts/`. Everything routes through
`MotionTokens.animation(_:reduceMotion:)` and honors
`@Environment(\.accessibilityReduceMotion)`.

### AND-340 — Depth & glass

Elevation/shadow ladder so foreground cards lift off the background; restrained
gradient/glow accent on the net-worth hero; tighten the `SurfaceTokens`
fill/stroke opacity ladder into a coherent depth scale. Keep the macOS 15
material fallback and the macOS 26+ liquid-glass progressive enhancement
(`SurfaceTokens.liquidGlassAvailability`). Must scale gracefully across
transparency levels.

### AND-341 — Richer data viz

Per-account sparklines, a net-worth hero trend chart with gradient area fill,
an animated balance-mix bar, and gradient fills on existing charts. Series logic
in `PlaidBarCore`, unit-tested. **Open risk:** the net-worth trend needs a
historical series that may not exist yet — either derive it from cached
balances/transactions or treat the hero chart as blocked on a history source.

### AND-342 — Texture & accents

Optional low-contrast animated mesh/gradient background and consistent category
color accents (always paired with icon + label). Lowest priority — layer it on
once motion/depth/data-viz have settled.

## Non-negotiables (apply to every piece)

- **Strict concurrency**: `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` stays clean.
- **Logic in `PlaidBarCore`**, not views — Sendable, testable, reusable.
- **Never meaning by color alone** — every effect is decorative reinforcement,
  paired with text/icon; contrast preserved at all transparency levels
  (`ACCESSIBILITY.md`).
- **Reduce Motion** disables all motion and animated texture.
- Verifiable from demo fixtures (`swift run PlaidBar --demo`).
