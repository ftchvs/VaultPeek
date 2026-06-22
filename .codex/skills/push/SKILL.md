---
name: push
description: Publish a VaultPeek branch, open/update a PR, and merge only through the safe gate.
---

# Push

Use only after Felipe explicitly approves pushing/opening a PR, or when the run
is clearly covered by a scoped VaultPeek approval.

1. Confirm the branch and latest validation.
2. Push the branch with tracking.
3. Open or update a PR against `main`.
4. PR body must include:
   - summary,
   - product impact,
   - validation commands and results,
   - known warnings or blockers.
5. Request review when appropriate, including `@codex review` when using Codex
   as the reviewer.
6. Wait for GitHub checks and address review feedback.
7. Merge only when local gates passed, GitHub checks are green, review feedback
   is addressed, and the final diff is safe: no secrets, no real financial data,
   no generated artifacts, no unsafe destructive behavior, and no local-first
   boundary violations.
