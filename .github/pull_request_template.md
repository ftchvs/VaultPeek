## Summary

-

## Autonomous task IDs

- Task ID(s): <!-- e.g. T002 -->
- Backlog slice: <!-- e.g. PR-001: Loop Governance And Backlog Hygiene -->
- Scope note: <!-- one focused slice; call out if intentionally docs-only -->

## Agent coordination

- Builder agent: <!-- e.g. Hermes, Otto, Codex -->
- Builder branch/worktree: <!-- branch and local checkout/worktree path if relevant -->
- Reviewer/merge steward: <!-- usually Otto for autonomous PlaidBar PRs -->
- Coordination note: <!-- whether another agent may push to this branch, or should review only -->

## Changed files

-

## Local gates

- [ ] `git diff --check`
- [ ] `swift build --target PlaidBar --skip-update --disable-keychain` or documented why not needed.
- [ ] `swift build --target PlaidBarServer --skip-update --disable-keychain` when server/shared DTO/package code changed, or documented why not needed.
- [ ] Focused tests or `swift test` when core/server logic changed, or documented the local Swift Testing limitation.
- [ ] Secret scan completed for docs, source, tests, commands, workflows, and agent prompt files.

## GitHub checks

- [ ] Required GitHub checks are green before merge.
- [ ] `otto-openclaw-merge-gate` is green before merge.
- [ ] Skipped checks are expected and not required for this PR.
- [ ] Any failing, pending, cancelled, missing, or ambiguous required check blocks merge.
- [ ] Claude review auth/token/session/setup-only failures are documented as non-blocking, or there are no such failures.

## Privacy and safety impact

- [ ] I used only sandbox or synthetic financial data in tests, screenshots, examples, and docs.
- [ ] I did not include real Plaid credentials, access tokens, account IDs, transaction exports, raw balances, or screenshots with real financial data.
- [ ] This change preserves the local-first boundary: no hosted backend, telemetry, cloud sync, multi-user account system, or cloud AI over private transaction data.
- [ ] User-facing copy remains honest about local storage, Plaid credentials, production approval, and unsupported security properties.

## Reviewer local-first and secret-exposure checklist

- [ ] The diff does not introduce, log, display, persist, or document real Plaid secrets, access tokens, public tokens, item IDs, account IDs, transaction exports, raw balances, or real financial screenshots.
- [ ] New status, diagnostics, error, analytics-like, AI, or logging surfaces expose only readiness metadata or synthetic/demo data, never private financial records or identifiers.
- [ ] Any server, storage, setup, or diagnostics change keeps PlaidBar local-first: localhost-only companion server, local data directory, no hosted backend, telemetry, tracking, cloud sync, multi-user account system, or cloud AI over transaction data.
- [ ] Any optional AI behavior is local-only, off by default, explainable, reversible, and non-blocking when no local model runtime is configured.
- [ ] Any documentation, examples, fixtures, tests, and screenshots use sandbox or synthetic data and do not imply production readiness, notarization, distribution, or security properties that have not been verified.

## UI and accessibility checks

- [ ] I checked keyboard access and visible focus for UI changes, or this PR has no UI changes.
- [ ] I spot-checked VoiceOver labels or announcements for UI changes, or this PR has no UI changes.
- [ ] I kept balances, risk, utilization, errors, and chart meaning understandable without relying on color alone.
- [ ] I updated docs or screenshots if user-facing behavior changed.

## Merge safety

- [ ] Final diff reviewed for secrets, private financial data, generated artifacts, scope creep, and unsafe destructive behavior.
- [ ] Merge is within the scoped PlaidBar approval in `docs/autonomous-roadmap.md`, or Felipe explicitly approved this PR.
- [ ] PR head SHA was rechecked immediately before merge.
- [ ] No other agent is actively mutating this branch/worktree.
- [ ] After merge, completed task IDs will be recorded in the roadmap ledger and backlog checklist.
