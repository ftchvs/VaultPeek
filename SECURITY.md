# Security

PlaidBar is a local-first macOS menu bar app for sensitive financial data. Treat Plaid credentials, access tokens, account identifiers, balances, transaction data, and local database contents as private.

## Supported Versions

The `main` branch is the supported development line before stable releases are published.

## Reporting a Vulnerability

Please do not open a public GitHub issue for suspected vulnerabilities, token handling bugs, private financial data exposure, or exploitable security issues.

Use GitHub private vulnerability reporting if available, or contact the repository owner through the GitHub profile. Include:

- affected commit or version
- steps to reproduce
- impact
- whether Plaid tokens, account metadata, transaction data, or local database contents may be exposed
- suggested remediation, if known

## Data Handling Boundaries

- Do not share real Plaid `client_id`, `secret`, `access_token`, `public_token`, item IDs, account IDs, transaction exports, or screenshots with real balances in issues, pull requests, logs, or discussions.
- Screenshots, tests, fixtures, and public examples should use sandbox or synthetic financial data.
- Logs should not include real account numbers, access tokens, raw transaction details, or secrets.
- Environment variables such as `PLAID_SECRET` can leak through terminal history or process inspection on a compromised machine.

## Security Model

- PlaidBar has no hosted backend, analytics, telemetry, or tracking.
- The companion server should bind to `127.0.0.1` only.
- Plaid secrets and access tokens must not be embedded in the app binary.
- The local server stores Plaid item access tokens in environment-scoped SQLite files under `~/.plaidbar/`:
  `plaidbar-sandbox.sqlite` for sandbox and `plaidbar-production.sqlite` for production.
- Existing legacy `plaidbar.sqlite` data, SQLite sidecar files, and matching transaction cache are copied into a scoped database only when the legacy environment is explicit (`PLAIDBAR_MIGRATE_LEGACY_DATABASE=sandbox|production`) or can be inferred from the existing transaction-cache context. Ambiguous legacy databases are left untouched to avoid sandbox/production token crossover. Explicit migration can replace an existing scoped store, backs up the previous scoped SQLite store and transaction cache before copying legacy data, and writes a migration marker so restarts do not reapply stale legacy data.
- The app/server auth token is generated locally under `~/.plaidbar/auth-token`.
- Protect your macOS user account, disk encryption, backups, and shell history.
- App-server communication should preserve local-only assumptions unless a future change explicitly documents otherwise.

## Supported Modes

- `--demo` app mode uses hardcoded local fixture data and does not call Plaid.
- `--sandbox` server mode calls Plaid sandbox and requires sandbox credentials.
- Production mode calls Plaid production and requires Plaid approval plus production credentials.

Use sandbox or demo data when sharing screenshots, reproductions, or public examples.

## Maintainer Response

Maintainers will acknowledge credible reports, investigate the scope, and fix or document mitigations before public disclosure when appropriate.
