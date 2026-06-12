---
title: Teller Evaluation — Cost-Transparent Plaid Alternative
status: proposed
linear: [AND-345]
date: 2026-06-12
---

# Teller Evaluation: Cost-Transparent Plaid Alternative

> **Scope:** Design/research document only. No implementation. This doc evaluates [Teller](https://teller.io) as a data-provider alternative or complement to Plaid for VaultPeek's consumer use case, per Linear AND-345. All pricing figures are labeled with retrieval date; third-party or derived figures are explicitly marked **estimate**.

## 1. Recommendation (summary)

**Teller should be an *experimental* provider now, a candidate *fallback/secondary* provider later, and is not viable as the *primary* or sole provider.** (Decision owner: Felipe — the promote/decline call is gated on the criteria in §10.)

| Question | Answer |
|---|---|
| Primary provider? | **No.** Missing Capital One, Discover, U.S. Bank, SoFi, and all investment/loan account types — unacceptable coverage holes for a US consumer dashboard. |
| Fallback/secondary? | **Plausible.** Strong overlap on depository + credit-card data, dramatically cheaper and fully transparent pricing, and a BYO-credentials story that is *better* than Plaid's. Promote only after the PoC and the decision criteria in §10 pass. |
| Experimental now? | **Yes.** Free sandbox + free 100-connection development environment make a zero-cost PoC possible behind a provider abstraction. |
| Managed (hosted) tier provider? | **Not preferred.** Per the managed-link architecture doc, *any* managed tier (Plaid or Teller) routes data-plane traffic through a credential-injecting hosted relay — Teller is not categorically worse on transit, but it would mean a second relay for a provider whose coverage disqualifies it as sole provider (§7). Revisit only if Teller offers per-user certificates, which would uniquely enable a relay-free managed mode. |

The single most attractive Teller property for VaultPeek's consumer-subscription exploration is **public, per-unit pricing** ($0.30/enrollment/month for transactions, retrieved 2026-06-12), which enables an honest COGS line in a Stripe-billed tier — something Plaid's quote-only pricing cannot provide today.

The single most disqualifying property is **coverage**: Teller's live institutions directory (7,008 institutions, queried 2026-06-12) is missing several of the largest US issuers despite homepage marketing claims (Capital One is named on Teller's homepage but absent from the live directory — flagged as a discrepancy to raise with Teller).

## 2. Why evaluate Teller

VaultPeek (currently PlaidBar) is exploring a consumer subscription with managed bank linking. Plaid's production pricing is quote-only and per-Item subscription fees bill even on broken/idle Items, making COGS hard to state honestly to customers (see companion Plaid pricing notes; all Plaid dollar figures in this doc are **estimates** from third-party contract data, retrieved 2026-06-12). Teller publishes prices on its homepage. AND-345 asks for a head-to-head evaluation against VaultPeek's actual usage shape.

VaultPeek's actual usage shape, from code (read 2026-06-12 in this worktree):

- `Sources/PlaidBarServer/Plaid/PlaidClient.swift` — the full Plaid surface VaultPeek consumes: `link/token/create` (Hosted Link, `products: ["transactions"]`, US-only), `link/token/get`, `item/public_token/exchange`, `accounts/get`, `accounts/balance/get`, `transactions/sync` (cursor-based, page size 500), `item/remove`.
- `Sources/PlaidBarCore/Utilities/Constants.swift` — background refresh every **15 minutes** (`backgroundRefreshInterval = 15 * 60`, minimum 5 minutes); `creditUtilizationWarningThreshold = 30.0`.
- `Sources/PlaidBarCore/Utilities/TransactionSyncReducer.swift` — pure reducer over Plaid's `added`/`modified`/`removed` sync deltas.
- `Sources/PlaidBarCore/Utilities/RecurringDetector.swift` — recurring/subscription detection grouped by `merchantName`, classified by date-interval medians.
- `Sources/PlaidBarServer/Storage/PlaidTokenVault.swift` — Keychain-backed secret storage; SQLite stores only `keychain:<item_id>` references.

## 3. Pricing comparison: 3-institution and 8-institution users

### 3.1 Unit prices

