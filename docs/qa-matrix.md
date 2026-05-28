# QA Matrix

This matrix defines the minimum 1.0 release candidate checks. It is deliberately
manual-friendly because PlaidBar crosses macOS UI, local server, Plaid sandbox,
local storage, notifications, and distribution.

## Automated Gates

| Gate | Command | Required For |
|------|---------|--------------|
| Whitespace/diff sanity | `git diff --check` | Every PR |
| Shell syntax | `bash -n Scripts/*.sh Scripts/plaidbar-run` | Script or release changes |
| Formula syntax | `ruby -c Formula/plaidbar.rb` | Packaging changes |
| App build | `swift build --target PlaidBar --skip-update --disable-keychain` | Every PR |
| Strict concurrency | `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --disable-keychain` | Release candidates |
| Release build | `swift build -c release --disable-keychain` | Release candidates |
| Test suite | `swift test --skip-update --disable-keychain` | CI and local when toolchain supports Swift Testing |
| Sandbox smoke | `./Scripts/smoke-sandbox.sh` | Server/config changes |
| Screenshots | `./Scripts/screenshots.sh` | UI/docs release changes |

## Manual Product QA

| Area | Scenario | Expected Result |
|------|----------|-----------------|
| Demo | Launch with `--demo` | Dashboard renders fixture data without Plaid credentials |
| First run | Click View Demo | Sheet dismisses and demo accounts appear |
| Sandbox setup | Launch `./Scripts/run.sh --sandbox` with credentials | Preflight passes and Plaid Link opens |
| Sandbox return | Complete Plaid Link, then click Check Connection | App verifies linked item, loads accounts, runs transaction sync, then opens dashboard |
| Linked item pending accounts | Plaid item exists but accounts are empty | Setup stays in completion state and explains that accounts still need to load |
| Accounts pending sync | Accounts exist but no sync has completed | Setup stays in completion state and asks for the first sync check |
| Missing credentials | Launch sandbox without credentials | Preflight blocks Link and explains missing credentials |
| Wrong mode | App expects sandbox but server is production, or reverse | Preflight shows environment mismatch |
| Server offline | App opens without server in non-demo mode | Recovery state explains server offline |
| Dashboard filters | All/Cash/Credit/Savings/Debt/Status | Rows and details match selected scope |
| Account drill-down | Select account row | Detail surface shows balances, status, and actions |
| Transactions | Apply date/category/account filters | Matching rows update; zero state can clear filters |
| Recurring | Open recurring view with insufficient history | Empty state explains history requirement |
| Settings General | Local Data section | Path, reveal/copy, and reset controls are visible |
| Settings Accounts | Add Account | Setup/connect sheet opens from Accounts tab |
| Settings Accounts | Remove item | Confirmation explains local vs Plaid/bank boundaries |
| Notifications | Permission denied | UI explains system permission and avoids false enabled state |
| Reconnect | Item is `login_required` | Reconnect action is visible from status/account surfaces |

## Accessibility QA

| Check | Expected Result |
|-------|-----------------|
| Keyboard navigation | Primary actions are reachable without pointer-only interaction |
| VoiceOver labels | Icon-only buttons have useful labels |
| Color independence | Risk, balance, utilization, sync, and chart meanings have text/icon backup |
| Focus states | Keyboard focus remains visible |
| Reduced motion | Animations do not block comprehension |
| Screenshot readability | README screenshots remain legible at documented widths |

## Security and Privacy QA

| Check | Expected Result |
|-------|-----------------|
| Secret scan | No real secrets, tokens, or private keys in docs/source/tests |
| Status endpoint | `/api/status` exposes readiness metadata, not secrets |
| Auth middleware | `/api/*` rejects missing/invalid bearer token |
| Data directory | `~/.plaidbar/` uses private user permissions where supported |
| Auth token | `auth-token` uses private file permissions where supported |
| Sandbox/production | Stores and transaction cache are scoped by environment |
| Reset copy | UI explains local reset does not guarantee Plaid/bank revocation |
| Screenshots | Assets contain demo/sandbox/synthetic data only |

## Release Candidate Exit Criteria

- Automated gates pass or have a documented toolchain-only exception.
- Manual product QA has no critical blocker.
- Accessibility QA has no keyboard or VoiceOver blocker in primary flows.
- Security/privacy QA has no known secret, token, or real-data exposure.
- README, PRD, release notes, screenshots, and version metadata match the
  release candidate.
