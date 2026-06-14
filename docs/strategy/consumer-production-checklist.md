---
title: Consumer Plaid Integration — Production Readiness Checklist
status: owner-gated
linear: [AND-347, AND-348, AND-349, AND-350]
date: 2026-06-13
---

# Consumer Plaid Integration — Production Readiness Checklist

**Owner-only runbook.** This is the concrete, sequenced list of what Felipe (the
owner) must do to take the consumer (Hosted Link) integration live — real
end-users link banks **without supplying their own Plaid credentials**, funded by
a Stripe subscription, through a stateless hosted bridge that stores **no** user
financial data. The non-gated software foundation for this track already exists
in the tree (deployment seam, credential-resolver seam, entitlement middleware
shell, entitlement model — see "What is already built" below). Everything in this
checklist is gated behind `docs/strategy/approval-gates.md` and requires owner
action: production credentials, dashboard configuration, Plaid approval, hosted
infrastructure, and live billing. **Do not let an agent perform any step here.**

Design source of truth, do not duplicate it here:
`docs/strategy/managed-link-architecture.md` (broker + blind proxy),
`docs/strategy/subscription-entitlements.md` (Stripe + Ed25519 entitlements, D1–D10),
`docs/strategy/approval-gates.md` (what must be approved before code).

---

## What is already built (non-gated foundation, no action needed)

These shipped as inert seams; selecting them changes no runtime behavior until
the steps below are done. They exist so the gated work drops in without
re-architecting:

