# Troubleshooting

This guide covers the common problems a new PlaidBar user or contributor should
be able to solve without reading the source.

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
- Quit any older PlaidBar process and relaunch with `--demo`.

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

## App Says Server Is Offline

Checks:

- Start the local server with `plaidbar-server --sandbox` or
  `./Scripts/run.sh --sandbox`.
- Confirm the port matches the app configuration.
- Visit `http://127.0.0.1:8484/health` if using the default port.
- If using a custom port, export the same `PLAIDBAR_SERVER_PORT` before starting
  the app.
- Quit duplicate PlaidBar/PlaidBarServer processes if they are conflicting.

## API Calls Return Unauthorized

The app and server share a local bearer token stored under the PlaidBar data
directory.

Checks:

- Confirm the app and server use the same `PLAIDBAR_DATA_DIR`.
- Confirm `~/.plaidbar/auth-token` exists.
- Restart both the app and server after changing the data directory.
- Avoid copying `auth-token` into public logs or issues.

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
- Refresh after returning to PlaidBar.

## Notifications Do Not Fire

Checks:

- Open Settings > Notifications.
- Confirm notifications are enabled in PlaidBar.
- Confirm macOS notification permission is allowed for PlaidBar.
- Check large transaction, low balance, and credit utilization thresholds.
- Remember that duplicate alerts are intentionally deduplicated.

If macOS permission was revoked, re-enable notifications in System Settings and
restart PlaidBar.

## Local Data Reset Did Not Revoke Bank Access

That is expected. Local reset clears PlaidBar's local data. It does not
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
- No other PlaidBar window is blocking the scripted flow.
- Run from the repository root.

Screenshots should use demo or sandbox data only.

## Local Test Command Fails With `no such module 'Testing'`

Some local Swift toolchains do not include the Swift Testing module expected by
the test target. CI is currently the canonical test signal when local toolchain
support is missing.

Still run the smaller local gates:

```bash
git diff --check
bash -n Scripts/*.sh Scripts/plaidbar-run
ruby -c Formula/plaidbar.rb
swift build --target PlaidBar --skip-update --disable-keychain
```
