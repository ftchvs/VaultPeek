---
name: review
description: Review PlaidBar PRs and local changes for production-readiness risks.
---

# Review

Focus review on:

- misleading security or production claims,
- Plaid environment mismatch bugs,
- local data loss risks,
- SwiftUI state bugs,
- broken demo/sandbox/production onboarding,
- untested finance calculations,
- confusing empty/error states,
- docs that no longer match behavior.

Check:

```bash
git diff --check
swift build --target PlaidBar --skip-update --disable-keychain
```

For PRs, inspect CI, Claude/Codex review comments, and mergeability before
recommending merge.
