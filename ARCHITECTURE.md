# Architecture

Deep dive into PlaidBar's design decisions and implementation details.

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
┌─ PlaidBar.app ──────────────────────┐
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
- **Extensibility**: Future CLI tools or iOS app can use the same server
- **Testability**: Server API is testable with `curl`

### Process Lifecycle

Both processes are started together via `Scripts/run.sh`:

```bash
swift run PlaidBarServer --sandbox &   # Background
swift run PlaidBar &                    # Background
wait                                    # Ctrl+C stops both
```

In production, the server would run as a LaunchAgent for auto-start at login.

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
| `Formatters.swift` | Currency (full/abbreviated/compact), date, percentage formatting |
| `Constants.swift` | Ports, intervals, thresholds, keychain keys |

All types are `Codable`, `Sendable`, and `Hashable` where appropriate.

### PlaidBarServer (Hummingbird 2)

The companion server. Binds to `127.0.0.1:8484`.

**Routes:**

```
GET  /health                    → 200 OK
POST /api/link/create           → { linkToken, linkUrl }
GET  /oauth/callback?public_token=...  → HTML success/error page
GET  /api/accounts              → [AccountDTO]
GET  /api/accounts/balances     → [AccountDTO] (real-time)
DELETE /api/accounts/:itemId    → 204 No Content
GET  /api/transactions/sync     → SyncResponse
GET  /api/status                → ServerStatus
GET  /api/items                 → [ItemStatus]
```

**Storage (SQLite via Fluent):**

```sql
-- items: stores Plaid access tokens
CREATE TABLE items (
    id TEXT PRIMARY KEY,          -- Plaid item_id
    access_token TEXT NOT NULL,
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
└── MainPopover
    ├── SetupView (if !isSetupComplete)
    └── TabContainer
        ├── AccountsView (grouped by type, net balance)
        ├── TransactionsView (search, group by date)
        ├── SpendingView (donut chart, category breakdown)
        └── CreditView (utilization bars, warnings)
```

**Background Refresh:**

A `Task` runs every 15 minutes to refresh account balances (free cached endpoint) and every 30 minutes for transaction sync (cursor-based incremental).

## Data Flow

### Account Linking (F1)

```
1. User clicks "Add Account"
2. App → POST /api/link/create → Server
3. Server → POST /link/token/create → Plaid
4. Server returns { linkToken, linkUrl }
5. App opens linkUrl in Safari
6. User completes Plaid Link in browser
7. Plaid redirects to localhost:8484/oauth/callback?public_token=xxx
8. Server exchanges public_token → access_token
9. Server stores access_token in SQLite
10. App refreshes → new accounts appear
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

1. Environment variables: `PLAID_CLIENT_ID`, `PLAID_SECRET`
2. CLI flags: `--port`, `--sandbox`, `--config`
3. Defaults: port 8484, sandbox mode if `--sandbox` flag

### Data Storage

```
~/.plaidbar/
├── plaidbar.sqlite    # Fluent database (items + sync cursors)
└── auth-token         # App ↔ server shared secret
```

## Testing Strategy

61 tests across 3 suites, all using Swift Testing framework:

| Suite | Tests | Coverage |
|-------|-------|----------|
| PlaidBarCoreTests | 36 | DTOs, formatters, constants, Codable roundtrips |
| PlaidBarServerTests | 5 | Plaid response decoding, config, type conversion |
| PlaidBarTests | 20 | Business logic: net balance, spending aggregation, filtering |

Server integration tests (starting Hummingbird, making HTTP calls) are planned for v0.2.

## Future Architecture Considerations

- **LaunchAgent**: Ship a plist for auto-starting the server at login
- **Webhooks**: Plaid can push updates instead of polling — requires a tunnel or relay service
- **iOS Companion**: The server API is already REST; an iOS app could connect via Tailscale/local network
- **Multiple providers**: Abstract the Plaid client behind a protocol to support Teller, MX, etc.
