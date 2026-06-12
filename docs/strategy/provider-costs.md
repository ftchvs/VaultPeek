---
title: Provider Cost Assumptions — Plaid Production Pricing
status: proposed
linear: [AND-344]
date: 2026-06-12
---

# Provider Cost Assumptions: Plaid Production Pricing

**Design/research document only. No implementation.** This doc establishes the provider-cost (COGS) assumptions for the VaultPeek consumer subscription exploration: what Plaid actually bills for, what our app actually calls, cost per linked Item per month under low/base/high scenarios, break-even versus candidate subscription price points, the sandbox→production path, and risks.

All dollar figures are labeled with retrieval date. **Plaid publishes no per-product price list** — every dollar figure below that is not a plan-structure fact is an **ESTIMATE** from third-party negotiated-contract data and must be validated with a Plaid sales quote before any pricing decision is finalized.

---

## 1. AND-344 acceptance criteria coverage

| Acceptance criterion | Status |
|---|---|
| Walk through Plaid Trial/Production access until pricing page is visible before submission | **Open — requires human dashboard access.** Direct fetches of `support.plaid.com` return 403; the Plaid Dashboard "Launch Center" (dashboard.plaid.com/developers/launch-center) gives personalized requirements and self-serve quotes. Action item in §9. |
| Capture pricing for Transactions, Recurring Transactions, Balance, Liabilities, Investments, Auth, Identity, Hosted Link delivery | §3 (billing model, official) + §4 (dollar estimates, third-party) |
| Document whether pricing is per Item, per account, one-time, subscription, or per request | §3 |
| Update the financial model with low/base/high provider cost scenarios | §5–§6 define the scenarios; any sibling financial-model doc in `docs/strategy/` should consume these numbers |
| Confirm billing behavior when Items are removed, users cancel, or access tokens remain active | §7 |
| No screenshots containing private account details or production secrets | Complied — this doc contains no screenshots, credentials, account IDs, or balances |

---

## 2. What VaultPeek actually calls today (grounded in code)

Product-mix assumptions below are derived from the real server client, not aspiration. Source: `Sources/PlaidBarServer/Plaid/PlaidClient.swift`, `Sources/PlaidBarServer/Routes/AccountRoutes.swift`, `Sources/PlaidBar/App/AppState.swift`, `Sources/PlaidBarCore/Utilities/Constants.swift` (read 2026-06-12 in this worktree).

| Plaid endpoint | Where called | Billing class | Steady-state frequency |
|---|---|---|---|
| `/link/token/create` with `products: ["transactions"]`, Hosted Link (`PlaidClient.swift:45`) | Link + relink flows | Free; initializes **Transactions subscription** on the Item | Once per link/relink |
| `/item/public_token/exchange` | Link completion | Free | Once per link |
| `/accounts/get` | `refreshAccounts()` → background refresh loop (`AppState.swift:678`) | **Free** (cached balances) | Every 15 min (`backgroundRefreshInterval`) |
| `/transactions/sync` | `syncTransactions()` (`PlaidClient.swift:132`) | Covered by the **Transactions monthly subscription** | Every 30 min (`transactionSyncInterval`), up to `maxTransactionSyncPages = 100` |
| `/accounts/balance/get` | `getBalances()` route exists; app-side `refreshBalances()` (`AppState.swift:699`) **has no callers** — no UI or timer invokes it | **Per-request fee** | **Zero** today |
| `/item/remove` | Unlink flow (`PlaidClient.swift:143`) | Free; **stops the Transactions meter** | On user unlink |

Three load-bearing cost findings:

1. **The current product mix is "Transactions subscription only."** Link tokens request only `transactions`; no Auth, Identity, Liabilities, or Investments products are initialized, so no one-time or additional subscription fees accrue. Real-time balances come for free via `/accounts/get` (refreshed server-side by Plaid alongside transactions sync).
2. **The billed Balance endpoint is currently dead code on the billing path.** The `/api/accounts/balances` server route is wired, but nothing in the app calls it. Keep it that way by default; if a "force-refresh balances now" button ships, every press is a per-request fee × number of Items.
3. **Recurring detection is local, not bought.** `Sources/PlaidBarCore/Utilities/RecurringDetector.swift` computes recurring streams from synced transactions on-device. VaultPeek does **not** need Plaid's Recurring Transactions subscription (a separate per-Item monthly fee). This is a deliberate cost-avoidance assumption — preserve it.

