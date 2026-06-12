---
title: Provider Abstraction over Plaid and Teller
status: proposed
linear: [AND-346]
date: 2026-06-12
---

# Provider Abstraction over Plaid and Teller

**This is a design document. Nothing in it is implemented, and nothing in it should be implemented from this doc alone** — it exists to de-risk the decision (AND-346: "define the smallest provider abstraction needed to avoid hard-locking VaultPeek to one bank data vendor") and to honor the acceptance criteria on that issue. All Teller pricing/coverage figures below were retrieved 2026-06-12; figures marked *(estimate)* are estimates.

## 1. Why an abstraction, and why now

VaultPeek (PlaidBar) is hard-wired to Plaid in exactly four places, all inside `PlaidBarServer`:

| Coupling point | File | What's Plaid-specific |
|---|---|---|
| API client | `Sources/PlaidBarServer/Plaid/PlaidClient.swift` | `actor PlaidClient` — link token create/get, public-token exchange, `/accounts/get`, `/accounts/balance/get`, `/transactions/sync`, `/item/remove`; `PlaidError` enum |
| Wire models | `Sources/PlaidBarServer/Plaid/PlaidModels.swift` | `PlaidAccount`, `PlaidTransaction`, `PlaidTransactionsSyncResponse`, error envelope |
| Token + cursor storage | `Sources/PlaidBarServer/Storage/TokenStore.swift`, `Storage/Database.swift`, `Storage/PlaidTokenVault.swift` | `ItemModel` (schema `items`), `SyncCursorModel` (schema `sync_cursors`), Keychain vault keyed by Plaid `item_id` |
| Credentials/config | `Sources/PlaidBarServer/Config/ServerConfig.swift` | `plaidClientId`, `plaidSecret`, `plaidEnvironment`, `credentialsConfigured` |

Crucially, the **UI layer is already provider-agnostic**. The app and `PlaidBarCore` consume only normalized DTOs (`AccountDTO`, `TransactionDTO`, `BalanceDTO`, `SyncResponse`, `ItemStatus` in `Sources/PlaidBarCore/Models/`), and the route handlers (`Routes/AccountRoutes.swift`, `Routes/TransactionRoutes.swift`) already perform Plaid→DTO mapping inline. The abstraction therefore lives entirely behind the existing localhost API: **no app-side changes, no `PlaidBarCore` DTO changes are required for v1** of this design.

Why Teller specifically: public per-unit pricing (transactions $0.30/enrollment/month, balance $0.10/call, retrieved 2026-06-12) enables an honest COGS line for a Stripe-billed consumer tier, and its free development environment (100 real connections, no production-approval gate) is friendlier to the BYO-credentials story than Plaid. Why not Teller-only: it is US-only, depository + credit-card only, and missing Capital One, Discover, U.S. Bank, and SoFi (live institution list, 2026-06-12) — so the realistic shape is **Plaid and Teller side by side**, which is exactly what forces the abstraction.

## 2. Concept mapping

| Concept | Plaid | Teller | Normalized term |
|---|---|---|---|
| One user-bank login | Item (`item_id`) | Enrollment | **Connection** |
| Long-lived secret per connection | `access_token` | access token (Basic auth) | connection credential |
| App-level secret | `client_id` + `secret` | mTLS client certificate + key | provider credentials |
| Link UX | Link / Hosted Link | Teller Connect (JS widget) | link session |
| Reconnect/repair | Link update mode | Connect repair flow | refresh connection |
| Incremental sync | cursor (`/transactions/sync`) | date-window + `from_id` pagination, 7–10 day overlap rescan | sync state (opaque) |

"Connection" deliberately replaces "Item" in all new naming. Plan limits in the subscription tiers count **connections, regardless of provider** — this is acceptance criterion 3 ("model provider Items/enrollments consistently enough for plan limits") and is what makes entitlement gating provider-agnostic (§8).

## 3. Protocol shape

The six operations match AND-346's acceptance criteria verbatim: `connectInstitution`, `listAccounts`, `syncTransactions`, `getBalances`, `refreshConnection`, `disconnectInstitution`. Sketch (Swift 6, all types `Sendable`, mirroring the existing `actor PlaidClient` conventions):

