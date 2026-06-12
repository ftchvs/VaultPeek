# Agent Collaboration Protocol

PlaidBar can be advanced by more than one local agent on the shared Mac mini.
Use this protocol to keep autonomous work fast without creating branch,
worktree, or merge collisions.

## Roles

- Hermes is the primary builder loop for autonomous PlaidBar implementation.
- Otto is the operator/reviewer/merge steward.
- Felipe is out of the loop by default for scoped PlaidBar production-readiness
  work unless a decision exceeds the boundaries below.

## Coordination Channels

Use these channels in order. Do not rely on private memory or hidden chat state
as the only source of truth for a branch.

1. **GitHub PR** is the canonical handoff channel for a completed slice.
   - The builder records task IDs, changed files, local gates, privacy impact,
     and any limitations in the PR body.
   - The reviewer records final gate decisions, skipped-check rationale, and
     merge notes in PR comments.
2. **Linear PlaidBar project** is the human-facing status channel.
   - Use it for material operating-model changes, larger milestones, and
     cross-agent process updates.
   - Do not require Felipe to approve routine PRs once this protocol's gates
     pass.
3. **Repo docs** are the durable policy channel.
   - `docs/agent-collaboration.md` defines the live collaboration protocol.
   - `commands/plaidbar-prod-loop.md` defines the builder loop entrypoint.
4. **Local coordination state** is the optional machine channel.
   - Agents may write uncommitted local state under `.agent-state/` or `/tmp`
     to record active branch/worktree ownership.
   - Never commit live local state files. Commit only templates or examples.
   - Use `docs/agent-coordination-state.example.json` as the state shape.

## Worktree Ownership

- Hermes should work from its own builder-owned checkout or temporary worktree,
  such as `/Users/otto/.openclaw/workspace/repos/PlaidBar` when launched via
  the Codex CLI examples in `commands/plaidbar-prod-loop.md`.
- Otto should review and fix from a separate operator-owned checkout or worktree,
  such as `/private/tmp/PlaidBar-otto` for this scheduled loop.
- Do not mutate another agent's active worktree.
- Before pushing to a branch another agent owns, verify that agent is not
  actively editing or running a write step on the same branch.

## Collision-Avoidance Preflight

Before editing, pushing, commenting, or merging, the acting agent should:

1. Check open PRs and identify the branch/head SHA for the slice.
2. Check the local process list or active session surface for PlaidBar work on
   the same branch/worktree.
3. Use a separate checkout/worktree when reviewing another agent's branch.
4. Re-read the PR head SHA immediately before merge.
5. If the head changed during review, stop, fetch the new head, and re-review
   before commenting or merging.

If another agent is actively mutating the same branch, leave a PR comment or
coordination note instead of pushing over it.

## Autonomous Merge Gates

Otto may merge PlaidBar PRs without asking Felipe when all of these are true:

- PR is not draft.
- GitHub branch protection reports these checks as green on the latest PR head:
  `CI / build`, `Claude Code Review / claude-review`,
  `Codex Code Review / codex-review`, and
  `Otto OpenClaw Merge Gate / otto-openclaw-merge-gate`.
- Diff is scoped to one coherent task or PR slice.
- No blocking Claude, Codex, or human review issue remains.
- Local verification passed, or CI fully covers the relevant gate.
- GitHub checks are green, or only non-required/skipped checks remain.
- Claude or Codex auth/token/session/setup failures are blocking review-gate
  failures unless Felipe explicitly grants a one-off override for that PR.
- Privacy/local-first boundaries are preserved.
- No secrets, local databases, screenshots, logs, or build artifacts are added.
- The PR branch is not being actively mutated by Hermes or another agent.

If any gate is unclear, pause the merge and leave a PR comment with the blocker.

## GitHub Merge Gate

GitHub branch protection should treat CI, both LLM review gates, and
Otto/OpenClaw as first-class merge gates. The required checks on `main` are:

- `CI / build`: the macOS/Xcode/Swift build, test, packaging, and sandbox smoke
  gate.
- `Claude Code Review / claude-review`: automatic Claude review on every PR
  opened, synchronized, reopened, or marked ready for review.
- `Codex Code Review / codex-review`: automatic Codex CLI OAuth review on every
  PR opened, synchronized, reopened, or marked ready for review. The job fails
  closed if the repository `CODEX_AUTH_JSON_B64` secret is unavailable or the
  Codex CLI review fails.
- `otto-openclaw-merge-gate`: the autonomous handoff and coordination gate,
  published by the trusted base-branch workflow onto the PR head SHA.

The Otto/OpenClaw gate is intentionally not a replacement for review. It runs
from trusted base-branch workflow code via `pull_request_target`; it must not
execute PR-controlled scripts or workflow logic. The workflow publishes the
required `otto-openclaw-merge-gate` check run on the PR head SHA so branch
protection evaluates the actual commit being merged. It checks that the PR is
not draft, uses the autonomous PR template, includes filled agent coordination
fields and autonomous task IDs, includes local gate evidence, and does not add
obvious local/generated artifact paths. Branch protection then prevents merges
while either required check is failing, pending, missing, cancelled, or
ambiguous.

## PR Handoff Format

Every autonomous PR should include:

- task ID(s)
- changed files and behavior
- verification commands/results
- privacy and local-first impact
- known risks or follow-up
- agent/worktree note: builder agent, branch, and whether another agent should
  avoid pushing to that branch

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

## Channel Escalation Rules

- **Routine implementation:** PR body plus local gates are enough.
- **Head changed during review:** PR comment with the old/new SHA and a
  re-review note.
- **Claude/Codex review failure:** treat auth, token, quota, session, setup, and
  substantive findings as blocking unless Felipe explicitly grants a one-off
  override; document the exact check and reason in the PR.
- **Merge completed:** PR merge body records local gates and CI state; Linear
  update only when the merge is part of a broader milestone or policy change.
- **Collision or unclear ownership:** pause the push/merge and leave a PR
  comment or local coordination note naming the branch and active worktree.
- **Out-of-scope decision:** ask Felipe instead of encoding the decision in the
  protocol.
