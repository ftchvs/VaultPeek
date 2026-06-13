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
| Attention queue | Trigger stale sync, denied notifications, missing credentials, or login-required fixture | Dashboard surfaces prioritized attention without hiding balances or account rows |
| Account drill-down | Select account row | Account inspector opens on the RIGHT with balances, status, and actions; the left Wealth Summary rail and center dashboard stay in place (three-column) |
| Inspector dismissal | Esc, the inspector ✕, re-click the row, or switch filters | Closes only the inspector and returns to the two-column state; focus returns to the row on Esc/✕/re-click |
| Local insight receipt | Open demo dashboard with transactions | Receipt shows source rows, time window, top category, recurring estimate, local-only badge, and disabled/no-runtime copy when no local AI runtime is configured |
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
# Headless light/dark renders (no Screen Recording permission needed). Writes
# docs/qa/appearance-{light,dark}/render-{dashboard,flyout,settings-appearance}.png.
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
- `--render-snapshot` captures the dashboard, one account inspector, and the
  Settings → Appearance pane (the latter rendered into an off-screen hosting
  window — `render-settings-appearance.png`, AND-366). The other Settings tabs
  (General/Accounts/Notifications/About), setup preflight, and the non-default
  dashboard filters are only reachable through `Scripts/screenshots.sh` (UI
  automation) or a manual
  pass.
- Rasterization captures the popover *content view*, not its position relative
  to the screen, so the leading-edge anchor and screen-edge clamp (AND-370/374)
  are not visible in a render. Those are covered by the `PopoverGeometry` unit
  tests (deterministic clamp math, including the too-narrow-display fallback)
  plus the manual no-jump / near-edge / multi-monitor pass below.

### Three-column popover (AND-367 / AND-375)

The selected-account state is a three-column popover: a permanent Wealth Summary
rail (left, 320pt), the center dashboard (480pt), and an account inspector
(right, 320pt). Widths: setup 480, two-column 801, three-column 1122.

Automated coverage:

- `PopoverGeometryTests` — the 480 / 801 / 1122 width math and the on-screen
  clamp (fits unchanged, pulled-left near the right edge, leading-edge-wins on a
  display too narrow for 1122, and a secondary-display origin).
- `DashboardAccountSelectionTests` — selection survives only while the account is
  visible; a filter change or a removed account deselects (closes the inspector).
- The committed renders under `docs/qa/` (`render-dashboard.png` = 801 two-column,
  `render-flyout.png` = 1122 three-column) in light and dark.

Manual-only (headless rasterization cannot show window position or assistive
tech):

| Check | Expected Result |
|-------|-----------------|
| No-jump on open/close | Selecting an account grows the popover rightward; the Wealth Summary rail does not shift horizontally. Deselecting returns to two columns without a jump |
| First open with a persisted selection (AND-405) | With `dashboard.selectedAccountId` set from a prior session, the popover opens directly at the three-column width and the inspector fills in (brief loading placeholder) — it does NOT open two-column and jump to three-column once accounts load |
| Narrow / scaled display (AND-405) | On a display/zoom where 1122 doesn't fit (e.g. scaled ~1024pt), the popover caps to the screen and the center dashboard flexes/scrolls while the rail + inspector keep 320pt; the inspector ✕ and recovery controls stay on-screen. Extreme zoom (≲ ~1002pt usable) is the documented Tier-2 overlay residual |
| Near a display edge | Opening the inspector with the menu-bar item near the right edge clamps the popover on-screen (shifts left), keeping the rail visible; nothing renders off-screen |
| Multi-monitor | Opening on a secondary display clamps within that display's visible frame |
| Keyboard | Esc closes the inspector before the popover; focus returns to the selected row; filter change clears selection without trapping focus |
| VoiceOver | Selecting a row announces the account opened in the inspector; the inspector reads as a trailing inspector, not replacement left content; selected/unselected row state is spoken |
| Reduce Transparency | Rail, center, and inspector stay legible in both appearances (manual toggle) |

### Matrix status (last pass: 2026-06-13, demo fixtures)

| Surface | Light | Dark | Light + Reduce Transparency | Dark + Reduce Transparency |
|---------|-------|------|-----------------------------|----------------------------|
| Dashboard, no selection (two-column 801pt) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Selected account (three-column 1122pt: rail + dashboard + right inspector) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Account inspector (credit, right column) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Dashboard filters (Cash/Credit/Savings/Debt/Status) | Code-inspected only (filters reuse the All-state visual system) | Code-inspected only | Needs human eyes | Needs human eyes |
| Settings → Appearance (transparency + preview/presets + Display section) | Pass — headless render | Pass — headless render | Needs human eyes | Needs human eyes |
| Settings (General/Accounts/Notifications/About) | Needs `screenshots.sh` or human eyes | Needs `screenshots.sh` or human eyes | Needs human eyes | Needs human eyes |
| Setup sandbox preflight | Needs `screenshots.sh` or human eyes | Needs `screenshots.sh` or human eyes | Needs human eyes | Needs human eyes |

2026-06-13 pass notes, recorded from the committed renders under `docs/qa/`:

- The renders now cover the three-column model (AND-367): `render-dashboard.png`
  is the 801pt two-column state (Wealth Summary rail + center dashboard) and
  `render-flyout.png` is the 1122pt three-column state with the account inspector
  on the right — the rail stays visible when an account is selected (AND-375 AC).
- `render-settings-appearance.png` covers Settings → Appearance at the 560pt
  minimum width (AND-366): the transparency slider, the live preview + Solid/
  Balanced/Glass presets (AND-364), and the Display section pickers — Appearance,
  Contrast, Decorative Effects, Density (AND-365). Both appearances confirm top
  anchoring, slider/label readability, and no text overlap at the minimum width.
  The preview card's vibrant material composites against nothing off-screen (same
  caveat as the popover); Reduce Transparency for this pane stays a manual check.
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
| CLI auth | Source/developer `plaidbar-cli status --json` reads the local bearer token and fails closed without exposing it |
| Data directory | `~/.vaultpeek/` uses private user permissions where supported |
| Legacy storage migration | Missing default files copy from `~/.plaidbar/` without overwriting newer `~/.vaultpeek/` files |
| Auth token | `auth-token` uses private file permissions where supported |
| Plaid tokens | Runtime stores access-token bytes in Keychain when available; fallback builds are documented |
| Sandbox/production | Stores and transaction cache are scoped by environment |
| Reset copy | UI explains local reset does not guarantee Plaid/bank revocation |
| Screenshots | Assets contain demo/sandbox/synthetic data only |
| Local AI boundary | Insight receipts and category hints stay local-only and do not send raw transaction data to cloud AI services |

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
