# Troubleshooting

This guide covers the common problems a new VaultPeek user or contributor
should be able to solve without reading the source. (VaultPeek was renamed from
PlaidBar; the `plaidbar`/`plaidbar-server` executable names and `PLAIDBAR_*`
environment variables are intentionally unchanged.)

## Demo Mode Shows No Data

Expected command:

```bash
plaidbar --demo
```

or from source:

```bash
swift run PlaidBar --demo
```

Checks:

- Confirm the app icon is visible in the menu bar.
- Click the menu bar icon to open the popover.
- If setup is visible, choose View Demo.
- Quit any older VaultPeek (or legacy PlaidBar) process and relaunch with
  `--demo`.

Demo mode should not require Plaid credentials or the local server.

## Sandbox Setup Fails

Expected command:

```bash
export PLAID_CLIENT_ID=your_sandbox_client_id
export PLAID_SECRET=your_sandbox_secret
./Scripts/run.sh --sandbox
```

Checks:

- Confirm `PLAID_CLIENT_ID` and `PLAID_SECRET` are set in the same shell.
- Confirm the server is running in sandbox mode, not production mode.
- Confirm the setup preflight shows server online and sandbox environment.
- Confirm the browser can open the Plaid Hosted Link URL.
- Check that no other server is already using the configured port.

Run the sandbox smoke test when debugging server startup:

```bash
./Scripts/smoke-sandbox.sh
```

## Production Setup Does Not Open Plaid Link

Production requires Plaid production approval and production credentials.

Checks:

- Confirm the server is not running with `--sandbox`.
- Confirm `PLAID_ENV=production` if using a config file.
- Confirm production `PLAID_CLIENT_ID` and `PLAID_SECRET` are available to the
  server.
- Confirm setup preflight says production, not sandbox.
- Confirm Plaid has approved the app for production use.

Do not reuse sandbox credentials in production mode.

## Production Mode Reports Missing Credentials (503)

The server boots without credentials into a setup state: `/health` and
`/api/status` keep working, and Plaid-backed routes return `503` until both
credentials are present and the server restarts.

The `503` body and the server boot log name exactly which variable is missing.
A partially configured `server.conf` (for example `PLAID_CLIENT_ID` set but
`PLAID_SECRET` forgotten) is the most common cause and reports the single
missing variable instead of a generic credentials message.

Checks:

- Read the `503` error body or server log line: it says whether
  `PLAID_CLIENT_ID`, `PLAID_SECRET`, or both are missing.
- Confirm both values are in `server.conf` (or exported in the server's
  environment) with no empty values — blank assignments count as missing.
- Restart the server after fixing `server.conf`; credentials are read at boot.
- For production, confirm the values are production credentials from an
  approved Plaid application. Sandbox credentials will not work in production
  mode.

## Production Mode Shows No Linked Accounts After Sandbox Testing

That is expected, not data loss. Sandbox and production use strictly separate
local stores (`plaidbar-sandbox.sqlite` vs `plaidbar-production.sqlite`) and
separate caches in the same data directory, so real financial data and test
data never mix. Each mode starts empty until accounts are linked in that mode.

## App Says Server Is Offline

Checks:

- Start the local server with `plaidbar-server --sandbox` or
  `./Scripts/run.sh --sandbox`.
- Confirm the port matches the app configuration.
- Visit `http://127.0.0.1:8484/health` if using the default port.
- If using a custom port, export the same `PLAIDBAR_SERVER_PORT` before starting
  the app.
- Quit duplicate VaultPeek app/server processes if they are conflicting.
- If a legacy PlaidBar.app is still installed, quit and delete it: it shares
  the same bundle identifier and default port 8484 with VaultPeek.app.

## API Calls Return Unauthorized

The app and server share a local bearer token stored under the VaultPeek data
directory.

Checks:

- Confirm the app and server use the same `PLAIDBAR_DATA_DIR`.
- Confirm `~/.vaultpeek/auth-token` exists for default installs.
- If this Mac was used before the VaultPeek storage migration, confirm
  `~/.plaidbar/auth-token` was copied or restart once with both directories
  available.
