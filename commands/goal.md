---
description: Continue PlaidBar production-readiness work for multiple hours.
argument-hint: "[focus area] [--hours=2-4] [--no-commit]"
---

# /goal

Run the PlaidBar production-readiness loop for a multi-hour work session.

Default goal:

> Make PlaidBar feel like RepoBar for personal finance: a native macOS menu-bar
> instrument with a GitHub-style heatmap header, dense account/card rows,
> financial scope filters, and drill-in details for each account.

## How To Use

```bash
/goal
/goal "trust-first local data controls" --hours=2
/goal "empty states and error recovery" --hours=3
/goal "RepoBar-style finance dashboard" --hours=4
```

This command intentionally delegates the detailed operating loop to:

```text
commands/plaidbar-prod-loop.md
```

Read that file first, then execute the same loop with the `/goal` arguments as
the requested focus/timebox.

## Priority Order

1. RepoBar-style finance dashboard:
   - heatmap header at the top of the popover,
   - segmented filters for All, Cash, Credit, Savings, Debt, and Status,
   - compact rows for accounts/cards with balance, utilization/status, and last update,
   - row selection or drill-in details for a specific credit card/account.
2. Trust-first local data controls in Settings.
3. Sharper empty and error states across Accounts, Transactions, and Credit.
4. Server/config preflight for environment and credential readiness.
5. Reconnect/degraded-item handling.
6. Demo and screenshot polish.
7. Distribution readiness only after the real Plaid flow is reliable.

## RepoBar Design Reference

Study RepoBar before changing PlaidBar's primary UI:

- `https://repobar.app`
- `https://github.com/steipete/RepoBar`
- local reference clone, when present: `/Users/otto/.openclaw/workspace/repos/RepoBar`
- attached screenshot target: translucent macOS popover, GitHub contribution
  heatmap header, segmented filters, dense selected rows, and right-arrow drill-in.

Translate the pattern to finance instead of copying GitHub concepts literally:

- Repo heatmap -> daily spend/cashflow heatmap.
- Repository cards/rows -> checking, savings, credit card, loan, and other account rows.
- Issues/PRs/forks metadata -> balance, available credit, utilization, pending count, sync freshness.
- Repository submenu -> account/card detail view with transactions, limits, status, and recovery actions.
- Pinned/local/work filters -> All/Cash/Credit/Savings/Debt/Status finance filters.

## Stop Conditions

Stop and report when:

- the requested timebox ends,
- a coherent slice is committed and ready for push/PR approval,
- verification fails on a real regression,
- a product/security decision needs Felipe.

Never push, open PRs, or merge from `/goal` without explicit approval.
