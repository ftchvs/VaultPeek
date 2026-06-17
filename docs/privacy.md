# Privacy

VaultPeek (formerly PlaidBar) is local-first personal finance software. It has
no hosted VaultPeek backend, no analytics, no telemetry, and no tracking.

This document states the privacy contract the implementation and public docs
must continue to match.

## What Leaves Your Mac

VaultPeek sends data to Plaid only when you use sandbox or production Plaid
mode. In those modes, the local companion server calls Plaid API endpoints to:

- create a link session
- exchange a public token after Plaid Link completes
- fetch account metadata and balances
- sync transactions
- remove or update a linked item when requested

Demo mode does not call Plaid.

## What Does Not Leave Your Mac

VaultPeek does not send financial data to a VaultPeek-owned server because
there is no VaultPeek cloud backend.

VaultPeek does not include:

- analytics
- telemetry
- advertising pixels
- hosted sync
- multi-user accounts
- cloud dashboards

## Managed Bank Linking (Planned — Not Yet Available)

VaultPeek's roadmap includes an optional **managed cloud bridge** for bank
linking: instead of bringing your own Plaid keys, a hosted VaultPeek service
would broker the bank connection on your behalf. In the planned design (see
`docs/strategy/managed-link-architecture.md` and
`docs/strategy/managed-link-consent-operations.md`), the boundary is **"never
stored," not "never transits."** The broker would hold only your identity,
entitlement, and an item registry; your financial data (accounts, balances,
transactions) would still live only on your Mac dashboard. But because Plaid
requires VaultPeek's production credentials, managed-mode data-plane responses
would **transit a hosted VaultPeek stateless proxy** (transit-only, in memory,
never persisted and never logged) on the way to your Mac. So managed mode would
break the "no data ever leaves a VaultPeek server" promise while preserving the
"no financial data is ever stored off your Mac" promise.

Managed support would also have a hard no-secrets rule: helpers could guide
users through VaultPeek screens, but they could not ask for, receive, type, or
store bank credentials, MFA codes, Plaid tokens, raw account IDs, balances,
transactions, local databases, logs, or screenshots containing financial data.
The exact wording will be finalized — and approved — before any managed surface
ships.

This managed mode does not exist today. As of this writing:

- There is no VaultPeek cloud backend, no managed broker, and no billing.
- The app's plan picker is a **preview** of proposed tiers; selecting a plan
  changes nothing, charges nothing, and grants no access.
- Every connection today is **bring-your-own (BYO)** Plaid keys (or demo data).
  BYO/demo modes are intended to stay free and to use **no VaultPeek-hosted
  service** — but BYO still talks to Plaid directly from your local server (see
  "What Leaves Your Mac" above); it is not "local-only" in the sense that real
  bank data never leaves your Mac.

When and if managed linking ships, this document, `README.md`, and
`SECURITY.md` will state exactly what the bridge touches, what transits it, what
is never stored there, and what happens on cancellation — before any managed
surface is enabled. Until then, treat any "managed plan" copy in the app as a
forward-looking preview, not a description of current behavior.

## Local Data

By default, VaultPeek stores local data under:

```text
~/.vaultpeek/
```

The directory can be overridden with `PLAIDBAR_DATA_DIR`.
Existing default installs using `~/.plaidbar/` are copied into
`~/.vaultpeek/` on startup when the new directory does not already contain the
same file. The legacy directory is left in place as rollback evidence, and
newer `~/.vaultpeek/` files are never overwritten by migration.

Current local data may include:

- local app-server auth token
- Plaid item records
- Plaid access-token references in SQLite, with access-token bytes in macOS
  Keychain when Security framework support is available
- account metadata
- balances
- account and transaction caches
- pending link-session state
- local server logs

Sandbox and production use separate scoped stores.

`/api/status` is authenticated and limited to readiness metadata: server
version, Plaid environment, credential availability, storage path, item counts,
synced item count, sync readiness, and last sync time. When the caller opts in
with `?include=items`, it also returns the same authenticated item-health
snapshot as `/api/items` — per-item Plaid `item_id`, institution name,
connection status, last sync, last webhook, and whether a sync is pending. It
should not contain Plaid secrets, Plaid access tokens, public tokens, local
auth tokens, account IDs, balances, or transactions.

## Credentials

Plaid credentials are provided to the local server through the environment or a
local config file. They should not be embedded in the app binary, committed to
the repository, pasted into public issues, or included in screenshots.

Examples in documentation use placeholders only.

## Screenshots and Issues

Public screenshots, bug reports, tests, and fixtures should use demo, sandbox,
or synthetic financial data.

The in-flight Privacy Mask and App Lock work is planned as display-safety
controls, not storage controls. Until the corresponding app controls ship, this
section is a release gate for that work rather than a claim about the current
published build:

- **Privacy Mask** should hide balances, account endings, utilization values,
  transaction amounts, merchant names, and other financial details from the app
  chrome while keeping the dashboard usable on a shared desktop.
- **App Lock** should block access until local macOS authentication succeeds.
  When the app is locked, refresh and notification behavior must follow the
  user's lock policy and must fail closed when a safe policy is unavailable.
- **Notification privacy** should not include account names, balances,
  transaction amounts, merchants, utilization status, or recovery details while
  Privacy Mask or App Lock is active. Use generic copy instead.

These controls do not delete local data and do not change where data is stored.
They reduce accidental disclosure on-screen, in notifications, and in public QA
artifacts.

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

Resetting local data removes VaultPeek-owned database files, account and
transaction caches, pending Link sessions, and stored Plaid access-token entries
when present. It leaves `server.conf`, app/server auth, preferences, and
unrelated files in the storage directory untouched.

The storage-directory migration does not rename Keychain entries. Plaid access
tokens continue to use the existing Keychain service so migrated SQLite
`keychain:<item_id>` references keep working.

Local reset does not necessarily delete records from the Plaid Dashboard or
revoke bank permissions outside VaultPeek. Users who need complete revocation
should also review Plaid Dashboard and bank-side permission settings.

## Stable Release Privacy Checklist

- README privacy claims match implementation.
- Setup copy explains local storage before Plaid Link opens.
- Settings shows the local storage path.
- Privacy Mask and App Lock copy states the difference between on-screen
  masking, local authentication, and local data retention.
- Notification previews and release notes use generic copy when private; no
  release artifact claims sensitive notification detail is shown while masked or
  locked.
- Reset/remove actions explain local-vs-Plaid-vs-bank boundaries.
- Status endpoints do not expose secrets.
- Logs do not print secrets or raw financial exports.
- Screenshots contain no real financial data and any privacy/app-lock screenshot
  uses demo, sandbox, or synthetic values only.
