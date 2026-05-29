# Release Notes Drafts

This file holds human-written release summaries before they are copied into a
GitHub release. `CHANGELOG.md` may be generated from repository history, so keep
curated release messaging here.

## v1.0.0 - Published

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
  distribution, and open-source readiness.
- Architecture, privacy, and troubleshooting docs for public contributors and
  early users.

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
- `ruby -c Formula/plaidbar.rb`
- `swift build --target PlaidBar --skip-update --disable-keychain`
- strict-concurrency build
- release build
- screenshot generation
- GitHub CI
- Claude review when session quota permits
