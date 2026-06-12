# Release Runbook

PlaidBar 1.0 ships as a source-built Homebrew formula first. A local
drag-install DMG can be built with `./Scripts/package-dmg.sh`: it wraps a
self-contained `PlaidBar.app` (app + bundled `PlaidBarServer`, auto-started on
launch) with an `/Applications` symlink. The DMG is ad-hoc signed; Developer ID
signing, notarization, cask, and the Sparkle appcast remain deferred until the
clean-machine Gatekeeper path is real, so first launch needs right-click >
Open and release notes must say so.

The bundle ships `AppIcon.icns` (checked by `Scripts/validate-app-bundle.sh`).
The icon is generated from code — rerun `./Scripts/generate-app-icon.sh` to
regenerate `Sources/PlaidBar/Resources/AppIcon.icns` after design changes.

## Current Release

- Current version: `v1.0.0`
- 1.0 distribution shape: formula-only SwiftPM executable install
- GitHub release: tagged from clean `main`
- Homebrew tap command:

```bash
brew tap ftchvs/plaidbar https://github.com/ftchvs/PlaidBar
brew install plaidbar
```

Installed commands:

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
rg 'tag: "v' Formula/plaidbar.rb
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

For non-publishing Homebrew verification from a development checkout, avoid
uninstalling or reinstalling user packages. Use read-only or dry-run checks:

```bash
ruby -c Formula/plaidbar.rb
HOMEBREW_NO_AUTO_UPDATE=1 brew audit --strict --formula plaidbar
HOMEBREW_NO_AUTO_UPDATE=1 brew style plaidbar
HOMEBREW_NO_AUTO_UPDATE=1 brew install --dry-run --build-from-source plaidbar
HOMEBREW_NO_AUTO_UPDATE=1 brew test plaidbar
```

If Homebrew reports that `plaidbar` is already installed and up to date during
the dry run, that is enough for local branch verification. Do a destructive
reinstall only on a clean release machine or disposable Homebrew environment.

3. Open and merge the release-prep PR only after GitHub CI passes.

## Publish Checklist

From clean `main` after the release-prep PR is merged and CI is green:

```bash
git pull --ff-only origin main
./Scripts/release.sh --publish
```

Then verify the published install path:

```bash
brew tap ftchvs/plaidbar https://github.com/ftchvs/PlaidBar
brew reinstall --build-from-source plaidbar
plaidbar-server --help
plaidbar-server --version
plaidbar-run --help
```

Run the published install check only on a clean release machine or disposable
Homebrew environment so it does not disturb a user's existing local install.

## Formula-Only Scope

The formula installs the SwiftPM-built menu bar executable, local companion
server, and launcher script:

- `plaidbar`
- `plaidbar-server`
- `plaidbar-run`

The formula path is acceptable for 1.0 because PlaidBar is local-first,
open-source, and still targeted at technical early users who can run a
source-built macOS utility.

Do not claim notarized app distribution until all of these are complete:

- Developer ID signing configured
- app archive or DMG/ZIP packaging decided
- notarization and ticket stapling automated
- Gatekeeper verified on a clean machine
- Sparkle appcast configured, signed, hosted, and tested
- Homebrew cask tested separately from the formula
