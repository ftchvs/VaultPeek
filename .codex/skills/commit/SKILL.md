---
name: commit
description: Create one focused PlaidBar commit with validation evidence.
---

# Commit

1. Inspect `git status --short`, `git diff`, and `git diff --staged`.
2. Stage only files that belong to the current PlaidBar slice.
3. Do not stage screenshots, logs, `.build`, derived data, local databases, or
   credentials.
4. Use a conventional commit subject under 72 characters.
5. Include a concise body with summary and validation commands.
6. Never commit secrets or real financial data.
