# 03 — Repository Archaeology: How VaultPeek Became a Menu-Bar App, and Why That's Now in Tension

**Purpose.** Reconstruct the architectural history of VaultPeek (formerly PlaidBar) to answer three questions for the proposed pivot from "menu-bar popover-primary" to "full native macOS 26 window app":

1. **Why** was the menu-bar / popover architecture originally chosen?
2. Which assumptions behind that choice are now **invalid**?
3. Which past decisions should be **preserved** through any migration?

Scope: read-only reconstruction from git history (859 commits, 2026-03-18 → 2026-06-19), the decision-trail docs, and the shipped source tree. All evidence is cited by commit SHA, PR number, AND-issue, or doc path. No real Plaid data appears here.

---

## Executive summary / timeline

VaultPeek shipped as a menu-bar app on day one and never had an explicit "menu-bar vs window" decision — the menu bar *was* the product thesis ("RepoBar/CodexBar for personal finance"). Over 15 months the product hardened that thesis into a written constitution (`docs/v1.0-roadmap.md` §"Menu Bar First"), then — under real Apple-HIG UX review — quietly grew a series of detached `NSWindow` surfaces that the same constitution classifies as "treat with skepticism." Two distinct things people call "the macOS 26 migration" happened: a **platform** migration (Liquid Glass, App Intents, widgets — AND-508–515, merged 2026-06-18) that fully landed, and a **product-model** migration (popover → window) that was *deliberately declined* in the same window and only ever crept in feature-by-feature. That gap is the heart of this archaeology.

