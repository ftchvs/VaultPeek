# Architecture

Deep dive into VaultPeek's design decisions and implementation details.

VaultPeek was renamed from PlaidBar; SwiftPM target names (`PlaidBar`,
`PlaidBarServer`, `PlaidBarCore`), `PLAIDBAR_*` environment variables, SQLite
filenames, and the Keychain service intentionally keep the old name for
compatibility. See the "Naming compatibility" section in
[README.md](README.md).

## Design Principles

1. **Privacy first** — All data stays on the user's machine. No cloud, no sync, no telemetry.
2. **Secret isolation** — Plaid credentials and access tokens never touch the app binary. The companion server owns all secrets.
3. **Offline resilience** — The app caches everything locally. It works without network access using cached data.
4. **Single toolchain** — Both app and server are Swift. One language, one package manager, lower barrier for contributors.

## Two-Process Architecture

### Why not a single process?

Plaid's security model requires that `client_secret` and `access_token` never exist in client-side code. A browser extension or Electron app would face the same constraint. Our solution: a lightweight local server that holds all secrets and proxies API calls.

```
User clicks "Refresh"
        │
        ▼
┌─ VaultPeek.app ─────────────────────┐
│  GET http://127.0.0.1:8484/api/accounts  │
└──────────────────┬──────────────────┘
                   │ localhost only
┌──────────────────▼──────────────────┐
│  PlaidBarServer                     │
│  1. Load access_token from SQLite   │
│  2. POST https://plaid.com/accounts/get │
│  3. Transform → AccountDTO          │
│  4. Return JSON to app              │
└──────────────────┬──────────────────┘
                   │ HTTPS
┌──────────────────▼──────────────────┐
│  Plaid API                          │
└─────────────────────────────────────┘
```

Benefits:
- **Security**: Secrets never in app memory
- **Restartability**: Server and app restart independently
- **Extensibility**: The source-built `plaidbar-cli` uses the same authenticated
  localhost server without exposing Plaid credentials to terminal clients
- **Testability**: Server API is testable with `curl`

### Process Lifecycle

For source-based sandbox development, both processes can be started together via
`Scripts/run.sh`:

```bash
swift run PlaidBarServer --sandbox &   # Background
swift run PlaidBar &                    # Background
wait                                    # Ctrl+C stops both
```

For app-bundle style launches, PlaidBar can start its bundled companion server
when needed. Source/developer checkouts can also run the server explicitly with
`swift run PlaidBarServer`.

## Target Breakdown

### PlaidBarCore (Shared Library)

Zero external dependencies. Contains:

| File | Purpose |
|------|---------|
| `AccountDTO.swift` | Account model + `AccountType` enum |
| `BalanceDTO.swift` | Balance with computed `effectiveBalance` and `utilizationPercent` |
| `TransactionDTO.swift` | Transaction with `isIncome`, `displayName`, `displayAmount` |
| `SpendingCategory.swift` | 17 categories mapped to Plaid's `personal_finance_category.primary` |
| `LinkResponse.swift` | Link token response + item status models |
| `SyncResponse.swift` | Transaction sync response (added/modified/removed) |
| `ServerStatus.swift` | Server health + `PlaidEnvironment` enum |
| `LocalAIInsights.swift` | Local-only activity receipt and category-hint presentation models |
| `AttentionQueue.swift` | Prioritized recovery prompts for dashboard/status surfaces |
| `Dashboard*.swift` | Dashboard status, nav, change, empty, and drill-in presenters |
| `Formatters.swift` | Currency (full/abbreviated/compact), date, percentage formatting |
| `Constants.swift` | Ports, intervals, thresholds, keychain keys |

All types are `Codable`, `Sendable`, and `Hashable` where appropriate.

### PlaidBarServer (Hummingbird 2)

The companion server. Binds to `127.0.0.1:8484` by default, or the
`PLAIDBAR_SERVER_PORT` / `--port` override when configured.

**Routes:**

```
GET  /health                    → 200 OK
POST /api/link/create           → { linkToken, linkUrl }
GET  /oauth/callback?state=...  → Hosted Link success/error page
GET  /api/accounts              → [AccountDTO]
GET  /api/accounts/balances     → [AccountDTO] (real-time)
DELETE /api/accounts/:itemId    → 204 No Content
GET  /api/transactions/sync     → SyncResponse
GET  /api/status                → ServerStatus
GET  /api/items                 → [ItemStatus]
```

**Storage (SQLite via Fluent + Keychain where available):**

```sql
-- items: stores Plaid item records and token references
CREATE TABLE items (
    id TEXT PRIMARY KEY,
    access_token TEXT NOT NULL,   -- keychain:<item_id> on macOS runtime builds
    institution_id TEXT,
    institution_name TEXT,
    status TEXT NOT NULL,         -- connected | login_required | error
    created_at DATETIME,
    updated_at DATETIME
);

-- sync_cursors: tracks transaction sync position per item
CREATE TABLE sync_cursors (
    item_id TEXT PRIMARY KEY,
    cursor TEXT NOT NULL,
    updated_at DATETIME
);
```

On macOS runtime builds with Security framework support, Plaid access-token
bytes are stored in Keychain and SQLite stores `keychain:<item_id>` references.
Fallback builds without Keychain support may store token bytes locally in the
SQLite store; release and security docs call out that boundary explicitly.

**Plaid Client:**

An `actor`-based HTTP client using Foundation `URLSession`. Handles:
- Link token creation
- Public → access token exchange
- Account and balance fetching
- Incremental transaction sync (cursor-based)
- Item removal

All Plaid requests use `snake_case` JSON encoding/decoding to match Plaid's API convention.

### PlaidBar (SwiftUI App)

A menu bar-only app (`LSUIElement = true`) using `MenuBarExtra` with `.window` style.

