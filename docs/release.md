# Release Runbook

VaultPeek (formerly PlaidBar) is proprietary software distributed privately to
licensed users. Homebrew distribution is discontinued: the public tap has been
retired and `Formula/plaidbar.rb` removed. The DMG is the distribution channel.

VaultPeek ships as a drag-install `VaultPeek-<version>.dmg` built with
`./Scripts/package-dmg.sh`:
it wraps a self-contained `VaultPeek.app` (app + bundled `PlaidBarServer`,
auto-started on launch) with an `/Applications` symlink. The DMG is currently
ad-hoc signed; Developer ID signing, notarization, and the Sparkle appcast
remain deferred until the clean-machine Gatekeeper path is real, so first launch
needs right-click > Open and release notes must say so. The signing and
notarization runbook (prep only, not yet performed) is `docs/distribution.md`;
the final gate set before tagging is `docs/release-checklist.md`.

The bundle ships `AppIcon.icns` (checked by `Scripts/validate-app-bundle.sh`).
The icon is generated from code — rerun `./Scripts/generate-app-icon.sh` to
regenerate `Sources/PlaidBar/Resources/AppIcon.icns` after design changes.

## Current Release

- Current version: `v1.0.0`
- 1.0 distribution shape: privately-distributed drag-install DMG
- GitHub release: tagged from clean `main` (private repo)

Bundled executables (inside `VaultPeek.app`; executable names stay
`PlaidBar`/`PlaidBarServer` until the staged SwiftPM product rename):

```bash
VaultPeek.app/Contents/MacOS/PlaidBar --demo
VaultPeek.app/Contents/MacOS/PlaidBarServer --sandbox
```

Repository helper scripts such as `Scripts/vaultpeek-run` and the deprecated
`Scripts/plaidbar-run` alias are source-checkout conveniences. They are not
staged into the drag-install DMG.

## Release-Prep PR Checklist

Work through `docs/release-checklist.md` end to end. The command skeleton:

1. Confirm metadata alignment:

```bash
./Scripts/verify-version-alignment.sh
```

2. Commit the release-prep changes, then run local release gates from the clean
   release-prep branch (this now includes app-bundle packaging and validation):

```bash
./Scripts/release.sh --allow-current-branch
PLAID_CLIENT_ID=ci_smoke_client PLAID_SECRET=ci_smoke_secret ./Scripts/smoke-sandbox.sh
./Scripts/screenshots.sh
```

The `ci_smoke_client` and `ci_smoke_secret` values are CI-safe dummy values for
the server startup smoke only. The smoke script does not open Plaid Link or sync
Plaid data, but it must still report sandbox credentials as configured.

3. Build and sanity-check the distributable DMG from the release-prep branch:

```bash
./Scripts/package-dmg.sh
./Scripts/validate-app-bundle.sh
```

4. Open and merge the release-prep PR only after GitHub CI passes.

## Publish Checklist

From clean `main` after the release-prep PR is merged and CI is green:

```bash
git pull --ff-only origin main
./Scripts/release.sh --publish
```

Then build and verify the distributable DMG on a clean release machine:

```bash
./Scripts/package-dmg.sh
./Scripts/validate-app-bundle.sh .build/VaultPeek.app
```

Clean-install verification (required before distributing):

1. Copy `.build/VaultPeek-<version>.dmg` to a machine (or fresh user account)
   without a prior install or `~/.vaultpeek` data directory.
2. Open the DMG, drag `VaultPeek.app` to `/Applications`, and launch via
   right-click > Open (ad-hoc signed build).
3. Confirm the menu bar item appears and the bundled server reports healthy
   in the Status view before distributing.

Verify clean-profile production setup before distributing — on a clean macOS
user profile (or with `PLAIDBAR_DATA_DIR` pointed at an empty directory):

1. Launch the app with no existing local data; the server must boot into the
   credential-less setup state (app reachable, `/api/status` reports
   `credentialsConfigured=false`, setup surfaces show guidance — no crash, no
   silent failure).
2. Add production credentials to `server.conf` and restart; the setup
   preflight must show production mode with credentials configured.
3. Confirm the storage path uses the production store
   (`plaidbar-production.sqlite`) and that no sandbox store or sandbox data is
   created or read.

This step requires Plaid production approval and real production credentials;
it cannot be simulated with sandbox credentials. If production approval is not
in place, record the step as not verified rather than skipping it silently.

Distribute the resulting DMG privately to licensed users.

## Distribution Scope

The DMG ships a self-contained `VaultPeek.app` bundling the menu bar app and
local companion server:

- `PlaidBar` app executable (displayed to users as VaultPeek)
- `PlaidBarServer` companion server executable

Source-checkout launcher scripts (`Scripts/vaultpeek-run` and the deprecated
`Scripts/plaidbar-run` alias) are not included in the DMG.

The ad-hoc-signed DMG is acceptable for 1.0 because VaultPeek is local-first and
distributed privately to a controlled set of licensed users who can complete the
first-launch right-click > Open step.

Do not claim notarized public app distribution until all of these are complete
(runbook: `docs/distribution.md`, scaffold: `Scripts/notarize.sh`):

- Developer ID signing configured
- notarization and ticket stapling automated
- Gatekeeper verified on a clean machine
- Sparkle appcast (or equivalent private update channel) configured, signed,
  hosted, and tested