- Restart both the app and server after changing the data directory.
- Avoid copying `auth-token` into public logs or issues.

## Default Storage Did Not Migrate

VaultPeek uses `~/.vaultpeek/` as its default local data/config directory.
On startup, default installs copy missing files from `~/.plaidbar/` into
`~/.vaultpeek/`.

Expected behavior:

- Existing `auth-token`, `server.conf`, SQLite stores and sidecars, account and
  transaction caches, pending link sessions, and `server.log` are copied when
  the destination filename is absent.
- Existing `~/.vaultpeek/` files are preserved and never overwritten.
- `~/.plaidbar/` is left in place for rollback until the user deletes it.
- After a local reset, VaultPeek writes a small reset marker so old databases,
  caches, and pending link sessions are not copied back from `~/.plaidbar/`.
- Keychain Plaid access tokens keep the existing service name so SQLite
  `keychain:<item_id>` references remain valid after file migration.

Recovery checks:

- Quit the VaultPeek app and its companion server.
- Confirm both directories are private to the current user.
- Move only the missing file from `~/.plaidbar/` to `~/.vaultpeek/` if a newer
  VaultPeek file is not already present.
- To roll back temporarily, set `PLAIDBAR_DATA_DIR=~/.plaidbar` before starting
  both the app and server.

## Accounts Are Linked But Transactions Are Empty

Possible causes:

- Plaid has not returned historical transactions yet.
- The item needs another sync.
- The account has no transaction history.
- Filters are hiding every transaction.
- The app/server are pointed at different data directories or environments.

Actions:

- Click Refresh.
- Clear transaction filters.
- Open Status and check item health.
- Confirm sandbox vs production mode.

## Reconnect Is Required

Plaid may mark an item as requiring login or re-authentication.

Actions:

- Open Status or Settings > Accounts.
- Use the reconnect action for the affected institution.
- Complete the Plaid browser flow.
- Refresh after returning to VaultPeek.

## Notifications Do Not Fire

Checks:

- Open Settings > Notifications.
- Confirm notifications are enabled in VaultPeek.
- Confirm macOS notification permission is allowed for VaultPeek.
- Check large transaction, low balance, and credit utilization thresholds.
- Remember that duplicate alerts are intentionally deduplicated.

If macOS permission was revoked, re-enable notifications in System Settings and
restart VaultPeek.

Source-built executable runs may report notification permission as
unavailable or denied if macOS cannot register the process as an app bundle.
VaultPeek avoids calling the notification center in that state so Settings does
not crash. Signed/notarized app-bundle notification behavior remains part of the
post-1.0 distribution work.

## Local Data Reset Did Not Revoke Bank Access

That is expected. Local reset clears VaultPeek's local data. It does not
guarantee revocation in Plaid Dashboard or at the bank. For complete revocation,
review Plaid Dashboard and the bank's connected-app permissions.

## Screenshot Script Fails

Expected command:

```bash
./Scripts/screenshots.sh
```

Checks:

- Terminal has macOS Screen Recording permission.
- Terminal has macOS Accessibility permission for UI automation.
- No other VaultPeek window is blocking the scripted flow.
- Run from the repository root.

Screenshots should use demo or sandbox data only.

## Local Test Command Fails With `no such module 'Testing'`

Some local Swift toolchains do not include the Swift Testing module expected by
the test target. CI is currently the canonical test signal when local toolchain
support is missing.

The recorded toolchain baseline (CI: `macos-15` runner with Xcode 16; package
`swift-tools-version: 6.0`) and the release-time escape hatch
(`PLAIDBAR_RELEASE_SKIP_TESTS=1`, valid only for this documented mismatch) live
in `docs/release-checklist.md`. `Package.swift` probes known Xcode and Command
Line Tools paths for `lib_TestingInterop.dylib`; if your toolchain lives
elsewhere, set `DEVELOPER_DIR` to its developer directory.

Still run the smaller local gates:

```bash
git diff --check
bash -n Scripts/*.sh Scripts/vaultpeek-run Scripts/plaidbar-run
swift build --target PlaidBar --skip-update --disable-keychain
```