```swift
// Sources/PlaidBarServer/Providers/BankDataProvider.swift (proposed)

enum ProviderID: String, Codable, Sendable {
    case plaid
    case teller
    case fixture   // demo mode (§9)
}

protocol BankDataProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }   // §6

    // -- Link flow ------------------------------------------------------
    /// Phase 1: produce a browser-openable link session. Plaid: Hosted Link
    /// URL via /link/token/create (today: PlaidClient.createLinkToken).
    /// Teller: a locally served Connect page wrapping connect.js, mirroring
    /// the existing one-time-state pattern in Auth/PendingLinkSessionStore.
    func connectInstitution(_ request: LinkRequest) async throws -> LinkSession

    /// Phase 2: completion callback → durable connections. Plaid: public
    /// token exchange (PlaidClient.exchangePublicToken) — may yield several
    /// connections per session (see PlaidLinkTokenGetResponse.publicTokens).
    /// Teller: Connect onSuccess yields the access token directly (no
    /// exchange step).
    func completeConnect(_ completion: LinkCompletion) async throws -> [NewConnection]

    // -- Data -----------------------------------------------------------
    /// Normalized accounts for one connection (today: AccountRoutes maps
    /// PlaidAccount → AccountDTO inline; that mapping moves into the
    /// adapter, §5).
    func listAccounts(credential: ConnectionCredential) async throws -> [AccountDTO]

    /// Fresh balances. NOTE: per-call billed on Teller ($0.10/call,
    /// retrieved 2026-06-12) — gated by capabilities.balanceCost (§6).
    func getBalances(credential: ConnectionCredential) async throws -> [AccountDTO]

    /// Incremental transaction delta against opaque per-connection state.
    func syncTransactions(
        credential: ConnectionCredential,
        state: ProviderSyncState
    ) async throws -> ProviderSyncDelta

    // -- Lifecycle ------------------------------------------------------
    /// Repair a connection in reauth state (Plaid update-mode link token,
    /// today PlaidClient.createUpdateLinkToken; Teller Connect repair).
    func refreshConnection(
        credential: ConnectionCredential,
        request: LinkRequest
    ) async throws -> LinkSession

    /// Revoke at the provider (Plaid /item/remove; Teller
    /// DELETE /accounts/:id). Local deletion is the caller's job — the
    /// ordering rule in AccountRoutes.removeItem (revoke first, keep local
    /// row on failure for retry) is preserved at the route layer, §8.
    func disconnectInstitution(credential: ConnectionCredential) async throws
}
```

Supporting types:

```swift
struct LinkRequest: Sendable {
    let completionRedirectUri: String      // localhost callback, as today
    let products: [String]                 // ["transactions"]
}

struct LinkSession: Sendable {
    let sessionId: String                  // one-time state (PendingLinkSessionStore)
    let url: String                        // what the app opens in the browser
}

struct NewConnection: Sendable {
    let providerConnectionId: String       // Plaid item_id / Teller enrollment id
    let credential: ConnectionCredential   // goes straight into the vault, §7
    let institutionId: String?
    let institutionName: String?
}

/// Opaque per-connection sync position. Serialized into the existing
/// sync-state row (§4). Plaid: the cursor string. Teller: a small JSON
/// blob {sinceDate, overlapDays, recentIdsDigest} for the documented
/// 7–10 day overlap-rescan pattern.
struct ProviderSyncState: Sendable {
    let raw: String?                       // nil = initial full sync
}

/// Identical in shape to what /transactions/sync returns today, so
/// PlaidBarCore.SyncResponse and TransactionSyncReducer stay untouched.
struct ProviderSyncDelta: Sendable {
    let added: [TransactionDTO]
    let modified: [TransactionDTO]
    let removed: [String]
    let hasMore: Bool
    let nextState: ProviderSyncState
}
```

Design rules baked into the shape:

