---
title: Plaid Production Approval — Decision Record & Evidence Pack
status: decided
linear: [AND-391]
date: 2026-06-14
decision: Launch demo + bring-your-own-keys; defer managed Plaid production approval Post-MVP
---

# Plaid Production Approval — Decision Record & Evidence Pack

**Linear:** [AND-391](https://linear.app/andeslab/issue/AND-391) · parent epic
[AND-386](https://linear.app/andeslab/issue/AND-386) · Milestone: *Plaid
Production Safety* · **Decision ratified 2026-06-14 by Felipe (DRI).**

This document is the decision record and evidence checklist required by AND-391.
It answers the four questions in the issue's acceptance criteria — *can first
users connect real banks, under what plan, at what cost, and with what
limitations?* — and records the launch-mode decision so no agent or future
session re-opens it without a new Felipe decision.

## Decision (2026-06-14)

**VaultPeek's MVP launches in demo + bring-your-own-Plaid-keys mode. VaultPeek
does not apply for, hold, or operate a Plaid production relationship at launch.
Managed/turnkey live banking — and the Plaid production approval it would
require — is deferred Post-MVP, gated on the D1 hosted-footprint decision (see
[`pricing-and-launch.md` §9](pricing-and-launch.md) and the
[MVP launch decision log](../mvp-launch-decision-log.md)).**

This is the documented "Default if undecided" from the cutline's gated-decisions
table, now explicitly chosen. It keeps the zero-hosted-footprint privacy promise
intact for launch.

## The four acceptance-criteria questions, answered

### 1. Can first users connect real banks?

Yes — through **bring-your-own-keys (BYO) mode**, which already ships. A user
who has their own Plaid credentials (sandbox, development, or their own
Plaid-approved production credentials) links real institutions directly; the
Plaid relationship is theirs, and account data plus access tokens stay on their
Mac (`Sources/PlaidBarServer/` → `127.0.0.1:8484` → Plaid, never transiting
VaultPeek).

No — VaultPeek does **not** offer *managed* (turnkey, no-keys-needed) live
banking at launch. That path needs a hosted link-token broker and VaultPeek's
own Plaid production approval, both deferred.

### 2. Under what plan?

**Free, local-first public beta.** BYO-keys is free forever (the trust anchor,
[`pricing-and-launch.md` §4](pricing-and-launch.md)). There is no paid tier, no
subscription, and no account to create at launch. Demo mode (`--demo`) is the
zero-setup entry point.

### 3. At what cost?

- **To the user, from VaultPeek: $0.** VaultPeek charges nothing and runs no
  billing at launch.
- **BYO production users** are billed by Plaid directly under *their own* Plaid
  account — VaultPeek never sees or fronts that cost.
- **To VaultPeek: $0 recurring provider cost**, because VaultPeek holds no Plaid
  Items at launch (no managed broker). The per-Item Plaid economics that would
  apply to a future managed tier are modeled in
  [`provider-costs.md`](provider-costs.md) and
  [`pricing-and-launch.md` §5](pricing-and-launch.md) — all third-party
  *estimates*; a real Plaid sales quote (decision D2) is a prerequisite before
  any managed/paid launch and is **not** required for this MVP.

### 4. With what limitations?

- Users who want live data must already have (or obtain) their own Plaid
  credentials; obtaining Plaid production approval in BYO mode is the user's
  responsibility, not VaultPeek's.
- No managed/turnkey linking, no realtime balance perks gated to a tier, no
  multi-Mac entitlement — all Post-MVP.
- Distribution is an ad-hoc-signed drag-install DMG (right-click → Open);
  notarization is deferred (`../distribution.md`).
- Sandbox passing ≠ production readiness; the two modes keep strictly separate
  SQLite stores (`README.md` §"Sandbox limitations").

## Evidence checklist for a FUTURE managed-production application

If/when Felipe greenlights managed linking (D1) and a Plaid production
application, this is the artifact checklist — most of it already drafted in
existing strategy docs, so the future application is assembly, not net-new
research:

| Artifact Plaid review expects | Where it already exists / what's still needed |
|---|---|
| Company / app identity, use-case description | **Needs** Felipe's business/legal entity details (owner-only) |
| Product data-flow & local-first storage boundaries | ✅ [`managed-link-architecture.md`](managed-link-architecture.md) §5; [`../privacy.md`](../privacy.md); `SECURITY.md` |
| Data minimization / what the hosted service never sees | ✅ [`managed-link-architecture.md`](managed-link-architecture.md) §5.2, §9 |
| Expected Plaid products & per-Item cost expectations | ✅ [`provider-costs.md`](provider-costs.md); [`pricing-and-launch.md` §5](pricing-and-launch.md) (estimates; real quote = D2) |
| Consumer onboarding / consent surface | ✅ [`managed-link-architecture.md`](managed-link-architecture.md) §7, §11; [`subscription-entitlements.md`](subscription-entitlements.md) §6 |
| Production security questionnaire / MSA | **Needs** Felipe — VaultPeek (not the user) signs the MSA in the managed model |
| Approval dependencies & gates | ✅ [`approval-gates.md`](approval-gates.md); [`consumer-production-checklist.md`](consumer-production-checklist.md) |

**An agent cannot apply for or attest Plaid production approval** — it requires
Felipe's business identity, legal signature, and a go/no-go decision. This
record exists so that when that decision is made, the evidence pack is ready.

## Status

AND-391 is **resolved for the MVP as "deferred, demo/BYO launch."** The issue
stays in the *Plaid Production Safety* milestone as the home for the future
production application; it is not an MVP launch blocker.
