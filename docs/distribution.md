# Distribution: Ad-Hoc Build (Bring Your Own Signing)

> **Status: ad-hoc-signed, unsigned-for-distribution.** This repository ships an
> ad-hoc-signed build path only. There is no team-specific Apple Developer
> identity, entitlements file, or notarization tooling in the tree. The only
> true distribution claim is: an ad-hoc-signed `.app`/DMG that needs
> right-click → Open on first launch. Developer ID signing, notarization, App
> Group entitlements, and Sparkle auto-update are **bring-your-own** — a
> contributor must add their own identity and tooling. Licensing is governed by
> [`LICENSE`](../LICENSE); this document describes the build, not the license.

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

## What May Be Claimed, When

Release language (README, About, release notes) must match what has actually
been performed. Signing/notarization tooling is **not** in this repository, so
the default build may only make the ad-hoc claim:

| Build stage | May claim | Must NOT claim |
|-------------|-----------|----------------|
| Ad-hoc build (the default, shipped here) | "ad-hoc signed", "right-click → Open on first launch" | "notarized", "Developer ID signed", "Gatekeeper-approved" |
| After bring-your-own Developer ID signing (not in repo) | "Developer ID signed" | "notarized" (until a notarytool pass + staple) |
| After bring-your-own notarization + `stapler staple` (not in repo) | "notarized", normal double-click launch | — |

Until a real notarized + clean-machine pass is done by a contributor with their
own identity, the only accurate language is **"ad-hoc signed, right-click →
Open"**.

## Gatekeeper Verification (clean machine, hard requirement)

The structural validity of the bundle/DMG is gated automatically
(`./Scripts/package-app.sh` + `./Scripts/validate-app-bundle.sh`, and
`./Scripts/package-dmg.sh` for release candidates — see
[qa-matrix.md](qa-matrix.md) "App bundle / DMG package validation"). The actual
Gatekeeper open behavior cannot be asserted by the build and must be verified by
a human on a clean machine:

1. Build the DMG (`./Scripts/package-dmg.sh`) and download it over a browser so
   the quarantine bit is set, on a Mac that has never run a dev build.
2. `spctl --assess --type execute --verbose VaultPeek.app` — for an ad-hoc build
   this is expected to report rejected / unsigned (it passes only once a real
   Developer ID + notarization pass is done).
3. `stapler validate VaultPeek.app` — expected to fail until the app is notarized
   and stapled.
4. Human path: open the DMG → drag `VaultPeek.app` to `/Applications` → a plain
   double-click is expected to be blocked → the one-time workaround is
   **right-click (Control-click) → Open**, then confirm. After the first launch
   it opens normally; the menu bar item appears, demo mode renders, the bundled
   server starts, and `~/.vaultpeek/` is created with private permissions.

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
4. Verify on a clean machine using the **Gatekeeper Verification** steps above:
   `spctl --assess`, `stapler validate`, and a real download → drag-install →
   double-click launch with no right-click workaround.

Only after a real notarized + clean-machine pass may README/About/release-notes
language change from "ad-hoc signed" to "notarized" (see **What May Be Claimed,
When** above).

## Sparkle auto-update (dormant, bring-your-own)

Sparkle 2.x ships in the bundle but is dormant: `Info.plist` carries a
placeholder `SUPublicEDKey` and sets no `SUFeedURL`, so no update feed is live.
Enabling it is bring-your-own: generate EdDSA keys (private key stays out of the
repo), set a real `SUPublicEDKey` + an HTTPS `SUFeedURL`, sign each release
archive with `sign_update`, and the archive must already be notarized.