1. **The protocol returns `PlaidBarCore` DTOs, not wire models.** Provider wire models (`PlaidModels.swift`, future `TellerModels.swift`) never escape the adapter. Today's inline mapping in `AccountRoutes.listAccounts` (lines 49–66) and `TransactionRoutes.toDTO` moves into the adapters as pure static functions (§5, §9).
2. **Sync state is opaque.** Routes and `TokenStore` treat it as a string, exactly as the `cursor` column is treated today. Teller's lack of a cursor API is an adapter-internal problem: the Teller adapter re-queries the overlap window, diffs against the ids/digest in its serialized state, and emits added/modified/removed — so `PlaidBarCore.TransactionSyncReducer` (`Sources/PlaidBarCore/Utilities/TransactionSyncReducer.swift`) and the app's two-phase cursor-commit flow (`POST /api/transactions/sync/cursors`, `SyncCursorCommitRequest`) work unchanged for both providers.
3. **Webhooks are explicitly out of scope.** Both providers offer webhooks (Plaid; Teller HMAC-signed `enrollment.disconnected`, `transactions.processed` — docs retrieved 2026-06-12), but both require a publicly reachable HTTPS endpoint, which is incompatible with the local-first promise. VaultPeek already polls Plaid; the abstraction stays polling-based. If a managed tier ever adds a hosted webhook relay, that is a separate hosted component with its own tension callout (§10) — it must relay *change signals only* ("connection X changed"), never financial payloads.

## 4. Storage changes (`TokenStore`, `Database.swift`)

Minimal, additive, and backward-compatible:

- **`items` table** (`ItemModel` in `Storage/Database.swift`): add a `provider` string column via a new migration (`AddProviderToItems`), defaulting existing rows to `"plaid"`. The primary key stays the provider's native connection id (Plaid ids and Teller ids are globally distinct token formats; collisions are not realistic, and keeping the raw id avoids rewriting Keychain account names for existing users).
- **`sync_cursors` table** (`SyncCursorModel`): no schema change. The `cursor` column already stores an opaque string per connection; Teller adapters store serialized `ProviderSyncState` JSON there. Optionally rename in docs only ("sync state"), not in schema.
- **`TokenStore`** (`Storage/TokenStore.swift`): `saveItem` gains a `provider:` parameter; `getAllItems()` gains a by-provider variant for capability-aware refresh loops; everything else (`updateItemStatus`, cursor save/get, stats used by `/api/status`) is provider-neutral already.
- A small `ProviderRegistry` (id → `any BankDataProvider`) is constructed in `App.swift` from `ServerConfig` and handed to routes in place of the concrete `PlaidClient`. Routes look up the provider per item row (`item.provider`).

## 5. DTO normalization into `PlaidBarCore` models

Acceptance criterion 4: document which data features are normalized and which remain provider-specific.

### Normalized (both providers → core DTOs)

| Core field | Plaid source | Teller source | Notes |
|---|---|---|---|
| `AccountDTO.id` | `account_id` | account `id` | provider-scoped opaque string |
| `AccountDTO.itemId` | item id | enrollment id | the Connection id; rename to `connectionId` is a future core change, not required |
| `AccountDTO.type` | `type` → `AccountType` | depository/credit only | Teller can never produce `.loan`/`.investment` (capability flag, §6) |
| `AccountDTO.mask` | `mask` | `last_four` | |
| `BalanceDTO.available/current` | `balances.available/current` | `available`/`ledger` | Teller values are **strings** → parsed to `Double` in adapter |
| `BalanceDTO.limit` | `balances.limit` | **not provided** | Teller credit cards get `limit == nil`; `BalanceDTO.utilizationPercent` already returns `nil` in that case (`Sources/PlaidBarCore/Models/BalanceDTO.swift`), so credit-utilization UI degrades gracefully — but must say "limit unavailable", never imply zero (ACCESSIBILITY.md: never meaning through color/absence alone) |
| `TransactionDTO.amount` | Plaid sign convention: **positive = money out** (documented in `TransactionDTO.swift`) | signed string, **negative = money out** | **Teller adapter flips the sign and parses the string.** The Plaid convention is the normalized convention because `TransactionDTO.isIncome`, `SpendingSummary`, and every chart already assume it |
| `TransactionDTO.date` | `date` (YYYY-MM-DD) | ISO 8601 `date` | truncate to day |
| `TransactionDTO.name/merchantName` | `name`/`merchant_name` | `description`/`details.counterparty.name` | |
| `TransactionDTO.category` | `personal_finance_category.primary` → `SpendingCategory` | Teller's 28 standardized categories → static mapping table → `SpendingCategory` | lossy on both sides; unmapped → `.other`. The Teller table is a pure `[String: SpendingCategory]` constant — trivially unit-testable |
| `TransactionDTO.pending` | `pending` | `status == "pending"` | |
| `ItemConnectionStatus` | `ITEM_LOGIN_REQUIRED` → `.loginRequired` | `enrollment.disconnected` reason / 401-class errors → `.loginRequired` | see §8 error normalization |