- **Deployment seam** — `DeploymentMode { .local | .hostedBridge }` +
  `RemoteBridgeConfig` placeholder (`Sources/PlaidBarServer/Config/DeploymentMode.swift`).
  Read from `PLAIDBAR_DEPLOYMENT`; defaults to `.local` (today's BYO-keys path),
  byte-for-byte unchanged. `RemoteBridgeConfig` holds no live endpoints.
- **Credential-resolver seam** — `AccessTokenResolver` protocol with the
  Keychain-backed local impl (the only one wired) and an inert request-supplied
  stub that fails closed (`Sources/PlaidBarServer/Auth/AccessTokenResolver.swift`).
- **Entitlement middleware shell** — `EntitlementMiddleware` between
  `APITokenMiddleware` and `SetupStateMiddleware`; always `.allow`, enforces
  nothing (`Sources/PlaidBarServer/Middleware/EntitlementMiddleware.swift`).
- **Entitlement model** — `Entitlement` / `EntitlementTier` / `EntitlementDecision`
  (`Sources/PlaidBarCore/Models/Entitlement.swift`), the verified-token shape from
  the entitlements doc §4.2.

---

## Phase 0 — Strategy gates (no money, no infra yet)

Nothing below may begin until these `approval-gates.md` gates are signed with an
approval record:

1. **Plaid pricing/COGS gate (AND-344)** — replace estimate-only rates with a
   dated dashboard or sales quote (Transactions, Balance, Hosted Link delivery,
   `/item/remove` billing shutoff, PAYG vs committed, Growth minimums).
2. **Managed broker go/no-go (AND-347)** — accept the privacy-promise change:
   managed financial data *transits* VaultPeek's stateless proxy but is *never
   stored* there; access tokens stay on the device (Variant 1, architecture doc
   §5.3).
3. **Stripe entitlements decisions D1–D10 (AND-348)** — in particular D1 (Stripe
   + DIY Ed25519 signer), D3 (BYO stays ungated), D4 (30-day TTL / 14-day grace),
   D8 (cancellation retention + 7-day reconnect), D10 (rename timing).
4. **Pricing + privacy copy (AND-349 + cross-doc)** — Personal/Plus caps and
   prices, BYO-free promise, amended `SECURITY.md` / `docs/privacy.md` wording.

---

## Phase 1 — Plaid production access (owner-only; weeks of lead time)

5. **Open a Plaid production account** under the **VaultPeek** name (resolve the
   rename first — D10 / open question O5 — so you do not undergo Plaid review
   twice). Capture `PLAID_CLIENT_ID` and the **production** `PLAID_SECRET`; these
   are the *organization* credentials that live **only** on the hosted bridge,
   never in any user's app or local server.
6. **Request Plaid production approval.** Complete the Plaid application review:
   product questionnaire, company/use-case description, security questionnaire
   (point to `SECURITY.md` and the no-storage blind-proxy posture), and the data
   handling / data minimization answers (registry-only storage; no financial
   payloads persisted). Expect back-and-forth; this is the long pole.
7. **Enable Hosted Link** for the production application in the Plaid dashboard
   (the consumer flow opens Plaid's hosted page; no embedded Link SDK).
8. **Register production redirect / allowed URIs** in the Plaid dashboard:
   - The bridge HTTPS completion redirect (replaces today's
     `http://localhost:8484/oauth/callback`; localhost is a sandbox-only
     affordance — architecture doc §5.5).
   - Any OAuth-institution redirect URIs Plaid requires for prod.
   - Confirm the `vaultpeek://link/complete` deep-link bounce / associated-domains
     fallback (open question O2).
9. **Resolve open question O1 with Plaid:** can an Item be administratively
   removed (to stop per-Item billing) **without** the access token, given device
   custody? The answer decides the orphan runbook vs forcing the token-vault
   variant. Document the answer in `managed-link-architecture.md` §5.3.

## Phase 2 — Provision the hosted bridge (owner-only infra + secrets)

10. **Stand up the control plane** (the ~6-endpoint broker: link-token mint,
    public-token exchange, item registry, removal, entitlement issuance, Stripe
    webhook). It stores **only** identity, entitlement, device public keys, and an
    item registry (`user_id, item_id, institution_id, status, timestamps`). Never
    transactions, balances, account numbers, or tokens (architecture doc §5.2).
11. **Stand up the blind proxy** (data plane: stateless, no DB, no body logs;
    injects the org secret; enforces the endpoint allowlist `/transactions/sync`,
    `/accounts/get`, `/item/remove`; validates managed-item binding). Open-source
    it — openness is the trust mechanism (architecture doc §5.4, §13).
12. **Store the Plaid org secret in KMS**, reachable only by the two bridge
    services; rotation on schedule and on incident. No human reads it in
    plaintext in normal operation (architecture doc §9).
13. **Point the app/server at the bridge** via config/env (these are the
    placeholders the foundation already reads): set `PLAIDBAR_DEPLOYMENT=hosted-bridge`,
    `PLAIDBAR_BRIDGE_CONTROL_PLANE_URL`, `PLAIDBAR_BRIDGE_DATA_PLANE_URL`, and
    `PLAIDBAR_ENTITLEMENT_PUBLIC_KEY` (the Ed25519 *public* key only). Until the
    gated client code lands these are inert; they activate nothing on their own.

## Phase 3 — Stripe billing + entitlement signer (owner-only; live money)

14. **Create Stripe products/prices** for Personal and Plus (no unlimited, no
    lifetime — AND-349). Decide tax posture (Stripe Tax vs MoR — D9).
15. **Wire Stripe Checkout** (browser-based sign-in + purchase; the app polls for
    the entitlement to land — architecture doc §7, "plan-before-link").
16. **Wire the Stripe webhook receiver** in the control plane with **signature
    verification + idempotent processing** (threat T9). On
    `checkout.session.completed` / subscription lifecycle events, issue/refresh
    the entitlement.
17. **Stand up the Ed25519 entitlement signer** co-located in the broker (D1
    pattern C): Stripe webhook → Ed25519/PASETO-signed entitlement token
    (`tier`, `institution_limit`, `items_used`, `subscription_status`,
    `expires_at`; 30-day TTL — entitlements doc §4.2). Keep the **private** key
    in KMS; embed only the **public** key in the client (step 13).
18. **Implement cancellation cleanup (D8):** at period end + 7-day reconnect
    window, drive `/item/remove` (device-driven under Variant 1) and run the
    orphan runbook for devices that never return — every lingering Item is live
    Plaid COGS.

## Phase 4 — Activate enforcement + privacy copy (owner-only)

19. **Turn on entitlement enforcement** in the (now-gated) client code:
    `EntitlementMiddleware.evaluate` verifies the signed token, TTL/grace, and
    managed-item count for `.hostedBridge` mode, returning `402` on
    limit/entitlement failures. BYO/`.local` stays ungated (D3) — the shell
    already short-circuits `.local` to `.allow`.
20. **Swap the read-route token source** to the request-supplied resolver for
    `.hostedBridge` (device supplies its custodied token; proxy injects the org
    secret). The local Keychain path is unchanged for `.local`.
21. **Publish the amended privacy promise** (`SECURITY.md`, `docs/privacy.md`,
    marketing): distinguish BYO local-only mode from managed mode — what the
    broker stores, what transits it, what is never stored, what happens on
    cancellation (cross-doc gate).

## Phase 5 — Pre-launch verification (owner-only)

22. **End-to-end sandbox dry-run** of the full bridge path (link → exchange →
    sync → remove) before pointing at production.
23. **Verify the no-storage / no-body-log claim** on the live blind proxy
    (inspect logs; confirm metadata-only access logs, 30-day retention).
24. **Confirm billing shutoff:** removing an institution stops its Plaid meter;
    cancellation removes managed Items within the documented window.
25. **Security review of the bridge** against the threat model (architecture doc
    §10): org-secret blast radius, link-session CSRF (one-time state + TTL +
    single-use device-signed claim), entitlement bypass, webhook forgery.

---

## Owner-gated items (never auto-implemented)

- Deploying the hosted bridge (control plane + blind proxy + KMS).
- Entering / storing production Plaid credentials (`PLAID_CLIENT_ID`, prod
  `PLAID_SECRET`).
- Obtaining Plaid production approval.
- Registering production redirect / allowed URIs and enabling Hosted Link in the
  Plaid dashboard.
- All live Stripe billing: products/prices, Checkout, webhook, the Ed25519
  entitlement signer and its private key.
- Publishing the amended privacy promise.

These are listed in `gatedItems` of the implementing PR and must carry an
`approval-gates.md` approval record before any related code merges.