| Date | Milestone | Evidence |
|------|-----------|----------|
| **2026-03-18** | Initial MVP: three-target SwiftPM package; `PlaidBar` is a `MenuBarExtra(.window)` app with `LSUIElement=true`; `PlaidBarServer` (Hummingbird) owns secrets; `PlaidBarCore` shared. Tab-based UI (`AccountsView`/`TransactionsView`/`SpendingView`/`CreditView`). | `546fe43`; original `ARCHITECTURE.md` |
| **2026-05-27** | RepoBar-style redesign merged (PR #30): "open dashboard popover by default" — pivot from tab-first to glanceable dashboard-first popover. | `d080fd0` |
| **2026-06** | Tab tree removed → single drill-in model (AND-312). | `99ca54e` (#272) |
| **2026-06-12/13** | Three-column popover contract authored (AND-368) and shipped (AND-367/369–376): permanent Wealth Summary rail + center dashboard + right inspector. | `8a94948` (#310), `b2961d9` (#315), `docs/three-column-popover-contract.md` |
| **2026-06-13** | First detached desktop window lands as a *floating utility `NSPanel`* (PR #351), bundled with the Hosted Link fix. | `b5be256` |
| **2026-06-13** | UX audit against HIG/WWDC finds the panel is a non-native "utility HUD"; **owner constraint recorded: "keep the menu-bar popover as the primary, default surface … no architecture pivot."** | `docs/ux-audit-2026-06-13.md` |
| **2026-06-14** | **AND-384 GUI pass (PR #357):** the detached panel is rebuilt as a real managed `NSWindow` with behind-window translucency; "3-columns-always"; `.accessory→.regular` activation on show. Popover stays primary; window is "on demand." | `c276291` |
| **2026-06-14** | MVP cutline ratified: AND-384 (detachable window) and AND-385 (widget) classified **Post-MVP / Native Expansion**, "test against menu-bar-first." | `docs/mvp-launch-decision-log.md` |
| **2026-06-18** | **macOS 26 platform migration (Epics A–G, AND-508–515)** merged via stacked PRs #514–520: macOS 26 deployment floor, drop macOS 15 fallbacks, Liquid Glass unconditional, App Group + Widget + Control Center + App Intents, Dynamic Type, SF Symbols 7 audit. | `f41f7f4`, `cf7e5a2`, `d672e0b`, `fda1427`, `ef49795`, merges `13a3e5e`…`63d6306` |
| **2026-06-19** | **Two more detached `NSWindow`s** ship: Category Dashboard window (AND-539, #544) and multi-select Review Table window (AND-532/555/556, #552), both explicitly "reusing the proven AND-384 managed-NSWindow pattern." | `ff1bfa8`, `85d6c42` |
| **2026-06-19** | Latest: animated shared-element reflow on the dashboard (AND-577, #571) — still polishing the popover. | `2119292` |

**The arc in one line:** a menu-bar utility, by thesis, grew a constitution forbidding "large canvas / persistent workspace" surfaces — then shipped three of them anyway, each justified individually, while the platform underneath fully moved to macOS 26. The product-model never formally caught up to what the code now does.

---

## 1. WHY the menu-bar architecture was chosen

The menu-bar form factor was **never debated — it was the founding premise.** The very first commit message is "*initial PlaidBar MVP — macOS menu bar app for Plaid banking data*" (`546fe43`), and the original README frames the entire product as filling the gap left by the defunct *Balance* menu-bar app:

> "PlaidBar is an open-source macOS menu bar app … display bank account balances … all from your status bar. **No cloud. No telemetry. All data stays local.**"
> "**Glanceable** — Net balance visible right in the menu bar" (README @ `546fe43`)

The product north star codifies this as identity, not implementation detail:

> "Build VaultPeek … into a local-first macOS menu bar dashboard for Plaid data: **RepoBar/CodexBar for personal finance.** The app should make the user's financial state glanceable without becoming a full budgeting product. **One click should answer** [posture / did it sync / what needs attention / has spending changed]." (`GOAL.md`)

By the time the long-term brief was written, "Menu Bar First" was an explicit, load-bearing principle with a stated *anti-goal*:

> "VaultPeek should remain a **menu bar utility, not a full desktop finance app that happens to have a menu bar icon.** … **Any feature that needs a large canvas, long workflow, or persistent workspace should be treated with skepticism** unless it strengthens the menu bar experience." (`docs/v1.0-roadmap.md` §"Menu Bar First")

Three concrete forces locked it in:

- **Glance value proposition.** The menu-bar label *is* the product's headline — "net cash, total cash, credit utilization, recent spend, or icon-only … The glance succeeds when the user can decide whether to open the popover" (`docs/v1.0-roadmap.md` §"The Glance"). A glance only exists if the app lives in the menu bar.
- **Density / RepoBar lineage.** The CLAUDE.md north star is "RepoBar/CodexBar-style density: high-signal numbers one click away in a native macOS popover." The popover form forces compactness — "compact rows over large decorative cards" (`docs/v1.0-roadmap.md` §"Dense, Native, Readable").
- **Background/resident posture.** `LSUIElement=true`, `.accessory` activation policy, and a companion server that "can restart independently of the UI" presume a quiet resident menu-bar agent, not a focused document app. Energy-aware background refresh (AND-568, `9462d0f`) is explicitly "for the **resident menu-bar app**."

**Note the asymmetry:** the *two-process security boundary* got a written "Why not a single process?" rationale in the first ARCHITECTURE.md. The *menu-bar form factor never did* — it was assumed. There is no architecture-decision record arguing menu-bar over window; the burden of proof was only ever placed on *deviating* from it.

---

## 2. The AND-384 decision in full context

AND-384 ("Detachable pinnable window") is where the popover-vs-window tension becomes explicit and documented, and it resolves in a way that is internally contradictory.

**What was decided (2026-06-13, owner Felipe):** Faced with a Principal/Staff UX audit of the demo, the owner set a hard constraint, recorded verbatim:

> "**User constraint (decided): keep the menu-bar popover as the primary, default surface** ('polish the popover only' + 'quick popover, window on demand'). The free-drag/resize requirement is therefore delivered by **fixing the existing on-demand detached window into a real native window, not by a desktop-first rewrite. No new SwiftUI `Window` scene; no architecture pivot.**" (`docs/ux-audit-2026-06-13.md` §intro)

This is corroborated in user memory ("PlaidBar 2026-06-14 AND-384 GUI pass — user chose popover-primary 'polish only' (NOT desktop-first/Window scene)").

**What actually shipped (2026-06-14, PR #357, `c276291`):** A *real, managed* `NSWindow` — not a HUD:

- `NSPanel`→`NSWindow`, `[.titled,.closable,.miniaturizable,.resizable]`, `level=.normal`, default (Managed) collection behavior → "drags, resizes, minimizes, tiles, and joins Mission Control / Stage Manager / Spaces."
- Non-opaque window + clear background + behind-window `NSVisualEffectView` for true translucency.
- **The app elevates `.accessory → .regular` on show** (Dock + Cmd-Tab presence) and restores `.accessory` on re-dock.
- "Three columns always"; "Open in Window" added to the status-item menu; `--detach` launch flag for QA.

So the build delivered a window that behaves like a primary application window — Dock icon, Cmd-Tab, full window management — while the *decision* insisted the popover stays primary and "no architecture pivot." The reconciliation was a follow-up "Keep on top" toggle (added in the same PR) that re-introduces the floating-glance behavior *as opt-in*, so the default is a managed window but the original AND-384 acceptance criteria (floating glance panel) survive behind a preference.

**How the cutline classified it (2026-06-14):** Despite the working detached window already in `main`, the MVP decision log lists AND-384 as **Post-MVP / "Native Expansion" / Backlog**, with the rationale:

> "A persistent detached window is exactly the kind of 'large canvas / persistent workspace' surface the product brief says to treat with skepticism unless it strengthens the menu-bar experience. It is a deliberate post-MVP exploration, not a launch requirement, and it needs its own data-boundary and menu-bar-first review before it earns a place." (`docs/mvp-launch-decision-log.md` §"Native Expansion")

**The contradiction, precisely stated:** the working code (a real activating `NSWindow`, shipped) and the governing doc (AND-384 is unproven backlog "treated with skepticism") describe two different products. The window exists, is wired into the menu, and was reused twice more — but the constitution still treats windowing as a hypothesis. A pivot to window-primary is therefore not a green-field move; it is **ratifying, formalizing, and de-risking something that already partially shipped under an explicitly contrary decision.**

---

## 3. What the "macOS 26 migration" actually did — platform vs product model

There are two different migrations conflated under one name. Distinguishing them is essential.

### What the macOS 26 migration (AND-508–515, Epics A–G) DID — platform adoption

Merged 2026-06-18 via stacked PRs #514–520. It moved the *technology baseline* to macOS 26 (Tahoe), fully and unconditionally:

- **Epic A (AND-509, `cf7e5a2`):** committed to the macOS 26 deployment floor — `MACOSX_DEPLOYMENT_TARGET 15.0→26.0`, CI runner `macos-15→macos-26`, Xcode 26; docs reframed Liquid Glass as *baseline*, not progressive enhancement.
- **Epic B (AND-510, `d672e0b`):** dropped all macOS 15 fallbacks; Liquid Glass and ControlWidget paths made unconditional (net-negative LOC).
- **Epic C (AND-511, `fda1427`):** adopted `.glassEffect`, `.buttonStyle(.glass)`, `glassEffectID` morphs, `GlassEffectContainer`, scroll-edge effects across popover/panels/controls.
- **Epic D (AND-512):** App Group snapshot store + Finance App Intents bundle (Siri/Spotlight/Shortcuts).
- **Epic E (AND-513):** Control Center controls + App-Group-backed widgets.
- **Epic F (AND-514, `ef49795`):** SF Symbols 7 audit (kept the custom Vault glyph); "menu-bar/window scene modernization" — but the spike (F2) found "SwiftUI 7 still exposes **no declarative frame-origin/placement hook for a `MenuBarExtra(.window)` host window**," so the leading-edge pin *kept* its `NSViewRepresentable + setFrameOrigin` bridge.
- **Epic G (AND-515):** macOS 26 QA matrix, Dynamic Type (`@ScaledMetric` hero balances), architecture notes.

### What it did NOT do — change the product model

The platform migration **preserved the menu-bar product model wholesale.** Critically:

- The new glance surfaces (widget, Control Center, App Intents) are explicitly *out-of-process display-only* satellites of a menu-bar app, reading a redacted `GlanceSnapshot` through an App Group — "The extension cannot reach the app's `AppState` or the companion server" (`docs/architecture.md` §"Glance Surfaces"). These *reinforce* the resident-glance model rather than replace it with a window.
- Epic F's scene-modernization spike confirmed the app is still a `MenuBarExtra(.window)` host, with its anchoring done by an AppKit bridge — not a SwiftUI `Window` scene.
- The macOS 26 floor doc and the architecture vision still describe `PlaidBar` as the "native SwiftUI **menu bar** app" (`docs/v1.0-roadmap.md` §"Architecture Vision").

**Bottom line for the pivot:** the *hard, framework-level part* of "macOS 26" — Liquid Glass, App Intents, widgets, Dynamic Type, the deployment floor — is **already done and shipping**. A window-primary pivot therefore inherits a modern macOS 26 foundation; it does **not** need to redo platform adoption. What it must do is the part the 2026-06-18 migration deliberately left untouched: change the **product model** from "resident glance + on-demand window" to "window-primary," which means resolving the activation-policy posture, the `MenuBarExtra` scene, and the constitution — none of which the platform migration addressed.

---

## 4. The popover-vs-window tension over time (every time windows crept in)

Windowing did not arrive once; it accreted in four distinct, individually-justified steps, each one expanding the window surface while the governing docs held the menu-bar line.

| When | What crept in | How it was justified | Tension with the constitution |
|------|---------------|----------------------|-------------------------------|
| **2026-06-13** (`b5be256`, #351) | First "detachable desktop window" — a floating utility `NSPanel`. Shipped *bundled* with a Hosted Link 500 fix and "consumer-prod foundation," not as a standalone windowing decision. | Buried in a multi-purpose PR; AND-407 hardening later flagged it as "partial." | A persistent window appears with no menu-bar-first review; arrived as a side effect. |
| **2026-06-14** (`c276291`, #357) | The panel becomes a **real managed, activating `NSWindow`** with `.accessory→.regular` elevation, 3-columns-always, "Open in Window" menu item. | UX audit + explicit "popover stays primary, window on demand, no architecture pivot." | A primary-class application window now exists, but the decision says the popover is primary and there's "no pivot." `.regular` activation gives the app a Dock icon — the most un-menu-bar-utility thing possible — yet only on demand. |
| **2026-06-14** | AND-384 + AND-385 codified as **Post-MVP "Native Expansion," "treat with skepticism."** | Cutline discipline: keep the MVP small; windowing is unproven. | The doc treats as hypothetical-backlog a window that already shipped to `main` and is in the menu. |
| **2026-06-19** (`ff1bfa8` #544; `85d6c42` #552) | **Two more detached `NSWindow`s**: Category Dashboard (donut + sortable SPENT/BUDGET/LEFT Table) and a multi-select Review Table (power-review with bulk recategorize). Both "reuse the proven AND-384 managed-NSWindow + behind-window NSVisualEffectView pattern" and the "shared refcounted `AppActivationPolicyCoordinator`." | Each tied to a Copilot-parity feature spec (category dashboard, review inbox), Option A "no recompute." | These are squarely "large canvas / long workflow / persistent workspace" surfaces — a sortable financial table and a multi-select bulk-edit workflow — exactly what "Menu Bar First" says to resist. The product is *already* a multi-window app in practice. |

**The pattern:** the menu-bar constitution was never overruled — it was *outgrown by accretion.* Each window was a local, defensible decision ("just polish the existing detach," "just surface the dashboard that already exists," "just a power-review table"). Summed, they make VaultPeek a three-window-plus-popover-plus-widgets application whose own roadmap still calls a detached window an unproven Post-MVP risk. The shared infrastructure (`DetachedDashboardWindowController`, `CategoryDashboardWindowController`, `ReviewTableWindowController`, `AppActivationPolicyCoordinator`, behind-window `NSVisualEffectView`) is now mature and reused — the window pattern is, de facto, a core part of the architecture.

---

## 5. ASSUMPTIONS NOW INVALID

| # | Original assumption | Why it no longer holds | Evidence |
|---|---------------------|------------------------|----------|
| **A1** | **A single glanceable popover answers the user's questions; windows are at most an on-demand convenience.** | The product has shipped *three* detached windows for content the popover can't hold — a 3-column workspace, a sortable category Table, and a multi-select bulk-review Table. The "large canvas" the constitution forbade is now load-bearing for real features. | `c276291`, `ff1bfa8` (#544), `85d6c42` (#552); contrast `docs/v1.0-roadmap.md` §"Menu Bar First" |
| **A2** | **AND-384 (detachable window) is unproven, skepticism-warranted backlog needing a menu-bar-first review before it "earns a place."** | It shipped, was hardened (AND-420, `c18cc66`), and was reused as the *foundation* for two later windows. The pattern is proven and depended-upon, not hypothetical. | `docs/mvp-launch-decision-log.md` §"Native Expansion" vs `c276291`, `ff1bfa8`, `85d6c42` |
| **A3** | **The app is a quiet `.accessory` resident with no Dock presence.** | Every detached window elevates to `.regular` (Dock icon, Cmd-Tab) via a shared refcounted coordinator. The app *already* toggles into a normal app posture routinely; window-primary just makes that the default instead of transient. | `c276291` (`.accessory→.regular`), `85d6c42` (`AppActivationPolicyCoordinator`), regression-fix history `4f90b29`, `2a6e81d` |
| **A4** | **`MenuBarExtra(.window)` is the right host; its width/anchoring quirks are worth living with.** | The popover's quirks generated repeated fixes — width on the active screen (`526d895`), three-column geometry on narrow displays (`5020832`), leading-edge pin via an AppKit bridge because SwiftUI offers no hook (`ef49795` F2). A real resizable `NSWindow`/`Window` scene removes this entire class of fragility. | `526d895`, `5020832`, `ef49795`, `docs/three-column-popover-contract.md` §4–5 |
| **A5** | **Liquid Glass / macOS 26 is a "progressive enhancement, not a minimum."** | The macOS 26 migration made it the **unconditional baseline** and removed all fallbacks; the deployment floor is macOS 26. Any pivot can assume modern APIs (incl. SwiftUI `Window`, `windowResizability`, `.glassEffect`) are simply available. | `cf7e5a2`, `d672e0b`, `fda1427` |
| **A6** | **The three-column popover width (~1122pt) is a reasonable popover size.** | A 1122pt popover is window-sized; the contract itself needs a mandatory multi-tier screen-constrained fallback (cap, flex, overlay) to fit displays. The audit's own dial-back suggestion was "apply always-3-columns only in the resizable detached window." A real window resolves the width problem natively. | `docs/three-column-popover-contract.md` §3, §5; `docs/ux-audit-2026-06-13.md` §5 |
| **A7** | **Translucency can be achieved within the menu-bar popover host.** | Real behind-window read-through required dropping the `MenuBarExtra` host entirely for a non-opaque `NSWindow` + `NSVisualEffectView`; the C4 spike confirmed the behind-window effect only reads correctly on the detached window. (User memory: MenuBarExtra glass is effectively impossible via host-window surgery.) | `c276291` Wave 2, `fda1427` C4 spike; user memory "VaultPeek-menubarextra-glass-impossible" |

**Single most important now-invalid assumption: A1.** The premise that one glanceable popover (plus an optional convenience window) is sufficient is empirically false in the shipped product — three windows now carry real, distinct workflows. The product is already multi-window; the pivot mostly admits in writing what the code already does.

---

## 6. DECISIONS TO PRESERVE through any migration

These are the load-bearing decisions a window-primary pivot must **not** disturb. Most are orthogonal to the form factor — they are about security, data boundaries, and code structure, not about where pixels are drawn.

| # | Decision | Why it must survive |
|---|----------|---------------------|
| **P1** | **Two-process security boundary** — `PlaidBar` (UI) talks only to `127.0.0.1` `PlaidBarServer` over HTTP; the server owns the Plaid `client_secret`/`access_token`; SQLite holds only `keychain:<item_id>` references. | This is the *one* architecture decision with a written "Why not a single process?" rationale (`546fe43` ARCHITECTURE.md): "Plaid's security model requires that `client_secret` and `access_token` never exist in client-side code." It is form-factor-independent and non-negotiable. A window app must still proxy through the local server. |
| **P2** | **Core-centric, `Sendable`, testable business logic in `PlaidBarCore`.** | Swift 6 strict-concurrency (`-strict-concurrency=complete -warnings-as-errors`) is the CI gate that "most often fails" (CLAUDE.md). Summaries, formatters, recurring detection, sync reduction, *and the new window models* (`CategoryDashboardTableModel`, `ReviewTableRow`/`ReviewTableSort`) already live in Core with TDD tests. Window views must keep delegating to Core, not embed logic. |
| **P3** | **Local-first, no hosted backend, no telemetry, no cloud.** | The North Star and the ratified 2026-06-14 MVP decision (defer all hosted/managed/monetization). Re-stated in every roadmap doc. A pivot changes the *window*, never the *data boundary*. |
| **P4** | **Single drill-in model; no tab tree (AND-312).** | The removed `AccountsView`/`TransactionsView`/`SpendingView`/`CreditView`/`StatusView` tab tree (`99ca54e`) was a deliberate simplification; the three-column contract explicitly forbids reintroducing it ("New detail belongs in the inspector, not a tab container," `docs/three-column-popover-contract.md` §2). A bigger window must not be an excuse to bring tabs back. |
| **P5** | **Recovery is a first-class surface; one width across states; settled-on-open.** | "Recovery Is A Primary Experience" (`docs/v1.0-roadmap.md`); the AND-384 fix made demo "open settled" by loading fixtures synchronously to kill the 480→801 jump (`c276291` Wave 1). Window mode must keep recovery states and avoid layout flashes. |
| **P6** | **Accessibility: never meaning by color alone; Reduced Motion; Dynamic Type; VoiceOver.** | Enforced across the three-column contract §6, `ACCESSIBILITY.md`, the Review Table ("category pressure rides on glyph + text, never color alone," `85d6c42`), and Dynamic Type hero balances (AND-515). These constraints are UI-surface-agnostic and must carry over. |
| **P7** | **Privacy Mask / App Lock + redacted glance snapshots.** | A second trust boundary (App Group) with write-time *and* read-time redaction (`docs/architecture.md`; AND-517 `b275d9e`; App Lock wiring `217ccc9`). Each window already participates (the Review Table "withholds merchant + amount under Privacy Mask"). Window-primary mode must preserve the masking contract on every surface. |
| **P8** | **Sandbox/synthetic data only in tests, screenshots, examples; conservative distribution claims.** | CLAUDE.md hard rule; release-checklist discipline. Independent of form factor. |

---

## 7. Migration risks surfaced by history

History shows exactly which areas are fragile, because they broke and were patched repeatedly.

- **R1 — Activation-policy thrash (`.accessory` ↔ `.regular`).** The single most repeatedly-fixed area: "restore activation policy after opening settings" (`4f90b29`, #230), "clarify account drill-in activation path" (`6e8a26f`), AND-385 "activation refresh" follow-ups (`2a6e81d`), and the shared *refcounted* `AppActivationPolicyCoordinator` introduced precisely because "opening both [a window and Settings] at once can … strand the menu-bar app in `.regular` / the Dock" (`c276291` P2). **A window-primary app makes `.regular` the default** — which actually *removes* much of this hazard, but the migration must delete the now-obsolete refcounting carefully and not leave half-toggled policy paths. This is the area most likely to regress mid-migration.

- **R2 — `MenuBarExtra` anchoring / width plumbing.** Popover width and the three-column geometry needed multiple fixes: active-screen width (`526d895`), narrow-display three-column geometry + persisted-selection open (`5020832`), and a leading-edge pin that *must* use an `NSViewRepresentable + setFrameOrigin` bridge because "SwiftUI 7 still exposes no declarative frame-origin hook for a `MenuBarExtra(.window)` host window" (`ef49795` F2). Migrating to a SwiftUI `Window` scene would delete this fragile bridge — a *benefit* — but the unit-tested `PopoverGeometry.clampedLeadingX` anchoring math and the three-column fallback tiers (`docs/three-column-popover-contract.md` §5) are tied to the popover host; they must be re-homed or retired deliberately, not orphaned.

- **R3 — Translucency host surgery.** True translucency required abandoning the popover host for a non-opaque `NSWindow` + behind-window `NSVisualEffectView`; the C4 spike found SwiftUI glass did *not* read the desktop through on the transparent window and the AppKit backdrop was kept (`fda1427` C4). User memory records that behind-window translucency "can't be done via `MenuBarExtra(.window)` host-window surgery." **Do not re-attempt the failed popover-glass approaches**; the window path is the proven one, and a `Window` scene should reuse the behind-window vibrancy pattern, not SwiftUI-native glass alone, for desktop read-through.

- **R4 — Appearance cascade.** Light/Dark was historically fragile: "three overlapping scheme sources," `NSApp.appearance` applied post-paint, a detached panel frozen at creation (`docs/ux-audit-2026-06-13.md` §1; fix `c276291` Wave 1). The lesson: **`NSApp.appearance` is the single authoritative API**, applied before first paint, with separately-hosted windows leaving `appearance==nil` to inherit. A new top-level window must follow this exact pattern or the flash/freeze bugs return. The P2 debt of "redundant `environment(\.colorScheme)` overrides" was explicitly deferred and is still outstanding (`docs/ux-audit-2026-06-13.md` §4) — migrate that debt, don't inherit it blindly.

- **R5 — Windows bundled into unrelated PRs.** The first detached window arrived inside a Hosted-Link-fix PR (`b5be256`), and AND-407 had to do a "partial" post-merge hardening pass to catch up (`docs/qa/and407-post-merge-hardening.md` §5). A formal window-primary pivot should be its *own* tracked change with its own QA matrix, not smuggled alongside feature work — the history shows windowing slips through review when bundled.

- **R6 — Doc/code divergence as a process risk.** The clearest systemic risk: working code (a shipped activating window, reused twice) and the governing constitution (AND-384 is unproven backlog "to treat with skepticism") have been out of sync for the entire windowing era. If the pivot is approved, the **decision log, v1.0-roadmap §"Menu Bar First," post-mvp-roadmap, and CLAUDE.md must be updated in lockstep** — otherwise the next agent will "correct" the window work back toward popover-primary citing the still-authoritative docs. (User memory repeatedly notes agents acting on stale repo state.)

- **R7 — `MenuBarExtra` is still a hard product promise.** The menu-bar glance, the configurable menu-bar label modes, the live signal-meter glyph (AND-485, `9cd1201`), and the energy-aware *resident* refresh (AND-568, `9462d0f`) all assume the app lives in the menu bar. A pivot to window-*primary* must decide whether the menu-bar presence **stays as a secondary glance** (most consistent with history and the widget/Control Center investment) or is dropped (high-risk: discards the founding value proposition and the just-shipped glance-surface ecosystem). History strongly favors *keeping* the menu-bar glance and *adding* a primary window — i.e. a both/and, not an either/or.

---

## 8. Key lessons learned

1. **The form factor was a thesis, not a decision.** Menu-bar was never argued for against alternatives; it was the premise. That means the bar for pivoting is *lower* than it looks — there is no rigorous "why menu-bar beats window" record to overturn, only an accreted constitution defending an assumption.
2. **The product already pivoted in code; only the docs didn't.** Three detached windows, a refcounted activation coordinator, and a proven NSWindow+vibrancy pattern make VaultPeek a multi-window app today. The pivot is largely a *formalization*, which de-risks it substantially.
3. **The two migrations are separable, and the hard one is done.** macOS 26 *platform* adoption (Liquid Glass, App Intents, widgets, Dynamic Type, deployment floor) fully landed 2026-06-18. The *product-model* migration (popover→window) is the remaining work and is mostly architectural posture (activation policy, scene type, constitution), not framework adoption.
4. **The fragile zones are known and narrow:** activation policy, `MenuBarExtra` anchoring/width, translucency host, and appearance cascade. A window-primary model *removes or simplifies* most of them (R1, R2) rather than adding new ones — the popover host was the source of the fragility, not the cure.
5. **Don't bundle windowing into feature PRs** (R5) and **update the governing docs in lockstep** (R6); both are repeated, history-proven failure modes.
6. **Preserve the boundaries, change the surface.** Everything that makes VaultPeek trustworthy — two-process security, Core-centric `Sendable` logic, local-first, no telemetry, single drill-in, recovery-first, accessibility, privacy mask — is orthogonal to popover-vs-window. A pivot is safe precisely to the extent it touches only the presentation surface and leaves §6 intact.