### Provider-specific (kept inside the adapter, or dropped)

- **Plaid:** `personal_finance_category.detailed` + confidence, `PlaidItem.availableProducts/billedProducts`, request ids.
- **Teller:** `running_balance` on posted transactions (deliberately not surfaced in v1; noted as a future opportunity — it could back `BalanceTrend` charts *without* billed balance calls), transaction `type` (`card_payment`, `atm`, …), HATEOAS `links`, identity/verify products.
- Anything provider-specific that later proves valuable gets promoted via an explicit core DTO change, never leaked through a stringly-typed side channel.

## 6. Capability flags

Capabilities are how the rest of the system avoids `if provider == .teller` conditionals, and how cost traps are made structural rather than tribal knowledge:

```swift
struct ProviderCapabilities: Sendable {
    let accountTypes: Set<AccountType>     // plaid: all; teller: [.depository, .credit]
    let syncStrategy: SyncStrategy         // .cursor | .windowedRescan
    let balanceCost: BalanceCost           // .includedWithSync | .billedPerCall
    let providesCreditLimit: Bool          // plaid: true; teller: false
    let supportsHostedLink: Bool           // plaid: true; teller: false (local Connect page instead)
    let supportsUpdateModeRepair: Bool     // plaid: true; teller: true (Connect repair)
    let multipleConnectionsPerLinkSession: Bool  // plaid Hosted Link: true; teller: false
    let geography: Set<String>             // country codes; teller: ["US"]
}
```

Concrete consumers:

- **`balanceCost == .billedPerCall`** → the refresh scheduler must never include `getBalances` in the routine poll loop for that provider; balances come from `listAccounts`/sync data instead. This is the single most important flag: naive 4×/day balance polling on 3 Teller banks ≈ $36.90/mo per user *(estimate, retrieved pricing 2026-06-12)* vs ~$0.90/mo *(estimate)* for transactions-only sync.
- **`accountTypes`** → setup/link UI sets expectations ("investments not available via this provider") before the user connects; the wealth-summary surface knows not to await investment accounts from Teller connections.
- **`providesCreditLimit == false`** → credit views show "limit unavailable" state rather than treating `nil` as anomalous.
- **`/api/status`** may expose *capability summaries* per configured provider (readiness metadata only — consistent with the existing rule that status never exposes tokens, account ids, balances, or transactions).

## 7. Config and Keychain handling per provider

### Config (`Config/ServerConfig.swift`)

Today: flat `plaidClientId`/`plaidSecret`/`plaidEnvironment` with the load order CLI flags > config file > environment, and the deliberate credential-less setup state (`credentialsConfigured == false` → routes return 503, server still boots for `/health` + `/api/status`). The abstraction generalizes, preserving all of that:

```swift
struct ServerConfig {
    let providers: [ProviderID: ProviderConfig]
    var configuredProviders: Set<ProviderID> { ... }   // replaces credentialsConfigured

    enum ProviderConfig {
        case plaid(clientId: String, secret: String, environment: PlaidEnvironment)
        case teller(applicationId: String, certificateRef: String, environment: TellerEnvironment)
    }
}
```

