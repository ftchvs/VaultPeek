# Changelog

All notable changes to PlaidBar.

---

## [2026-05-27 01:26 UTC] — Chore

add PlaidBar production loop command (#27)

`f2825de`

---


## [2026-05-27 01:14 UTC] — Feature

clarify production onboarding (#26)

`aacb40a`

---


## [2026-05-27 00:33 UTC] — Feature

add diagnostics status panel (#25)

`c47f90a`

---


## [2026-05-26 23:56 UTC] — Feature

add menu bar summary modes (#24)

`35dd335`

---


## [2026-05-26 23:11 UTC] — Feature

add spending heatmap (#23)

`7173f3a`

---


## [Unreleased] — Feature

- Add cleaner first-run onboarding that separates View Demo, Connect Sandbox, and Use Production Credentials, with local storage disclosure and server environment checks before Plaid Link.
- Add a Status tab with CodexBar-style diagnostics for server health, sync recency, account/transaction counts, Plaid item state, and recovery actions.
- Add CodexBar-style menu bar summary modes for net cash, total cash, credit utilization, recent spend, and icon-only.
- Add a GitHub-style spending heatmap to the Spending tab, with daily intensity cells for spend and net cashflow modes.
- Add core heatmap bucketing tests for date ranges, transfer/income exclusions, and net cashflow signs.
- Add a `Last 90 Days` spending period so the heatmap has enough history to be useful.

---

## [2026-05-26 21:42 UTC] — Feature

add PlaidBar trust goal and status strip (#22)

`98b2c91`

---


## [2026-05-26 04:31 UTC] — Documentation

add repo health baseline

`0a11092`

---


## [2026-05-26 03:57 UTC] — Documentation

add accessibility guidance

`10ee235`

---


## [2026-03-19 20:21 UTC] — Documentation

update README screenshots and roadmap for v0.4

`f2751a5`

---


## [2026-03-19 19:48 UTC] — Fix

resolve all 9 open issues for v0.4 (#19)

`4296072`

---


## [2026-03-19 19:16 UTC] — Documentation

comprehensive PRD and DESIGN.md updates for v0.3 (#18)

`79fd8e9`

---


## [2026-03-19 18:41 UTC] — Documentation

autoresearch-optimized PRD and DESIGN.md for v0.3

`5322f69`

---


## [2026-03-19 06:02 UTC] — Fix

correct test count in CHANGELOG from 80+ to 86

`7f6d6bc`

---


## [2026-03-19 06:00 UTC] — Feature

PlaidBar v0.3.0 — Data Exploration, Recurring Detection, Notifications (#11)

`72278e3`

---


## [v0.3.0] — Data Exploration, Recurring Detection, Notifications

- **Transaction detail sheet**: Tap any transaction to see merchant, raw name, category, amount, date, account, and pending status
- **Transaction filtering**: Category, account, and date range filter chips below search bar
- **Recurring detection**: Automatic detection of recurring charges (Netflix, Spotify, rent, etc.) with frequency badges and monthly total
- **Recent/Recurring toggle**: Segmented picker in Transactions tab switches between recent and recurring views
- **Month-over-month comparison**: SpendingView shows delta vs previous period with arrow, amount, and percentage
- **Notification system**: Large transaction (>$500), low balance (<$100), and high utilization alerts via macOS notifications
- **Notification settings**: New Settings tab with master toggle, per-trigger controls, and thresholds
- **Design token cleanup**: Added `Spacing.xxs` (2pt), `Spacing.rowVertical` (6pt), `SemanticColors.brand`, `.brandSecondary`, `.recurring` — replaced 15+ hardcoded values
- **Expanded demo data**: 41 transactions spanning 60 days with 3 months of recurring merchants for algorithm demonstration
- **86 tests**: RecurringDetector unit tests, filter logic, spending delta, notification triggers

---

## [2026-03-19 04:10 UTC] — Update

Merge pull request #6 from ftchvs/dev

`71d79c6`

---


## [v0.2.0] — Design System & Charts

- **Design system**: Semantic color tokens, 5-level typography scale, 8pt spacing grid
- **4 chart types**: Spending donut, trend line, income vs expense bars, credit utilization gauge
- **Balance sparkline**: Net balance history in popover header
- **Settings persistence**: All preferences saved to UserDefaults across launches
- **Launch at login**: SMAppService integration
- **Sparkle auto-update**: Check for Updates in About tab
- **Keyboard shortcuts**: Cmd+1-4 tab switching, Cmd+R refresh, Cmd+N add account
- **Accessibility**: Secondary cues for color-only info (Issue #3), threshold icons (Issue #4)
- **Fix**: Replace nonisolated(unsafe) formatter with computed property (Issue #5)
- **Enhanced empty states**: Action buttons in ContentUnavailableView
- **Step indicators**: Onboarding progress dots
- **Docs**: DESIGN.md (design system), PRD.md (product requirements)

---

## [2026-03-18 23:44 UTC] — Feature

polish UI with animations, hover states, and layout refinements (#1)

`e05f814`

---
## [2026-03-18 23:39 UTC] — Update

Refactor after 3-agent code review: fix deterministic avatar colors (DJB2 hash), extract HoverHighlight ViewModifier, smooth RefreshIcon spin, collapse utilizationColor ranges, use shared DateFormatter, cache SpendingView computed properties.

`8032f06`

---

## [2026-03-18 23:30 UTC] — Feature

Add UX polish v0.1.1: hero balance header, institution avatars, hover states, search bar styling, spending top-5 rollup, thicker credit bars with color gradient, tab animations, error banner transitions, last-synced indicator, menu bar tooltip.

`65e5d7b`

---

## [2026-03-18 22:00 UTC] — Fix

Fix picker label leak, add --demo mode with mock data for 4 accounts and 15 transactions.

`2bdd0e8`

---

## [2026-03-18 21:00 UTC] — Feature

Initial PlaidBar MVP — macOS menu bar app for Plaid banking data. 56 files, accounts/transactions/spending/credit tabs, Swift Charts donut, server client, Keychain auth.

`546fe43`

---
