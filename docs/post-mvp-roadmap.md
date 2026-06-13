# VaultPeek Post-MVP Roadmap

**Linear:** [AND-397](https://linear.app/andeslab/issue/AND-397) · **Milestone:** Provider & Platform Expansion · **Status:** Backlog · **Owner:** Felipe (DRI)

## Purpose

This is the one-page narrative for what VaultPeek builds *after* the public MVP launch — and, just as importantly, what it deliberately will not build. It is a companion to two other documents and contradicts neither:

- [`docs/v1.0-roadmap.md`](v1.0-roadmap.md) is the long-term product brief — the constitution. This roadmap inherits its North Star, Horizons, and Product Boundaries.
- [`docs/mvp-launch-decision-log.md`](mvp-launch-decision-log.md) is the launch cutline — the single source of truth for what ships in the MVP. This roadmap treats that cutline's six blockers as "Now" and does not re-derive them.

A reader should finish this page understanding the *order* of the next several phases, *why* each one must precede the next, and which Linear milestone owns each. It is a narrative, not a task tracker; when a phase begins, the work is planned in its Linear milestone, not here.

**North Star, unchanged and load-bearing for every phase below:** make a privacy-conscious Mac user feel in control of their finances *without* becoming a full budgeting suite — local-first, no hosted backend, no telemetry, no cloud (`docs/v1.0-roadmap.md` §North Star).

## The shape of the work

VaultPeek 1.0 already shipped under its former name, PlaidBar. So the MVP launch is not "build the product" — it is "make a private, shipping 1.0 safe to present publicly under the VaultPeek name" (`docs/mvp-launch-decision-log.md` §"Current product truth"). Everything after the launch tag therefore falls into two buckets: a **safety track** that must be cleared before VaultPeek can responsibly grow its surface or its business, and an **excellence/expansion track** that makes the already-good instrument better and, eventually, broader.

The phases below are strictly ordered. Each precedes the next for a concrete reason, not a stylistic one.

## Now / Next / Later at a glance

| Horizon | Phase | Linear milestone | Representative issues | Gate |
|---|---|---|---|---|
| **Now** | MVP launch (the public envelope) | MVP Launch · Release & Distribution | AND-387, AND-388, AND-389, AND-390, AND-395, AND-325 | Ships now — see the cutline |
| **Next** | 1 · Plaid production safety | Plaid Production Safety | AND-391 | Felipe: launch-mode decision |
| **Next** | 2 · Subscription & managed linking | Subscription & Managed Linking | AND-392, AND-393, AND-394 | Felipe: D1 hosted-footprint go/no-go |
| **Next** | 3 · Design system & interaction excellence | Design System & Interaction Excellence | AND-378, AND-379, AND-380, AND-381, AND-382, AND-383 | None — autonomous polish |
| **Later** | 4 · Local AI & product intelligence | Subscription & Managed Linking (Product Intelligence wedge) | AND-398, AND-399, AND-400, AND-401, AND-402, AND-403 | Per-feature data-boundary review |
| **Later** | 5 · Native expansion | Native Expansion | AND-384, AND-385 | Menu-bar-first review |
| **Later** | 6 · Provider & platform expansion | Provider & Platform Expansion | (this doc, AND-397) | Identity review |

Phases 2 and 3 can run in parallel after Phase 1 — design excellence carries no business gate — but the dependency *line* that matters runs through the safety track: **MVP → subscription safety → design excellence → local AI → native expansion → provider/platform expansion.**

## Now — the MVP launch

Defined entirely by the cutline. Six blockers, in order: the decision log itself (AND-387), the launch QA matrix (AND-388), the public launch surface (AND-389), the support & operations runbook (AND-390), the release-packaging checklist run (AND-395), and the PlaidBar→VaultPeek repo rename (AND-325, sequenced last because it touches the most surfaces and a product named "VaultPeek" cannot launch from a repo named PlaidBar). When all six are Done, the public VaultPeek MVP is tagged.

Everything below is out of this launch by design. See [`docs/mvp-launch-decision-log.md`](mvp-launch-decision-log.md) for the full classification of every board candidate — this roadmap does not restate it.

## Next — clearing the path to grow

### Phase 1 — Plaid production safety · *milestone: Plaid Production Safety*

The MVP launches in **demo + bring-your-own-keys** form, with zero hosted footprint and the privacy promise fully intact (`docs/strategy/pricing-and-launch.md` §10 step 1). The first post-launch question is whether VaultPeek ever offers *managed, turnkey* live banks — and that requires Plaid **production** approval: a security questionnaire, an MSA, and an evidence pack (**AND-391**).

**Why it precedes everything else in the growth track:** every business-expansion phase that follows (managed linking, monetized tiers) depends on a live production relationship with a data provider. There is no point building entitlement matrices or billing on top of a provider relationship that has not been approved. This phase is also a **Felipe-only go/no-go** — an agent cannot apply for or attest production approval — so it is the first decision gate, not the first build.

### Phase 2 — subscription safety & managed linking · *milestone: Subscription & Managed Linking*

This is the phase the entire dependency order is built to protect. Managed linking (**AND-394**) is the feature that breaks the *literal* local-first promise: because Plaid forbids shipping the org `secret` in distributed clients, a managed tier needs a link-token broker and a stateless, memory-only sync relay that financial data must *transit* (it is never *stored*) — the first hosted footprint VaultPeek would ever ship (`docs/strategy/pricing-and-launch.md` §2; `docs/strategy/managed-link-architecture.md`). Monetization rides on top of it: a Free/Plus/Managed entitlement matrix (**AND-392**) and a Stripe billing lifecycle (**AND-393**).

**Why it must come before design excellence and local AI in priority order, even though those carry no gate:** this is the phase where VaultPeek's *identity* is most at risk. The amended public promise, the broker architecture, live billing, and the institution caps that keep per-Item provider costs from going underwater (Plus is margin-negative at its 8-institution cap on pay-as-you-go rates — `docs/strategy/pricing-and-launch.md` §5.3) are all **gated on Felipe's existential D1 decision: whether VaultPeek adds *any* hosted footprint at all.** Until that decision is made, nothing here starts; the safe default is to stay free, local-first, and BYO-keys. Track B (managed SaaS) *never* replaces Track A (the free, fully local product); Track A is the trust anchor that makes Track B's privacy story credible (`docs/strategy/pricing-and-launch.md` §1). Resolving this safety-and-trust question early keeps every later phase from being built on an undecided foundation.

## Later — making the instrument better, then broader

### Phase 3 — design system & interaction excellence · *milestone: Design System & Interaction Excellence*

With the safety track resolved (or explicitly deferred by Felipe), the next work sharpens the surface every other feature lands on. This is high-polish, low-risk, *autonomous* work with no business gate: tabular numerics (**AND-378**, the one item pulled into a launch-beta window), per-account inline sparklines (**AND-379**), interactive charts (**AND-380**), GlassEffectContainer / Liquid Glass (**AND-381**), a zoom hero transition (**AND-382**), and scroll-edge depth (**AND-383**).

**Why it precedes local AI:** product-intelligence features (Phase 4) render *into* this design system — insight receipts, recurring cards, a monthly-review surface. A denser, more legible, more interactive instrument is the canvas those features need. Building intelligence first and polish second would mean redesigning the same surfaces twice. Liquid Glass specifically stays a *progressive enhancement, not a minimum requirement* — used only behind compiler and availability gates, never a floor (`docs/v1.0-roadmap.md` §"Liquid Glass").

### Phase 4 — local AI & product intelligence · *milestone: Subscription & Managed Linking (Product Intelligence wedge)*

This is where VaultPeek gets smarter without getting larger. The local-AI foundation is **already partially shipped**: `LocalAIInsightsService` (with `OllamaLocalInsightModel` and the `LocalAIInsightBuilder`) and the local insight-receipt pattern — display-safe evidence chips, explicit time windows, a "Local" pill, and clear "no model runtime configured" degradation — already exist in the app (`docs/autonomous-roadmap.md` progress ledger, 2026-06-11 entries). The wedge builds on it: a transaction review inbox (**AND-399**), recurring-bills detection (**AND-400**), explainable safe-to-spend (**AND-401**, already shipped this cycle), lightweight category budgets (**AND-402**), and a weekly money review (**AND-403**), under parent **AND-398**. *(Board note: AND-398–403 currently live in the Subscription & Managed Linking milestone, not the separate "Local AI Privacy Track" milestone; route them to a dedicated Product Intelligence milestone if one is created — mirrors the cutline's board note.)*

**Why it precedes native expansion, and why it is guarded hardest:** these features sit squarely in the "Allowed Later With Care" / "Resist" tension of the North Star. Better recurring-charge explanation and category-level alerts are *explicitly* Horizon-5 later items, each requiring an individual data-boundary review (`docs/v1.0-roadmap.md` §"Allowed Later With Care"). The riskiest members — category budgets (AND-402) and the weekly review workflow (AND-403) — are the most "budgeting-suite"-shaped work on the board, and the product's defining constraint is *control without becoming a budgeting suite.* Every feature here must pass a menu-bar-first and local-first review, and any AI step must keep raw transaction data on-device: deterministic templates are always the source of numbers; the on-device model may only *rephrase* them. A cloud model over private transactions is out of scope and would require its own product decision. Settling the intelligence surface *before* expanding to new native surfaces (Phase 5) means each new surface inherits a vetted, on-device intelligence layer rather than re-litigating the boundary.

### Phase 5 — native expansion · *milestone: Native Expansion*

Only after the core instrument is stable, polished, and intelligently complete does VaultPeek grow to new macOS surfaces: a detachable, pinnable window (**AND-384**) and a widget extension + Control Center presence (**AND-385**).

**Why it comes this late:** both introduce new surfaces and new targets, and both must be tested against the *Menu Bar First* principle — VaultPeek "should remain a menu bar utility, not a full desktop finance app that happens to have a menu bar icon" (`docs/v1.0-roadmap.md` §"Menu Bar First"). A detached window is exactly the kind of "large canvas / persistent workspace" the brief says to treat with skepticism; a widget is a named Horizon-5 "Allowed Later With Care" item requiring a data-boundary review. Expanding the *number* of surfaces before the *content* of the core surface is final would scatter effort across canvases that the intelligence and design phases might still reshape.

### Phase 6 — provider & platform expansion · *milestone: Provider & Platform Expansion*

The furthest horizon: carefully scoped alternate Plaid-like provider support (e.g. a Teller path behind a minimal provider abstraction so the local server and broker are not hard-wired to one aggregator — `docs/strategy/provider-abstraction.md`, `docs/strategy/teller-evaluation.md`), redacted export, signed app-bundle distribution (Developer ID + notarization — Felipe-gated on his Apple Developer credentials), and a private Sparkle update channel.

**Why it is last:** provider abstraction only pays off once the managed model (Phase 2) is real and the feature surface (Phases 3–5) is stable enough that swapping the data layer underneath is a contained change rather than a moving target. Signing/notarization stays deferred until "signing, notarization, Gatekeeper verification, and release automation are real" (`docs/v1.0-roadmap.md` §"Horizon 4: Distribution Confidence") — the project should not make a distribution promise it cannot yet keep. This document (AND-397) lives in this milestone because a narrative of what comes after the MVP is, by definition, the last thing the launch itself needs.

## Explicit non-goals

These directions stay **out of scope** unless the project deliberately changes its identity, and each requires a Felipe-level decision — no agent may implement them. Quoting the brief's "Resist" stance (`docs/v1.0-roadmap.md` §"Resist"), these remain off the roadmap:

- **Hosted backend** *(the one bounded exception: the minimal link-token broker + entitlement check + stateless no-storage sync relay of Phase 2, and only if Felipe approves D1).*
- **Cloud sync.**
- **Telemetry by default.** The privacy-preserving metrics *plan* (AND-396) is a thinking artifact only; it must never become "add analytics," and launching with *no* metrics is the correct default.
- **Multi-user finance platform.**
- **iOS companion app.**
- **Investment portfolio dashboard.**
- **Cloud AI/ML over private transactions** or any insight feature that sends raw financial data off-device.
- **Generic Plaid developer playground.**

Two further hygiene boundaries carried from the launch decisions: **Homebrew distribution is dead** (intentionally discontinued; the DMG is the sole channel — no task may resurrect a `brew install` path), and the privacy claim is always the *precise* version, never an unqualified "we never see your data."

The test for any new candidate is the North Star: does it make the local-first, menu-bar-first finance instrument more trustworthy and more glanceable, or does it broaden the product into something it was built not to be? Anything that fails that test is narrowed or marked out of scope.

## Bottom line

The MVP launches a finished product as a coherent public envelope. After that, VaultPeek clears its safety track first — production approval, then the hosted-footprint and monetization decision — because every later phase is built on it. Then it makes the instrument *better* (design, on-device intelligence) before it makes it *broader* (native surfaces, new providers). Throughout, the hosted footprint stays minimal-or-absent, the data stays on the user's Mac, and the product stays a cockpit, not a budgeting suite.
