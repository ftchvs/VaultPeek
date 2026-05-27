# PlaidBar Goal

## North Star

Build PlaidBar into a local-first macOS menu bar dashboard for Plaid data: CodexBar for personal finance.

The app should make the user's financial state glanceable without becoming a full budgeting product. One click should answer:

- How much cash do I have?
- How much credit am I using?
- What changed recently?
- Is my Plaid sync healthy?
- Do I need to act?

## Product Positioning

PlaidBar is not a cloud finance platform, budgeting app, portfolio tracker, or analytics service. It is a native macOS utility for a single user who wants fast, private visibility into their own Plaid-connected accounts.

The public repo should prove three things:

- The UI works with polished demo data.
- The Plaid sandbox path works end to end.
- The production path is understandable, local-only, and honest about data storage.

## Operating Modes

| Mode | Purpose | Success Criteria |
|------|---------|------------------|
| Demo | GitHub screenshots, UI review, contributor onboarding | Runs with no Plaid credentials and shows realistic fixture data |
| Sandbox | Real Plaid development/demo flow | Links a sandbox institution, syncs accounts and transactions, shows last-sync state |
| Production | Personal use with approved Plaid credentials | Uses real credentials locally with clear storage/security boundaries |

## Design Direction

PlaidBar should feel like a compact financial instrument, not a bank website squeezed into a popover.

The near-term visual target is RepoBar-style density adapted to finance:

- **Heatmap first:** lead with a GitHub-contribution-style financial heatmap that makes daily spend/cashflow intensity visible before the user reads rows.
- **Instrument rows:** show cash, savings, credit cards, loans, and other accounts as compact status rows with a dot/icon, name, key metric, secondary detail, and last-updated/sync clue.
- **Filterable scope:** use a RepoBar-like segmented control for All, Cash, Credit, Savings, Debt, and Status so the popover stays one surface instead of separate finance silos.
- **Drill-in details:** selecting an account or card opens a focused detail view/sheet with transactions, limits/utilization, due-date metadata when available, sync status, and reconnect/remove actions.
- **Native translucency:** match the macOS menu-bar feel in the attached RepoBar reference: material background, separators, compact row height, subtle selected state, and minimal decorative chrome.

Design principles:

- **At-a-glance first:** the menu bar label and top popover area should prioritize one clear financial summary plus sync health.
- **Dense but calm:** keep rows compact, aligned, and scannable. Use whitespace for grouping, not decorative cards.
- **Status-rich:** show environment, server state, last sync, stale data, and account reconnect needs without forcing users into logs.
- **Finance-native semantics:** green/red/orange must carry consistent financial meaning; avoid decorative color.
- **Trust over flash:** never hide local storage or credential requirements behind marketing language.
- **Keyboard-friendly:** preserve fast tab switching and refresh commands; important actions should not require hunting.
- **Accessible by default:** every color-coded signal needs text, icon, or shape backup.

## Design Improvements To Implement

Prioritize these before adding new finance features:

1. **RepoBar-style finance dashboard**
   - Reshape the main popover around a heatmap header, segmented finance filters, and dense account/card rows.
   - Replace the tab-first mental model with one glanceable overview while preserving deeper screens through row selection.
   - Make credit cards, savings/checking, and sync health readable from the same list.
   - Use the attached RepoBar screenshot and `https://repobar.app` as the visual reference, but keep PlaidBar finance semantics.

2. **Top status strip**
   - Show environment: Demo, Sandbox, or Production.
   - Show server state: Connected, Offline, Syncing, Error.
   - Show last sync time and stale-data warning.

3. **Menu bar summary modes**
   - Let users choose the menu bar label: Net cash, total cash, credit utilization, recent spend, or compact icon-only.
   - Keep the default conservative: net cash or account health, not noisy transaction counts.
   - Implemented local slice: settings picker, persisted mode, shared summary calculator, and focused tests.

4. **Spending heatmap**
   - Add a GitHub-style daily grid for recent spending intensity.
   - Support both total spend and net cashflow so income/refunds do not disappear from the story.
   - Keep day details local and glanceable: amount, transaction count, and date.

5. **CodexBar-style health panel**
   - Add a small diagnostics/settings surface for local server URL, Plaid environment, item count, last sync, and refresh cadence.
   - Make failures actionable: missing credentials, server offline, token expired, Plaid error.
   - Implemented local slice: Status tab with server/sync/data/item diagnostics and refresh/connect/settings recovery actions.

6. **Cleaner onboarding**
   - Separate "View Demo", "Connect Sandbox", and "Use Production Credentials".
   - Never imply sandbox works without credentials unless the app can actually do that.
   - Explain what data is stored before the user links an account.
   - Implemented local slice: first-run chooser with Demo, Sandbox, and Production paths; server environment checks before Plaid Link; local storage disclosure before linking.

7. **Sharper empty and error states**
   - Accounts: explain whether there is no data, no server, or no linked institution.
   - Transactions: distinguish no synced history from filters returning zero results.
   - Credit: explain if no credit accounts are linked.

8. **Trust-first settings**
   - Add a local data section with `~/.plaidbar/` storage path, reset/delete options, and clear warnings.
   - Keep dangerous actions explicit and confirmation-gated.

9. **Long-running production loop**
   - Use `/goal` for multi-hour, Codex-assisted production-readiness work.
   - Keep each run focused on one reviewable slice with verification evidence.
   - Stop before push, PR, or merge unless explicitly approved.

## Worth Implementing

- Reliable Plaid sandbox onboarding.
- Real production credential setup documentation.
- Local server health/status visibility.
- Manual refresh plus background refresh with visible stale-data state.
- GitHub-style spending heatmap for daily spend intensity and net cashflow.
- Account reconnect/token-expired handling.
- Polished demo fixtures and screenshots.
- Security and privacy docs that match actual implementation.
- Focused tests around mode selection, config validation, formatting, recurring detection, and sync response handling.

## Not Worth Implementing Yet

- Multi-user support.
- Hosted backend or cloud sync.
- Full budgeting workflows.
- Investments, exports, webhooks, Teller, mobile companion, or desktop widgets.
- Production distribution/notarization work before sandbox is reliable.
- Token encryption claims before token encryption or Keychain-backed token storage exists.

## First Milestone

Make `main` trustworthy as a public open-source project:

- Demo mode runs without Plaid.
- Sandbox mode fails fast without credentials and works with real sandbox credentials.
- README, `SECURITY.md`, and issue templates are public-safe.
- The app shows mode/server/sync health clearly.
- CI passes and local smoke checks are documented.

## Definition Of Done

A new contributor should be able to clone the repo, run demo mode, understand sandbox credential setup, verify the local architecture, and know exactly what is safe or unsafe to share publicly.
