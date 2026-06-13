# Release Notes Drafts

This file holds human-written release summaries before they are copied into a
GitHub release. `CHANGELOG.md` may be generated from repository history, so keep
curated release messaging here.

## Unreleased (post-1.0.0 main)

### Changed

- Visible product identity renamed to VaultPeek; SwiftPM targets, executables,
  bundle identifier, and Keychain entries intentionally remain PlaidBar.
- Relicensed as proprietary, closed-source software. The public Homebrew
  formula and tap were retired; distribution is now a privately shared,
  ad-hoc-signed drag-install DMG (`./Scripts/package-dmg.sh`).
- Default local storage moved to `~/.vaultpeek/` with a non-destructive
  migration from `~/.plaidbar/`.
- Release gates repaired and extended: `Scripts/release.sh` no longer checks
  the removed Homebrew formula and now packages and validates the app bundle;
  version alignment and bundle validation also run in CI
  (`Scripts/verify-version-alignment.sh`, `Scripts/validate-app-bundle.sh`).

### Deferred (still true, do not claim otherwise)

- Developer ID signing, notarization, stapling, and a clean-machine Gatekeeper
  pass have NOT been performed. First launch of the DMG build still requires
  right-click > Open. Prep runbook: `docs/distribution.md`; scaffold:
  `Scripts/notarize.sh`.
- Sparkle auto-updates are dormant: `SUPublicEDKey` is a placeholder and no
  appcast feed exists.

### Verification Targets

- `./Scripts/release.sh --allow-current-branch`
- `./Scripts/verify-version-alignment.sh`
- `./Scripts/package-dmg.sh` + `./Scripts/validate-app-bundle.sh`
- `docs/release-checklist.md` end to end before the next tag

## PlaidBar Is Now VaultPeek - Unreleased

PlaidBar has been renamed to **VaultPeek**. Same product, same local-first
promise: *private finance, one glance away.*

### What Changed

- The app you see is now **VaultPeek**: app bundle (`VaultPeek.app`), menu bar
  identity, setup/settings copy, and DMG (`VaultPeek-<version>.dmg`, volume
  name `VaultPeek`).
- The default local data directory is now `~/.vaultpeek/` (previously
  `~/.plaidbar/`). `PLAIDBAR_DATA_DIR` still overrides it.
- Documentation, roadmap, security/privacy/support copy, and release notes use
  the VaultPeek name.

### What Did Not Change

- **Your financial data stays local.** No cloud backend, no telemetry, no
  tracking; the rename changes nothing about data handling.
- **The Plaid integration is unchanged.** Linked items, credentials, sandbox
  and production modes, and the localhost-only companion server work exactly
  as before.

### Data Migration (Already Shipped)

Default installs migrate automatically on the first launch after upgrading.
The migration is a copy, not a move, and it is idempotent:

- Files are copied from `~/.plaidbar/` into `~/.vaultpeek/` only when the
  destination file does not already exist; newer VaultPeek files are never
  overwritten.
- SQLite stores are copied with their `-wal`/`-shm`/`-journal` sidecars as an
  atomic set; if a VaultPeek copy of a store already exists, the legacy store
  and its sidecars are preserved rather than copied.
- Account and transaction caches that embed the storage path are rewritten to
  the new directory during the copy.
- `~/.plaidbar/` is left in place as rollback evidence. To roll back
  temporarily, set `PLAIDBAR_DATA_DIR=~/.plaidbar` for both app and server.
- After a Reset Local Data action, a reset marker prevents old databases,
  caches, and pending link sessions from being copied back in from the legacy
  directory.
- Plaid access tokens keep the existing Keychain service
  (`PlaidBar.PlaidAccessToken`) so migrated SQLite `keychain:<item_id>`
  references keep resolving. Explicit `PLAIDBAR_DATA_DIR` overrides are not
  migrated.

### IMPORTANT: Upgrading From PlaidBar.app

Installing VaultPeek.app does **not** remove an existing
`/Applications/PlaidBar.app`. Delete the old PlaidBar.app after installing
VaultPeek:

- Both apps share the same bundle identifier, so macOS launch behavior
  (login items, notifications, "Open" routing) is ambiguous while both exist.
- Both apps' bundled servers bind the same default port `8484`, so running
  both at once causes port contention and confusing offline states.

### Known Old-Name Compatibility Surfaces

Intentional, kept for compatibility:

- SwiftPM targets/products and app-bundle executables: `PlaidBar`,
  `PlaidBarServer`, `PlaidBarCore`, `plaidbar-cli` (staged rename tracked
  separately).
- Environment variables and config keys: `PLAIDBAR_SERVER_PORT`,
  `PLAIDBAR_DATA_DIR`, `PLAIDBAR_MIGRATE_LEGACY_DATABASE`,
  `PLAIDBAR_SMOKE_PORT`.
- Keychain service name: `PlaidBar.PlaidAccessToken`.
- SQLite store filenames: `plaidbar-sandbox.sqlite`,
  `plaidbar-production.sqlite`.
- Source-checkout helper `Scripts/plaidbar-run` remains a deprecated alias for
  `Scripts/vaultpeek-run`.
- GitHub repository slug `ftchvs/PlaidBar` until the repo rename lands.

### Follow-Ups

- Update the application display name/branding in the Plaid Dashboard so the
  Plaid Link consent screen shows VaultPeek.
- Repo rename (`ftchvs/PlaidBar` -> VaultPeek) and the in-app GitHub links that
  depend on it.
