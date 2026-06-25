# Security

VaultPeek (formerly PlaidBar) is a local-first macOS menu bar app for sensitive financial data. Treat Plaid credentials, access tokens, account identifiers, balances, transaction data, and local database contents as private.

## Supported Versions

| Version | Supported |
|---------|-----------|
| `1.0.x` | Yes |
| `main` | Active development |
| `< 1.0` | No; upgrade recommended |

Security fixes target `main` first and may be released as a `1.0.x` patch when
they affect the stable release line.

## Reporting a Vulnerability

Please do not open a public GitHub issue for suspected vulnerabilities, token handling bugs, private financial data exposure, or exploitable security issues.

Use GitHub private vulnerability reporting if available, or contact the repository owner through the GitHub profile. Include:

- affected commit or version
- steps to reproduce
- impact
- whether Plaid tokens, account metadata, transaction data, or local database contents may be exposed
- suggested remediation, if known

## Data Handling Boundaries

- Do not share real Plaid `client_id`, `secret`, `access_token`, `public_token`, item IDs, account IDs, transaction exports, or screenshots with real balances in issues, pull requests, logs, or discussions.
- Screenshots, tests, fixtures, and public examples should use sandbox or synthetic financial data.
- Logs should not include real account numbers, access tokens, raw transaction details, or secrets.
- Environment variables such as `PLAID_SECRET` can leak through terminal history or process inspection on a compromised machine.

## Security Model

- VaultPeek has no hosted backend, analytics, telemetry, or tracking.
- Optional managed bank linking is planned but not shipped. Before it ships, a
  consent, audit, and escalation boundary must be approved: support
  helpers may guide users through VaultPeek screens, but must never ask for,
  receive, type, store, or audit-log bank credentials, MFA codes, Plaid tokens,
  raw account identifiers, balances, transactions, local databases, logs, or
  screenshots containing real financial data.
- The companion server should bind to `127.0.0.1` only.
- Plaid secrets and access tokens must not be embedded in the app binary.
- The local server keeps Plaid item records in environment-scoped SQLite files under `~/.vaultpeek/`
  (default since the VaultPeek rename; legacy default installs are migrated from `~/.plaidbar/`):
  `plaidbar-sandbox.sqlite` for sandbox and `plaidbar-production.sqlite` for production. The SQLite
  filenames intentionally keep the `plaidbar-` prefix.
- On macOS builds with Security framework support, Plaid access-token bytes are
  stored in Keychain under the `PlaidBar.PlaidAccessToken` service and SQLite
  stores only a `keychain:<item_id>` reference. Build/test environments without
  Keychain support may fall back to local SQLite token storage, so release
  claims must distinguish runtime Keychain behavior from fallback builds.