**State Management:**

```swift
@Observable @MainActor
final class AppState {
    var accounts: [AccountDTO] = []
    var transactions: [TransactionDTO] = []
    // ... computed: netBalance, transactionsByDate, spendingByCategory
}
```

Single `@Observable` state object injected via SwiftUI `@Environment`. No Combine, no `ObservableObject`.

**View Hierarchy:**

```
MenuBarExtra
├── MenuBarLabel (icon + balance text)
└── MainPopover (dashboard-first surface)
    ├── SetupView (if setup is incomplete)
    ├── status strip + latest change receipt
    ├── 365-day spend/cashflow heatmap
    ├── DashboardNavBand (Cash/Credit/Savings/Debt/Status filters)
    ├── compact account rows + selected account drill-in / AccountDetailFlyout
    ├── AttentionQueueView (degraded-item recovery prompts)
    └── local insight receipt
```

**Background Refresh:**

A `Task` runs every 15 minutes to refresh account balances (free cached endpoint) and every 30 minutes for transaction sync (cursor-based incremental).

## Data Flow

### Account Linking (F1)

```
1. User clicks "Add Account"
2. App → POST /api/link/create → Server
3. Server creates a one-time local state and POSTs /link/token/create → Plaid
4. Server returns { linkToken, linkUrl }
5. App opens linkUrl in Safari
6. User completes Plaid Link in browser
7. Plaid redirects to localhost:8484/oauth/callback?state=xxx
8. Server consumes the one-time state and fetches the completed Link session
9. Server exchanges public_token → access_token
10. Server stores access_token in SQLite
11. App refreshes → new accounts appear
```

### Transaction Sync (F3)

Uses Plaid's cursor-based `/transactions/sync` for incremental updates:

```
1. App → GET /api/transactions/sync
2. Server loads cursor from SQLite (or "" for first sync)
3. Server → POST /transactions/sync → Plaid
4. Plaid returns { added, modified, removed, nextCursor, hasMore }
5. Server saves nextCursor, transforms → TransactionDTOs
6. App merges: appends added, updates modified, removes deleted
7. If hasMore, repeat from step 2
```

First sync pulls ~90 days of history. Subsequent syncs are incremental (typically 0-5 new transactions).

## Concurrency Model

Swift 6 strict concurrency throughout:

| Component | Isolation |
|-----------|-----------|
| `AppState` | `@MainActor` (UI state) |
| `ServerClient` | `actor` (network calls) |
| `PlaidClient` | `actor` (Plaid API calls) |
| `TokenStore` | `actor` (database access) |
| All DTOs | `Sendable` structs |
| Route handlers | `@Sendable` closures |

No data races by construction.

## Configuration

### Server Config Resolution

1. Environment variables: `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV`, `PLAIDBAR_SERVER_PORT`, `PLAIDBAR_DATA_DIR`
2. Optional config file from `--config`, using the same `KEY=value` names as the environment
3. CLI overrides: `--port`, `--sandbox`
4. Defaults: production mode and port 8484 unless overridden

When a config file is provided, its values override the inherited process
environment. Explicit CLI flags still win so one-off launches can safely
override a checked local config.

The menu bar app does not read the server config file directly. If server config
changes `PLAIDBAR_SERVER_PORT` or `PLAIDBAR_DATA_DIR`, the same values must be in
the app process environment so `ServerClient` reaches the correct server and
auth-token path.

### Data Storage

```
~/.vaultpeek/
├── plaidbar-sandbox.sqlite       # Sandbox items + sync cursors
├── plaidbar-production.sqlite    # Production items + sync cursors
└── auth-token         # App ↔ server shared secret
```

`~/.vaultpeek/` is the default since the VaultPeek rename. Default installs
copy missing files from the legacy `~/.plaidbar/` directory on startup without
overwriting newer files; `PLAIDBAR_DATA_DIR` still overrides the location, and
the SQLite filenames intentionally keep the `plaidbar-` prefix.

On upgrade, a legacy `plaidbar.sqlite`, its SQLite sidecar files, and its
matching transaction cache are copied into an environment-scoped database only
when the legacy environment is explicit
(`PLAIDBAR_MIGRATE_LEGACY_DATABASE=sandbox|production`) or can be inferred from
the existing transaction-cache context. Ambiguous legacy databases stay
untouched to avoid sandbox/production token crossover. Explicit migration backs
up any existing scoped SQLite store and transaction cache before copying legacy
data, then writes a migration marker so restarts do not reapply stale legacy
data.

## Testing Strategy

Unit tests span 3 suites, all using Swift Testing framework:

| Suite | Coverage |
|-------|----------|
| PlaidBarCoreTests | DTOs, formatters, constants, Codable roundtrips |
| PlaidBarServerTests | Plaid response decoding, config, type conversion |
| PlaidBarTests | Business logic: net balance, spending aggregation, filtering |

Server tests cover config, status contracts, Plaid decoding, auth behavior, and
route-adjacent reducers. Full end-to-end Plaid sandbox coverage remains a manual
or smoke-test gate because it depends on external sandbox credentials.

Suite size is not hard-coded in these docs; derive the current count with `swift test list` or a ripgrep over `Tests/` (`rg -n "@Test" Tests/`), which is the source of truth.

## Future Architecture Considerations

- **Distribution**: Keep private DMG and source/developer paths stable; add
  notarization and Sparkle appcast only after signing and Gatekeeper checks are
  real
- **Webhooks**: Plaid can push updates instead of polling, but a relay/tunnel
  would need an explicit privacy review because PlaidBar has no hosted backend
- **Multiple providers**: Abstract the Plaid client behind a protocol only if it
  strengthens the local menu-bar instrument instead of becoming a generic
  provider playground
