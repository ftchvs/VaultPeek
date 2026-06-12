---
title: Stripe Subscription Entitlements & Institution Limits
status: proposed
linear: [AND-348]
date: 2026-06-12
---

# Stripe Subscription Entitlements & Institution Limits — Design

**Design doc only. No implementation.** Linear AND-348 is titled "Implement Stripe subscription entitlements and institution limits"; this document is the design that must be approved *before* any implementation starts. Its acceptance criteria are treated as the spec this design must satisfy (traceability table in §10). All code references below are to the current tree (`Sources/`), read 2026-06-12. All third-party pricing figures were retrieved 2026-06-12; figures marked **(est.)** come from third-party comparisons, not vendor invoices. Proposed numbers (limits, windows, prices) are **proposals**, not commitments.

---

## 0. Decisions required from Felipe before implementation

Implementation is explicitly deferred until these are decided. Recommendations are marked ★. Decision IDs below are local to this doc — companion docs number their own lists (e.g., rename timing is D10 here and D4 in the pricing doc; cancellation retention is D8 here and touches provider-costs §7).

| # | Decision | Options | Recommendation |
|---|----------|---------|----------------|
| D1 | Entitlement architecture | (a) Stripe + Keygen Cloud, (b) ★ Stripe + DIY Ed25519 token signer co-located with the link-token broker, (c) Merchant-of-Record (Polar/Lemon Squeezy) built-in keys, (d) self-hosted Keygen CE | (b) — one minimal hosted surface serves both jobs (§3) |
| D2 | Tier shape | Personal / Plus institution caps + price points | Personal = 3 institutions, Plus = 8, per the companion pricing doc (proposed there: Personal $79/yr or $9/mo, Plus $129/yr early-access or $15/mo → $149/yr; not final) |
| D3 | Do limits apply to BYO-Plaid-keys mode? | Gate everything vs gate only managed linking | ★ No — BYO mode stays fully ungated (§7, fraud pragmatism) |
| D4 | Offline & grace windows | TTL / grace day counts | ★ 30-day token TTL, 14-day post-expiry grace (§5) |
| D5 | Degraded-mode semantics | Hard lock vs read-only cached vs perpetual-fallback analog | ★ "Your data stays; managed linking & sync stop" — never brick (§6) |
| D6 | Device policy | Devices per license; auto-deactivate-oldest? | ★ 2 Macs per license, CleanShot-style auto-deactivate oldest |
| D7 | Trial | Length; card-upfront vs no-card | ★ Defer to the pricing doc's D10 default: demo mode IS the trial, no card-free *live* trial (live Items bill Plaid fees from day one), 30-day refund instead. If Felipe approves a live trial anyway, implement as 14-day no-card via Stripe `trial_settings` pause-on-expiry. (Earlier draft recommended 14-day no-card; flagged because it directly conflicted with pricing doc D10.) |
| D8 | Cancellation retention | When are broker-managed Plaid items removed; reconnect window | ★ Remove at period end + 7-day reconnect courtesy window (§8) |
| D9 | Sales tax | Stripe direct (+ Stripe Tax) vs MoR (Paddle/Polar/Stripe Managed Payments, public preview as of Feb 2026) | Defer; affects fees, not the entitlement design |
| D10 | Branding collisions | VaultPeek rename touches Keychain service `com.ftchvs.PlaidBar` (`Constants.swift:49`), product names in Stripe, license artifact paths | Decide rename timing before Stripe products are created |

---

## 1. Scope and product context

VaultPeek's consumer plans (parent epic AND-343) introduce **managed bank linking**: the user no longer brings their own Plaid keys; a hosted broker mints link tokens against VaultPeek's Plaid account. Per-connection Plaid/Teller fees are a genuinely recurring cost, which is what justifies a subscription for the *service* — while the *app* must keep its local-first promises.

This doc designs:

1. The license/entitlement model for a **DMG-distributed, non-Mac-App-Store** macOS app billed via Stripe.
2. Institution limits per plan and where they are enforced.
3. Offline grace, downgrade/limit-exceeded UX, cancellation behavior.
4. Privacy-minimal entitlement checks compatible with the no-telemetry promise.

Out of scope: price points and unit economics (companion pricing doc), the broker's Plaid/Teller mechanics (companion managed-linking doc), Teller specifics.

## 2. The local-first tension — explicit callout

Current promise (README/SECURITY.md): **no hosted backend, no telemetry, data stays on the machine.** Today the only network destinations are Plaid's API (from the local server) and nothing else; `/api/*` is bearer-token gated locally (`Sources/PlaidBarServer/Auth/APITokenMiddleware.swift`).

