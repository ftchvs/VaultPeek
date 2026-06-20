# Architecture

VaultPeek is intentionally split into a native macOS app, a local companion
server, and a shared core library. The split keeps Plaid secrets out of the UI
process and keeps the public product story simple: local app, local server,
Plaid API, local storage.

VaultPeek is the product name (formerly PlaidBar). Module, target, and
executable names below intentionally keep the PlaidBar name; see
[Naming Compatibility](#naming-compatibility).

## Module Boundaries

| Module | Responsibility | Must Not Do |
|--------|----------------|-------------|
| `PlaidBar` | SwiftUI menu bar app, popover, setup flow, settings, local client calls, notification UX | Store Plaid secrets, call Plaid directly, contain server persistence logic |
| `PlaidBarCore` | Shared DTOs, formatting, sync reducers, recurring detection, dashboard presenters, attention queue models, local insight receipt models, local data path helpers | Depend on SwiftUI, Hummingbird, Plaid network clients, or cloud AI SDKs |
| `PlaidBarServer` | Hummingbird localhost API, Plaid API client, SQLite storage, link flow, token vault, auth middleware | Render UI, depend on app state, expose secrets in status responses |
| `PlaidBarCache` | App-only disposable SwiftData read-model cache (`@Model` + `@ModelActor`) for instant cold render and offline reads, scoped per Plaid environment | Become a source of truth, reach the server/CLI/widget targets, write to the App Group container, or sync to iCloud |

## Runtime Topology

```text
VaultPeek.app
  SwiftUI MenuBarExtra
  Settings and setup windows
  ServerClient with local bearer token
        |
        | HTTP on 127.0.0.1:{port}
        v
PlaidBarServer
  /health without auth
  /api/* with local bearer token
  SQLite under ~/.vaultpeek/
  Plaid API client
        |
        | HTTPS
        v
Plaid API
```

## Local Server Contract

The app talks to the server through `ServerClient`. The server exposes:

- `GET /health`
- `GET /api/status` for version, environment, credential readiness, storage
  path, linked item count, synced item count, and last sync time
- `GET /api/items`
- `POST /api/link/create`
- `POST /api/link/update/:itemId`
- `GET /oauth/callback`
- `GET /api/accounts`
- `GET /api/accounts/balances`
- `GET /api/transactions/sync`
- `POST /api/transactions/cursors`
- `DELETE /api/accounts/:itemId`

`/health` and `/oauth/callback` are public on localhost. `/api/*` requires the
local bearer token stored in the VaultPeek data directory.

`plaidbar-cli` is a source/developer local client for this same contract. It
reads the local bearer token, talks to `127.0.0.1`, and prints table or `--json`
output; it does not read Plaid Dashboard credentials or bypass the companion
server.

Local insight receipts are intentionally app/core-side presentation artifacts.
They summarize local transaction rows and can expose disabled/no-runtime state,
source-row count, windows, top categories, recurring estimates, and category
hints. They must not add a cloud AI path or send raw transaction data off-device.

## Configuration

The server reads configuration from environment variables, an optional config
file, and explicit CLI flags. Later inputs override earlier ones.

| Setting | Purpose |
|---------|---------|
| `PLAID_CLIENT_ID` | Plaid client ID for sandbox or production |
| `PLAID_SECRET` | Plaid secret for the selected environment |
| `PLAID_ENV` | `sandbox` or `production` |
| `PLAIDBAR_SERVER_PORT` | Local server port, default from `PlaidBarConstants` |
| `PLAIDBAR_DATA_DIR` | Local data directory, default `~/.vaultpeek/` |
| `PLAIDBAR_MIGRATE_LEGACY_DATABASE` | Explicit legacy migration environment |

The default server should bind to localhost only. If a future change expands
network reachability, that change must update `SECURITY.md`, this document, and
the setup UI.

## Storage Layout

Default local data directory:

```text
~/.vaultpeek/
```

Default installs copy missing files from the legacy `~/.plaidbar/` directory
into `~/.vaultpeek/` on startup. Existing `~/.vaultpeek/` files win, so the
migration is idempotent and does not overwrite newer data. `PLAIDBAR_DATA_DIR`
keeps pointing app and server to an explicit custom directory when needed.

Current important files:

| File | Purpose |
|------|---------|
| `auth-token` | Local app-server bearer token |
| `plaidbar-sandbox.sqlite` | Sandbox Plaid item/account storage and token references |
| `plaidbar-production.sqlite` | Production Plaid item/account storage and token references |
| `transactions-*.json` | Environment/path-scoped transaction cache |
| `pending-link-sessions.json` | Pending Plaid Hosted Link state |

The data directory is created with private user permissions. Cache/token files
are written with private file permissions where the platform supports it.
On macOS runtime builds with Security framework support, Plaid access-token
bytes are stored in Keychain and SQLite stores `keychain:<item_id>` references.
Those Keychain references intentionally keep the original PlaidBar service name
during the storage migration so existing linked items keep resolving.
Fallback builds without Keychain support may store token bytes locally in the
SQLite store, so release/security docs must stay explicit about that boundary.

## Glance Surfaces: App Group, Widget, Control Center, App Intents (AND-515)

On the macOS 26 floor, VaultPeek ships out-of-process "glance" surfaces that run
in a separate widget extension: a Notification Center / desktop widget, a
Control Center control, and App Intents reachable from Spotlight, Siri, and
Shortcuts. The extension cannot reach the app's `AppState` or the companion
server, so the app publishes a small display-only snapshot through a shared App
Group container.

| Element | Module | Responsibility | Must Not Do |
|---------|--------|----------------|-------------|
| `GlanceSnapshot` + `GlanceSnapshotStore` | `PlaidBarCore` | Define and read/write the shared display contract (App Group file, atomic, `0600`) | Carry tokens, account IDs, merchants, or transaction rows |
| `PlaidBarWidgetExtension` | widget extension | Render the widget, host the Control Center control, and expose the `Refresh balances` App Intent | Call Plaid, call the companion server, read the bearer token, or hold credentials |
| `AppState` glance writer | `PlaidBar` | Debounce-write the snapshot on data change, clear on reset, consume queued commands | Write sensitive values into the snapshot |

### Snapshot and command contract

- **App Group:** `group.com.ftchvs.PlaidBar`. `GlanceSnapshotStore` resolves it
  via `containerURL(forSecurityApplicationGroupIdentifier:)` and falls back to
  the local data directory when no App Group entitlement is present (the widget
  then shows an "Open VaultPeek" unavailable state).
- **`glance-snapshot.json`** holds *only* net worth, today's change, a
  normalized sparkline, `updatedAt`, and an `isDemo` flag. Writes are atomic and
  debounced (`GlanceSnapshotWriteDebouncer`, ~400 ms) and skipped when the
  display content is unchanged.
- **`glance-command.json`** is a one-shot queue. The `RefreshBalancesIntent`
  writes a single typed `GlanceCommandRequest` (`refreshBalances` + timestamp)
  and opens the app; the running app consumes and deletes it, then performs the
  real refresh through `ServerClient`. The extension never refreshes data
  itself.
- **Deep link:** the widget opens `vaultpeek://dashboard`.

### Security boundary

The App Group is a second trust boundary and follows the same rule as the status
endpoint: only display-ready, low-sensitivity values cross it. The snapshot must
never contain Plaid access tokens, the local bearer token, Plaid client secrets,
account IDs, item IDs, account masks, merchant names, or transaction rows, and
the command channel carries no data-bearing parameters.

**Privacy Mask / App Lock contract.** While Privacy Mask or App Lock is active,
the app re-writes the shared `FinanceSnapshot` (the value-bearing contract read
by the App Intents / Siri / Spotlight surfaces, the widget, and the Control
Center control) in a redacted, value-free form: no balances, safe-to-spend,
per-account figures, bills, or utilization — only `isMasked == true`. Redaction
happens at *write* time as defense-in-depth, on top of the *read*-time gate where
each reader independently checks `isMasked` (e.g. the widget gates on
`AppGroupSnapshotStore.loadIfAvailable()?.isMasked`) and withholds values or
shows placeholders. With both gates a reader that ignored `isMasked` would still
find no real figures to leak.

The widget's net-worth path additionally reads `glance-snapshot.json`. That file
is now re-written redacted on every mask/lock transition (AND-517):
`GlanceSnapshot.make(isMasked:)` calls `redacted()`, which zeroes net worth,
today's change, and the sparkline and sets `isRedacted`, while keeping only the
non-sensitive `updatedAt`/`isDemo` metadata. `AppState.writeGlanceSnapshot`
passes `shouldMaskFinancialValues`, so the on-disk glance file carries no real
figures while masked. The masked widget guarantee therefore now rests on two
independent gates — the redacted-at-write glance file **and** the read-time
`FinanceSnapshot.isMasked` check (the widget shows its placeholder/unavailable
state when masked) — so a reader that ignored `isMasked` would still find no real
net-worth, today's-change, or sparkline values on disk to leak.

If a future change adds any field to `GlanceSnapshot` or `FinanceSnapshot`, it
must be reviewed against this boundary, `SECURITY.md`, and the status-endpoint
contract.

## Naming Compatibility

VaultPeek was renamed from PlaidBar at the product level. The following
surfaces intentionally keep the PlaidBar name and must not be renamed without
an explicit migration plan:

- SwiftPM targets/products and app-bundle executables: `PlaidBar`,
  `PlaidBarServer`, `PlaidBarCore`, `plaidbar-cli` (staged rename, tracked
  separately).
- Environment variables and config keys: `PLAIDBAR_SERVER_PORT`,
  `PLAIDBAR_DATA_DIR`, `PLAIDBAR_MIGRATE_LEGACY_DATABASE`,
  `PLAIDBAR_SMOKE_PORT`.
- Keychain service: `PlaidBar.PlaidAccessToken` — SQLite `keychain:<item_id>`
  references must keep resolving.
- SQLite store filenames: `plaidbar-sandbox.sqlite`,
  `plaidbar-production.sqlite`.
- Legacy default data directory: `~/.plaidbar/` (migration source only).
- GitHub repository slug: `ftchvs/VaultPeek`. The old `ftchvs/PlaidBar` slug
  should redirect for compatibility.

## Status Endpoint Contract

`GET /api/status` is authenticated and release-auditable. It may expose only:

- app/server version
- Plaid environment
- whether Plaid credentials are configured
- local storage path
- linked item count
- synced item count
- sync readiness
- last sync time

It must not expose Plaid client secrets, access tokens, public tokens, local
auth tokens, account IDs, item IDs, account balances, transaction rows, or raw
Plaid error payloads.

## Sandbox and Production Separation

Sandbox and production must remain separated at every layer:

- separate server mode
- separate database file
- environment-specific transaction cache context
- setup UI that confirms expected mode before opening Plaid Link
- docs that avoid implying sandbox and production can be mixed safely

Legacy `plaidbar.sqlite` migration is intentionally conservative. Ambiguous
legacy data should not be copied into a scoped store.

## Link Flow

1. The app asks the local server to create a Plaid Hosted Link session.
2. The server creates a Plaid link token using the configured environment.
3. The browser opens the Hosted Link URL.
4. Plaid redirects to `http://localhost:{port}/oauth/callback`.
5. The server validates pending session state and exchanges the public token.
6. The server stores the resulting Plaid item locally.
7. The app refreshes item/account/status data from the local server.

The app should show preflight readiness before step 1 and visible recovery
states if any later step fails.

## Error Handling Principles

- Preserve last-known data during transient server or Plaid failures.
- Prefer typed, user-readable local errors over raw server bodies.
- Truncate server error messages before rendering.
- Do not clear local data because Plaid, network, or credential checks fail.
- Make each degraded state actionable: start server, check mode, add account,
  reconnect item, clear filters, or open Settings.

## Architecture Debt

- Add endpoint-level documentation for request/response DTOs.
- Add a clean duplicate-instance strategy and document expected behavior.
- Ship 1.0 as a privately-distributed, ad-hoc-signed DMG unless Developer ID
  signing, notarization, a private update channel, and clean-machine Gatekeeper
  checks are completed separately.