Hosted Link note: the code uses Hosted Link with a 30-minute URL returned to the local app (`urlLifetimeSeconds: 30 * 60`), not SMS/email delivery. Per Plaid's billing docs (retrieved 2026-06-12), the Hosted Link one-time fee applies to sessions **delivered via SMS/email**; URL-handoff sessions appear not to incur it. **Verify in the dashboard quote — low confidence.**

---

## 3. Plaid billing model (official, retrieved 2026-06-12)

Source: https://plaid.com/docs/account/billing/ and https://plaid.com/pricing/. Plaid bills **per Item (per bank connection), not per user**. A user linking 3 institutions = 3 Items = 3× fees.

| Product | Billing model | Relevant to VaultPeek? |
|---|---|---|
| **Transactions** | **Monthly subscription per Item.** Bills while a valid `access_token` exists — even with zero API calls, even if calls are failing. No mid-month proration. `/transactions/refresh` is a separate per-request fee. | **Yes — the dominant COGS line.** |
| **Recurring Transactions** | Monthly subscription per Item | No — detected locally (§2) |
| **Balance** (`/accounts/balance/get`) | Per successful request | Not on steady-state path; only if an on-demand refresh feature ships |
| **Liabilities** | Monthly subscription per Item | Not today; candidate future product (credit/loan detail) |
| **Investments** | **Two** monthly subscriptions per Item (Holdings + Investments Transactions) | Not today; candidate future product |
| **Auth** | One-time fee per Item | No — VaultPeek doesn't move money |
| **Identity** | One-time fee per Item | No |
| **Hosted Link delivery** | One-time fee per SMS/email-delivered session | Likely no (URL handoff, §2) — verify |
| `/accounts/get`, Item endpoints, Institutions endpoints | Free | Yes — our refresh loop |

Plan structure (official): **Pay-as-you-go** (no minimum, month-to-month, some products excluded), **Growth** (12-month commitment, discounted rates), **Custom** (negotiated). A support-article summary claims Growth has a "$100/month minimum + three-month commitment," which **conflicts** with the official 12-month language — treat as low-confidence/unverified.

---

## 4. Dollar figures — ALL ESTIMATES (retrieved 2026-06-12)

Plaid's rates are quote-only. Two independent estimate sets disagree materially — that spread is itself a signal of how negotiable pricing is.

| Product | Vendr (38 contracts) — ESTIMATE | Monetizely — ESTIMATE | Blog-tier aggregate — LOW-CONFIDENCE ESTIMATE |
|---|---|---|---|
| Transactions (per Item/mo) | $0.30–$0.60 | ~$1.50 at low volume | $1.50–$2.00 (PAYG, 0–1k Items) → $0.30–$0.60 (50k+, negotiated) |
| Balance (per call) | $0.05–$0.15 | $0.30–$0.50 | — |
| Auth (one-time) | $0.10–$0.25 | $0.30–$1.00 | — |
| Identity (one-time) | $0.15–$0.30 | $1.00–$1.50 | — |
| Committed-plan minimums | $1,000–$3,000/mo small-scale | ~$500/mo baseline | ~$500/mo at 1k–10k Items; ~$3k/mo at 10k–50k |

Sources: https://www.vendr.com/marketplace/plaid; https://www.getmonetizely.com/articles/plaid-vs-yodlee-how-much-will-financial-data-apis-cost-your-fintech; costbench.com and similar (all retrieved 2026-06-12). Vendr also reports median annual contract value $9,000/yr, negotiated discounts of 15–40%, and hidden costs (implementation $5k–$25k+, premium support $10k–$50k/yr) — all ESTIMATES.

**Working planning range: Transactions ≈ $0.30–$1.50 per Item per month**, depending on volume and commitment.

---

## 5. Cost per linked Item/month — low/base/high scenarios

Scenario rates (Transactions subscription only, per §2 product mix; all ESTIMATES, retrieved 2026-06-12):