| Product | Teller (official, teller.io homepage, retrieved 2026-06-12) | Plaid (**estimates**, third-party contract data, retrieved 2026-06-12) |
|---|---|---|
| Transactions | $0.30 per enrollment per month | ~$0.30–$0.60/Item/mo (committed, Vendr est.) to ~$1.50/Item/mo (PAYG, blog-tier est.) — **estimate; Plaid does not publish rates** |
| Balance | $0.10 per API call ("live" fetch from bank) | ~$0.05–$0.50 per call (**estimate**, sources disagree 3–6x) |
| Account list | Free (`GET /accounts`) | Free (`/accounts/get` documented as free) |
| Verify (account/routing) | $1.50 per account | Auth ~$0.10–$1.00 one-time/Item (**estimate**) |
| Identity | $1.75 per call | ~$0.15–$1.50 per call (**estimate**) |
| Free tier | 100 live connections (development env, real banks, no approval gate) | Trial plan: 10 Production Items free (US/Canada teams created on/after 2026-04-15; `/item/remove` does **not** free cap slots) |

### 3.2 Monthly COGS per user (transactions-driven sync, no routine balance polling)

Assumes the provider-appropriate sync pattern: transactions subscription only, balances derived from transaction `running_balance` (Teller) or bundled account balances (Plaid `/accounts/get` is free). All Plaid figures are **estimates**.

