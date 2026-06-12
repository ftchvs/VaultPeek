# Release Runbook

PlaidBar is proprietary software distributed privately to licensed users. The
public Homebrew tap has been retired and `Formula/plaidbar.rb` removed.

PlaidBar 1.0 ships as a drag-install DMG built with `./Scripts/package-dmg.sh`:
it wraps a self-contained `PlaidBar.app` (app + bundled `PlaidBarServer`,
auto-started on launch) with an `/Applications` symlink. The DMG is currently
ad-hoc signed; Developer ID signing, notarization, and the Sparkle appcast
remain deferred until the clean-machine Gatekeeper path is real, so first launch
needs right-click > Open and release notes must say so.

The bundle ships `AppIcon.icns` (checked by `Scripts/validate-app-bundle.sh`).
The icon is generated from code — rerun `./Scripts/generate-app-icon.sh` to
regenerate `Sources/PlaidBar/Resources/AppIcon.icns` after design changes.

## Current Release

- Current version: `v1.0.0`
- 1.0 distribution shape: privately-distributed drag-install DMG
- GitHub release: tagged from clean `main` (private repo)

Bundled commands (inside `PlaidBar.app`):

```bash
plaidbar --demo
plaidbar-server --sandbox
plaidbar-run --sandbox
```

## Release-Prep PR Checklist

1. Confirm metadata alignment:

```bash
cat version.env
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/PlaidBar/Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/PlaidBar/Resources/Info.plist
sed -n 's/.*appVersion: String = "\([^"]*\)".*/\1/p' Sources/PlaidBarCore/Utilities/Constants.swift
```

2. Commit the release-prep changes, then run local release gates from the clean
   release-prep branch:

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
./Scripts/validate-app-bundle.sh
```

Distribute the resulting DMG privately to licensed users.

## Distribution Scope

The DMG ships a self-contained `PlaidBar.app` bundling the menu bar app, local
companion server, and launcher:

- `plaidbar`
- `plaidbar-server`
- `plaidbar-run`

The ad-hoc-signed DMG is acceptable for 1.0 because PlaidBar is local-first and
distributed privately to a controlled set of licensed users who can complete the
first-launch right-click > Open step.

Do not claim notarized public app distribution until all of these are complete:

- Developer ID signing configured
- notarization and ticket stapling automated
- Gatekeeper verified on a clean machine
- Sparkle appcast (or equivalent private update channel) configured, signed,
  hosted, and tested