| Scenario | Rate per Item/mo | Basis |
|---|---|---|
| **Low** | **$0.45** | Midpoint of committed/negotiated range ($0.30–$0.60); plausible at 10k+ Items with a Growth/Custom contract |
| **Base** | **$1.00** | Early committed plan or mid-tier PAYG; midpoint of the estimate sets |
| **High** | **$1.50** | PAYG list at launch volume (Monetizely + blog-tier convergence) |

Cost per **user** = Items/user × rate. Engaged PFM users link ~2–3 institutions (ESTIMATE — industry rule of thumb; instrumenting actual Items/user distribution is a prerequisite for any paid launch):

| Items per user | Low ($0.45) | Base ($1.00) | High ($1.50) |
|---|---|---|---|
| 1 | $0.45 | $1.00 | $1.50 |
| 2 | $0.90 | $2.00 | $3.00 |
| **3 (planning assumption)** | **$1.35** | **$3.00** | **$4.50** |
| 4 | $1.80 | $4.00 | $6.00 |

Adders not in the table (all zero under the current code path): Balance per-call fees if an on-demand refresh feature ships ($0.05–$0.50/call, ESTIMATE); Liabilities or Investments subscriptions if those products are added (each is another per-Item monthly line; Investments is two).

---

## 6. Break-even vs. subscription price points