- Staged SwiftPM product/executable rename.

## Post-1.0 Design and Trust Roadmap - Active

### Focus

- Keep VaultPeek's public story aligned with the shipped `v1.0.0` release
  (published under the former PlaidBar name).
- Move the dashboard toward a RepoBar-style finance instrument: native material,
  compact rows, a prominent 365-day heatmap, and status-rich selected-account
  details.
- Treat Liquid Glass as a macOS 26+ progressive enhancement while preserving the
  macOS 15 material fallback.
- Continue recovery convergence across dashboard, setup, settings, Plaid item
  health, local server state, notification permissions, and empty data states.
- Keep source/developer CLI behavior, local insight receipts, the attention
  queue, and README screenshot expectations documented as part of the public
  product contract.

### Verification Targets

- `git diff --check`
- `swift build --target PlaidBar --skip-update --disable-keychain`
- `./Scripts/screenshots.sh` after visual changes
- Peekaboo window/UI validation for regenerated screenshots when available
- Manual VoiceOver and keyboard checks for dashboard filters, footer actions,
  recovery buttons, and selected account detail surfaces

## v1.0.0 - Published

(Historical note, 2026-06: the public Homebrew formula described below was
retired when PlaidBar was relicensed as proprietary. The notes are kept as
shipped.)

### Added

- First stable formula-only release candidate for a local-first macOS Plaid menu
  bar dashboard.
- Public release train aligned around install docs, QA matrix, release runbook,
  security model, support links, and current screenshots.

### Changed

- Version metadata now targets `1.0.0` across `version.env`, `Info.plist`,
  runtime constants, tests, and the Homebrew formula tag.
- 1.0 remains intentionally formula-only; notarized app/cask and Sparkle appcast
  distribution are documented as post-1.0 work until signing is real.

### Verification Targets

- `./Scripts/release.sh --allow-current-branch`
- `PLAID_CLIENT_ID=ci_smoke_client PLAID_SECRET=ci_smoke_secret ./Scripts/smoke-sandbox.sh`
- `./Scripts/screenshots.sh`
- Published tag install check: `brew install --build-from-source plaidbar`

## v0.9.0 - Published

### Added

- Formula-only distribution candidate aligned around the current dashboard,
  onboarding, status, local-data, and security hardening work.
- Release preflight script support for release-prep PR validation from a
  non-`main` branch while keeping publish locked to clean `main`.

### Changed

- Version metadata now targets `0.9.0` across `version.env`, `Info.plist`,
  runtime constants, and the Homebrew formula tag.
- Release docs define the 1.0 install path as source-built Homebrew formula
  first, with notarized `.app` and cask distribution deferred until signing and
  appcast infrastructure are actually ready.

### Verification Targets

- `./Scripts/release.sh --allow-current-branch`
- `brew install --build-from-source plaidbar` from a tagged release
- GitHub CI build/tests/smoke

## v0.7-v0.8 - Unreleased

### Added

- Dashboard Status readiness panel with mode, server state, linked item count,
  synced item count, credential readiness, last sync, and recovery actions.
- Security contract tests for the status payload and local bearer-token
  comparison.

### Changed

- Status filter is now a recovery surface, not only an account filter. It
  prioritizes server offline, missing credentials, no linked item, unloaded
  balances, item errors, login-required items, incomplete first sync, and stale
  sync.
- Security/privacy docs now distinguish macOS Keychain runtime token storage
  from fallback builds and define the authenticated `/api/status` no-secret
  payload contract.

### Verification Targets

- Select Status in demo mode and verify healthy local demo readiness.
- Verify offline server and stale sync states expose a single primary action.
- Confirm `/api/status` exposes readiness metadata only.
- `swift build --target PlaidBar --skip-update --disable-keychain`

## v0.6.0 - Unreleased

### Added

- First-run completion state for Plaid Link return: setup now distinguishes
  waiting for Link, linked item without accounts, accounts without first sync,
  blocked errors, and dashboard-ready completion.

### Changed

- Onboarding only completes after a linked item has loaded accounts and the
  first transaction sync check has completed.

### Verification Targets

- Clean-profile sandbox QA with `PLAIDBAR_DATA_DIR=$(mktemp -d)`.
- `swift test --filter FirstRunCompletion --skip-update --disable-keychain`
- `swift build --target PlaidBar --skip-update --disable-keychain`

## v0.5.0 - Published

### Added

- Setup preflight for server, mode, credential, storage, and linked-item
  readiness before Plaid Link opens.
- Manual setup readiness recheck.
- Settings screenshots for Local Data, Accounts, and Notifications.
- README screenshot refresh for current dashboard, setup, and settings surfaces.
- Version metadata alignment for the v0.5 release candidate.
- 1.0 roadmap covering product, design/frontend, system architecture, security,
  distribution, and release readiness.
- Architecture, privacy, and troubleshooting docs for licensed users and internal
  collaborators.

### Changed

- Settings > Accounts Add Account and setup demo actions now route through the
  visible setup/connect flow.
- Dashboard footer icon buttons include accessibility labels.

### Security

- Account removal copy and local data controls clarify local deletion versus
  Plaid Dashboard or bank-side permission boundaries.

### Verification Targets

- `git diff --check`
- `bash -n Scripts/*.sh Scripts/plaidbar-run`
- `swift build --target PlaidBar --skip-update --disable-keychain`
- strict-concurrency build
- release build
- screenshot generation
- GitHub CI
- Claude review when session quota permits
