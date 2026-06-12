# AGENTS.md

## Review guidelines

- Treat any path that moves Plaid `client_secret`, access tokens, public tokens, raw Plaid payloads, real account IDs, transaction IDs, balances, local SQLite data, logs, or screenshots into the SwiftUI app, docs, tests, or generated artifacts as high priority.
- The app target may call only the local PlaidBarServer API for Plaid-backed data. Plaid credentials and provider tokens must remain inside `PlaidBarServer` storage/keychain code.
- Preserve local-first behavior unless the PR explicitly documents a scoped product change and its privacy/security consequences.
- Flag Swift strict-concurrency regressions, non-`Sendable` shared models, or code that would fail `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.
- For UI changes, verify that finance values, risk states, utilization, errors, and chart meaning are not communicated by color alone.
- Prefer focused, serious findings over style feedback; note concrete file/line evidence and the user impact.
