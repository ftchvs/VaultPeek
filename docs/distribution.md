# Distribution: Open-Source Ad-Hoc Build (Bring Your Own Signing)

> **Status: OPEN-SOURCE BUILD — ad-hoc, unsigned.** This repository ships an
> ad-hoc-signed build path only. There is no team-specific Apple Developer
> identity, entitlements file, or notarization tooling in the tree. The only
> true distribution claim is: an ad-hoc-signed `.app`/DMG that needs
> right-click → Open on first launch. Developer ID signing, notarization, App
> Group entitlements, and Sparkle auto-update are **bring-your-own** — a
> contributor must add their own identity and tooling.

## What the repo builds today

`Scripts/package-app.sh` produces `.build/VaultPeek.app`:

- Builds all targets in release configuration.
- Embeds `PlaidBarServer`, the `PlaidBarWidgetExtension.appex`, and
  `Sparkle.framework`.
- **Ad-hoc signs the whole bundle without entitlements**
  (`codesign --force --deep --sign -`). This keeps the bundle launchable: App
  Sandbox, app-groups, and `keychain-access-groups` need a Team ID +
  provisioning profile, and applying them to an ad-hoc signature makes launchd
  refuse to spawn the app ("Launchd job spawn failed", RBS error 163).
- Runs `Scripts/validate-app-bundle.sh` to confirm structure: the app +
  server binaries, the embedded Sparkle framework `@rpath`, and the
  `.appex` (WidgetKit extension point, Info.plist, binary, verifiable ad-hoc
  signature).

`Scripts/package-dmg.sh` stages that ad-hoc `.app` into a drag-install DMG
(`.build/VaultPeek-<version>.dmg`) with an `/Applications` symlink.

```bash
./Scripts/package-app.sh      # build + ad-hoc-signed .app
./Scripts/package-dmg.sh      # wrap it in a drag-install DMG
```

Because the build is ad-hoc-signed (not notarized), a downloaded DMG requires
**right-click → Open** on first launch so macOS Gatekeeper lets it run.

## Widget / App Group limitation in the ad-hoc build

The WidgetKit extension is embedded in the bundle, but its widgets read a
shared snapshot through an **App Group** (`GlanceSnapshot` / `FinanceSnapshot`
in `PlaidBarCore`). App Groups require an App Group entitlement and a real
signing identity. The bare ad-hoc build **omits** that entitlement, so:

- the menu-bar app, server, demo mode, and local use all work; but
- the widget cannot read the shared snapshot and will not be surfaced in the
  widget gallery / Control Center.

Making the widget functional requires bringing your own App Group entitlement
and Developer ID signing identity (below).

## Bring Your Own Signing (optional, not shipped)

If you want a signed and/or notarized build, you supply the Apple Developer
pieces yourself. None of this lives in the repo:

1. An Apple Developer Program membership and a **Developer ID Application**
   certificate in your login keychain.
2. Your own entitlements files. At minimum, to make the widget's shared
   snapshot work you need an App Group entitlement (e.g.
   `com.apple.security.application-groups` with a `group.<your-team>.<id>`
   value) on both the app and the `.appex`, plus matching
   `keychain-access-groups` for the Plaid access-token bytes the server stores
   in the Keychain.
3. Your own signing/notarization tooling. Sign **inside-out** (nested code
   first): Sparkle's XPC helpers and `Updater.app`, then `Sparkle.framework`,
   then `PlaidBarServer`, then the `.appex` (with its entitlements), then the
   outer `VaultPeek.app` (with its entitlements) — never `codesign --deep` for
   a real signing pass. Then `notarytool submit --wait` and `stapler staple`
   the app and the DMG.
4. Verify on a clean machine: `spctl --assess`, `stapler validate`, and a real
   download → drag-install → double-click launch with no right-click workaround.

Only after a real notarized + clean-machine pass may README/About/release-notes
language change from "ad-hoc signed" to "notarized".

## Sparkle auto-update (dormant, bring-your-own)

Sparkle 2.x ships in the bundle but is dormant: `Info.plist` carries a
placeholder `SUPublicEDKey` and sets no `SUFeedURL`, so no update feed is live.
Enabling it is bring-your-own: generate EdDSA keys (private key stays out of the
repo), set a real `SUPublicEDKey` + an HTTPS `SUFeedURL`, sign each release
archive with `sign_update`, and the archive must already be notarized.
