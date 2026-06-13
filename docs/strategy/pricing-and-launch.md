---
title: VaultPeek Pricing Bundles, Launch Copy, and Consumer Strategy Summary
status: proposed
linear: [AND-349, AND-343]
date: 2026-06-12
---

# VaultPeek Pricing & Launch Strategy

> **Design/research document only. Nothing in this doc is implemented, and nothing should be implemented from it until the open decisions in §9 are resolved.** All pricing figures retrieved 2026-06-12 unless noted; third-party Plaid cost figures are **estimates** (Plaid publishes no price list).

Cross-doc implementation approval gates for AND-344 through AND-349 live in
[`approval-gates.md`](approval-gates.md).

---

## 1. Strategy summary (AND-343)

VaultPeek (today: PlaidBar) is a local-first macOS menu bar dashboard for bank data. The current product requires bring-your-own Plaid credentials — a hard ceiling on mainstream adoption. The consumer direction explored here adds a **managed bank-linking subscription**: the user pays VaultPeek through Stripe, VaultPeek holds the Plaid (or Teller) relationship and pays provider fees, and the Mac client stays local-first.

Core conclusions:

1. **Two tracks, explicitly separated.** Track A is the existing local-first, BYO-keys product — it stays free and fully local, and is itself viable indefinitely on Plaid's free Trial plan (10 Items for US/Canada teams created on/after 2026-04-15). Track B is a managed consumer SaaS with tiered subscriptions. Track B never replaces Track A; Track A is the trust anchor that makes Track B's privacy story credible.
2. **Minimal hosted footprint.** Managed linking and Stripe entitlements require *some* hosted component, which is in direct tension with the current literal promise ("no hosted backend, no telemetry, data stays on your machine"). The resolution is a **link-token broker + entitlement check, plus a stateless sync relay** — financial data is NEVER *stored* on VaultPeek servers. Whether sync traffic can avoid *transiting* a VaultPeek service entirely is settled in the companion managed-link architecture doc: with Plaid it cannot (every data-plane call requires VaultPeek's `secret`, which Plaid forbids shipping in client software), so managed-tier sync passes through a stateless, memory-only "blind proxy" that persists and logs nothing (see §2).
3. **Provider costs are recurring and per-Item**, so pricing must bundle provider cost into plans with institution caps — no unlimited links, no lifetime deals, no free live-bank tier (see §6).
4. **Recommended tiers:** Free Demo, Personal ($79/yr or $9/mo, up to 3 institutions), Plus ($129/yr early-access annual or $15/mo, up to 8 institutions; rising to $149/yr once premium features mature), with a later extra-institution add-on (see §4).
5. **Plaid's real rates are sales-gated.** All margin math below uses third-party estimates with a wide spread ($0.30–$1.50/Item/mo for Transactions). **A Plaid sales quote — and a Teller comparison — must be obtained before any price is published.** Teller's more transparent public pricing should be evaluated in the companion provider doc; no Teller figures were independently verified in this research pass.

## 2. The local-first tension (hard constraint, stated up front)

Today's promise, verbatim from the product's positioning: *no cloud backend, no telemetry, all data stays on the user's machine.* The architecture enforces it — the SwiftUI app talks only to `127.0.0.1:8484`; the local server (`Sources/PlaidBarServer/`) holds Plaid tokens in macOS Keychain and Plaid item records in local SQLite.

A managed consumer tier breaks the *literal* version of that promise in three places, and the docs and launch copy must say so honestly:

| Hosted component | Why it is unavoidable | What it sees | What it must NEVER see |
|---|---|---|---|
| **Link-token broker** | Plaid forbids `client_secret` in distributed clients; in the managed model VaultPeek (not the user) holds the Plaid relationship, signs the MSA, and completes the security questionnaire | That an enrollment happened; institution ID; Plaid `item_id`; the public→access token exchange in transit | Transactions, balances, account numbers, holdings — the access token is delivered to the **user's local server** and stored in **their** Keychain |
| **Stateless sync relay ("blind proxy")** | Plaid data-plane calls (`/transactions/sync`, `/accounts/get`) require VaultPeek's `secret`, which cannot ship in client software (Plaid policy) — so managed-mode sync cannot go device→Plaid directly (managed-link architecture doc §5.4) | Sync requests/responses **in transit only** — memory-only, no database, no body logging; relay code open-sourced | Any financial data **at rest** — it stores nothing, ever |
| **Entitlement service (Stripe)** | Subscription state must be verifiable | Email, plan, payment status, count of linked institutions (for cap enforcement) | Any financial data whatsoever |

Architectural consequence accepted as a cost of the model: **a link-token-broker-only architecture does not reduce Plaid billing exposure.** Plaid bills VaultPeek per Item per month regardless of whether data transits VaultPeek's servers (plaid.com/docs/account/billing/, retrieved 2026-06-12). The broker minimizes the *privacy* footprint, not the *cost* footprint.

Amended public promise (draft, see launch copy §7; wording pending D1 and must stay consistent with the blind-proxy disclosure in the managed-link architecture doc §11): *"We never store your financial data. We run exactly one small service: it connects you to your bank, checks your subscription, and relays your sync traffic to the bank network without ever writing it down — the relay's code is open source. Everything you see — your balances, transactions, history — is stored only on your Mac."*

**Decision gate (AND-343 acceptance criterion):** no hosted backend or non-local data flow may be implemented until Felipe explicitly approves the broker architecture and the amended promise (§9, D1).

## 3. What exists in code today (grounding)

Read from `/Users/ftchvs/Developer/pb-worktrees/consumer-docs/Sources` on 2026-06-12:

- **Demo mode already ships.** `swift run PlaidBar --demo` runs on local fixtures with zero Plaid calls (`Sources/PlaidBar/App/PlaidBarApp.swift`, `AppState.swift`). The Free Demo tier is therefore **already built** — it costs nothing to offer and nothing per user.
- **No entitlement or institution-cap enforcement exists anywhere.** `LinkRoutes` will mint a link token for any authenticated local request; `TokenStore` has no item cap. Tier caps (3/8 institutions) are net-new work on both server and broker sides.
- **The billable-endpoint split already matters.** `PlaidClient` calls free `/accounts/get` (`Sources/PlaidBarServer/Plaid/PlaidClient.swift:107`), per-request-billed `/accounts/balance/get` (`:116`), and subscription-billed `/transactions/sync` (`:132`). Account routes expose both `accounts` (free endpoint) and `balances` (billable endpoint) paths (`Sources/PlaidBarServer/Routes/AccountRoutes.swift:13`). With a 15-minute background refresh and 30-minute transaction sync (`Sources/PlaidBarCore/Utilities/Constants.swift:30-31`), an aggressive refresh policy hitting `/accounts/balance/get` could generate ~96 billable calls/Item/day. **Cost lever:** default refresh should use the free `/accounts/get` + sync-derived balances; reserve realtime `/accounts/balance/get` for explicit user-triggered refresh, and consider making this a Plus perk.
- **Churn hygiene plumbing exists.** `/item/remove` is already wired (`AccountRoutes.swift:135`, `PlaidClient.swift:137`). Plaid Transactions subscriptions bill monthly per Item *even with zero API calls and even when broken*, with no proration — so managed-tier cancellation flows **must** call `/item/remove` for every Item or VaultPeek pays for churned users forever.

## 4. Tiers (AND-349)

| | **Free Demo** | **Personal** | **Plus** | **Extra-institution add-on** *(later)* |
|---|---|---|---|---|
| Price | $0 | **$79/yr** or **$9/mo** | **$129/yr** (early-access) or **$15/mo**; → **$149/yr** once premium features mature | est. **$24/yr or $2.50/mo per institution** (pending provider quote) |
| Institutions | 0 live (fixture data) | **up to 3** | **up to 8** | +1 each, Plus only |
| Bank linking | None — demo fixtures | Managed (broker) | Managed (broker) | Managed |
| Surface | Full UI on demo data | Menu bar cockpit, balances, spending, credit, recurring, core alerts | Everything in Personal + premium features as they mature (advanced alert rules, monthly financial review, realtime balance refresh; future: wealth summary, multi-Mac — feature/tier mapping owned by the consumer-experience roadmap doc) | — |
| Purpose | Try the entire product risk-free; conversion funnel | The default plan | Power users, many accounts | Pressure valve so caps never force a tier jump |

Also free, forever, outside the tier table: **BYO-keys mode** (current product). Users who bring their own Plaid credentials pay VaultPeek nothing for linking; on Plaid's Trial plan (10 Items free) this is sustainable indefinitely for a single user. Keeping it free is deliberate: it proves the privacy architecture is real, not marketing, and it is the answer to "what if VaultPeek's service shuts down."

Cap rationale: 3 institutions covers the median US PFM user (~2–3 engaged institutions — **estimate**, industry rule of thumb per the unit-economics research; instrumenting the real distribution is a launch prerequisite); 8 covers nearly everyone else. Caps are the mechanism that keeps per-Item provider costs bounded per subscriber.

### Early-access mechanics

- Plus at $129/yr is **annual-only early access** (monthly $15 available but not discounted) — annual prepay buffers the non-prorated monthly Plaid billing risk.
- **Price-lock for early subscribers** (recommended, pending D5): anyone subscribing at $79/$129 keeps that rate as long as they stay subscribed, even after Plus moves to $149. This copies Lunch Money's price-lock-for-life pattern and explicitly counter-positions against YNAB's resented increase treadmill ($60 one-time → $109/yr over its history).

## 5. Price-point grounding

### 5.1 Competitor anchors (all retrieved 2026-06-12)

| Product | Price | Custody | Note |
|---|---|---|---|
| Copilot Money | $13/mo · $95/yr | Cloud (GCP) | Closest analog: Apple-native, design-led, managed Plaid. No menu bar surface. |
| Monarch Money | Core $99.99/yr · Plus $199/yr | Cloud | $199 Plus tier shows premium headroom in the category |
| YNAB | $109/yr · $14.99/mo | Cloud | Price-increase backlash = opening for a price-lock promise |
| Lunch Money | $10/mo · PWYW ≥ $60/yr, price-locked | Cloud (indie) | **$60/yr is the floor for sustainable indie Plaid economics** |
| Actual Budget | Free/OSS; user pays SimpleFIN $15/yr | **Local/self-hosted** | Proof a real audience insists on local data; SimpleFIN is the cost-transparency benchmark |
| Balance (defunct, 2017) | $4.99–$19.99/mo | Cloud | Menu-bar precedent; **died on Plaid unit economics at ~$50/yr for 5 accounts** — the cautionary tale our caps exist to avoid |

Placement: Personal $79/yr sits **above Lunch Money's $60 floor and below Copilot's $95 / Monarch's $99.99** — credible for a single-surface product (menu bar cockpit, not a full budgeting suite) with a privacy story no cloud competitor can match. Plus $129–$149 sits between Copilot and Monarch Plus, justified only as premium features mature (hence the staged $129 → $149). The local-first + glanceable quadrant is currently **empty** — no maintained competitor occupies it — which supports modest premium pricing over the indie floor but does not support Monarch-Plus-level pricing at launch.

### 5.2 Provider cost model (ALL Plaid dollar figures are third-party ESTIMATES; retrieved 2026-06-12)

Plaid bills **per Item (bank connection), per month**, for Transactions — even with zero API calls, no proration, `/item/remove` is the only off switch. Working estimate range for the Transactions subscription: **~$1.50/Item/mo at pay-as-you-go** (Monetizely/blog-tier estimates) down to **~$0.30–$0.60/Item/mo at committed/negotiated scale** (Vendr marketplace data, 38 contracts; median ACV $9,000/yr). Balance refresh is per-call (est. $0.05–$0.50/call — sources disagree 3–6x). One-time Auth/Identity fees est. $0.10–$1.00/Item if those products are added.

### 5.3 Margin model (estimates; Stripe at its long-published standard 2.9% + $0.30 — not re-verified 2026-06-12, confirm current rate card before finalizing; assumes direct distribution, NOT Mac App Store — see D9)

| Plan | Net revenue/mo after Stripe | COGS @ PAYG est. $1.50/Item/mo | COGS @ committed est. $0.50/Item/mo | Gross margin range |
|---|---|---|---|---|
| Personal $79/yr (≈$6.58/mo) | ≈ $6.37 | 2 items avg: $3.00 · 3-cap worst: $4.50 | $1.00 · $1.50 | **29–84%** |
| Personal $9/mo | ≈ $8.44 | $3.00 · $4.50 | $1.00 · $1.50 | 47–88% |
| Plus $129/yr (≈$10.75/mo) | ≈ $10.41 | 5 items typical: $7.50 · **8-cap worst: $12.00** | $2.50 · $4.00 | **−15% to 76%** |
| Plus $15/mo | ≈ $14.26 | $7.50 · $12.00 | $2.50 · $4.00 | 16–82% |
| Plus $149/yr (≈$12.42/mo) | ≈ $12.06 | $7.50 · $12.00 | $2.50 · $4.00 | **≈0% to 79%** |

**The honest risk in this table:** Plus is **underwater at the 8-institution cap on pay-as-you-go estimated rates**. Plus economics only work if at least one of these holds: (a) a committed Plaid contract at ≤ ~$1.00/Item/mo, (b) realized institution mix well below the cap (most Plus users at 4–5), (c) Teller (or another provider) prices materially below Plaid for this workload. This is why the recommendation (§10) sequences a Plaid sales quote *before* the public pricing page, and why early-access Plus is annual-prepay. The add-on price (est. $24/yr/institution) is set to cover PAYG worst case ($18/yr/Item) with margin.

Margin assumptions on record (AND-349 acceptance criterion): average 2 institutions on Personal, 5 on Plus; Transactions-only product mix at launch (no Auth/Identity/Investments subscriptions in v1 managed tier); refresh policy defaults to free endpoints (§3); broker + entitlement infra fixed cost est. $50–150/mo at launch scale (single small host — estimate); support cost not yet modeled; Plaid implementation/premium-support fees ($5k–$25k+ / $10k–$50k/yr per Vendr estimates) treated as a scale-up cost, avoided at launch by PAYG or Growth entry tier.

## 6. Guardrails — what we deliberately do NOT offer (AND-349)

| Anti-pattern | Why not |
|---|---|
| **Unlimited institution links** | Provider billing is per-Item-month and uncapped; one outlier user can erase the margin of fifty normal ones. Balance (2017) died exactly here. |
| **Lifetime deals** | Revenue is one-time; Plaid/Teller, Stripe, and support costs recur monthly forever. A lifetime user is a perpetual liability. |
| **Free live-bank tier** | Every live Item costs real money monthly even if the user never opens the app (no proration, bills while broken). Free tier = demo fixtures only; free *linking* exists only as BYO-keys, where the user holds the Plaid relationship. |
| **Very low pricing (<$60/yr)** | Below the Lunch Money floor, indie Plaid economics demonstrably don't close once support and infra are included. |
| **Visible API markup ("Plaid pass-through + fee")** | Provider cost is bundled into plan price. Cost-transparency is honored in the FAQ ("your subscription covers what banks' data networks charge us"), not as a line item — per AND-343. |

## 7. Launch copy drafts (AND-349)

Positioning rule for all copy: VaultPeek is a **private Mac money cockpit** — high-signal numbers one glance away — **not a full budgeting suite**. Never claim "we never see your data" unqualified; always the precise version. Honest, plain, no fintech-bro hype.

### Tagline

> **Private finance, one glance away.**

### Hero (landing page)

> **VaultPeek**
> **Private finance, one glance away.**
> Your balances, spending, and credit — live in your Mac's menu bar. Your financial data stays on your Mac. Not our servers. Not anyone's.
> [Try the demo — no account, no bank, no signup]

### Subhead / how-it-works block

> Most finance apps copy your transactions to their cloud and ask you to trust them. VaultPeek doesn't. The app and its data live entirely on your Mac — encrypted in your Keychain and a local database. Our service does three small things: connects you to your bank, checks your subscription, and relays your sync traffic to the bank network without storing or logging any of it — the relay's code is open source so you can check. We never store a balance, a transaction, or an account number. That's not a policy. It's the architecture.

### Pricing page copy

> **Demo — Free.** The full VaultPeek experience on realistic sample data. No account, no card, no bank login. Kick every tire.
>
> **Personal — $79/year or $9/month.** Link up to 3 banks or cards. Live balances, spending, credit utilization, and recurring charges in your menu bar. Cancel anytime; your data is already on your Mac, so there's nothing to export — and nothing for us to delete.
>
> **Plus — $129/year, early access.** Link up to 8 institutions and get new premium features first. Early-access pricing is locked in for as long as you stay subscribed — when Plus grows up and the price goes to $149, yours doesn't.
>
> **Bring-your-own-keys — Free, forever.** Developers and the privacy-obsessed can keep using VaultPeek with their own Plaid credentials, fully local, no VaultPeek account at all. We built it that way first, and we're keeping it.

### Privacy promise (trust page — the honest version, per the §2 constraint)

> **What runs where.**
> On your Mac: the app, a local server, your bank connections (in macOS Keychain), your balances and transaction history (local SQLite). On our servers: your email, your subscription status, a one-time handshake each time you link a bank, and a relay that passes your sync traffic through to Plaid without writing any of it down. We can see *that* you connected an institution. We never store, log, or look at *anything inside it.*
>
> **What changed from our original promise.** We used to say "no hosted backend, period." Adding bank linking without making you sign up for a Plaid developer account requires one small hosted service. We've kept it as small as honesty allows: a link handshake, a subscription check, and a no-storage sync relay (its code is open source). Your financial data is never stored on it — and the bring-your-own-keys mode still works with zero VaultPeek servers involved.

### App Store-style one-liner / social

> The menu bar finance app that keeps your money data on your Mac. Balances, spending, credit — one glance, nothing stored in anyone's cloud.

### FAQ snippets

> **Why isn't there a free plan with live banks?** Because every live bank connection costs us real money every month, paid to the data networks (Plaid) that banks use. A "free" plan would mean selling something else — your data or your attention. We'd rather charge a fair price and sell nothing else.
>
> **Is this a budgeting app?** No. VaultPeek is a cockpit, not a workshop — your numbers, one glance away, dense and fast. If you want envelope budgeting, YNAB is great. If you want to stop opening four banking apps a day, that's us.
>
> **What happens if VaultPeek shuts down?** Your data is on your Mac, so you lose nothing. And bring-your-own-keys mode works with no VaultPeek service at all.

## 8. Provider strategy pointer

Per AND-343, the provider strategy (Plaid vs Teller, minimal provider abstraction so the local server and broker are not hard-wired to one aggregator) is detailed in the companion docs in `docs/strategy/` from this same PR. Pricing-relevant facts owned by *this* doc: Plaid rates are sales-gated and estimate-based (§5.2); Teller publishes more transparent pricing and **must be quoted side-by-side before pricing is final** (no Teller figures verified in this pass); Plaid's free Trial plan (10 Items) makes BYO-keys sustainably free and means managed linking is sold on **convenience and zero-setup**, not cost.

## 9. Open product decisions for Felipe

| # | Decision | Options / default | Why it gates launch |
|---|---|---|---|
| D1 | **Approve the hosted footprint at all** (broker + entitlements) and the amended public promise (§2) | Go / no-go. No default — this is the existential one | AND-343 explicitly requires this gate before any hosted backend work |
| D2 | **Get the real Plaid quote** (PAYG vs Growth committed) before publishing prices | Required regardless | Plus margin swings from −15% to +76% on this number (§5.3) |
| D3 | **Provider at launch:** Plaid-first, Teller-first, or dual via abstraction | Default: quote both, decide on numbers + institution coverage | Could fix the Plus margin problem outright |
| D4 | **Rename timing:** "PlaidBar" cannot be a commercial brand (built on Plaid's trademark). VaultPeek rename must land before any paid launch | Default: rename before pricing page goes live | Legal/brand risk |
| D5 | **Price-lock promise:** lifetime rate-lock for early subscribers, yes/no | Default: yes (Lunch Money pattern, anti-YNAB positioning) | Affects copy and future repricing freedom |
| D6 | **BYO-keys stays free forever** and stated publicly | Default: yes — it is the trust anchor | Hard to walk back once promised |
| D7 | **Plus early access: annual-only or also monthly?** | Default: both, but only annual gets the $129 discount | Monthly Plus at PAYG rates is the thinnest margin cell |
| D8 | **Add-on pricing + ship timing** (est. $24/yr per extra institution) | Default: post-launch, only if cap complaints are real | Premature complexity otherwise |
| D9 | **Distribution: direct (Stripe) vs Mac App Store** | Default: direct-only at launch — App Store's 15–30% cut breaks the §5.3 margin table and Apple IAP rules complicate Stripe entitlements | Changes every margin number |
| D10 | **Trial/refund policy** for paid tiers | Default: no card-free live trial (Items cost money day one); demo mode IS the trial; 30-day refund | Touches §6 free-live-bank guardrail |

## 10. Recommendation

Launch the consumer track in this order, contingent on D1:

1. **Now (free):** Ship the rename (D4) and the launch site with Demo + BYO-keys only — the copy in §7 works today minus the paid tiers. Zero hosted footprint yet, promise unbroken.
2. **Before any pricing page:** Plaid sales quote + Teller quote (D2/D3). If committed Transactions pricing lands at ≤ ~$1.00/Item/mo, the proposed tiers are safe across the table; if not, either Teller-first or raise Plus to $149 from day one.
3. **Paid launch:** Personal $79/yr / $9/mo (3 institutions), Plus $129/yr annual early-access / $15/mo (8 institutions), price-locked for early subscribers (D5), direct distribution + Stripe (D9), demo-as-trial + 30-day refund (D10). Hosted footprint strictly limited to link-token broker + entitlement check + the stateless no-persistence sync relay (managed-link architecture doc); cancellation flow calls `/item/remove` for every Item.
4. **Later:** Plus → $149/yr for new subscribers once at least two genuinely premium features have shipped (advanced alert rules, monthly financial review, realtime refresh, wealth summary); extra-institution add-on only if cap pressure shows up in support (D8).

The bet, in one sentence: nobody else occupies *local-first + glanceable*, the category's sustainable price band is well-bracketed at $60–$100/yr, and $79 buys the only finance dashboard whose honest answer to "where is my data?" is "on your Mac."

## Sources

- Linear AND-349, AND-343 (acceptance criteria; fetched 2026-06-12)
- Competitive research brief, 2026-06-12 (Copilot, Monarch, YNAB, Lunch Money, Actual Budget, Balance, simplebanking; all prices retrieved 2026-06-12)
- Plaid production pricing research brief, 2026-06-12 — official: plaid.com/pricing, plaid.com/docs/account/billing, plaid.com/docs/sandbox; estimates: vendr.com/marketplace/plaid, getmonetizely.com, costbench.com (all retrieved 2026-06-12; dollar figures are estimates — Plaid publishes no price list)
- Code read 2026-06-12 from this worktree: `Sources/PlaidBarCore/Utilities/Constants.swift`, `Sources/PlaidBarServer/Plaid/PlaidClient.swift`, `Sources/PlaidBarServer/Routes/AccountRoutes.swift`, `Sources/PlaidBar/App/PlaidBarApp.swift`