- `server.conf` keys: existing `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV` unchanged; new `TELLER_APPLICATION_ID`, `TELLER_CERTIFICATE_REF`, `TELLER_ENV` (sandbox | development | production — Teller's development env is real banks, unbilled, 100-enrollment cap; retrieved 2026-06-12).
- The 503 setup-state semantics become **per provider**: a Teller-only config serves Teller routes and returns the credential-guidance error only for Plaid-backed connections, and vice versa. `PlaidError.credentialsNotConfigured` generalizes to `ProviderError.credentialsNotConfigured(ProviderID)` (§8).

### Keychain (`Storage/PlaidTokenVault.swift` → `ProviderTokenVault`)

Two distinct secret classes per provider, both staying strictly inside the server process (the hard security boundary from ARCHITECTURE.md is unchanged — the SwiftUI app never sees any of this):

1. **Per-connection credentials** (Plaid `access_token`, Teller access token). Today's pattern generalizes cleanly: SQLite stores only a reference, secret bytes live in Keychain.
   - Keep the existing service (`LocalDataStore.plaidAccessTokenKeychainService`) and `keychain:<item_id>` reference format for **existing Plaid rows** — zero migration for current users.
   - New writes use a provider-namespaced reference `keychain:<provider>:<connection_id>` with a per-provider service constant added beside the existing one in `Sources/PlaidBarCore/Utilities/LocalDataStore.swift`. `resolve(storedToken:)` parses both formats (no provider segment ⇒ plaid). `deleteOrphanedTokens(referencedItemIds:)` and `pruneOrphanedKeychainTokens()` extend to iterate all provider services.
2. **App-level provider secrets.** Plaid: `client_id`/`secret` stay in `server.conf`/env as today (BYO model). Teller: the **mTLS client certificate + private key is the analog of Plaid's `secret`** and must never ship in a distributed binary. Proposed handling: import the user's Teller cert/key as a `SecIdentity` in the login Keychain; `TELLER_CERTIFICATE_REF` in `server.conf` names the identity; the Teller adapter resolves it at request time and answers `URLSession` client-certificate challenges via `URLSessionDelegate` (standard `SecIdentity` flow — no Apple-platform blocker). A PEM-file path fallback (0600 perms enforced, same pattern as `ServerConfig.writePrivateTextFile`) is acceptable for the BYO power-user tier but Keychain is the default.

## 8. Error normalization and status mapping

Acceptance criterion 2: preserve provider-specific error/recovery details **without leaking raw provider payloads to UI**.

Today's pipeline: `PlaidError.apiError(statusCode:errorType:errorCode:errorMessage:)` → routes pattern-match `errorCode == "ITEM_LOGIN_REQUIRED"` → `ItemConnectionStatus.loginRequired` persisted on the item row → app reads normalized status. The UI never sees the Plaid payload. The abstraction keeps that exact shape and widens it:

```swift
enum ProviderError: Error, Sendable {
    case credentialsNotConfigured(ProviderID)          // → 503 + setup guidance (as today)
    case reauthRequired(ProviderDetail)                // plaid ITEM_LOGIN_REQUIRED;
                                                       // teller 401 / enrollment.disconnected
    case connectionGone(ProviderDetail)                // plaid INVALID_ACCESS_TOKEN /
                                                       // ITEM_NOT_FOUND / ITEM_NOT_ACCESSIBLE
    case rateLimited(ProviderDetail)                   // HTTP 429 (both)
    case transient(ProviderDetail)                     // retryable transport/5xx (both)
    case providerFailure(ProviderDetail)               // everything else

    struct ProviderDetail: Sendable {
        let provider: ProviderID
        let httpStatus: Int?
        let rawCode: String?       // e.g. "ITEM_LOGIN_REQUIRED" — server logs ONLY
        let message: String        // sanitized; safe to log
    }
}
```

- `ProviderDetail` is **logged server-side and stored nowhere the app can read**. Routes map `ProviderError` cases → `ItemConnectionStatus` (`.loginRequired`/`.error`) and HTTP status, exactly as `AccountRoutes.itemStatus(for:)` and `TransactionRoutes` do today. `ItemConnectionStatus` (in `Sources/PlaidBarCore/Models/LinkResponse.swift`) is the *only* error vocabulary that crosses the localhost boundary.
- The disconnect ordering rule generalizes verbatim from `AccountRoutes.removeItem` + `canDeleteLocalItemAfterPlaidRemoveError`: revoke at provider first; on `connectionGone` proceed to local deletion; on any other failure keep the local row (and Keychain entry) for retry and surface 502. This rule is provider-agnostic once errors are normalized — which is what makes the disconnect tests in §9 writable once, against the protocol.
- Retry policy (`PlaidClient`'s exponential backoff, retryable-status/transport classification, `singleAttempt` for non-idempotent exchange/remove) moves to a shared `ProviderHTTPTransport` helper so Teller inherits identical semantics; the static helpers (`isRetryableHTTPStatus`, `retryDelayNanoseconds`, `allowedAttempts`) are already pure and tested.

## 9. Test strategy

Following the repo convention (CLAUDE.md): Swift Testing (not XCTest), shared logic testable without network, fixtures always synthetic/sandbox.

1. **Provider contract suite** (`Tests/PlaidBarServerTests/ProviderContractTests.swift`): one parameterized suite run against every `BankDataProvider` conformance, backed by a stub HTTP transport (`PlaidClient` already accepts an injectable `URLSession`; the Teller adapter follows suit, including a stub for the mTLS challenge path). The contract asserts the normalization invariants for each provider: amount sign convention, date format, `nil` limit handling, status mapping for the reauth-class error, sync-delta correctness, opaque-state round-trip.
2. **Fixtures** (`Tests/PlaidBarServerTests/Fixtures/{plaid,teller}/*.json`): synthetic JSON only — never recorded production payloads.
   - plaid: `accounts.json`, `transactions_sync_page1.json`/`page2.json` (hasMore pagination), `error_item_login_required.json`, `error_invalid_access_token.json`.
   - teller: `accounts.json` (string balances, `last_four`, no limit), `transactions_window_a.json` / `transactions_window_b.json` where window B re-IDs a pending→posted transaction from window A — the case that proves the overlap-rescan dedupe emits `removed:[oldId] + added:[newId]` and that `TransactionSyncReducer` converges; `error_unauthorized.json`.
3. **Mapping unit tests**: the pure static mappers (`PlaidAccount → AccountDTO`, `TellerTransaction → TransactionDTO`, Teller category table) get direct table-driven tests. Core-side behavior they feed (`SpendingSummary`, `RecurringDetector`, `TransactionSyncReducer`) already has tests in `Tests/PlaidBarCoreTests/` and needs no provider awareness.
4. **Entitlement gating tests** (acceptance criterion 5): plan-limit logic is a pure function proposed for `PlaidBarCore` (most testable logic lives there), e.g. `ConnectionEntitlement.canAddConnection(currentCount:planLimit:)`. Tests assert: gate counts connections **across providers** (2 Plaid + 1 Teller == 3 against the limit); `connectInstitution` route refuses with a normalized, non-provider-specific error when at limit; `disconnectInstitution` frees a slot; the gate never inspects provider-specific data. (How the limit value is obtained — local config vs Stripe entitlement check — is the companion billing doc's problem; the gate function is identical either way.)
5. **Disconnect behavior tests** (acceptance criterion 5): against both adapters via the contract suite — revoke fails with `transient` → local row + Keychain entry retained, 502 returned; revoke fails with `connectionGone` → local deletion proceeds; success → row, cursor, and Keychain entry all removed (mirrors `TokenStore.deleteItem` + orphan pruning today); per-provider Keychain namespacing means deleting a Teller connection cannot touch a Plaid token.
6. **Fixture provider**: a third conformance, `FixtureProvider`, serves the demo dataset. This makes `--demo` mode the abstraction's first consumer and keeps the contract suite honest (three implementations, not two).
7. **CI gate**: all of the above must pass `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` — every proposed type above is designed `Sendable`-first for that reason.

## 10. Local-first tension and the managed tier

The abstraction itself is **fully local**: BYO-Plaid and BYO-Teller both keep every secret and every byte of financial data on the user's machine, preserving the product promise (no hosted backend, no telemetry). Two places where a hosted component becomes unavoidable, and the minimal footprint for each:

1. **Managed Plaid linking** (user doesn't bring their own Plaid keys): requires a hosted **link-token broker + entitlement check, plus a stateless data-plane relay**. The broker holds VaultPeek's Plaid `client_secret`, mints link tokens, and performs the public-token exchange; the resulting `access_token` is delivered once to the local server and stored in the local Keychain vault. After linking, financial data is **never stored** hosted — but (per the managed-link architecture doc) data calls cannot go directly device→Plaid in managed mode, because every Plaid data call requires the `secret`, which Plaid forbids shipping in clients; they are relayed through a stateless, memory-only **blind proxy** that persists and logs nothing. The abstraction absorbs this as a transport seam inside the Plaid adapter (direct-to-Plaid for BYO; broker for token acquisition + blind proxy for data calls in managed mode) — the protocol shape in §3 is unchanged.
2. **Managed Teller would need its own hosted relay.** Teller access tokens are useless without the application's mTLS certificate (auth docs, retrieved 2026-06-12). A broker therefore *cannot* hand the token to the client for direct use unless the client also holds a certificate (the exact analog of why Plaid's `secret` can't ship in clients) — a managed-Teller tier would route **every API call through a cert-holding hosted relay**: the same transit-only posture as the Plaid blind proxy above, but a second relay built for a secondary provider with disqualifying coverage gaps. Consequences for this design:
   - Managed-Teller is **out of scope** unless Teller agrees to per-user/per-device certificate issuance (not a documented offering — open question for Teller sales, §11). The capability/config model already accommodates this: a per-user cert is just a different `certificateRef`.
   - BYO-Teller, by contrast, is *more* local-first-friendly than BYO-Plaid: the development environment offers 100 real connections with no production-approval gate (retrieved 2026-06-12).
3. **Webhooks** (both providers) need a public HTTPS endpoint; the design stays polling-based (§3). Any future hosted webhook relay must carry change *signals* only, never payloads.

## 11. Open questions

Items 1–3 are questions for Teller (sales/support); items 4–6 are VaultPeek product decisions for Felipe.

1. **Teller native Connect terms**: TellerKit (github.com/tellerhq/tellerkit) is a single-day repo from 2024-05 with no license and no SPM manifest; the predecessor repo states native usage is "not supported unless separately agreed." Default plan is therefore the web Connect widget served from the local server (mirrors the existing Hosted Link + `PendingLinkSessionStore` flow); native bindings need a Teller agreement first.
2. **Per-user Teller certificates** — gates any managed-Teller tier (§10).
3. **Teller transaction history depth** — undocumented, institution-dependent; affects first-sync expectations.
4. **Core naming**: rename `AccountDTO.itemId`/`TransactionDTO.itemId` → `connectionId` (a coordinated core+app change; cosmetic, deferred).
5. **Surface `running_balance`** from Teller to power balance trends without billed balance calls — promising but needs a core DTO change (§5).
6. **Whether the UI shows provider identity per connection** (probably yes in Settings, no in dashboard surfaces).

## 12. Related

- AND-346 (this doc), parent AND-343 (consumer strategy epic). Companion docs in `docs/strategy/` cover managed linking, Teller as a cost-transparent tier, and Stripe entitlements; this doc defines only the server-side abstraction they depend on.
- Code referenced: `Sources/PlaidBarServer/Plaid/PlaidClient.swift`, `Sources/PlaidBarServer/Plaid/PlaidModels.swift`, `Sources/PlaidBarServer/Storage/TokenStore.swift`, `Sources/PlaidBarServer/Storage/PlaidTokenVault.swift`, `Sources/PlaidBarServer/Storage/Database.swift`, `Sources/PlaidBarServer/Config/ServerConfig.swift`, `Sources/PlaidBarServer/Routes/{Account,Link,Transaction}Routes.swift`, `Sources/PlaidBarCore/Models/{AccountDTO,BalanceDTO,TransactionDTO,SyncResponse,LinkResponse}.swift`, `Sources/PlaidBarCore/Utilities/TransactionSyncReducer.swift`.