A subscription cannot be verified with zero hosted footprint. This design's resolution:

- **Minimal hosted footprint:** exactly one small hosted service — the same broker that managed linking already requires — gains one extra job: issuing signed entitlement tokens. No second vendor-facing service, no analytics, no event stream.
- **Financial data is NEVER stored on the hosted service.** For BYO users, account data, balances, transactions, and Plaid access tokens flow only `app → localhost:8484 → Plaid`, exactly as today — nothing transits VaultPeek. For managed-mode users, data-plane calls are relayed through the same hosted service's stateless blind proxy (managed-link architecture doc §5.4) — transit-only, memory-only, never persisted or logged. The hosted service sees license identity and (for managed mode) the count of connections it itself brokered — never what's in them.
- **The entitlement ping is specified byte-for-byte (§4.3) and published in SECURITY.md**, inspectable like everything else in a localhost-server product.
- **Degraded ≠ bricked (§6):** losing the subscription removes the hosted service from your life; it does not remove your data or the app.
- **BYO-keys mode remains fully offline-capable and ungated** — the zero-hosted-footprint path continues to exist for users who want it.

This is a real narrowing of the promise ("no hosted backend" → "one narrowly-scoped hosted endpoint, only if you opt into managed linking or a paid plan") and must be stated plainly in marketing and SECURITY.md, not buried.

## 3. Architecture choice

Four viable patterns surveyed (research retrieved 2026-06-12):

| # | Pattern | Hosted footprint | Fit |
|---|---------|-----------------|-----|
| A | Merchant of Record w/ built-in keys (Lemon Squeezy / Polar / Paddle) | Vendor hosts everything | Weak: keys are unsigned online-validated strings; LS's future is tied to the Stripe Managed Payments migration (Stripe acquired LS July 2024; Managed Payments public preview Feb 2026, LS license-key API survival unconfirmed); Paddle Billing has no native licensing |
| B | Stripe + Keygen Cloud | Keygen-hosted licensing API + small webhook glue | Strong features (Ed25519 offline license files, entitlement flags, free Dev tier ≤100 active licensed users, flat-fee scaling — retrieved 2026-06-12) but adds a second third-party that holds customer license state |
| C | ★ Stripe + DIY signer in the broker | One small service: Stripe webhooks → Ed25519/PASETO-signed entitlement tokens; app/server verify with embedded public key | Pairs naturally with the link-token broker VaultPeek already needs; **one hosted surface serves both jobs**; ~hundreds of lines, no per-launch server dependency |
| D | Self-hosted Keygen CE | You run a license server | Avoids third-party data sharing but maximizes self-hosted surface; overkill for two tiers |

**Recommendation (D1): pattern C.** The broker (required anyway for managed Plaid) gains three endpoints: Stripe webhook receiver, entitlement-token issuance, device activation. Keygen Cloud (B) is the fallback if building token issuance in-house proves slower than expected — its offline cryptographic license files (`aes-256-gcm+ed25519`) implement the same artifact this design specifies.

