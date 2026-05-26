# Security

PlaidBar handles sensitive financial metadata locally. Please report security or
privacy issues responsibly.

## Supported versions

The `main` branch is the supported development line before stable releases are
published.

## Reporting a vulnerability

Use GitHub private vulnerability reporting if available, or contact the
repository owner through the GitHub profile. Do not open a public issue for
secrets, token handling bugs, private financial data exposure, or exploitable
vulnerabilities.

Please include:

- affected commit or version
- steps to reproduce
- impact
- whether Plaid tokens, account metadata, transaction data, or local database
  contents may be exposed
- suggested remediation, if known

## Security model

- The companion server should bind to `127.0.0.1` only.
- Plaid secrets and access tokens must not be embedded in the app binary.
- Screenshots, tests, and examples must use sandbox or synthetic financial data.
- Logs should not include real account numbers, access tokens, raw transaction
  details, or secrets.
- App-server communication should preserve local-only assumptions unless a
  future change explicitly documents otherwise.

## Maintainer response

Maintainers will acknowledge credible reports, investigate the scope, and fix or
document mitigations before public disclosure when appropriate.
