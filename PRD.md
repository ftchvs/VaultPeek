# PlaidBar — Product Requirements

## Vision

A menu bar app that makes personal finance data glanceable. One click to see all accounts, recent transactions, spending patterns, and credit utilization — no browser login required.

## Persona

**Solo developer / tech-forward professional** who:
- Has 2-5 bank accounts and credit cards
- Wants a quick glance at finances without logging into bank websites
- Values privacy (no cloud sync, no telemetry)
- Runs macOS as primary OS
- Comfortable with terminal for initial setup

## Jobs to Be Done

1. **Glance at net worth** — See total balance in menu bar without clicking
2. **Check recent charges** — "What was that $142 charge?" answered in 2 clicks
3. **Monitor credit utilization** — Keep utilization under 30% for credit score
4. **Understand spending patterns** — Category breakdown over time
5. **Stay updated** — Background refresh keeps data fresh without manual action

## Feature Matrix

### v0.1 (shipped)

- [x] Menu bar net balance display
- [x] Account list grouped by type (depository, credit)
- [x] Transaction list grouped by date, searchable
- [x] Spending donut chart by category
- [x] Credit utilization progress bars
- [x] Sandbox demo mode
- [x] Local companion server (Hummingbird)
- [x] Hover states, avatars, animations
- [x] Setup/onboarding flow

### v0.2 (current)

- [x] Design system (semantic colors, typography, spacing)
- [x] Settings persistence (UserDefaults)
- [x] Launch at login (SMAppService)
- [x] Sparkle auto-update integration
- [x] Keyboard shortcuts (Cmd+1-4, Cmd+R, Cmd+N)
- [x] Spending trend line chart
- [x] Income vs expense bar chart
- [x] Credit utilization gauge
- [x] Balance history sparkline
- [x] Enhanced empty states
- [x] Accessibility improvements (secondary cues for color-only info)
- [x] Fix: nonisolated(unsafe) formatter (Issue #5)

### Future (not committed)

- [ ] Budget alerts per category
- [ ] Multi-currency support
- [ ] Investment account tracking
- [ ] CSV/JSON export
- [ ] Webhook support for real-time updates
- [ ] macOS notifications for large transactions
- [ ] Homebrew cask distribution
- [ ] Recurring transaction detection
- [ ] Teller.io as alternative provider
- [ ] Widget for macOS desktop
- [ ] iOS companion app

## Non-Goals

- **Not a budgeting app** — No envelope budgeting, no goal tracking, no bill reminders
- **No cloud sync** — All data stays local. Period.
- **No multi-user** — Single-user, single-machine
- **No transaction editing** — Read-only view of bank data
- **No AI/ML features** — Simple categorization from Plaid, no smart insights

## Success Metrics

| Metric | Target |
|--------|--------|
| GitHub stars | 100 in first 3 months |
| Build success rate | 100% on CI |
| Open issues | < 5 at any time |
| Time to first data | < 3 minutes (sandbox mode) |
| Menu bar to data | 1 click |
