# Changelog

All notable changes to PlaidBar.

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
