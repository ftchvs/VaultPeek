---
description: Continue PlaidBar production-readiness work for multiple hours.
argument-hint: "[focus area] [--hours=2-4] [--no-commit]"
---

# /goal

Run the PlaidBar production-readiness loop for a multi-hour work session.

Default goal:

> Make PlaidBar trustworthy and useful with real Plaid data: clear local data
> controls, reliable sandbox/production setup, actionable diagnostics, and
> polished empty/error states.

## How To Use

```bash
/goal
/goal "trust-first local data controls" --hours=2
/goal "empty states and error recovery" --hours=3
```

This command intentionally delegates the detailed operating loop to:

```text
commands/plaidbar-prod-loop.md
```

Read that file first, then execute the same loop with the `/goal` arguments as
the requested focus/timebox.

## Priority Order

1. Trust-first local data controls in Settings.
2. Sharper empty and error states across Accounts, Transactions, and Credit.
3. Server/config preflight for environment and credential readiness.
4. Reconnect/degraded-item handling.
5. Demo and screenshot polish.
6. Distribution readiness only after the real Plaid flow is reliable.

## Stop Conditions

Stop and report when:

- the requested timebox ends,
- a coherent slice is committed and ready for push/PR approval,
- verification fails on a real regression,
- a product/security decision needs Felipe.

Never push, open PRs, or merge from `/goal` without explicit approval.
