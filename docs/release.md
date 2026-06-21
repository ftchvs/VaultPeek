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

## Rollback

Use this when a published release is broken and must be withdrawn. VaultPeek
distribution today is git/tag/DMG-based: a tag `v<version>`, a GitHub release on
`ftchvs/VaultPeek`, and a privately distributed `VaultPeek-<version>.dmg`. There
is no live auto-update channel, so rollback is a manual withdraw-and-redistribute
of the prior good release. Notarization and Sparkle are deferred
(`docs/distribution.md`), so the Sparkle step below is N/A until that runbook is
executed and verified.

Work the steps in order.

### 1. Identify the bad release and the prior good one

- Bad release: tag `v<bad-version>`, its GitHub release on `ftchvs/VaultPeek`, and
  any distributed `VaultPeek-<bad-version>.dmg` (with its recorded SHA-256).
- Prior good release: the last `v<good-version>` whose
  `docs/release-checklist.md` gates passed and whose DMG was clean-install
  verified.

```bash
gh release list --repo ftchvs/VaultPeek
gh release view "v<bad-version>" --repo ftchvs/VaultPeek
git ls-remote --tags origin "v<bad-version>"
```

### 2. Stop the bleeding (withdraw the bad release)

Reverse exactly what `./Scripts/release.sh --publish` did (it runs `git tag -a`,
`git push origin <tag>`, `gh release create ... --generate-notes`).

```bash
# Delete (or yank) the GitHub release so it stops being offered.
gh release delete "v<bad-version>" --repo ftchvs/VaultPeek --yes

# Delete the bad tag on origin, then locally.
git push origin :refs/tags/v<bad-version>
git tag -d v<bad-version>
```

If you must keep the bad tag for forensics rather than deleting it, at minimum
delete the GitHub release so it is not the published artifact. Confirm the prior
good tag `v<good-version>` is now the effective latest:

```bash
gh release list --repo ftchvs/VaultPeek   # newest non-prerelease should be v<good-version>
git ls-remote --tags origin              # v<bad-version> gone from origin
```

Do not force-push `main`. If bad code reached `main`, land a normal revert PR
through the usual gates rather than rewriting history.

### 3. Re-distribute the prior good DMG (private channel)

Restore users to `VaultPeek-<good-version>.dmg` through the same private channel
the bad build went out on. Prefer the previously built, clean-install-verified
artifact for that version; if it is not retained, rebuild it from the prior good
tag and re-validate before sending:

```bash
git checkout v<good-version>
./Scripts/package-dmg.sh
./Scripts/validate-app-bundle.sh .build/VaultPeek.app
shasum -a 256 .build/VaultPeek-<good-version>.dmg   # match the recorded checksum
```

The build is ad-hoc signed, so the right-click > Open first-launch step still
applies. Tell users to delete the bad `VaultPeek.app` and reinstall the good one;
local data in `~/.vaultpeek/` is untouched by a reinstall.

### 4. Sparkle rollback (N/A until Sparkle is live)

Sparkle auto-updates are dormant — `SUPublicEDKey` is a placeholder and no
appcast feed exists (`docs/distribution.md`). There is no auto-update channel to
roll back today; redistribution in step 3 is the only mechanism.

When Sparkle is live (after the `docs/distribution.md` signing + notarization +
appcast runbook is executed and verified): publish an appcast entry that points
clients back to the last-good **notarized** build so auto-update installs the
rollback, and remove or supersede the bad version's appcast entry. Until then,
this step is N/A.

### 5. Communicate

- Record the known-bad version in `docs/release-notes.md`: note `v<bad-version>`
  as withdrawn, the symptom, and that `v<good-version>` is the supported build.
- Update user-facing support copy (the `SUPPORT.md` supported-versions line and
  the in-app support links) so the surfaced "latest" version matches the
  redistributed good build.

### 6. Verify post-rollback

Re-run the relevant `docs/release-checklist.md` gates against the restored
`v<good-version>` build before considering the rollback complete:

- Packaging And Distribution: `./Scripts/package-dmg.sh` +
  `./Scripts/validate-app-bundle.sh` pass; DMG opened and launched on a machine
  other than the build machine; SHA-256 recorded and matching.
- Privacy And Security: secret scan, `/api/status` contract test, `/api/*` auth
  tests pass on the restored build.
- Confirm `gh release list --repo ftchvs/VaultPeek` shows `v<good-version>` as the
  effective latest and the bad release/tag are gone.

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

Do not claim notarized public app distribution until all of these are complete.
Signing and notarization are bring-your-own in the open-source build (runbook:
`docs/distribution.md`):

- Developer ID signing configured
- notarization and ticket stapling automated
- Gatekeeper verified on a clean machine
- Sparkle appcast (or equivalent private update channel) configured, signed,
  hosted, and tested
