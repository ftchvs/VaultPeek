# QA Matrix

This matrix defines the minimum 1.0 release candidate checks. It is deliberately
manual-friendly because PlaidBar crosses macOS UI, local server, Plaid sandbox,
local storage, notifications, and distribution.

## Automated Gates

| Gate | Command | Required For |
|------|---------|--------------|
| Whitespace/diff sanity | `git diff --check` | Every PR |
| Shell syntax | `bash -n Scripts/*.sh Scripts/vaultpeek-run Scripts/plaidbar-run` | Script or release changes |
| App build | `swift build --target PlaidBar --skip-update --disable-keychain` | Every PR |
| Strict concurrency | `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --disable-keychain` | Release candidates |
| Release build | `swift build -c release --disable-keychain` | Release candidates |
| Test suite | `swift test --skip-update --disable-keychain` | CI and local when toolchain supports Swift Testing |
| Sandbox smoke | `./Scripts/smoke-sandbox.sh` | Server/config changes |
| Version alignment | `./Scripts/verify-version-alignment.sh` | Version metadata changes; release candidates (also runs in CI) |
| App bundle package validation | `./Scripts/package-app.sh` then `./Scripts/validate-app-bundle.sh` | Packaging/release changes (also runs in CI) |
| DMG package validation | `./Scripts/package-dmg.sh` then `./Scripts/validate-app-bundle.sh` | Release candidates |
| Release gate aggregate | `./Scripts/release.sh --allow-current-branch` | Release-prep PRs |
| Screenshots | `./Scripts/screenshots.sh` | UI/docs release changes |
| Appearance matrix renders | `./Scripts/qa-appearance-matrix.sh` | UI-affecting changes (light/dark regression evidence) |

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
| Dashboard Status | Select Status filter | Readiness panel shows mode, server state, credentials, linked/synced items, last sync, and one primary recovery action |
| Dashboard stale sync | Last sync is beyond the configured stale window | Status panel shows stale sync and offers Refresh |
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

## Visual QA: Appearance and Transparency Matrix

The popover relies on vibrant materials (`.ultraThinMaterial`) that respond to
system appearance and to Reduce Transparency, so every release-facing surface
must be checked in all four combinations. This matrix records what each pass
covered and how.

### How to run

```bash
# Headless light/dark renders (no Screen Recording permission needed).
# Writes docs/qa/appearance-{light,dark}/render-{dashboard,flyout}.png.
./Scripts/qa-appearance-matrix.sh

# Reduce Transparency half: toggle System Settings > Accessibility >
# Display > Reduce transparency manually, then:
PLAIDBAR_QA_MATRIX_SUFFIX="-reduce-transparency" ./Scripts/qa-appearance-matrix.sh

# Any single state, any appearance (also works with Scripts/screenshots.sh
# capture states):
.build/release/PlaidBar --demo --show-popover --appearance light
```

`--appearance light|dark` pins the whole app to one appearance regardless of
the host system setting. Unknown values fall back to the system appearance.

### Known limits of the headless path

- `--render-snapshot` rasterizes the popover content view directly, so
  vibrant materials composite against nothing instead of the desktop.
  Translucency therefore reads darker/flatter than on-screen. Headless renders
  are regression evidence for layout, copy, and contrast direction — final
  visual sign-off uses `Scripts/screenshots.sh` on-screen captures or eyes.
- Reduce Transparency is a system-wide accessibility setting with no
  supported per-process override, so that half of the matrix cannot be
  captured autonomously. It requires a manual toggle (procedure above).
- `--render-snapshot` captures the dashboard and one account fly-out. The
  Settings window, setup preflight, and the non-default dashboard filters are
  only reachable through `Scripts/screenshots.sh` (UI automation) or a manual
  pass.

### Matrix status (last pass: 2026-06-12, demo fixtures)

| Surface | Light | Dark | Light + Reduce Transparency | Dark + Reduce Transparency |
|---------|-------|------|-----------------------------|----------------------------|
| Dashboard overview (All) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Account fly-out (credit) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Account fly-out (savings) | Pass — ad hoc headless render | Not run | Needs human eyes | Needs human eyes |
| Dashboard filters (Cash/Credit/Savings/Debt/Status) | Code-inspected only (filters reuse the All-state visual system) | Code-inspected only | Needs human eyes | Needs human eyes |
| Settings (General/Accounts/Notifications/About) | Needs `screenshots.sh` or human eyes | Needs `screenshots.sh` or human eyes | Needs human eyes | Needs human eyes |
| Setup sandbox preflight | Needs `screenshots.sh` or human eyes | Needs `screenshots.sh` or human eyes | Needs human eyes | Needs human eyes |

2026-06-12 pass notes, recorded from the committed renders under `docs/qa/`:

- Both appearances force correctly end to end (header, heatmap, account rows,
  balance mix, insight receipt all follow the forced appearance).
- The 365-day heatmap shows continuous activity in both appearances — the
  former days-61–73 fixture dead zone is gone (see `DemoFixturesTests`).
- Color-independence backups confirmed in renders and code: utilization rows
  pair color with text ("84% • $790 available - due not synced"), the heatmap
  ships a Less/More legend plus `accessibilityLabel` summaries, and trend
  direction is reinforced by signed amounts, not color alone.
- Reduce Transparency (both appearances), grayscale full-screen check, and
  Retina hairline inspection (1px hairlines, no half-pixel chip borders) were
  NOT verified in this pass — they need a human on a Retina display.

## Security and Privacy QA

| Check | Expected Result |
|-------|-----------------|
| Secret scan | No real secrets, tokens, or private keys in docs/source/tests |
| Status endpoint | `/api/status` exposes readiness metadata, not secrets |
| Status contract test | Encoded `ServerStatus` contains only release-approved keys |
| Auth middleware | `/api/*` rejects missing/invalid bearer token |
| Auth comparison | Bearer token comparison accepts only exact token strings |
| Data directory | `~/.vaultpeek/` uses private user permissions where supported |
| Legacy storage migration | Missing default files copy from `~/.plaidbar/` without overwriting newer `~/.vaultpeek/` files |
| Auth token | `auth-token` uses private file permissions where supported |
| Plaid tokens | Runtime stores access-token bytes in Keychain when available; fallback builds are documented |
| Sandbox/production | Stores and transaction cache are scoped by environment |
| Reset copy | UI explains local reset does not guarantee Plaid/bank revocation |
| Screenshots | Assets contain demo/sandbox/synthetic data only |

## Release Candidate Exit Criteria

The full final gate set lives in `docs/release-checklist.md` (version/tag
hygiene, build/test gates with the recorded toolchain baseline, packaging,
privacy/security, accessibility, clean-profile setup, and merge/publish
gates). In summary:

- Automated gates pass or have a documented toolchain-only exception.
- Manual product QA has no critical blocker.
- Accessibility QA has no keyboard or VoiceOver blocker in primary flows.
- Security/privacy QA has no known secret, token, or real-data exposure.
- README, PRD, release notes, screenshots, and version metadata match the
  release candidate.
- GitHub checks are green on the head SHA and a manual safety read of the
  final diff happened before merge.
