# Privacy

PlaidBar is local-first personal finance software. It has no hosted PlaidBar
backend, no analytics, no telemetry, and no tracking.

This document states the privacy contract the implementation and public docs
must continue to match.

## What Leaves Your Mac

PlaidBar sends data to Plaid only when you use sandbox or production Plaid
mode. In those modes, the local companion server calls Plaid API endpoints to:

- create a link session
- exchange a public token after Plaid Link completes
- fetch account metadata and balances
- sync transactions
- remove or update a linked item when requested

Demo mode does not call Plaid.

## What Does Not Leave Your Mac

PlaidBar does not send financial data to a PlaidBar-owned server because there
is no PlaidBar cloud backend.

PlaidBar does not include:

- analytics
- telemetry
- advertising pixels
- hosted sync
- multi-user accounts
- cloud dashboards

## Local Data

By default, PlaidBar stores local data under:

```text
~/.plaidbar/
```

The directory can be overridden with `PLAIDBAR_DATA_DIR`.

Current local data may include:

- local app-server auth token
- Plaid item records
- Plaid access-token references in SQLite, with access-token bytes in macOS
  Keychain when Security framework support is available
- account metadata
- balances
- transaction cache
- pending link-session state

Sandbox and production use separate scoped stores.

`/api/status` is authenticated and intentionally limited to readiness metadata:
server version, Plaid environment, credential availability, storage path, item
counts, synced item count, sync readiness, and last sync time. It should not
contain Plaid secrets, Plaid access tokens, public tokens, local auth tokens,
account IDs, item IDs, balances, or transactions.

## Credentials

Plaid credentials are provided to the local server through the environment or a
local config file. They should not be embedded in the app binary, committed to
the repository, pasted into public issues, or included in screenshots.

Examples in documentation use placeholders only.

## Screenshots and Issues

Public screenshots, bug reports, tests, and fixtures should use demo, sandbox,
or synthetic financial data.

Do not publish:

- real Plaid credentials
- Plaid access tokens
- public tokens
- item IDs
- account IDs
- real balances
- real merchant history
- exported transaction files
- screenshots containing real financial details

Security-sensitive reports should follow [SECURITY.md](../SECURITY.md), not a
public GitHub issue.

## Local Reset Boundary

Resetting local data removes PlaidBar's local cache and local stored item data.
It does not necessarily delete records from the Plaid Dashboard or revoke bank
permissions outside PlaidBar. Users who need complete revocation should also
review Plaid Dashboard and bank-side permission settings.

## 1.0 Privacy Checklist

- README privacy claims match implementation.
- Setup copy explains local storage before Plaid Link opens.
- Settings shows the local storage path.
- Reset/remove actions explain local-vs-Plaid-vs-bank boundaries.
- Status endpoints do not expose secrets.
- Logs do not print secrets or raw financial exports.
- Screenshots contain no real financial data.