- Keychain access-token items are hardened to stay on the user's machine. Each
  item is written with the `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  data-protection class and `kSecAttrSynchronizable = false`, so the token is
  **never** copied to iCloud Keychain or any paired device, yet remains readable
  by the headless companion server after the first post-boot unlock (including
  while the screen is locked, which is required for background refresh). The
  weaker `WhenUnlockedThisDeviceOnly` class is intentionally avoided because it
  would block background reads on a locked screen, and the default
  iCloud-syncable classes (`WhenUnlocked`, `AfterFirstUnlock`) are avoided
  because they would let tokens leave the device. The protection is re-asserted
  on every write, so items created by older builds are upgraded in place. The
  accessibility-class decision is centralized in `KeychainAccessPolicy`
  (`PlaidBarCore`) and unit-tested in CI without requiring a live Keychain.
- Existing legacy `plaidbar.sqlite` data, SQLite sidecar files, and matching transaction cache are copied into a scoped database only when the legacy environment is explicit (`PLAIDBAR_MIGRATE_LEGACY_DATABASE=sandbox|production`) or can be inferred from the existing transaction-cache context. Ambiguous legacy databases are left untouched to avoid sandbox/production token crossover. Explicit migration can replace an existing scoped store, backs up the previous scoped SQLite store and transaction cache before copying legacy data, and writes a migration marker so restarts do not reapply stale legacy data.
- The app/server auth token is generated locally under `~/.vaultpeek/auth-token`
  (or `$PLAIDBAR_DATA_DIR/auth-token`).
- The disposable file-backed read-model cache (AND-566) accelerates cold render and
  offline reads. It holds financial values and Plaid identifiers, so — like the
  existing `accounts.json` / `transactions.json` caches — it is written **only**
  into the local private data dir (`~/.vaultpeek/dashboard-read-model-cache-v1.store`
  plus the per-transaction `transaction-cache-v1.store`, or `$PLAIDBAR_DATA_DIR`),
  with the directory at `0o700` and the store files tightened to `0o600`. Each
  store is a single plain JSON snapshot written by an actor-isolated store type —
  there are no SQLite `-wal`/`-shm` sidecars. `transaction-cache-v1.store` mirrors
  the full transaction history (transaction IDs, account IDs, merchant names,
  amounts), so it is the more sensitive of the two and must not be overlooked in a
  local-data audit. Being local-only JSON files, neither is **ever** synced to
  iCloud, and neither is **ever** written to the world-readable App Group
  container — that boundary remains exclusive to the redacted glance /
  `FinanceSnapshot` payloads. The cache is a **disposable** read-model:
  rebuildable from the authoritative in-memory/JSON data, never a source of truth,
  scoped per Plaid environment, and safe to delete at any time.
  `clearReadModelCache()` and `clearTransactionCache()` delete their respective
  stores on local reset and when the last institution is removed, but **only
  when a usable cache store can be opened**; if a store cannot be opened the
  clearer returns without deleting, so the matching `.store` file can survive a
  reset on disk. `LocalDataStore.resetLocalData` separately removes the
  JSON/scoped caches, Plaid SQLite files, pending-link state, goals, and logo
  cache. Every cache read/write `throws` and callers wrap in `try?`, so if a
  store file fails to open/read/write, the app falls back to its existing
  JSON/UserDefaults cold path with no behavior change.
- **Caveat — the cache follows `PLAIDBAR_DATA_DIR`.** The "never synced to
  iCloud" guarantee above is about iCloud Keychain and the App Group container,
  not the filesystem location of the data dir itself. These JSON read-model
  caches live wherever `PLAIDBAR_DATA_DIR` points (default `~/.vaultpeek/`,
  which is local). If you override `PLAIDBAR_DATA_DIR` to a cloud-synced folder
  (iCloud Drive, Dropbox, OneDrive, a synced network share, etc.), the
  disposable cache — which holds derived financial read-model data such as
  balances, merchant names, amounts, and Plaid identifiers, though **never**
  Plaid secrets, access tokens, or any Keychain material — can be copied
  off-device by that sync client. Production macOS builds keep Plaid access
  tokens in non-synchronizable `…ThisDeviceOnly` Keychain items and SQLite stores
  only `keychain:<item_id>` references; test or fallback builds without usable
  Keychain support can store token bytes in SQLite under `PLAIDBAR_DATA_DIR`.
  To keep the derived cache and any fallback token rows on-device, point
  `PLAIDBAR_DATA_DIR` at a local, non-synced directory.
- **Trust-boundary change — opt-in server-synced review state (AND-552).** By
  default the local server **never** stores transaction *review state* — the
  per-transaction overrides a user sets in the Review Inbox (chosen category,
  merchant rename, transfer flag, budget exclusion, free-text note, review
  status) and their categorization rules. That state is app-local JSON only.
  AND-552 adds an **optional** multi-device sync that, *only when the user
  explicitly opts in*, persists exactly that review state on the local server
  (the `review_metadata` / `review_rules` SQLite tables, served by
  `/api/review` behind the same bearer-token middleware as every other `/api`
  route). This deliberately **expands the server's stored data surface beyond
  Plaid limits and token references**: with sync on, the server SQLite holds the
  user's category overrides, merchant renames, and notes — display-safe derived
  values, **never** a Plaid token, access secret, or Keychain material. The
  opt-in is gated by `ServerSyncedReviewFeatureFlag` (default **OFF**); with it
  off — the default for a fresh install and every existing user — the app never
  constructs or sends a review snapshot, the `/api/review` tables stay empty,
  and behavior is byte-identical to before AND-552, so **no review data leaves
  the device without explicit consent**. Like the read-model cache, the synced
  tables live in the environment-scoped SQLite under `PLAIDBAR_DATA_DIR`
  (default local `~/.vaultpeek/`), so pointing the data dir at a cloud-synced
  folder can copy this review state off-device (see the `PLAIDBAR_DATA_DIR`
  caveat above). Opting back out clears the server-side tables
  (`DELETE /api/review`). Conflicting edits across devices resolve by per-record
  last-writer-wins on each record's `updatedAt` clock
  (`ReviewStateConflictResolver`), so a sync never invents a category the user
  did not choose.
- `/api/status` is authenticated and exposes readiness metadata: version,
  environment, credential availability, storage path, linked item count,
  synced item count, sync readiness, and last sync time. With the opt-in
  `?include=items` query parameter it additionally returns the same
  authenticated item-health snapshot served by `/api/items` — per-item Plaid
  `item_id`, institution name, connection status, last sync, last webhook, and
  whether a sync is pending. It must never include Plaid secrets, Plaid access
  tokens, public tokens, auth tokens, account IDs, balances, or transaction
  data.
- Protect your macOS user account, disk encryption, backups, and shell history.
- App-server communication should preserve local-only assumptions unless a future change explicitly documents otherwise.

## Supported Modes

- `--demo` app mode uses hardcoded local fixture data and does not call Plaid.
- `--sandbox` server mode calls Plaid sandbox and requires sandbox credentials.
- Production mode calls Plaid production and requires Plaid approval plus production credentials.

Use sandbox or demo data when sharing screenshots, reproductions, or public examples.

## Maintainer Response

Maintainers will acknowledge credible reports, investigate the scope, and fix or document mitigations before public disclosure when appropriate.
