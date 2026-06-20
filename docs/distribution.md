# Distribution Runbook: Signing, Notarization, Gatekeeper, Sparkle

> **Status: PREP ONLY — none of this has been performed.** Developer ID
> signing and notarization require Felipe's Apple Developer account
> credentials, which no agent holds. Until this runbook is executed and
> verified end to end on a clean machine, the only true distribution claim is:
> privately distributed, ad-hoc-signed DMG that needs right-click > Open on
> first launch. Do not soften that claim in README, release notes, or About
> copy (backlog T084).

This is the AND-309 execution plan. `Scripts/notarize.sh` is the executable
scaffold for the signing/notarization steps; it fails fast with instructions
until the required environment exists.

## One-Time Setup (Felipe)

1. Apple Developer Program membership active for the distributing team.
2. Create/download a **Developer ID Application** certificate into the login
   keychain. Confirm with:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

3. Create an app-specific password for notarization and store a notarytool
   profile (credentials live in the Keychain, never in the repo):

   ```bash
   xcrun notarytool store-credentials vaultpeek-notary \
       --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```

4. Export the environment the scaffold expects:

   ```bash
   export PLAIDBAR_SIGNING_IDENTITY="Developer ID Application: Felipe Chaves (TEAMID)"
   export PLAIDBAR_NOTARY_PROFILE="vaultpeek-notary"
   ```

## Entitlements Review (do this before the first signed build)

Current `Sources/PlaidBar/Resources/PlaidBar.entitlements`:

| Entitlement | Value | Review note |
|---|---|---|
| `com.apple.security.app-sandbox` | true | Currently **not enforced**: `Scripts/package-app.sh` ad-hoc signs without `--entitlements`, so the shipped bundle runs unsandboxed. The first hardened-runtime signature will actually enforce the sandbox — expect behavior changes and test everything. |
| `com.apple.security.network.client` | true | Required: app → localhost server, server → Plaid API. |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | `/.vaultpeek/`, `/.plaidbar/` | Needed for the local data directory while sandboxed. Acceptable for Developer ID distribution (it would be rejected on the App Store, which is not the plan). Revisit if storage moves to an app container. |
| `keychain-access-groups` | `$(AppIdentifierPrefix)com.ftchvs.PlaidBar` | Plaid access-token bytes live in Keychain; group must match the signing team prefix once a real team signs. |

Open items the first signed build must resolve:

- The bundled `PlaidBarServer` binds `127.0.0.1:8484`. Under an enforced
  sandbox a listening socket needs `com.apple.security.network.server` —
  either in a second entitlements file for the server binary or in the app
  entitlements if the server inherits them. Decide and test before notarizing.
- Hardened runtime (`--options runtime`) may require exception entitlements if
  anything loads plugins or uses JIT — none known today, but verify Sparkle
  and SwiftNIO behavior under hardened runtime.
- `Info.plist` ships `SUPublicEDKey` = `PLACEHOLDER_ED25519_KEY`. Replace with
  a real key or strip it before signing a public build (see Sparkle below).

## Signing Order (inside-out)

Implemented in `Scripts/notarize.sh`. Never use `codesign --deep` for the real
signing pass; sign nested code first:

1. Sparkle helpers: `Sparkle.framework/Versions/B/XPCServices/Installer.xpc`,
   `Downloader.xpc`, `Versions/B/Autoupdate`, `Versions/B/Updater.app` —
   each `codesign --force --options runtime --timestamp`.
2. `Sparkle.framework` itself.
3. `Contents/MacOS/PlaidBarServer`.
4. `Contents/PlugIns/PlaidBarWidgetExtension.appex` with
   `--entitlements PlaidBarWidgetExtension.entitlements --options runtime --timestamp`.
   `package-app.sh` only ad-hoc signs (no entitlements) this nested extension so
   the local/DMG build stays launchable; the notarized build must re-sign it
   here with its App Group + sandbox entitlements **before** the outer app, or
   the widget never reaches the gallery (AND-385/AND-586). `notarize.sh` verifies
   `group.com.ftchvs.PlaidBar` survived this pass before submitting.
5. `VaultPeek.app` with `--entitlements PlaidBar.entitlements --options runtime --timestamp`.

Then verify locally before submission:

