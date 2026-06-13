# Codex Skills For VaultPeek

Repo-local Codex skills keep VaultPeek (formerly PlaidBar) work focused on
production readiness.

- `vaultpeek-production-loop` — multi-hour improvement loop (formerly
  `plaidbar-production-loop`).
- `commit` — create one focused commit with validation evidence.
- `push` — publish a branch and open/update a PR after approval.
- `review` — review PRs/local diffs for production-readiness risks.

The main user-facing command is:

```bash
/goal
```

Its entrypoint lives in `commands/goal.md`; detailed loop instructions live in
`commands/vaultpeek-prod-loop.md` (`commands/plaidbar-prod-loop.md` remains as
a deprecated pointer for older automation prompts).