| Scenario | Teller (official rates) | Plaid PAYG (**estimate**) | Plaid committed (**estimate**) | BYO-keys (user's own account) |
|---|---|---|---|---|
| 3-institution user | **$0.90/mo** | ~$4.50/mo | ~$0.90–$1.80/mo | $0 on Teller dev tier (≤100 connections) or Plaid Trial (≤10 Items) |
| 8-institution user | **$2.40/mo** | ~$12.00/mo | ~$2.40–$4.80/mo | $0 (same caps; Plaid Trial cap is 10 Items and removals don't free slots — 8 institutions leaves little churn headroom) |

### 3.3 The balance-endpoint cost trap (do not port the current refresh loop 1:1)

`AccountRoutes.swift` exposes both `/api/accounts` (Plaid `/accounts/get`, free) and `/api/accounts/balances` (Plaid `/accounts/balance/get`, per-call). On Teller, **every** balance read is a billed "live" call at $0.10. If VaultPeek's current 15-minute background refresh (`Constants.swift`) naively hit Teller's balance endpoint once per account per cycle:

- ~96 calls/day × 30 days ≈ 2,880 calls/account/month × $0.10 ≈ **~$288/account/month** (**estimate**, arithmetic illustration).
- Even a modest 4x/day balance poll across 3 banks is ≈ $36.90/mo (**estimate**).

**Design consequence:** a Teller integration must derive routine balances from the transactions feed (`running_balance` on posted transactions, included in the $0.30/mo subscription) and reserve the billed balance endpoint for explicit user-initiated refreshes, if used at all. This is an architectural requirement, not a tuning detail.

## 4. Coverage (AND-345 AC: account types, balances, transactions, recurring inputs)

Verified against Teller's live public institutions endpoint (`GET https://api.teller.io/institutions`, 7,008 institutions, queried 2026-06-12) and API docs (retrieved 2026-06-12).

### 4.1 What VaultPeek needs vs what Teller has

| VaultPeek need | Teller support | Notes |
|---|---|---|
| Checking / savings | ✅ | Depository types: `checking, savings, money_market, certificate_of_deposit, treasury, sweep` |
| Credit cards | ✅ (`credit_card` type) | ⚠️ Balance schema is `ledger`/`available` only — **no documented credit-limit field**, which `creditUtilizationWarningThreshold` logic needs (Plaid provides `balances.limit`, mapped in `PlaidModels.swift`). Verify in PoC; if absent, utilization features degrade for Teller-sourced accounts. |
| Balances | ✅ (all 7,008 institutions) | Billed per call ($0.10); routine balances must come from transactions (§3.3) |
| Transactions | ✅ (all 7,008 institutions) | Signed string amount, `posted`/`pending` status, `running_balance`, enriched `details` |
| Recurring/subscription detection inputs | ✅ with caveats | `RecurringDetector` groups on `merchantName`; Teller's `details.counterparty.name` maps to it. Caveat: enrichment is async (`transactions.processed` webhook signals completion) — freshly synced transactions may lack counterparty data, shifting recurring results between syncs. Teller's 28 standardized categories must be mapped to VaultPeek's `SpendingCategory` taxonomy (currently fed by Plaid `personal_finance_category`). |
| Investments / brokerage | ❌ | No investment account types or products. Blocks wealth-summary ambitions for Teller-sourced data. |
| Loans / mortgages / liabilities | ❌ | No loan account types, no liabilities product. "Debt" filter limited to credit cards. |

### 4.2 Institution coverage (live directory, 2026-06-12)

- **Present:** Chase, Bank of America, Wells Fargo, Citibank, American Express, PNC, Truist, Ally, TD Bank, Regions, Fifth Third, Navy Federal, USAA, Schwab, Morgan Stanley, Huntington, Chime, Varo, Mercury, BMO.
- **Absent:** **Capital One** (despite Teller homepage marketing — discrepancy to raise with Teller), Discover, U.S. Bank, SoFi, Synchrony, KeyBank, M&T, Comerica, Santander, HSBC, Robinhood, Venmo, Vanguard, Fidelity brokerage, Goldman/Marcus (incl. Apple Card).
- **Geography:** US-only. Plaid claims 12,000+ institutions across 20+ countries.
- Per-product availability across the 7,008: balance 7,008, transactions 7,008, identity 6,816, verify-instant 6,205, payments 1,154.

### 4.3 Other AC gap checks (logos, consent UX, compliance, trust posture)

| Dimension | Assessment |
|---|---|
| **Institution logos** | Not documented in the institutions API response (name + product flags observed). Plaid provides institution logos via `/institutions/get`. If absent, VaultPeek self-derives branding for Teller accounts — open question for Teller (§11). |
| **Consent UX** | Teller Connect (JS widget) handles credential entry/MFA, mirrors Plaid Link. First-party native macOS bindings (TellerKit) exist but are stale and possibly agreement-gated (§5.3). Co-branded Connect screens are an Enterprise-tier feature. |
| **Compliance** | Under the Section 1033 authorized-third-party regime, whoever holds the provider relationship is the regulated party. BYO-Teller keeps the *user* as the relationship holder (consistent with current BYO-Plaid posture). Any managed tier makes VaultPeek the authorized third party regardless of provider. |
| **Trust posture** | SOC 2 Type 2 report access is gated behind Teller's Enterprise tier (homepage, retrieved 2026-06-12). Teller is a smaller company than Plaid; the stale state of its native SDKs (§5.3) is a maintenance-health signal. Data-freshness claim ("live, real-time" direct bank connections) is a positive differentiator vs Plaid's cached/batch behavior at some institutions, but is a marketing claim — verify in PoC. |

## 5. API fit vs the current `PlaidClient` surface

Mapping of every method in `Sources/PlaidBarServer/Plaid/PlaidClient.swift` to its Teller equivalent (Teller API docs, retrieved 2026-06-12):

| `PlaidClient` method | Plaid endpoint | Teller equivalent | Fit |
|---|---|---|---|
| `createLinkToken` / `createUpdateLinkToken` | `/link/token/create` (Hosted Link) | Teller Connect (JS widget; `connect.js`); no server-side link-token step — `applicationId` + environment config in the widget | **Different flow.** No token-create round trip; enrollment completes client-side and yields an access token directly. Update/repair mode exists in Connect. `PendingLinkSessionStore` one-time-state pattern would be re-pointed at Connect callbacks. |
| `getLinkToken` (poll Hosted Link result) | `/link/token/get` | N/A — Connect returns the enrollment (access token) in the success callback | **Simpler**, but the access token surfaces in the WebView callback; it must be handed to the server process immediately and never persisted app-side. |
| `exchangePublicToken` | `/item/public_token/exchange` | N/A — no public-token indirection | **Simpler.** One fewer secret-bearing round trip, but also removes the nice property that the UI only ever sees a *public* token. With Teller the UI surface briefly touches the real access token (mitigated: token is useless without the mTLS cert, §6). |
| `getAccounts` | `/accounts/get` (free) | `GET /accounts` (free) | **Good fit.** Field mapping: Plaid `accountId/name/officialName/mask/type/subtype` → Teller `id/name/last_four/type/subtype`, institution object included. |
| `getBalances` | `/accounts/balance/get` (per-call) | `GET /accounts/:id/balances` ($0.10/call) | **Fits but per-account** (N calls vs Plaid's one bulk call) and billed — see §3.3. Teller returns `ledger`/`available` as nullable *strings*; Plaid model uses `Double` (`PlaidBalances`). No `limit` field (§4.1). |
| `syncTransactions` | `/transactions/sync` (cursor, `added/modified/removed`, `hasMore`) | `GET /accounts/:id/transactions` with `count`/`from_id` pagination + `start_date`/`end_date` | **Worst fit.** No cursor sync, no delta semantics. Teller docs recommend re-querying with a 7–10 day overlap because pending→posted transitions can re-ID transactions. `TransactionSyncReducer` (keyed on stable IDs with explicit `removed` tombstones) cannot be reused as-is; a Teller-specific overlap/dedupe reducer is required, plus a fuzzy match (date+amount+description) for re-IDed pending transactions. The `CreateSyncCursors` migration's cursor storage becomes a last-sync watermark. |
| `removeItem` | `/item/remove` (stops billing) | `DELETE /accounts/:id` (revoke) | **Fits.** Same churn-hygiene requirement: disconnect flows must revoke to stop the $0.30/mo meter. |
| Error model (`PlaidError`, retry policy) | Plaid `error_type`/`error_code` | HTTP status + Teller error body; `enrollment.disconnected` webhook with `reason` | Retry/backoff scaffolding in `PlaidClient.post` ports directly; error taxonomy mapping needed for `UserFacingError`. Reconnect ("repair") flows map to Connect update mode, analogous to `createUpdateLinkToken` + `ReconnectRecoveryMessage`. |

Additional model-level deltas (`PlaidModels.swift` → Teller):

- **Amounts:** Plaid `Double` with positive-=-outflow convention; Teller signed **string** amounts. Sign convention must be verified in the PoC before mapping into `TransactionDTO.displayAmount` (a silent sign flip would corrupt every summary). The string type is an opportunity to move parsing to `Decimal`.
- **Categories:** Plaid `personal_finance_category` (primary/detailed/confidence) → Teller `details.category` (28 categories, no confidence). One-way mapping table into `SpendingCategory` required.
- **Webhooks:** Teller webhooks (HMAC-SHA256 `Teller-Signature`) require a public HTTPS endpoint — **incompatible with a purely local app**. VaultPeek already polls Plaid on a 15-minute cadence, so polling-only Teller operation is acceptable; enrichment-lag and disconnect detection just ride the poll loop.
- **DTO seam is healthy:** `PlaidBarCore` DTOs (`AccountDTO`, `TransactionDTO`, `SyncResponse`) are provider-neutral; provider-specific models live only in the server target. Coexistence (§8) means introducing an `AggregatorClient`-style protocol in front of `PlaidClient` and mapping both providers to the same DTOs — the routes (`AccountRoutes`, `TransactionRoutes`, `LinkRoutes`) already consume the client through a narrow surface.

## 6. Certificate auth implications for the local server

Teller authenticates with **two layers** (docs retrieved 2026-06-12): a per-application **mTLS client certificate** (required for all user-data requests in development/production) plus per-enrollment **access tokens** (HTTP Basic), which are "useless without a client certificate belonging to the application."

Implications for VaultPeek's two-process architecture:

1. **The cert private key is the new `client_secret`.** It must live exclusively in `PlaidBarServer`, never in the SwiftUI app and never in a distributed binary. This maps cleanly onto the existing boundary: today `PlaidClient` injects `config.plaidClientId`/`config.plaidSecret` into every request body; a `TellerClient` would instead hold a `SecIdentity`.
2. **Keychain storage extends the existing vault pattern.** `PlaidTokenVault.swift` stores token *bytes* in Keychain with SQLite holding only `keychain:<item_id>` references (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). The cert/key pair imports as a `SecIdentity` (`kSecClassIdentity`, e.g. via `SecPKCS12Import`), with config/SQLite holding only a reference. Enrollment access tokens reuse `PlaidTokenVault`'s string-token path unchanged.
3. **`URLSession` needs a delegate.** The current `PlaidClient` uses a plain delegate-less `URLSession` (`makeDefaultSession()`). mTLS requires answering `urlSession(_:task:didReceive:completionHandler:)` for `NSURLAuthenticationMethodClientCertificate` with a `URLCredential(identity:certificates:persistence:)`. Under the repo's CI gate (`-strict-concurrency=complete -warnings-as-errors`) the delegate must be a `Sendable`-safe final class holding an immutable identity reference — straightforward, but it is new concurrency surface to design, not a config flag.
4. **Lifecycle operations the server must own:** cert expiry detection and a user-facing renewal flow (new `UserFacingError` case + status surface in `StatusRoutes`); revocation/reissue after a suspected compromise (dashboard-driven, then re-import); and a setup flow for users to install their cert (BYO model) analogous to today's `PLAID_CLIENT_ID`/`PLAID_SECRET` in `server.conf` — but file-drop of a PKCS#12 + passphrase is meaningfully more friction than pasting two strings. Setup UX needs design work.
5. **Linux/CI caveat:** `PlaidClient.swift` carries `#if canImport(FoundationNetworking)` and `PlaidTokenVault` has non-Security fallbacks. `FoundationNetworking`'s client-certificate support is weaker than Darwin's; Teller-path tests on non-Darwin CI would need stubbing at the client boundary.
6. **A security upside worth stating:** even if an attacker exfiltrates Teller access tokens from disk, they are inert without the mTLS key. That is strictly better than Plaid access tokens, which are usable with any leaked `client_secret`.

## 7. Managed-tier tension with the local-first promise (required callout)

VaultPeek's promise today: **no hosted backend, no telemetry, all data stays on the user's machine.** Any managed-linking tier strains this; the question is whether Teller strains it more than Plaid:

- **Plaid managed model (for comparison):** the minimal hosted footprint is a **link-token broker + entitlement check + a stateless data-plane relay** — the hosted service creates link tokens and exchanges public tokens, then hands the access token to the user's local server; financial data is **never stored** hosted, but sync responses do *transit* a memory-only "blind proxy," because direct device→Plaid data calls would require VaultPeek's `client_secret` on the user's machine, which Plaid policy forbids (analyzed and accepted in the managed-link architecture doc, §5.4 there).
- **Teller managed model:** access tokens are useless without the application's mTLS certificate. A broker therefore **cannot** hand the token to the local app for direct use — unless every user's machine also holds the application cert (equivalent to shipping the master secret in the client; unacceptable, and the exact analog of the Plaid `secret` restriction) or Teller issues **per-user certificates** (not a documented offering; open question §11). The only documented-feature architecture is a hosted proxy holding the cert — **the same transit-only relay posture as the Plaid blind proxy**, requiring the same "never stored, never logged, open-source relay" discipline.
- **Conclusion:** on transit posture the two managed models are comparable — neither avoids relaying financial data, both can avoid storing it. The managed-tier provider decision therefore rests on coverage (§4.2, where Teller disqualifies itself as sole provider) and on not operating a second relay for a secondary provider. Teller remains the *better* BYO provider (free 100-connection development environment, no production approval gate, cert slots into the existing local Keychain vault). If a managed tier ships, it should be Plaid-based per the managed-link architecture doc while Teller remains BYO-only/experimental — unless Teller agrees to per-user certs, which would make Teller the only provider capable of a **relay-free** managed mode (strictly better than Plaid's best case).

## 8. Migration / coexistence risks

Coexistence (Plaid and Teller side-by-side, per-institution routing) is the realistic end-state given §4.2 — full migration is not on the table.

| Risk | Severity | Notes / mitigation |
|---|---|---|
| Transaction sync semantics diverge | **High** | `TransactionSyncReducer` assumes delta sync with tombstones; Teller needs an overlap-window reducer with fuzzy re-ID matching. Two reducers must produce identical `TransactionDTO` streams or every downstream summary (spending, recurring, trends) silently forks behavior. Mitigation: provider-agnostic reducer contract + shared fixture tests in `PlaidBarCoreTests`. |
| Duplicate/ghost transactions during pending→posted re-IDing | **High** | Teller re-IDs transactions; dedupe heuristics (date+amount+description) can both miss and over-merge. Directly pollutes `RecurringDetector` interval math. |
| Amount sign/type mismatch | **High (one-time)** | String vs Double, possibly inverted sign convention — must be locked down by PoC fixtures before any mapping code exists. |
| Credit-limit absence breaks utilization | Medium | `creditUtilizationWarningThreshold` features need `limit`; Teller balances expose only `ledger`/`available`. Degrade gracefully (hide utilization for Teller accounts) — never guess. |
| Cost-model inversion (balance polling) | **High** | §3.3. Refresh architecture must become provider-aware: Teller refresh = transactions-only. |
| Category taxonomy fork | Medium | 28 Teller categories vs Plaid's personal-finance taxonomy; a mapping table keeps `SpendingCategory` stable. |
| Enrichment lag shifts recurring/spending results between polls | Medium | Counterparty enrichment is async (webhook-signaled, but VaultPeek polls); re-derive summaries on each sync, tolerate churn. |
| Item-record schema assumes Plaid | Medium | Fluent `Items` table + `CreateSyncCursors` migration are Plaid-shaped; coexistence needs a `provider` column and provider-shaped cursor/watermark storage. |
| TellerKit (native SDK) is unusable as-is | Medium | Single-day repo (created/pushed 2024-05-17), binary xcframework only, **no license**, no SPM manifest; predecessor repo states native usage is "not supported unless separately agreed." Mitigation: host Connect JS via the existing Hosted-Link-style browser/`WKWebView` flow — low risk, mirrors current `LinkRoutes` design. |
| Two providers = two trust stories | Medium | Settings/onboarding must disclose which provider serves which institution; Teller's Enterprise-gated SOC 2 access weakens the trust page for a consumer audience. |
| Webhook-dependent features unavailable locally | Low | VaultPeek already polls; no regression vs current Plaid integration. |
| US-only geography | Low (today) | Matches current `countryCodes: ["US"]` in `PlaidClient.createLinkToken`; blocks any future international story through Teller. |

## 9. Proof of concept (AND-345 AC: "build a small PoC if needed")

This document is design-only (hard constraint for this PR), so the PoC is specified here as a follow-up work item rather than built:

**PoC scope (BYO-Teller, sandbox first, then development env — both free; retrieved 2026-06-12):**

1. Standalone `TellerClient` actor in a spike branch: mTLS `URLSession` delegate with a Keychain-resident `SecIdentity`; list accounts, fetch balances, page transactions for one sandbox enrollment.
2. Capture raw JSON fixtures and lock down: amount sign convention, balance string parsing, presence/absence of credit limit, presence/absence of institution logos, transaction history depth per test institution, behavior of pending→posted re-IDing across overlapping queries.
3. Map fixtures into `AccountDTO`/`TransactionDTO`; run the existing `RecurringDetector` and spending summaries over Teller-shaped data; diff results against Plaid-sandbox-derived equivalents.
4. Prototype the overlap-window reducer against recorded pending→posted sequences.

**PoC exit criteria:** fixtures answer every "verify in PoC" item flagged in §4–§6; recurring detection quality on Teller `counterparty` names is within tolerance of Plaid `merchant_name`; mTLS client builds clean under `-strict-concurrency=complete -warnings-as-errors`.

## 10. Decision criteria

Promote Teller from **experimental → fallback/secondary** only when *all* of the following hold:

1. **Coverage:** the institutions a given user actually holds are in Teller's live directory (per-user routing decision, checked at link time against `GET /institutions`) — and the §4.2 absent-majors list has not regressed.
2. **PoC exit criteria met** (§9), including amount-sign and dedupe correctness.
3. **Legal:** Teller confirms native/embedded Connect usage terms (or VaultPeek ships the JS-widget flow) and the TellerKit license question is moot or resolved.
4. **Cost model holds:** transactions-only refresh confirmed at $0.30/enrollment/month in a real development→production transition; balance endpoint excluded from automatic refresh paths by construction.
5. **Trust:** acceptable answer on SOC 2 access (or equivalent attestation) for a consumer-facing trust page.

Decline or defer Teller entirely if: per-user certificates are confirmed unavailable **and** the consumer strategy converges on managed linking as the primary offering (§7: a managed-Teller tier would mean operating a second cert-holding hosted relay for a provider with disqualifying coverage gaps); or if coverage regressions remove any of Chase/BofA/Wells Fargo/Amex.

## 11. Open questions for Teller (sales/support)

1. Native macOS Connect support terms — `ios-workaround` README says native usage is "not supported unless separately agreed"; TellerKit ships no license. What are the terms for a proprietary macOS product?
2. Per-user certificate issuance — is there any supported model where each end user holds their own client certificate (this decides the managed-tier question, §7)?
3. Transaction history depth per institution (undocumented).
4. Free-tier rate-limit thresholds (documented as existing but unspecified).
5. Capital One: homepage marketing names it, live institutions directory lacks it — what is the actual status/roadmap?
6. Institution logo/branding assets via API?
7. SOC 2 Type 2 report access outside the Enterprise tier?

## 12. Acceptance-criteria traceability (AND-345)

| Acceptance criterion | Where addressed |
|---|---|
| Compare Teller public pricing vs Plaid assumptions for 3- and 8-institution users | §3 (tables 3.1–3.2, cost-trap analysis 3.3) |
| Verify coverage: checking, savings, credit cards, balances, transactions, recurring inputs | §4.1 |
| Identify gaps: investments, liabilities, institution coverage, logos, consent UX, compliance, trust | §4.1 (investments/liabilities), §4.2 (institutions), §4.3 (logos/consent/compliance/trust) |
| Small proof of concept for list accounts, balances, transactions | §9 — specified as follow-up (this PR is design-docs-only by constraint); scope + exit criteria defined |
| Recommend primary / fallback / experimental | §1, §10 — **experimental now, candidate fallback later, never primary or managed-tier provider** |

## 13. Sources

All retrieved 2026-06-12 unless noted. Plaid dollar figures are third-party **estimates** (Plaid publishes no price list).

- https://teller.io/ — pricing, coverage claims, tiers
- https://teller.io/docs/api — environments, versioning, rate limits
- https://teller.io/docs/api/authentication — mTLS + access tokens
- https://teller.io/docs/api/accounts, …/account/balances, …/account/transactions — schemas, pagination, overlap-sync guidance
- https://teller.io/docs/api/webhooks — events, HMAC signing
- https://teller.io/docs/guides/connect — Connect widget, enrollment, repair
- https://teller.io/docs/guides/sdks — backend SDKs (no Swift)
- https://api.teller.io/institutions — live directory (7,008 institutions; queried directly 2026-06-12)
- https://github.com/tellerhq/tellerkit (created/pushed 2024-05-17, no license) and https://github.com/tellerhq/ios-workaround (last push 2022-01-26) — native SDK status
- https://plaid.com/pricing/ and https://plaid.com/docs/account/billing/ — Plaid plan structure, billing taxonomy, Trial plan
- https://www.vendr.com/marketplace/plaid and https://www.getmonetizely.com/articles/plaid-vs-yodlee-how-much-will-financial-data-apis-cost-your-fintech — Plaid rate **estimates**
- Repo code read in this worktree: `Sources/PlaidBarServer/Plaid/PlaidClient.swift`, `Sources/PlaidBarServer/Plaid/PlaidModels.swift`, `Sources/PlaidBarServer/Storage/PlaidTokenVault.swift`, `Sources/PlaidBarServer/Routes/AccountRoutes.swift`, `Sources/PlaidBarCore/Utilities/{Constants,TransactionSyncReducer,RecurringDetector}.swift`
- Anti-source: openbankingtracker.com's Teller entry ("3+ institutions") contradicts the live API count — excluded.