Known build-it-yourself cost of pattern C (and equally of B — Keygen's own Stripe example repo admits revocation wiring is left to the integrator): the **subscription-lifecycle → entitlement-state mapping (§9.2) is ours to spec and test**. It is specced here.

## 4. Entitlement model

### 4.1 Identity

- **License id:** opaque random id (`lic_…`) created on first successful Stripe Checkout, delivered by email and shown in the Customer Portal confirmation. Not derived from email or any PII.
- **Install id:** random UUID generated locally on first run, stored alongside the existing auth-token file under the data dir (0600, atomic write — reuse the `ServerConfig.writePrivateTextFile` pattern, `ServerConfig.swift:140`). **Not** the raw `IOPlatformUUID`: the broker never holds a stable hardware identifier. Device binding = (license_id, install_id) pairs, capped per D6.

### 4.2 The entitlement token (the only artifact)

An Ed25519-signed JSON document (PASETO v4.public or equivalent), verified locally by `PlaidBarServer` with an embedded public key. Proposed claims — this is also the **Entitlement API response shape** required by AND-348 AC#4:

```json
{
  "v": 1,
  "license_id": "lic_8f3a…",
  "plan": "plus",                      // "personal" | "plus"
  "subscription_status": "active",     // "trialing" | "active" | "past_due" | "canceled"
  "institution_limit": 8,              // managed connections allowed by plan (D2)
  "features": ["managed_linking", "premium_insights"],  // premium feature flags
  "trial_ends_at": null,               // ISO8601 or null
  "issued_at":  "2026-06-12T00:00:00Z",
  "expires_at": "2026-07-12T00:00:00Z" // token TTL (30d), NOT the subscription end
}
```

`active_institution_count` is deliberately **not** in the token: the local server computes it from its own SQLite item store (`tokenStore.itemCount()`, already used by `StatusRoutes.getStatus`, `StatusRoutes.swift:20`) and the broker independently knows only its own managed-connection count. The Entitlement API (the local server's view, §4.4) merges token claims + local count.

Why short-TTL tokens instead of embedding subscription expiry: embedded data in signed keys is immutable — poor for renewable subscriptions (Keygen's own offline-licensing guidance). A long-lived license id + periodically refreshed 30-day signed state is the standard resolution.

### 4.3 The wire protocol (privacy-minimal, published in SECURITY.md)

One request type, opportunistic (§5), HTTPS to the broker:

```
POST /v1/entitlement/refresh
{ "license_id": "lic_…", "install_id": "a1b2…", "app_version": "1.0.0" }
→ 200 { <entitlement token as above>, "sig": "ed25519:…" }
```

Hard guarantees, to be stated verbatim in SECURITY.md:

- Exactly these three request fields. No usage data, no feature events, no institution names, no counts, no balances, no hardware identifiers.
- Frequency: at most once per refresh interval (§5); zero steady-state pings while the cached token is fresh; zero ever in demo/BYO-unsubscribed mode.
- The response is a signed statement of "is this license entitled, to what, until when" — nothing else.
- The endpoint is the same host as the link-token broker; it is the **only** non-Plaid network destination in the product.

Trust-signaling option (Sublime Text portable-license precedent): cache the token as human-readable JSON at `~/.plaidbar/entitlement.json` (0600), app reads/refreshes it, user can inspect it. Recommended.

### 4.4 Local Entitlement API (AND-348 AC#4)

New authenticated local endpoint `GET /api/entitlement` on `PlaidBarServer` (registered like `StatusRoutes`, behind `APITokenMiddleware`), returning:

```json
{
  "plan": "plus",
  "subscription_status": "active",
  "entitlement_state": "entitled",     // local machine state, §6
  "institution_limit": 8,
  "active_institution_count": 4,       // tokenStore.itemCount()
  "trial_ends_at": null,
  "features": ["managed_linking", "premium_insights"],
  "token_expires_at": "2026-07-12T00:00:00Z",
  "grace_ends_at": null
}
```

Same hygiene as `/api/status`: readiness/entitlement metadata only — never tokens, account ids, balances, or transactions. The SwiftUI app (`ServerClient` → `AppState`) renders all subscription UX from this one payload.

## 5. Offline grace

Industry baseline for subscription desktop software (retrieved 2026-06-12): JetBrains tolerates 30 days fully offline plus a 1-week post-expiry grace and a perpetual-fallback license; Keygen policies commonly pair a 30-day offline window with ~5-day grace; Sublime Text never locks out at all. Synthesis: *validate opportunistically, cache a signed result, allow 14–30 days offline, degrade rather than hard-lock.*

Proposed policy (D4):

| Parameter | Value | Notes |
|-----------|-------|-------|
| Token TTL | 30 days | One tiny HTTPS request/month at steady state |
| Refresh attempts | At app launch and ~every 7 days, silent, with jitter; piggybacks on no other traffic | Failure is silent while token is fresh |
| Post-expiry grace | 14 days after `expires_at` | Visible countdown begins (§6 UX); tell the user when the clock started and how to fix it |
| Full offline runway | ~44 days worst case | 30d TTL + 14d grace |
| Clock tampering | Ignore (fraud pragmatism, §7) — at most, refuse tokens whose `issued_at` is in the local future | |

## 6. Entitlement states, degraded mode, and UX

### 6.1 Local state machine

```
entitled ──token expiry──▶ grace(14d) ──lapse──▶ degraded
   ▲                          │                      │
   └────── successful refresh ┴──────────────────────┘
over_limit  (orthogonal flag: active managed institutions > institution_limit)
```

`subscription_status` (Stripe truth) and `entitlement_state` (this machine, local) are distinct: `past_due` with a fresh token is still `entitled`; a perfectly paid subscription with 44 days of no network is `degraded` until one refresh succeeds.

### 6.2 Degraded mode = perpetual-fallback analog (D5)

"**Your data stays; live syncing stops.**" In `degraded`:

- All locally cached accounts, balances, transactions, insights remain fully readable. Nothing is deleted, hidden, or exported-only.
- Managed-mode sync/refresh stops (`RefreshService`/`SyncService` skip scheduled work) and managed link creation is refused.
- BYO-keys mode is untouched (D3).
- The app never shows a paywall over existing data — a status banner, not a lock screen.

Precedent already in the codebase: the credential-less setup state (`ServerConfig.credentialsConfigured`, `ServerConfig.swift:43`) — server boots, serves `/health` and `/api/status`, Plaid-backed routes return 503 until configured. Degraded entitlement is the same shape: app fully alive, one capability class disabled with an explanatory payload.

### 6.3 Downgrade & limit-exceeded UX (AND-348 AC#5 partial, AC#6)

Plus → Personal (8 → 3 limit) with 6 active managed institutions:

1. Nothing is deleted. Excess institutions become **paused**: cached data visible, no new syncs.
2. The app presents a picker: "Personal includes 3 connected institutions — choose which stay live." Until chosen, default = most recently synced N stay active.
3. Paused institutions show a distinct status (reusing `ItemConnectionStatus` surface in `/api/items`) with text + icon — never color alone (ACCESSIBILITY.md rule).
4. "Add account" while at limit: button stays visible but disabled-with-reason, with actions "Manage institutions" and "Upgrade to Plus" (opens Stripe Checkout/Portal in the default browser).
5. Server-side, the limit check (§9.1) returns a structured `402`-class error mapped through `UserFacingError` so the popover shows the reason, not a raw HTTP failure.

Grace countdown UX: menu-bar surface stays uncluttered; the popover shows "Subscription check overdue — N days before live sync pauses. Fix: get online / manage billing." Text + icon, no color-only signaling.

## 7. Fraud pragmatism

Consensus from indie-mac practice: copy protection primarily punishes paying customers; pirates run patched builds and never see the activation dialog. The goal is a speed bump plus honesty support, not DRM.

- **Gate the broker, not the binary.** The thing worth protecting is managed link-token issuance — a server-side, per-connection-cost action a cracked client cannot fake. Entitlement enforcement at the broker is simultaneously the strongest and least user-hostile control. A patched app that skips local checks gets… an app that still cannot mint managed link tokens.
- Ed25519-signed tokens: cheap to verify, hard to forge; no obfuscation, no anti-tamper kit, no kernel tricks.
- Soft device cap (D6): 2 installs per license; activating a 3rd auto-deactivates the oldest (CleanShot X pattern) instead of erroring. Abuse beyond that is a support conversation, not an engineering arms race.
- No clock-tamper paranoia, no hardware fingerprint lockdown, no phone-home heartbeats.
- BYO mode ungated (D3): someone determined to avoid paying can already run their own Plaid keys; that user was never revenue, and the path doubles as the local-first escape hatch.

## 8. Cancellation, data retention, disconnect (AND-348 AC#6)

| Event | Behavior |
|-------|----------|
| User cancels (Customer Portal) | Subscription runs to period end (`cancel_at_period_end`); entitlement tokens keep issuing until then |
| Period end reached | Token refresh returns `subscription_status: canceled`; managed sync and managed link creation stop immediately (no extra grace — grace is for *connectivity* failures, not cancellation) |
| Managed Plaid cleanup (D8) | Managed items are removed via `/item/remove` at period end + 7 days — stops VaultPeek's per-connection Plaid billing; the 7-day window lets an accidental cancellation resubscribe without relinking. **Caveat:** under the managed-link architecture doc's proposed device-custody model (its Variant 1), the broker holds no access tokens and cannot call `/item/remove` itself — removal is driven by the local server on next contact, and devices that never return fall to that doc's orphan runbook (its open question O1: administrative removal without the token). Note Plaid bills full months with no proration, so even the 7-day window can cost one extra Item-month |
| Local data | Retained indefinitely — it lives in the user's SQLite/Keychain under `~/.plaidbar/`, and we never reach into their machine. Stated explicitly in UX: "Canceling stops live syncing. Your downloaded data stays on your Mac." |
| Resubscribe after window | New managed links required; local history intact and re-associates by institution |
| Hard delete request | Broker deletes license record + Stripe customer on request (support flow); local data remains the user's to delete |

## 9. Enforcement points (app + server + broker)

### 9.1 Map

| Layer | Location (current code) | Enforces | Authority |
|-------|------------------------|----------|-----------|
| **Hosted broker** | new service (companion doc) | Refuses to mint managed link token when license invalid OR managed-connection count ≥ `institution_limit`; refuses entitlement issuance for dead subscriptions | **Authoritative** — survives any client patching |
| **Local server** | `LinkRoutes.createLinkToken` (`Sources/PlaidBarServer/Routes/LinkRoutes.swift:20`) — today it calls `plaidClient.createLinkToken` unconditionally | Pre-check: verify cached token signature/TTL and `tokenStore.itemCount() < institution_limit` before any network call; structured error otherwise. Also: sync scheduling honors entitlement state | Advisory (defense in depth + good errors; works for BYO consistency if D3 ever changes) |
| **Local server** | new `GET /api/entitlement` (§4.4), alongside `StatusRoutes` | Single source for UI state | n/a |
| **App** | `AppState` / `MainPopover` / `ServerClient` (`Sources/PlaidBar/…`) | Banners, disabled-with-reason controls, picker flows (§6.3) | Cosmetic only — never the security boundary, same principle as today's "app never sees Plaid secrets" split |

Note `createLinkToken`'s update-mode sibling (`createUpdateLinkToken`) is **not** limit-gated: repairing an existing connection must always work, even over-limit — repair doesn't add institutions.

### 9.2 Stripe wiring (AND-348 AC#1–3)

- **Products/prices:** `VaultPeek Personal`, `VaultPeek Plus`; monthly + annual prices each. Stripe Checkout (hosted page, opened in the default browser; the app polls `/api/entitlement` afterward — no embedded web views, no card data near the app).
- **Customer Portal:** card updates, plan switches, cancellation, invoices — zero custom billing UI (AC#2).
- **Webhook → entitlement-state table** (the part Keygen's example repo leaves as an exercise; specced here):

| Stripe event | Broker action |
|---|---|
| `checkout.session.completed` | Create license (`lic_…`), bind to Stripe customer, email key, begin issuing tokens |
| `customer.subscription.created` / `updated` | Update plan / `institution_limit` / `trial_ends_at`; plan changes take effect on next token refresh (≤30d worst case; portal flow should trigger the app to refresh immediately on next launch) |
| `invoice.paid` | Keep `subscription_status: active` |
| `invoice.payment_failed` | `past_due`; Stripe Smart Retries handle dunning; tokens keep issuing during `past_due` (don't punish a flaky card faster than Stripe does) |
| `customer.subscription.deleted` | `canceled`; stop issuing tokens; schedule managed-item removal (§8) |

Stripe processing/Billing/Tax fees: not retrieved for this doc — confirm current rate card at implementation time. Comparison points (retrieved 2026-06-12, all est. from third-party comparisons): Lemon Squeezy ~5% + $0.50, Polar 4% + $0.40, Paddle ~5% + $0.50; Keygen Cloud Dev tier free ≤100 active licensed users.

## 10. Traceability to AND-348 acceptance criteria

| AC | Where designed |
|----|----------------|
| Stripe Checkout supports Personal and Plus | §9.2, D2 |
| Customer Portal: card updates, cancellation, invoices | §9.2 |
| Webhooks update backend subscription status and plan | §9.2 table |
| Entitlement API returns plan, status, institution limit, active count, trial state, premium features | §4.2 (token), §4.4 (local API) |
| Link creation blocked when active institutions exceed plan limit | §9.1 (broker authoritative + local pre-check), §6.3 (UX) |
| Cancellation stops future sync/linking; data retention/disconnect defined | §8 |

## 11. Sources (all retrieved 2026-06-12)

- Keygen: pricing, Stripe integration + example repo, offline-license docs, validate-key/activation docs — keygen.sh/pricing, keygen.sh/integrate/stripe, keygen.sh/docs/choosing-a-licensing-model/offline-licenses
- Lemon Squeezy License API + Stripe acquisition / Managed Payments status — docs.lemonsqueezy.com/api/license-api, lemonsqueezy.com/blog/stripe-acquires-lemon-squeezy, lemonsqueezy.com/blog/2026-update
- Polar license keys (unauthenticated validate) — polar.sh/docs/api-reference/customer-portal/license-keys/validate
- JetBrains subscription licensing (30-day offline, 1-week grace, perpetual fallback) — sales.jetbrains.com/hc/en-gb/articles/206544679
- Sublime Text portable license keys — sublimetext.com/docs/portable_license_keys.html
- Perpetual-fallback license catalog (Sketch, TablePlus, Nova, CleanShot X, …) — github.com/vitorgalvao/perpetual-fallback-licenses; cleanshot.com/faq (auto-deactivate oldest device)
- Anti-piracy pragmatism — tyler.io/2011/05/18/experimenting-with-piracy, MacRumors thread on Little Snitch piracy
- License-manager survey (purchase-linked vs standalone keys) — Alberto Gallego, dev.to/albertogalca_58
