# Release Notes Drafts

This file holds human-written release summaries before they are copied into a
GitHub release. `CHANGELOG.md` may be generated from repository history, so keep
curated release messaging here.

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
