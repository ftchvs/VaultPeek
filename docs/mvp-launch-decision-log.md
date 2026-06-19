# VaultPeek MVP Launch Decision Log & Cutline

**Linear:** [AND-387](https://linear.app/andeslab/issue/AND-387) (parent epic [AND-386](https://linear.app/andeslab/issue/AND-386)) · **Milestone:** MVP Launch · **Status:** In Progress · **Due:** 2026-06-16 · **Priority:** Urgent

## Purpose

This is the single source of truth for **what blocks the public VaultPeek MVP launch and what does not.** Every candidate currently on the board is classified as exactly one of: **MVP blocker**, **Beta nice-to-have**, **Post-MVP**, or **Dead/Superseded**. A reader should finish this document knowing precisely which issues gate launch — with no ambiguity — and why every deferral is safe.

This is a decision log, not a task tracker. When the board changes, update the classifications here first.

## 2026-06-19 — Gate 0 ratified: window-first hybrid (ADR-001)

Felipe ratified **[ADR-001](strategy/macos26-migration/ADR-001-window-first-architecture.md): VaultPeek Window-First Hybrid Architecture** at Gate 0 ([AND-578](https://linear.app/andeslab/issue/AND-578)).

- **ADR-001 Accepted.** A primary `Window` / `NavigationSplitView` workspace becomes the main experience; the `MenuBarExtra` glance is retained as a first-class **reduced read+route** surface.
- **Supersedes** the AND-384 "popover-primary, polish-only (no `Window` scene)" decision and the v1.0-roadmap "Menu Bar First" guardrail **to the extent they forbid a primary window**. Security, concurrency, and local-first decisions are **preserved unchanged**.
- **Session-workflow scope stays in-product** (the condition distinguishing "migrate" from "delete the drift"): review / budgeting / planning / reconciliation become first-class window destinations rather than being removed.
- **macOS 26 ("Tahoe") floor approved** and already reflected in `Package.swift` (`.macOS("26.0")`).
- **Execution:** Epics 1–10 (AND-579…618). Critical path `Gate 0 → Epic 1 → Epic 2 → Epic 3 → (Epics 4/5/6 parallel) → Epic 7 → Epic 9`; Epic 9 (menu-bar simplification) **ships last**, gated on window parity; Epics 1–8 dual-run behind a feature flag (window hidden / popover default until parity). See [`migration-roadmap.md`](strategy/macos26-migration/migration-roadmap.md).

## Current product truth

VaultPeek 1.0 **already shipped** under its former name, PlaidBar, as a privately-distributed, ad-hoc-signed drag-install DMG for licensed macOS users (`docs/v1.0-roadmap.md` §"Current Product Truth"; `docs/release.md` "Current Release: v1.0.0"). The product is real, stable, and in users' hands today.

**This cutline is therefore not about building a product — it is about making a private 1.0 safe to present publicly under the VaultPeek name.** The MVP launch is a *naming, positioning, QA-evidence, and supportability* event layered on a shipping product. That reframes the entire cutline:

- The **product surface is done enough** — heatmap-first popover, dense rows, recovery convergence, local-data controls, and demo/sandbox/production modes all ship today (`GOAL.md`, the autonomous-roadmap progress ledger).
- What is *not* done is the **public envelope**: a coherent VaultPeek-named identity (the repo is still called PlaidBar), a launch QA matrix, a public README/positioning pass, a support runbook, and a confirmed release-checklist run.
- Everything that would **expand** the product — monetization, managed bank linking, a hosted footprint, new providers, design-system upgrades, native widgets — is explicitly out of scope for this launch and, in several cases, **gated on a Felipe decision that no agent can make.**

North star, unchanged and load-bearing for every call below: *make a privacy-conscious Mac user feel in control of their finances without becoming a full budgeting suite* — local-first, no hosted backend, no telemetry, no cloud (`docs/v1.0-roadmap.md` §North Star; `GOAL.md`).

## How to read the classifications

| Classification | Meaning | Effect on launch |
|---|---|---|
| **MVP blocker** | Launch is unsafe or incoherent without it. | Must be Done before the public VaultPeek tag. |
| **Beta nice-to-have** | Strengthens the launch but the launch survives without it; ship in a closed/early window. | Does not gate the tag. |
| **Post-MVP** | Real, wanted work assigned to a named later milestone — not generic backlog. | Explicitly out of the launch. |
| **Dead/Superseded** | No longer planned, or already satisfied by existing work. | Closed/folded; not tracked as launch work. |

---

## Decision table

| Issue | Title | Classification | Milestone | State | Owner | Rationale |
|---|---|---|---|---|---|---|
| [AND-387](https://linear.app/andeslab/issue/AND-387) | MVP launch decision log & cutline | **MVP blocker** | MVP Launch | In Progress | Felipe (DRI) | This doc; gates the rest of the epic. → [§MVP Blockers](#mvp-blockers) |
| [AND-388](https://linear.app/andeslab/issue/AND-388) | Launch QA matrix (sandbox/dev/prod/offline/restart/upgrade) | **MVP blocker** | MVP Launch | Todo | Felipe (DRI) | Public claim needs verified evidence. → [§MVP Blockers](#mvp-blockers) |
| [AND-389](https://linear.app/andeslab/issue/AND-389) | Public launch surface (README/screenshots/changelog/support/positioning) | **MVP blocker** | MVP Launch | Todo | Felipe (DRI) | The launch *is* the public surface. → [§MVP Blockers](#mvp-blockers) |
| [AND-390](https://linear.app/andeslab/issue/AND-390) | Support & operations runbook | **MVP blocker** | MVP Launch | In Progress | Felipe (DRI) | Public users need a support path. → [§MVP Blockers](#mvp-blockers) |
| [AND-395](https://linear.app/andeslab/issue/AND-395) | Release packaging checklist | **MVP blocker** | Release & Distribution | Todo | Felipe (DRI) | The tag itself; mostly satisfied, must be run. → [§MVP Blockers](#mvp-blockers) |
| [AND-325](https://linear.app/andeslab/issue/AND-325) | Rename GitHub repo PlaidBar→VaultPeek | **MVP blocker** | MVP Launch (seq. last) | Backlog | Felipe (DRI) | Cannot launch "VaultPeek" from a repo named PlaidBar. → [§MVP Blockers](#mvp-blockers) |
| [AND-396](https://linear.app/andeslab/issue/AND-396) | Privacy-preserving launch metrics plan | **Beta nice-to-have** | MVP Launch | In Progress | Felipe (DRI) | A *plan* is fine pre-launch; nothing instrumented. → [§Beta](#beta-nice-to-have) |
| [AND-391](https://linear.app/andeslab/issue/AND-391) | Plaid Production approval evidence pack | **Post-MVP** *(GATED)* | Plaid Production Safety | Todo | Felipe (DRI) | Launch as demo/BYO-keys; prod approval is a Felipe go/no-go. → [§Post-MVP](#plaid-production-safety) |
| [AND-392](https://linear.app/andeslab/issue/AND-392) | Free/Plus/Managed entitlement matrix | **Post-MVP** *(GATED)* | Subscription & Managed Linking | Todo | Felipe (DRI) | Monetization is a separate track; needs D1. → [§Post-MVP](#subscription--managed-linking) |
| [AND-393](https://linear.app/andeslab/issue/AND-393) | Billing lifecycle (Stripe) | **Post-MVP** *(GATED)* | Subscription & Managed Linking | Backlog | Felipe (DRI) | Live billing; cannot be auto-implemented. → [§Post-MVP](#subscription--managed-linking) |
| [AND-394](https://linear.app/andeslab/issue/AND-394) | Managed bank-link consent/audit/escalation | **Post-MVP** *(GATED)* | Subscription & Managed Linking | Todo | Felipe (DRI) | Breaks the literal local-first promise; needs D1. → [§Post-MVP](#subscription--managed-linking) |
| [AND-397](https://linear.app/andeslab/issue/AND-397) | Post-MVP roadmap narrative | **Post-MVP** | Provider & Platform Expansion | Backlog | Felipe (DRI) | By definition post-launch. → [§Post-MVP](#provider--platform-expansion) |
| [AND-398](https://linear.app/andeslab/issue/AND-398) | Product-intelligence wedge (parent) | **Post-MVP** | Subscription & Managed Linking | Backlog | Felipe (DRI) | "Allowed later with care"; not the MVP. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-399](https://linear.app/andeslab/issue/AND-399) | Transaction review inbox | **Post-MVP** | Subscription & Managed Linking | Backlog | Felipe (DRI) | New workflow surface; post-launch. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-400](https://linear.app/andeslab/issue/AND-400) | Recurring bills detection | **Post-MVP** | Subscription & Managed Linking | Backlog | Felipe (DRI) | Enrichment; "better recurring explanation" is a Horizon-5 idea. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-401](https://linear.app/andeslab/issue/AND-401) | Explainable safe-to-spend | **Post-MVP** | Subscription & Managed Linking | In Progress | Felipe (DRI) | In flight but not launch-blocking; ships when ready. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-402](https://linear.app/andeslab/issue/AND-402) | Lightweight category budgets | **Post-MVP** | Subscription & Managed Linking | Backlog | Felipe (DRI) | Closest to "budgeting suite"; guard hardest. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-403](https://linear.app/andeslab/issue/AND-403) | Weekly money review workflow | **Post-MVP** | Subscription & Managed Linking | Backlog | Felipe (DRI) | Workflow canvas; menu-bar-first skepticism applies. → [§Post-MVP](#product-intelligence-wedge) |
| [AND-378](https://linear.app/andeslab/issue/AND-378) | Tabular numerics | **Beta nice-to-have** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Cheap, high-polish; safe to slip into a beta window. → [§Beta](#beta-nice-to-have) |
| [AND-379](https://linear.app/andeslab/issue/AND-379) | Per-account inline sparklines | **Post-MVP** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Net-new viz; not launch-shaping. → [§Post-MVP](#design-system--interaction-excellence) |
| [AND-380](https://linear.app/andeslab/issue/AND-380) | Interactive charts | **Post-MVP** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Interaction expansion; post-launch. → [§Post-MVP](#design-system--interaction-excellence) |
| [AND-381](https://linear.app/andeslab/issue/AND-381) | GlassEffectContainer / Liquid Glass | **Post-MVP** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Liquid Glass is a *progressive enhancement, not a minimum*. → [§Post-MVP](#design-system--interaction-excellence) |
| [AND-382](https://linear.app/andeslab/issue/AND-382) | Zoom hero transition | **Post-MVP** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Motion polish; post-launch. → [§Post-MVP](#design-system--interaction-excellence) |
| [AND-383](https://linear.app/andeslab/issue/AND-383) | Scroll-edge depth | **Post-MVP** | Design System & Interaction Excellence | Backlog | Felipe (DRI) | Low-priority depth detail. → [§Post-MVP](#design-system--interaction-excellence) |
| [AND-384](https://linear.app/andeslab/issue/AND-384) | Detachable pinnable window | **Post-MVP** | Native Expansion | Backlog | Felipe (DRI) | Persistent-workspace surface — test against menu-bar-first. → [§Post-MVP](#native-expansion) |
| [AND-385](https://linear.app/andeslab/issue/AND-385) | Widget extension + Control Center | **Post-MVP** | Native Expansion | Backlog | Felipe (DRI) | "Desktop widget" is an explicit Horizon-5 later item. → [§Post-MVP](#native-expansion) |

> **Owner note:** VaultPeek is a single-owner product. "Felipe (DRI)" is the directly-responsible individual on every row because final calls — especially the gated ones — are his alone; authorized agents may *prepare* (draft docs, run gates, stage QA) under the 2026-05-30 scoped approval (`docs/autonomous-roadmap.md` §Operating Contract) but cannot decide gated items or publish.

---

## MVP Blockers

These six items, and only these six, gate the public VaultPeek tag. The list is deliberately small: the product already ships, so the blockers are the *public envelope*, not the product.

**[AND-387](https://linear.app/andeslab/issue/AND-387) — MVP launch decision log & cutline** · MVP Launch · In Progress · Felipe (DRI). This document. It blocks because every other launch decision references it; without an agreed cutline, the other epic children have no scope boundary.

**[AND-388](https://linear.app/andeslab/issue/AND-388) — Launch QA matrix** · MVP Launch · Todo · Felipe (DRI). A public launch makes verifiable claims (local-first, recovery-first, mode separation). Those claims must be backed by a run matrix across sandbox/dev/prod/offline/restart/upgrade. The scaffolding exists (`docs/qa-matrix.md`, `Scripts/smoke-sandbox.sh`, the release-checklist accessibility/clean-profile sections), but a *launch-scoped, executed* matrix is the evidence that makes the README honest. Blocks because shipping a finance tool publicly without a recorded QA pass is a trust failure the north star forbids.

**[AND-389](https://linear.app/andeslab/issue/AND-389) — Public launch surface** · MVP Launch · Todo · Felipe (DRI). README, screenshots, changelog, support copy, and positioning. For this launch the public surface *is* the deliverable — the product is built, so the launch is the act of presenting it coherently as VaultPeek. The pricing/launch doc already drafts positioning ("Private finance, one glance away"; "a cockpit, not a budgeting suite") with the explicit constraint to use *only the precise privacy claim*, never an unqualified "we never see your data" (`docs/strategy/pricing-and-launch.md` §7). Blocks because an incoherent or PlaidBar-named public surface is the launch failing.

**[AND-390](https://linear.app/andeslab/issue/AND-390) — Support & operations runbook** · MVP Launch · In Progress · Felipe (DRI). Public (even private-beta) users will hit Plaid item-expiry, server-offline, and mode-mismatch states. `docs/troubleshooting.md` and `SUPPORT.md` exist; this issue turns them into an operator-facing runbook (what to tell a user, how to triage, what is local vs Plaid-side). Blocks because launching a finance tool with no support path is irresponsible and erodes the trust claim.

**[AND-395](https://linear.app/andeslab/issue/AND-395) — Release packaging checklist** · Release & Distribution · Todo · Felipe (DRI). This is the tag-gate itself: version alignment, build/test gates, DMG packaging, clean-profile verify, privacy/secret scan. It is **already substantially satisfied** by `docs/release-checklist.md`, `docs/release.md`, and `docs/distribution.md`, and Homebrew was intentionally discontinued (`docs/release.md`). It remains a blocker not because it needs new work but because the checklist must be *executed and recorded* against the actual launch candidate before tagging. Keep distribution claims conservative: ad-hoc-signed DMG, right-click→Open on first launch — Developer ID signing/notarization/Sparkle stay deferred (Felipe-only; needs his Apple Developer credentials, `docs/distribution.md`).

**[AND-325](https://linear.app/andeslab/issue/AND-325) — Rename GitHub repo PlaidBar→VaultPeek** · MVP Launch, sequenced last · Backlog · Felipe (DRI). You cannot publicly launch a product named "VaultPeek" from a repository, README, and screenshots that say PlaidBar. The pricing doc names this an explicit pre-launch gate (D4: "PlaidBar cannot be a commercial brand … VaultPeek rename must land before any paid launch"). The rename is **sequenced last** among blockers because it touches the most surfaces and must follow the staged SwiftPM/executable-name compatibility plan (SwiftPM targets, `PLAIDBAR_*` env vars, Keychain service, and `~/.plaidbar/` paths intentionally keep the PlaidBar name per the README compatibility table). Blocks the *public* tag specifically — the GitHub repo rename and public-facing strings, not the internal executable names.

> **No ambiguous blockers.** Every blocker above is a concrete, owned deliverable with a milestone. Nothing in the blocker list depends on a yet-unmade scope decision; the genuinely open decisions are all in deferred buckets and flagged in [§Gated decisions for Felipe](#gated-decisions-for-felipe).

---

## Beta nice-to-have

These improve the launch but do not gate the tag. Ship them in a closed/early window or fold them into the first post-launch increment.

**[AND-396](https://linear.app/andeslab/issue/AND-396) — Privacy-preserving launch metrics plan** · MVP Launch · In Progress · Felipe (DRI). *Why deferred from blocking:* The north star and operating contract forbid telemetry by default and any hosted footprint (`docs/v1.0-roadmap.md` §Resist; `docs/autonomous-roadmap.md`). A metrics *plan* is a thinking artifact, not instrumentation — nothing is wired into the app, so it carries zero launch risk and the launch is fully coherent without it shipping. It is "nice-to-have" rather than "post-MVP" only because having the plan written down before launch lets the first real adoption signal (if Felipe ever approves any privacy-preserving measurement) be designed correctly. If Felipe questions this: launching with *no* metrics is the safe default and the correct one; this issue must never become "add analytics."

**[AND-378](https://linear.app/andeslab/issue/AND-378) — Tabular numerics** · Design System & Interaction Excellence · Backlog · Felipe (DRI). *Why deferred from blocking:* Monospaced/tabular figure alignment is genuine polish that improves a dense finance instrument, and it is cheap and low-risk (a typography token change). But misaligned-but-correct numbers do not break any product claim, so it cannot block a launch of an already-shipping product. It is the one design-excellence item worth pulling into a beta window because the cost/benefit is unusually favorable for a numbers-first popover; the rest of the design-excellence milestone is squarely post-MVP (below).

---

## Post-MVP (by milestone)

Real, wanted work — assigned to its correct milestone, not generic backlog. Each carries a one-paragraph rationale because Felipe may reasonably ask "why isn't this in the launch?"

### Plaid Production Safety

**[AND-391](https://linear.app/andeslab/issue/AND-391) — Plaid Production approval evidence pack** · Todo · Felipe (DRI) · **GATED.** *Rationale:* The MVP can launch publicly in **demo + bring-your-own-keys** form with zero hosted footprint and the privacy promise fully intact (`docs/strategy/pricing-and-launch.md` §10 step 1: "Ship the rename and the launch site with Demo + BYO-keys only … Zero hosted footprint yet, promise unbroken"). Plaid *production* approval is only required to offer managed/turnkey live banks, which is the monetization track, not the MVP. This issue is GATED because it depends on a Felipe-only decision: whether the launch mode is sandbox/demo/BYO or production (pricing doc D2/D3, and AND-391's own "needs sandbox-vs-production launch-mode decision by Felipe"). An agent cannot apply for or attest Plaid production approval. Correctly placed in Plaid Production Safety, not the launch milestone.

### Subscription & Managed Linking

All three are **GATED on the existential D1 decision** — whether VaultPeek adds *any* hosted footprint at all — and on the amended public promise (`docs/strategy/pricing-and-launch.md` §2, §9 D1). None can be auto-implemented; they are business decisions with legal, billing, and trust consequences.

**[AND-392](https://linear.app/andeslab/issue/AND-392) — Free/Plus/Managed entitlement matrix** · Todo · Felipe (DRI) · **GATED.** *Rationale:* Monetization tiers are a deliberately separate track ("Track B") that "never replaces Track A," the free local-first product (`pricing-and-launch.md` §1). No entitlement or institution-cap enforcement exists in code today (§3). Building the matrix presumes the decision to monetize, which is Felipe's alone. Launching the MVP free, local-first, and unmetered is the safe path and the trust anchor for any future Track B.

**[AND-393](https://linear.app/andeslab/issue/AND-393) — Billing lifecycle (Stripe)** · Backlog · Felipe (DRI) · **GATED.** *Rationale:* Live billing moves real money and requires a hosted entitlement service — a hard departure from the literal "no hosted backend" promise that only Felipe can authorize, and a financial-transaction surface that is non-negotiably owner-only. It also depends on a Plaid sales quote that swings Plus-tier margins from −15% to +76% (§5.3, D2). Nothing about an MVP of an already-shipping free product needs Stripe. Correctly in the latest-due, lowest-state position.

**[AND-394](https://linear.app/andeslab/issue/AND-394) — Managed bank-link consent/audit/escalation** · Todo · Felipe (DRI) · **GATED.** *Rationale:* Managed linking is the feature that *breaks the literal local-first promise* — it introduces a link-token broker and a stateless sync relay that financial data must transit because Plaid forbids shipping the org secret in clients (`pricing-and-launch.md` §2; `docs/strategy/managed-link-architecture.md`). That is exactly the kind of identity-changing move the product brief says must be Felipe-approved (`docs/v1.0-roadmap.md` §Resist). It cannot ship in an MVP that is launching *on* the privacy promise.

### Design System & Interaction Excellence

**[AND-379](https://linear.app/andeslab/issue/AND-379) sparklines · [AND-380](https://linear.app/andeslab/issue/AND-380) interactive charts · [AND-381](https://linear.app/andeslab/issue/AND-381) Liquid Glass · [AND-382](https://linear.app/andeslab/issue/AND-382) zoom hero · [AND-383](https://linear.app/andeslab/issue/AND-383) scroll-edge depth** · all Backlog · Felipe (DRI). *Rationale:* The product already meets its design bar — heatmap-first, dense rows, native material surfaces (`GOAL.md` design direction; autonomous-roadmap ledger). These are *enhancements to a surface that is already good enough to launch*, and Liquid Glass specifically is defined as "a progressive enhancement, not a minimum requirement … only behind compiler and availability gates" (`docs/v1.0-roadmap.md`). Pulling any of them into the launch adds risk and review surface to a shipping product for no launch-coherence gain. They belong together in the design milestone, post-tag. (AND-378 is the single exception, pulled to beta — see above.)

### Native Expansion

**[AND-384](https://linear.app/andeslab/issue/AND-384) — Detachable pinnable window** · Backlog · Felipe (DRI). *Rationale:* A persistent detached window is exactly the kind of "large canvas / persistent workspace" surface the product brief says to treat with skepticism unless it strengthens the menu-bar experience (`docs/v1.0-roadmap.md` §Menu Bar First). It is a deliberate post-MVP exploration, not a launch requirement, and it needs its own data-boundary and menu-bar-first review before it earns a place.

**[AND-385](https://linear.app/andeslab/issue/AND-385) — Widget extension + Control Center** · Backlog · Felipe (DRI). *Rationale:* "Desktop widget for a small subset of signals" is named explicitly as a Horizon-5 "Allowed Later With Care" item requiring a data-boundary review (`docs/v1.0-roadmap.md`). A widget is a new surface and a new target; it cannot block launching the menu-bar product it would complement.

### Product-intelligence wedge

Parent **[AND-398](https://linear.app/andeslab/issue/AND-398)** and children **[AND-399](https://linear.app/andeslab/issue/AND-399) review inbox · [AND-400](https://linear.app/andeslab/issue/AND-400) recurring bills · [AND-401](https://linear.app/andeslab/issue/AND-401) safe-to-spend (In Progress) · [AND-402](https://linear.app/andeslab/issue/AND-402) category budgets · [AND-403](https://linear.app/andeslab/issue/AND-403) weekly review** · Felipe (DRI). *Rationale:* This entire wedge sits in the "Allowed Later With Care" / "Resist" tension of the north star. Better recurring-charge explanation and category-level alerts are *explicitly* Horizon-5 later items, each requiring a data-boundary review (`docs/v1.0-roadmap.md` §Allowed Later). The riskier members are closest to the line VaultPeek must not cross: **AND-402 (category budgets)** and **AND-403 (weekly money review workflow)** are the most "budgeting-suite"-shaped items on the entire board — the parent epic's title literally calls it a "budgeting-suite wedge" — and the product's defining constraint is *"feel in control of finances WITHOUT becoming a full budgeting suite."* AND-401 (safe-to-spend) is In Progress and may ship on its own cadence when ready and explainable, but it is not a launch blocker: the MVP is coherent and valuable without it. None of these gate the tag; all belong in a post-MVP intelligence track where each gets its individual menu-bar-first and local-first review. *(Board note: these currently sit in the Subscription & Managed Linking milestone; if a dedicated "Product Intelligence" milestone is created, move them there.)*

### Provider & Platform Expansion

**[AND-397](https://linear.app/andeslab/issue/AND-397) — Post-MVP roadmap narrative** · Backlog · Felipe (DRI). *Rationale:* A narrative describing what comes *after* the MVP is, by definition, not part of the MVP. It is useful launch-adjacent communication but writing it does not gate the tag, and it should reflect the decisions in this log rather than precede them.

---

## Dead / Superseded

No current board candidate is classified Dead. The one adjacent retirement worth recording for launch-claim hygiene:

**Homebrew distribution — DEAD (intentionally discontinued).** The public tap was retired and `Formula/plaidbar.rb` removed; the DMG is the sole distribution channel (`docs/release.md`; `docs/v1.0-roadmap.md` §Allowed Later notes "Homebrew formula/cask distribution is discontinued"). The release-packaging blocker (AND-395) must *not* re-introduce Homebrew checks, and the public README/positioning (AND-389) must not imply a `brew install` path. This is recorded here so no launch task accidentally resurrects it.

---

## Gated decisions for Felipe

These are **decisions, not tasks.** No agent can implement them under the 2026-05-30 scoped approval, because each changes product/security/business scope or moves money (`docs/autonomous-roadmap.md` §Operating Contract; §Stop Conditions). Authorized agents may *prepare* surrounding artifacts (draft docs, stage evidence) but must stop and ask before acting.

> **Ratified 2026-06-14 (Felipe, DRI).** The monetization/hosted-footprint and Plaid launch-mode decisions below were taken explicitly: **defer all monetization, managed linking, and Plaid production; ship the MVP as a free, local-first beta (Demo + bring-your-own-keys), zero hosted footprint.** The "Decision" column now records made decisions, not pending defaults. Re-opening any of them requires a new Felipe decision.

| Decision | Issue(s) | What it gates | Decision (ratified 2026-06-14) |
|---|---|---|---|
| **D1 — Approve any hosted footprint** (link-token broker + entitlement service) and the amended public privacy promise | AND-392, AND-393, AND-394 | The entire Subscription & Managed Linking milestone | **DEFERRED.** No hosted footprint; launch free + local-first + BYO-keys. The whole Subscription & Managed Linking milestone stays Post-MVP. |
| **Launch mode: demo/BYO vs Plaid production** (incl. the Plaid sales quote, D2/D3) | AND-391 | Whether the MVP offers managed live banks | **DEMO + BYO-keys.** Production approval deferred; recorded in [`strategy/plaid-production-decision.md`](strategy/plaid-production-decision.md). |
| **Monetization go/no-go** (tiers, caps, price-lock) | AND-392, AND-393 | Any paid tier | **NO-GO for MVP.** Free, unmetered, local-first; the proposed tier matrix stays a Post-MVP spec ([`strategy/pricing-and-launch.md` §4](strategy/pricing-and-launch.md)). |
| **Signing & notarization** (Developer ID, Gatekeeper, Sparkle) — needs Felipe's Apple Developer credentials | AND-395 / `docs/distribution.md` | Notarized public distribution claims | **DEFERRED.** Ad-hoc-signed DMG, right-click→Open, claims kept conservative. |
| **Public rename execution & timing** | AND-325 | The public VaultPeek tag (this is a *blocker*, sequenced last) | **Still required before the public tag** (sequenced last among blockers). |

> The rename (AND-325) appears here *and* in MVP Blockers deliberately: it is a Felipe-owned action that also gates the tag. With the 2026-06-14 ratification, everything else in this table is settled for the MVP: the gated expansion work is deferred Post-MVP with the rationale below, and only the rename remains as a Felipe-owned launch action.

---

## How to use this cutline

1. **Ship the six blockers, in order.** AND-387 (this doc) → AND-388 QA matrix + AND-389 public surface + AND-390 support runbook (parallel) → AND-395 release-checklist run → **AND-325 rename last.** When all six are Done, the public VaultPeek MVP can be tagged.
2. **Treat the gated decisions as a checklist for Felipe, not a backlog for agents.** Nothing in Subscription & Managed Linking or Plaid Production Safety starts until the matching decision in [§Gated decisions](#gated-decisions-for-felipe) is made. Agents may prepare; they may not decide or publish.
3. **Hold the line on scope.** If a new candidate appears, classify it here *before* it gets launch attention. The test is the north star: does it make the local-first, menu-bar-first finance instrument more trustworthy for launch, or does it broaden the product? Budgeting-suite-shaped work (AND-402, AND-403) and hosted-footprint work stay out by default.
4. **Keep claims conservative and true.** Distribution is an ad-hoc-signed private DMG; the privacy claim is the precise version, never the unqualified one; no Homebrew, no telemetry, no hosted backend. The launch succeeds when the public surface matches the code exactly (`docs/v1.0-roadmap.md` §Horizon 1: Trust And Truth).

**Bottom line:** the product is done; the launch is the public envelope. Six blockers gate it — decision log, QA matrix, public surface, support runbook, release checklist, and the rename. Everything else is either a beta polish slice or a deliberately deferred, mostly Felipe-gated expansion of a product that must not become a budgeting suite.
