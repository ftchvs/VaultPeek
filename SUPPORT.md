# Support

PlaidBar is a local-first macOS utility for sensitive financial data. Public
support should stay useful without exposing private account details.

## Supported Versions

| Version | Status |
|---------|--------|
| `1.0.x` | Supported stable release line |
| `main` | Active development branch |
| `< 1.0` | Historical pre-1.0 releases; upgrade recommended |

Security fixes target `main` first and may be released as a `1.0.x` patch when
they affect the stable release line.

## Public Issues

Use GitHub issues for:

- setup bugs
- demo or sandbox flow bugs
- UI, accessibility, and documentation issues
- feature requests
- Homebrew formula/install problems

Do not include:

- real Plaid credentials or environment values
- Plaid access tokens, public tokens, item IDs, or account IDs
- screenshots with real balances, transactions, or institution details
- local database files, auth-token files, or transaction exports

Prefer demo mode, sandbox credentials, synthetic examples, and redacted logs.

## Security Reports

Do not open public issues for suspected vulnerabilities or private data
exposure. Use GitHub private vulnerability reporting from the Security tab, or
follow [SECURITY.md](SECURITY.md).

## Plaid-Specific Support

Plaid institution coverage, production approval, and Plaid API behavior may
require Plaid documentation or Plaid support. PlaidBar can help make local
server state and setup readiness visible, but it cannot grant Plaid production
access or change institution support.
