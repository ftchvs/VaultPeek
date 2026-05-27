# Codex Skills For PlaidBar

Repo-local Codex skills keep PlaidBar work focused on production readiness.

- `plaidbar-production-loop` — multi-hour improvement loop.
- `commit` — create one focused commit with validation evidence.
- `push` — publish a branch and open/update a PR after approval.
- `review` — review PRs/local diffs for production-readiness risks.

The main user-facing command is:

```bash
/goal
```

Its entrypoint lives in `commands/goal.md`; detailed loop instructions live in
`commands/plaidbar-prod-loop.md`.