Assumptions: 3 Items/user (planning assumption); Stripe standard card fee of 2.9% + $0.30 per charge (Stripe's long-published standard rate — **not re-verified on 2026-06-12; confirm before finalizing**); monthly billing; ignores Apple App Store cut (assume direct Stripe checkout for a non-MAS distribution), refunds, support, and infra for the link-token broker.

Net after Stripe, minus Plaid COGS at 3 Items/user → gross margin on list price:

| Monthly price | Net after Stripe | Low COGS $1.35 → margin | Base COGS $3.00 → margin | High COGS $4.50 → margin |
|---|---|---|---|---|
| $4.99 | $4.55 | $3.20 (64%) | $1.55 (31%) | **$0.05 (~1% — break-even)** |
| $7.99 | $7.46 | $6.11 (76%) | $4.46 (56%) | $2.96 (37%) |
| $9.99 | $9.40 | $8.05 (81%) | $6.40 (64%) | $4.90 (49%) |
| $14.99 | $14.26 | $12.91 (86%) | $11.26 (75%) | $9.76 (65%) |

Break-even linked-Item count per user (net revenue ÷ rate — beyond this, the user is unprofitable):

| Monthly price | Low ($0.45) | Base ($1.00) | High ($1.50) |
|---|---|---|---|
| $4.99 | 10 Items | 4 Items | 3 Items |
| $7.99 | 16 Items | 7 Items | 4 Items |
| $9.99 | 20 Items | 9 Items | 6 Items |
| $14.99 | 31 Items | 14 Items | 9 Items |

Readings:

- **$4.99/mo does not work at launch.** At PAYG-estimate rates, a 3-bank user is break-even before a single dollar of infra, support, or development cost. A power user with 5 Items is underwater.
- **$7.99–$9.99/mo is the viable launch band** under base/high COGS, provided the tier **caps linked Items** (e.g., 3–5 included, more on a higher tier). An uncapped "unlimited banks" promise at a fixed price is a direct margin leak because Plaid bills per Item.
- **Negotiating committed rates is worth ~30 points of margin** ($4.50 → $1.35 at 3 Items) — but committed plans carry $500–$3,000/mo minimums (ESTIMATE), i.e., roughly 150–1,000 paying users before the minimum is covered at base rates. Launch on Pay-as-you-go (no minimum, official), renegotiate at volume.
- **BYO-keys users cost VaultPeek $0 in Plaid fees.** Post-2026-04-15 Plaid signups get the free Trial plan (10 Production Items, Transactions/Balance/Liabilities/Investments bundled, most OAuth institutions including Chase/BofA/Wells Fargo) — arguably sufficient forever for a single-user local-first app. **This weakens the cost argument for managed linking; the managed tier's value is convenience and approval-friction removal, not price.** Price and message it accordingly.

---

## 7. Billing behavior on removal, cancellation, and idle tokens (official, retrieved 2026-06-12)

These are product requirements, not just accounting trivia:

1. **An Item bills until `/item/remove` is called.** The Transactions subscription charges "even if no API calls are made for the Item or API calls cannot be successfully made for the Item." A user who cancels their VaultPeek subscription but whose Items are never removed bills VaultPeek **forever**.
2. **No proration.** Items created or removed mid-month bill for the full month.
3. **Broken Items still bill.** An Item in a failed/login-required state costs the same as a healthy one until removed. Stale-Item reaping (e.g., remove Items unrecoverable for N days, after user notice) is a COGS control, not just hygiene.
4. **Design consequence (for the future design doc — no implementation here):** the managed-tier cancellation flow must call `/item/remove` for every Item at entitlement lapse (the entitlements doc proposes lapse + a 7-day reconnect courtesy window, its D8 — acceptable, but with no proration even a short window can incur one extra full Item-month), with a reconciliation sweep for Items orphaned by failed webhooks or uninstalls. The existing `removeItem` path in `PlaidClient.swift:143` is the right primitive; the gap is lifecycle orchestration tied to subscription state.
5. **Trial-plan gotcha:** `/item/remove` does **not** free slots against the 10-Item Trial cap, and subscription products added during Trial begin billing immediately upon upgrade to paid.

---

## 8. Sandbox → production path

Official sources: https://plaid.com/docs/sandbox/, https://plaid.com/docs/account/billing/, https://plaid.com/docs/launch-checklist/ (now "Launch Center"), retrieved 2026-06-12.

| Stage | Cost | Limits | Gate to next stage |
|---|---|---|---|
| **Sandbox** | Free, unlimited | Test Items only (`user_good`/`pass_good`); generic OAuth; no institution quirks | None — current `./Scripts/run.sh --sandbox` flow |
| **Trial plan** (US/Canada teams created ≥ 2026-04-15) | Free | **10 Production Items lifetime** (removal doesn't free slots); 8 bundled products; most OAuth institutions incl. Chase/BofA/Wells Fargo **without** the security questionnaire | Identity verification; "Personal use" signup path exists; auto-approved for most, else 2–3 business days |
| **Full Production (PAYG)** | Per-Item/per-request fees, **no minimum** (official) | None relevant | Application + company profile, Plaid MSA, **security questionnaire** (required for Chase et al. outside Trial); some OAuth institutions take 1–2 extra days after enablement |
| **Growth/Custom** | Committed, discounted | 12-month commitment (official page) | Sales negotiation |

Notes for VaultPeek:

- **Individuals are eligible** — "you can put your own name as the legal entity name" (support-article summary, retrieved 2026-06-12). The Trial plan is the sanctioned path for BYO-keys users.
- For the **managed** model, VaultPeek (the company) holds the Plaid relationship: VaultPeek signs the MSA, completes the security questionnaire, and under the Section 1033 authorized-third-party regime is the regulated "authorized third party" — not the end user. This is a compliance posture change, independent of dollars.
- EU/UK require a separate compliance process (≥1 week lead, support ticket for non-European businesses). US-first launch assumption.

---

## 9. Risks

| Risk | Severity | Notes / mitigation |
|---|---|---|
| **Pricing opacity** — no public price list; every figure in §4–§6 is third-party estimate; Vendr and Monetizely disagree by 3–6× on some lines (e.g., Balance per-call) | High | **Get a real dashboard/sales quote before any pricing decision** (open AND-344 criterion). Treat §5 scenarios as brackets, not point estimates. |
| **Committed-plan minimums** — $500–$3,000/mo (ESTIMATE) before discounted rates apply | High at launch | Launch PAYG (no minimum, official); renegotiate at ~150–1,000 paying users. |
| **Per-Item billing × uncapped linking** — margin scales inversely with user enthusiasm | High | Cap included Items per tier; meter and surface Items/user from day one. |
| **Items bill forever until removed** — cancellation/orphan leakage | Medium | `/item/remove` wired into cancellation + reaper sweep (§7). |
| **Pricing-change risk** — Plaid repriced its tiers as recently as 2026-04-15 (Trial plan introduction); quotes and plan structures move | Medium | Re-verify before launch; date-label every figure (done here). |
| **Conflicting Growth-plan terms** — 12-month vs. "$100/mo + 3-month" claims | Low | Resolve during sales conversation. |
| **Hosted Link fee ambiguity** — URL-handoff vs SMS/email delivery | Low | Confirm in quote (§2). |
| **Per-call Balance feature creep** — a future "refresh now" button silently converts a free path into a metered one | Medium | §2 finding: keep `refreshBalances()` unwired by default; any on-demand refresh needs rate-limiting and a COGS line. |
| **Trial-cap dead end for BYO users** — 10 lifetime Items; heavy relinking burns slots permanently | Low–Medium | Document for BYO users; relink-in-place (update-mode Link token, already implemented in `createUpdateLinkToken`) does not create a new Item. |

**Open actions (human, not doc):** (1) create/walk a Plaid team through the Dashboard Launch Center to the self-serve pricing/quote screen and capture actual PAYG rates for Transactions + Balance — without screenshotting secrets; (2) confirm Hosted Link URL-handoff fee treatment; (3) confirm Growth minimum/commitment terms.

---

## 10. Tension with the local-first promise

VaultPeek's current promise: **no hosted backend, no telemetry, all data stays on the user's machine.** A consumer subscription with managed bank linking cannot be delivered with zero hosted footprint — three hosted components are unavoidable, and this doc's cost model assumes them:

1. **Link-token broker** — managed users don't bring Plaid keys, so VaultPeek's `client_id`/`secret` must live in a hosted service that creates Link tokens and exchanges public tokens. Under the managed model VaultPeek is also the Plaid-registered entity (§8).
2. **Entitlement check** — Stripe-billed tiers require a hosted endpoint to verify subscription status.
3. **Stateless sync relay ("blind proxy")** — managed-mode data-plane calls need the same `secret`, so they are relayed through a memory-only, no-persistence proxy (managed-link architecture doc §5.4).

**Minimal hosted footprint (proposed constraint for all consumer-tier designs):** the hosted service does link-token brokering, entitlement verification, and stateless sync relaying **only**. Access tokens are delivered to and stored by the *local* PlaidBarServer (Keychain, as today); balances, transactions, and account identities are **never stored on VaultPeek's servers**. One correction the companion managed-link architecture doc establishes: in managed mode, `/transactions/sync` and `/accounts/get` traffic **cannot** flow directly device→Plaid, because every Plaid data-plane call requires VaultPeek's `secret` and Plaid forbids shipping it in client software — so that traffic transits a stateless, memory-only "blind proxy" that injects credentials and persists/logs nothing (BYO-keys traffic remains direct device→Plaid). The hosted service sees: a pseudonymous user ID, subscription state, and Item *count* (needed for tier caps and Plaid invoice reconciliation) — nothing financial at rest.

Two honest caveats this section must carry:

- **A broker-only architecture does not reduce Plaid billing exposure.** Plaid fees scale with connected Items regardless of whether financial data transits VaultPeek's servers. Minimal footprint is a privacy posture, not a cost lever.
- **Per-Item billing requires counting Items per user**, which is itself a (minimal) form of usage telemetry. The privacy story must say so explicitly rather than implying the hosted service knows nothing.

For BYO-keys users, nothing changes: no hosted components, no Plaid COGS to VaultPeek, the local-first promise holds in full.

---

## Sources

Official (retrieved 2026-06-12): plaid.com/pricing, plaid.com/docs/account/billing, plaid.com/docs/sandbox, plaid.com/docs/launch-checklist (→ Launch Center), plaid.com/docs/link/oauth, plaid.com/developer-policy. Support articles (support.plaid.com, via search summaries — direct fetch 403): 39994173227159 (Trial plan), 16110502116887 (pricing plans), 16194632655895 (cost models), 15769780649751 (OAuth access). Estimates (retrieved 2026-06-12): vendr.com/marketplace/plaid (38 contracts), getmonetizely.com Plaid-vs-Yodlee analysis, costbench.com (low confidence). Code (read 2026-06-12): `Sources/PlaidBarServer/Plaid/PlaidClient.swift`, `Sources/PlaidBarServer/Routes/AccountRoutes.swift`, `Sources/PlaidBar/App/AppState.swift`, `Sources/PlaidBar/Services/ServerClient.swift`, `Sources/PlaidBarCore/Utilities/Constants.swift`, `Sources/PlaidBarCore/Utilities/RecurringDetector.swift`.
