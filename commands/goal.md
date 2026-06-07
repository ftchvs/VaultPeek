---
description: Continue PlaidBar production-readiness work through the autonomous backlog.
argument-hint: "[focus area] [--hours=2-4] [--no-commit]"
---

# /goal

Run the PlaidBar production-readiness loop for a multi-hour work session or
one reviewable autonomous backlog task.

Default goal:

> Advance the next safe PlaidBar production-readiness task while preserving the
> local-first privacy contract, minimalist modern macOS design, and honest
> security boundaries.

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
docs/autonomous-loop-backlog.md
docs/autonomous-roadmap.md
```

Read those files first, then execute the same loop with the `/goal` arguments
as the requested focus/timebox. Treat one backlog task as the default iteration;
combine adjacent tasks only when the resulting PR remains easy to review.

## Priority Order

1. Minimalist modern dashboard polish: heatmap first, dense rows, semantic
   color, compact native controls, no marketing chrome.
2. Security and safety: token/storage invariants, status redaction, auth
   behavior, logs, screenshots, and destructive-action confirmations.
3. Local-first privacy: no PlaidBar backend, telemetry, cloud sync, multi-user
   state, or cloud AI over transaction data.
4. Plaid setup reliability: demo, sandbox, production preflight, reconnect,
   degraded item handling, and status diagnostics.
5. Optional local AI: local-only, off by default, explainable, reversible, and
   non-blocking when no local model runtime is configured.
6. Production readiness: QA matrix, release notes, troubleshooting, packaging
   checks, and honest distribution assumptions.

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
- a coherent task or PR slice is committed and ready for the PR/check/review
  loop,
- verification fails on a real regression,
- a product/security decision needs Felipe.

Interactive `/goal` defaults to local work. Push, open PRs, or merge only when
the current run is explicitly operating under the scoped PlaidBar approval
documented in `docs/autonomous-roadmap.md`, all local and GitHub checks are
green, and the safe PR loop says the diff is mergeable. If approval scope or
safety is unclear, stop with a handoff instead of merging.
