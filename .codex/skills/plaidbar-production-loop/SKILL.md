---
name: plaidbar-production-loop
description: Keep PlaidBar moving through multi-hour production-readiness improvement loops.
---

# PlaidBar Production Loop

Use this skill when Felipe asks to keep improving PlaidBar, make it production
ready, or run the repo-local `/goal` command.

## Goal

PlaidBar should become a local-first macOS menu bar dashboard for Plaid data:
CodexBar for personal finance. Favor trustworthy real-data readiness over new
feature breadth.

## Rules

- Work locally unless Felipe explicitly approves push or PR creation.
- Never merge from this skill.
- Do not add hosted backend, telemetry, cloud sync, multi-user support, or
  budgeting workflows.
- Do not overclaim security. If tokens are stored in SQLite, say that plainly.
- Keep changes small, reviewable, and backed by verification evidence.

## Loop

1. Inspect `git status --short --branch`, `GOAL.md`, `README.md`,
   `DESIGN.md`, and the files likely to change.
2. Choose one production-readiness slice:
   - local data controls,
   - empty/error states,
   - server/config preflight,
   - reconnect and degraded item handling,
   - demo/screenshot polish.
3. Implement using existing SwiftUI, `AppState`, `ServerClient`, settings,
   status, and `PlaidBarCore` patterns.
4. Run:
   - `git diff --check`
   - `swift build --target PlaidBar --skip-update --disable-keychain`
   - focused Swift tests when logic changed and the local toolchain supports it
   - a secret scan over docs, sources, tests, `commands`, and `.codex`
5. Commit only one coherent slice at a time.
6. Report progress with branch, changed files, validation, warnings, and next
   slice.

## Preferred Next Slice

When no focus is supplied, implement trust-first local data controls:

- show `~/.plaidbar/` in Settings,
- add copy/reveal actions if practical,
- add confirmation-gated reset/delete local data,
- explain what local reset does and does not remove.
