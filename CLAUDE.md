# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

VaultPeek (formerly PlaidBar) is a local-first macOS menu bar dashboard for [Plaid](https://plaid.com) financial data. SwiftPM targets, executables, `PLAIDBAR_*` environment variables, the Keychain service name, and legacy `~/.plaidbar/` paths intentionally keep the PlaidBar name; see the naming-compatibility table in `README.md`. No cloud backend, no telemetry — all data stays on the user's machine. The product north star is RepoBar/CodexBar-style density: high-signal numbers one click away in a native macOS popover.

## Commands

```bash
swift build                 # Build all targets
swift build -c release      # Release build (what CI builds)
swift test                  # Run all tests
swift run PlaidBar --demo   # Run app with local fixtures (no Plaid, no server, no credentials)
swift run PlaidBarServer --sandbox          # Run server standalone
./Scripts/run.sh --sandbox  # Build + run server AND app together (sandbox)
./Scripts/smoke-sandbox.sh  # Headless sandbox preflight: /health + auth-gated /api/status
./Scripts/screenshots.sh    # Capture README screenshots from demo data
```

Run a single test (Swift Testing, not XCTest):

```bash
swift test --filter PlaidBarCoreTests          # one suite
swift test --filter "someTestFunctionName"     # one test by name
```

Before pushing, replicate CI locally — the strict-concurrency build is the gate that most often fails:

```bash
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test
```

Lint/format (config in `.swiftformat`, `.swiftlint.yml`):

```bash
swiftformat Sources/ Tests/
swiftlint
```

## Architecture: two processes, one shared library

Three core SPM targets in `Package.swift` define the security split (the package also builds a widget extension, a CLI, and an app-only file-backed read-model cache — see below). The split is a hard security boundary, not just organization:

- **`PlaidBar`** (`Sources/PlaidBar/`) — SwiftUI `MenuBarExtra` app. The UI layer. It **only** talks to the local server over HTTP; it never sees Plaid `client_secret` or `access_token`.
- **`PlaidBarServer`** (`Sources/PlaidBarServer/`) — Hummingbird 2 companion server. Proxies all Plaid API calls, owns credentials and token storage. Binds to `127.0.0.1` only.
- **`PlaidBarCore`** (`Sources/PlaidBarCore/`) — shared library. DTOs (`Models/`) and pure utilities (`Utilities/`) used by both. **Most testable business logic lives here** — summaries, formatters, recurring detection, sync reduction, presentation/state mapping, typed routing/navigation state, goals. Prefer adding logic here over embedding it in views or routes.

Additional targets: **`PlaidBarCache`** (`Sources/PlaidBarCache/`) — app-only library holding the disposable file-backed read-model cache (actor-isolated stores persisting a `Codable` JSON snapshot to the private data dir, AND-566). It is kept out of the lean server/CLI/widget targets so private financial cache reads stay confined to the app; the pure read-model and mapper stay in `PlaidBarCore`. The cache is disposable, rebuildable, scoped per Plaid environment, and written only to the private data dir (see `SECURITY.md`). **`PlaidBarWidgetExtension`** and **`PlaidBarCLI`** (`plaidbar-cli`) round out the source targets.

Data flow: `PlaidBar.app` → HTTP `localhost:8484` → `PlaidBarServer` → HTTPS → Plaid API.

**Why the server exists:** Plaid forbids the secret/access-token from living in the client. The server keeps them out of the SwiftUI process, stores Plaid item records in local SQLite and access-token *bytes* in macOS Keychain (SQLite holds only `keychain:<item_id>` references), and can restart independently of the UI.

### Server internals (`Sources/PlaidBarServer/`)
- `App.swift` — `@main` entry. Sets up Fluent/SQLite, runs migrations (`CreateItems`, `CreateSyncCursors`), wires the Hummingbird router. `/health` and `/oauth/callback` are unauthenticated; everything under `/api` is behind `APITokenMiddleware`.
- `Routes/` — REST endpoints (Account, Link, Status, Transaction).
- `Plaid/` — `PlaidClient` + `PlaidModels`.
- `Storage/` — Fluent models/migrations (`Database.swift`), `TokenStore`, `PlaidTokenVault` (Keychain).
- `Config/ServerConfig.swift` — loads config from CLI flags > config file > environment. Enforces private SQLite store permissions.
- `Auth/` — `APITokenMiddleware`, `PendingLinkSessionStore` (one-time Hosted Link `state` validation).

### App internals (`Sources/PlaidBar/`)
- `App/` — `@main` `PlaidBarApp`, `AppState`; per-window `NavigationModel` (typed `Route`), `CommandPaletteModel` (⌘K), and `WindowActivationPolicy` (window-first scene plumbing; window-first is the default as of AND-616).
- `Services/` — `ServerClient` (HTTP), `NotificationService`, `LaunchService`, `LocalAIInsightsService`, on-device Foundation Models categorizers (`FoundationModelsMerchantCategorizer`/`FoundationModelsIncomeCategorizer`), `RecoveryActionDispatcher`, `GoalsStore` (local-first goals), `HapticFeedback`.
- `Views/` — `MainPopover` is the menu-bar glance surface; filter states (Cash/Credit/Savings/Debt/Status) reuse the same visual system. `Charts/` holds Swift Charts components.

**Architecture doctrine: window-first hybrid** (accepted at Gate 0 / AND-578). The main experience is a primary `Window` / `NavigationSplitView` workspace (Dashboard, Transactions, Budgets, Planning, Goals, Review Inbox, Insights, Alerts, Accounts, Settings). The `MenuBarExtra` glance is retained as a first-class **reduced read+route surface** (status, glance metrics, attention chips that deep-link into the window). Do **not** "revert" window surfaces to popover-only citing older docs — that doctrine is superseded. The window scene is the **shipping default as of AND-616 (Epic 9)**: `WindowFirstFeatureFlag.defaultValue` is now `true`, so a fresh install and every existing user lands in the window workspace with the menu bar reduced to the glance. The flag is retained only as an escape hatch — a QA pass or user can force the now-legacy popover-only build back on with `--window-first off` (or the `featureFlag.windowFirst` UserDefaults key); the override is parsed in `PlaidBarCore`'s `WindowFirstFeatureFlag`. Removing the legacy popover and the flag entirely (Stage 2, AND-598…600) is gated on on-hardware parity QA. `PlaidBarCore`, the server, the Plaid client, and the Keychain/localhost boundary are unchanged by this migration. Execution: Epics AND-579…618.
- `Theme/` — `DesignTokens`, `Typography` (semantic tokens + 8pt grid). See `DESIGN.md`.

## Conventions (enforced — see CONTRIBUTING.md)

- **Swift 6 strict concurrency.** All types must be `Sendable`. CI builds with `-strict-concurrency=complete -warnings-as-errors`, so a non-`Sendable` type fails the build, not just a warning. Targets compile in Swift 5 language mode but under the Swift 6 toolchain.
- **State: use `@Observable`**, not `ObservableObject`.
- **Put shared logic in `PlaidBarCore`**, not in views or routes — keeps it `Sendable`, testable, and reusable across both processes.
- **Never communicate balance, risk, utilization, errors, or chart meaning through color alone** (accessibility — `ACCESSIBILITY.md`).
- **Always use sandbox or synthetic data** in tests, screenshots, and examples. Never commit real Plaid credentials, access tokens, account IDs, or balances.

## Data modes

| Mode | Command | Plaid calls | Source |
|------|---------|-------------|--------|
| Demo | `swift run PlaidBar --demo` | No | Hardcoded fixtures |
| Sandbox | `./Scripts/run.sh --sandbox` | Yes (sandbox API) | Plaid sandbox creds |
| Production | `./Scripts/run.sh` | Yes (prod API) | Plaid-approved creds |

Sandbox/production need `PLAID_CLIENT_ID` and `PLAID_SECRET` exported (or set in `~/.vaultpeek/server.conf`). Server port defaults to `8484` (`PLAIDBAR_SERVER_PORT` to override); local data lives under `~/.vaultpeek/` by default (`PLAIDBAR_DATA_DIR` to override; legacy `~/.plaidbar/` files are migrated forward on startup without overwriting newer files). The private data dir holds SQLite stores, the auth token, and the disposable per-environment JSON read-model cache (`PlaidBarCache`), so the "local-only" framing assumes that path stays on-device: if a user points `PLAIDBAR_DATA_DIR` at a cloud-synced folder (iCloud Drive, Dropbox, etc.) the cache (derived financial read-model data, though never Plaid secrets or Keychain material) can sync off-device. Production macOS builds keep Plaid access-token bytes in non-synchronizable Keychain items; fallback builds without usable Keychain support can store token bytes in SQLite under `PLAIDBAR_DATA_DIR`. App Group glance snapshots for widgets/intents are separate from `PLAIDBAR_DATA_DIR` and can contain derived finance values after redaction rules run. Recommend a local, non-synced data dir (see `SECURITY.md`). Tunable constants are centralized in `Sources/PlaidBarCore/Utilities/Constants.swift` (refresh intervals, sync page caps, credit thresholds, app version).

## Server API

Localhost endpoints. `/health` and `/oauth/callback` are open; `/api/*` requires the bearer token at `~/.vaultpeek/auth-token` (or `$PLAIDBAR_DATA_DIR/auth-token`). Full table in `README.md` ("Server API Reference"). `/api/status` deliberately exposes readiness metadata only — never tokens, account IDs, balances, or transactions.

## Reference docs

`README.md` (most complete), `ARCHITECTURE.md` + `docs/architecture.md`, `DESIGN.md`, `GOAL.md`, `PRD.md`, `SECURITY.md`, `ACCESSIBILITY.md`, `docs/troubleshooting.md`, `docs/qa-matrix.md`.

`commands/goal.md` (`/goal`), `commands/vaultpeek-prod-loop.md`, and `.codex/skills/` contain a repo-local agentic production-readiness loop.