```bash
codesign --verify --deep --strict --verbose=2 .build/VaultPeek.app
```

## Notarization And Stapling

1. Zip the app (`ditto -c -k --keepParent`), submit with
   `xcrun notarytool submit --keychain-profile <profile> --wait`.
2. `xcrun stapler staple .build/VaultPeek.app`.
3. Build the DMG from the **stapled** app (do not rerun `package-app.sh`
   afterwards — it would re-sign ad-hoc over the Developer ID signature).
4. Sign the DMG, submit the DMG to notarytool, staple the DMG.
5. Record `shasum -a 256` for the released DMG.

If a submission is rejected, fetch the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile <profile>
```

## Gatekeeper Verification (clean machine, hard requirement)

On a Mac (or fresh macOS VM) that has never run a dev build:

```bash
spctl --assess --type exec --verbose=2 /Applications/VaultPeek.app
spctl --assess --type open --context context:primary-signature --verbose=2 VaultPeek-<version>.dmg
xcrun stapler validate /Applications/VaultPeek.app
```

Then the human pass: download the DMG over a browser (quarantine bit set),
drag-install, double-click launch — it must open with **no** right-click >
Open workaround, menu bar item appears, demo mode renders, server starts, and
`~/.vaultpeek/` is created with private permissions. Only after this passes
may README/About/release-notes language change from "ad-hoc signed" to
"notarized" (T084).

### Widget, Control Center, and App Intents discovery (AND-586)

The widget extension only loads from a **notarized, /Applications-installed**
build — an ad-hoc local/DMG bundle embeds the `.appex` (gated by
`validate-app-bundle.sh`) but macOS will not surface it in the gallery without a
real signature. After the notarized install, on the same clean machine confirm:

```bash
# The host registered the embedded extension with the WidgetKit plugin host.
pluginkit -m -v -i com.ftchvs.PlaidBar.WidgetExtension
```

Then, in the UI:

- **Widget gallery** (Notification Center → Edit Widgets, or desktop
  right-click → Edit Widgets): "VaultPeek" appears with the small/medium/large
  families; adding one shows the redacted placeholder until the app writes a
  snapshot.
- **Control Center / menu bar** (System Settings → Control Center → add a
  control): "Refresh balances", "Privacy Mask", "Safe to Spend", and "Credit
  Utilization" controls are listed.
- **Spotlight / Shortcuts**: searching "VaultPeek" surfaces the App Intents
  (e.g. Refresh balances, Privacy Mask) and the Spotlight snippet; Shortcuts →
  app actions lists the same intents.

If the gallery is empty, the `.appex` signature lost its App Group/sandbox
entitlements or was deep-signed away — re-run the inside-out signing order above
and re-check `codesign -d --entitlements :- <appex>`.

## Sparkle Update Channel (decide before promising updates)

Sparkle 2.x ships in the bundle today but is dormant: `SUPublicEDKey` is a
placeholder and no `SUFeedURL` is set, so no update feed is live. Before
enabling:

1. Generate EdDSA keys with Sparkle's `generate_keys`; the private key stays
   in Felipe's Keychain — never in the repo.
2. Put the real public key in `SUPublicEDKey` and add `SUFeedURL` pointing at
   a privately hosted `appcast.xml` (HTTPS).
3. Sign each release archive with `sign_update`; the appcast entry carries the
   EdDSA signature; the archive itself must already be notarized.
4. Sandboxed Sparkle needs its XPC services signed as above plus the
   downloader service decision documented in Sparkle's sandboxing guide.
5. Test the full update path: old version installed → appcast offers new
   version → update installs and relaunches → Gatekeeper stays happy.

Alternative track (Homebrew cask) was retired with the proprietary relicense;
the chosen track is the private DMG plus (eventually) Sparkle. A cask requires
public artifacts, which conflicts with private licensing.

## What May Be Claimed, When

| Claim | Allowed when |
|---|---|
| "Privately distributed DMG, right-click > Open on first launch" | Now (true today) |
| "Developer ID signed" | After signing order above runs with a real identity and `codesign --verify` passes |
| "Notarized" | After notarytool acceptance AND stapling AND clean-machine Gatekeeper pass |
| "Auto-updates via Sparkle" | After the appcast end-to-end test above |
