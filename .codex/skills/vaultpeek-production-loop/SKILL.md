---
name: vaultpeek-production-loop
description: Keep VaultPeek moving through multi-hour production-readiness improvement loops.
---

# VaultPeek Production Loop

> Formerly `plaidbar-production-loop`. SwiftPM targets, executables, and
> `PLAIDBAR_*` environment variables intentionally keep the PlaidBar name.

Use this skill when Felipe asks to keep improving VaultPeek, make it production
ready, or run the repo-local `/goal` command.

## Goal

VaultPeek should become a local-first macOS menu bar dashboard for Plaid data:
RepoBar/CodexBar for personal finance. Favor a dense, trustworthy, heatmap-first
menu-bar instrument over new feature breadth.

## Rules

- Work locally by default. Use a scoped VaultPeek approval for push, PR
  creation, and merge only when the current task is clearly inside that scope.
- Merge only after local gates pass, GitHub checks are green, review feedback is
  addressed, and a final safety read finds no secrets, real financial data,
  generated artifacts, or local-first boundary violations.
- Do not add hosted backend, telemetry, cloud sync, multi-user support,
  budgeting workflows, or cloud AI over private transaction data.
- Keep optional AI local-only, off by default, explainable, reversible, and
  non-blocking when no local model runtime is configured.
- Do not overclaim security. If tokens are stored in SQLite, say that plainly.
- Keep changes small, reviewable, and backed by verification evidence.

## Loop

1. Inspect `git status --short --branch`, `GOAL.md`, `README.md`,
   `DESIGN.md`, and the files likely to change.
2. Choose one unfinished task from the current backlog, combining adjacent
   tasks only when the PR remains easy to review.
3. Implement using existing SwiftUI, `AppState`, `ServerClient`, settings,
   status, and `PlaidBarCore` patterns.
4. Run:
   - `git diff --check`
   - `swift build --target PlaidBar --skip-update --disable-keychain`
   - focused Swift tests when logic changed and the local toolchain supports it
   - a secret scan over docs, sources, tests, `commands`, and `.codex`
5. Commit only one coherent slice at a time.
6. When scoped approval applies, push the branch, open or update the PR, request
   review, wait for green checks, address feedback, and merge only after the
   safety gate passes.
7. Report progress with branch, task IDs, changed files, validation, warnings,
   PR/check/merge status, and next slice.

## Preferred Next Slice

When no focus is supplied, implement the RepoBar-style finance dashboard:

- study `https://repobar.app`, `https://github.com/steipete/RepoBar`, and the
  local reference clone at `<your-local-RepoBar-clone>` when
  available,
- lead the popover with a GitHub-style daily spend/cashflow heatmap,
- add All/Cash/Credit/Savings/Debt/Status filters,
- show checking, savings, credit cards, loans, and other accounts as compact
  rows with balance/utilization/status/freshness,
- open a focused account/card detail surface from a selected row,
- keep finance semantics explicit and avoid full budgeting workflows.

After that, continue with trust-first local data controls:

- show the local data directory (default `~/.vaultpeek/`) in Settings,
- add copy/reveal actions if practical,
- add confirmation-gated reset/delete local data,
- explain what local reset does and does not remove.
