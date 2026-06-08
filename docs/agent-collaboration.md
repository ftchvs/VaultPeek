# Agent Collaboration Protocol

PlaidBar can be advanced by more than one local agent on the shared Mac mini.
Use this protocol to keep autonomous work fast without creating branch,
worktree, or merge collisions.

## Roles

- Hermes is the primary builder loop for autonomous PlaidBar implementation.
- Otto is the operator/reviewer/merge steward.
- Felipe is out of the loop by default for scoped PlaidBar production-readiness
  work unless a decision exceeds the boundaries below.

## Worktree Ownership

- Hermes should work from its own temporary worktree, commonly
  `/private/tmp/PlaidBar-otto`.
- Otto should review and fix from a separate checkout or worktree.
- Do not mutate another agent's active worktree.
- Before pushing to a branch another agent owns, verify that agent is not
  actively editing or running a write step on the same branch.

## Autonomous Merge Gates

Otto may merge PlaidBar PRs without asking Felipe when all of these are true:

- PR is not draft.
- Diff is scoped to one coherent task or PR slice.
- No blocking review issue remains.
- Local verification passed, or CI fully covers the relevant gate.
- GitHub checks are green, or only non-required/skipped checks remain.
- Privacy/local-first boundaries are preserved.
- No secrets, local databases, screenshots, logs, or build artifacts are added.
- The PR branch is not being actively mutated by Hermes or another agent.

If any gate is unclear, pause the merge and leave a PR comment with the blocker.

## PR Handoff Format

Every autonomous PR should include:

- task ID(s)
- changed files and behavior
- verification commands/results
- privacy and local-first impact
- known risks or follow-up

## Review Responsibilities

Otto's review should check:

- product clarity and user-facing copy
- accessibility and keyboard behavior
- local-first/privacy boundaries
- test coverage proportional to the change
- CI and local verification evidence
- roadmap/backlog updates match the actual implementation

## Current Operating Rule

Hermes can keep producing small PRs. Otto can review, fix if needed, comment,
wait for green checks, and merge. Felipe should only be pulled in for product
direction changes, destructive actions, external integrations, ambiguous
privacy/security decisions, or work outside PlaidBar's scoped autonomy.
