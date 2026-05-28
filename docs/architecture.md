# Architecture

PlaidBar is intentionally split into a native macOS app, a local companion
server, and a shared core library. The split keeps Plaid secrets out of the UI
process and keeps the public product story simple: local app, local server,
Plaid API, local storage.

## Module Boundaries

| Module | Responsibility | Must Not Do |
|--------|----------------|-------------|
| `PlaidBar` | SwiftUI menu bar app, popover, setup flow, settings, local client calls, notification UX | Store Plaid secrets, call Plaid directly, contain server persistence logic |
| `PlaidBarCore` | Shared DTOs, formatting, sync reducers, recurring detection, presentation helpers, local data path helpers | Depend on SwiftUI, Hummingbird, or Plaid network clients |
| `PlaidBarServer` | Hummingbird localhost API, Plaid API client, SQLite storage, link flow, token vault, auth middleware | Render UI, depend on app state, expose secrets in status responses |

## Runtime Topology

```text
PlaidBar.app
  SwiftUI MenuBarExtra
  Settings and setup windows
  ServerClient with local bearer token
        |
        | HTTP on 127.0.0.1:{port}
        v
PlaidBarServer
  /health without auth
  /api/* with local bearer token
  SQLite under ~/.plaidbar/
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
local bearer token stored in the PlaidBar data directory.

## Configuration

The server reads configuration from environment variables, an optional config
file, and explicit CLI flags. Later inputs override earlier ones.

| Setting | Purpose |
|---------|---------|
| `PLAID_CLIENT_ID` | Plaid client ID for sandbox or production |
| `PLAID_SECRET` | Plaid secret for the selected environment |
| `PLAID_ENV` | `sandbox` or `production` |
| `PLAIDBAR_SERVER_PORT` | Local server port, default from `PlaidBarConstants` |
| `PLAIDBAR_DATA_DIR` | Local data directory, default `~/.plaidbar/` |
| `PLAIDBAR_MIGRATE_LEGACY_DATABASE` | Explicit legacy migration environment |

The default server should bind to localhost only. If a future change expands
network reachability, that change must update `SECURITY.md`, this document, and
the setup UI.

## Storage Layout

Default local data directory:

```text
~/.plaidbar/
```

Current important files:

| File | Purpose |
|------|---------|
| `auth-token` | Local app-server bearer token |
| `plaidbar-sandbox.sqlite` | Sandbox Plaid item/token/account storage |
| `plaidbar-production.sqlite` | Production Plaid item/token/account storage |
| `transactions-*.json` | Environment/path-scoped transaction cache |
| `pending-link-sessions.json` | Pending Plaid Hosted Link state |

The data directory is created with private user permissions. Cache/token files
are written with private file permissions where the platform supports it.

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

## 1.0 Architecture Debt

- Add a clean architecture diagram to README or docs.
- Add focused tests around local auth-token file permissions where practical.
- Add endpoint-level documentation for request/response DTOs.
- Add a clean duplicate-instance strategy and document expected behavior.
- Decide whether the 1.0 install story is formula-only or notarized app bundle.
