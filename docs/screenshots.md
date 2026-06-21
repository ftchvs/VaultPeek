# Screenshots

VaultPeek screenshots are part of the product contract. They should show the
current design system, realistic states, and public-safe data.

## Public-Safe Rule

Only use demo, sandbox, or synthetic financial data in screenshots.

When Privacy Mask or App Lock screenshots become part of the release set, they
must be captured from demo data with the mask or lock control already enabled.
They should prove the privacy state with generic labels such as "Private" or
"Locked" and fixed placeholders, not by showing real values beside masked
values.

Do not publish screenshots containing:

- real account balances
- real merchant names
- real transaction history
- Plaid item IDs or account IDs
- terminal output containing credentials or tokens
- notification banners containing account names, balances, merchants,
  utilization status, or recovery details while Privacy Mask or App Lock is
  active in a build that includes those controls

## Generate Screenshots

From the repository root:

```bash
./Scripts/screenshots.sh
```

The script renders the window-first workspace surfaces headlessly via the
built-in render harness (`swift run PlaidBar --demo --render-window-first`) and
copies the README set into `Assets/`:

- `window-dashboard.png` — Dashboard workspace (hero)
- `window-transactions.png` — Transactions workspace
- `window-budgets.png` — Budgets workspace
- `window-insights.png` — Insights workspace
- `window-accounts.png` — Accounts workspace

The harness rasterizes each routed destination off-screen from demo fixtures, so
it needs **no Screen Recording permission, no UI automation, and no Plaid
credentials**. It writes one `window-<destination>.png` per in-shell destination
(dashboard, transactions, budgets, planning, goals, review, insights, alerts,
accounts) plus a best-effort `window-shell.png`; `Scripts/screenshots.sh` copies
only the committed README subset above.

The Dashboard surface includes a below-the-fold local insight receipt when demo
transactions are available. The receipt is intentionally local-only: it shows
source-row count, window, top category, recurring estimate, category hints, and
the disabled/no-runtime state when no local AI runtime is configured. It must
not imply cloud AI processing or send transaction data off-device.

## Appearance Matrix Renders

Light/dark regression evidence is captured headlessly (no Screen Recording
permission) with:

```bash
./Scripts/qa-appearance-matrix.sh
```

It renders the demo dashboard and account fly-out under forced light AND dark
appearance into `docs/qa/appearance-{light,dark}/`. Any capture state can also
be pinned to one appearance with `--appearance light|dark` — useful when the
host's system appearance would otherwise leak into `Scripts/screenshots.sh`
output. Coverage, limits (Reduce Transparency needs a manual toggle), and the
latest pass results live in [qa-matrix.md](qa-matrix.md).

## Demo Scenario Traceability

The demo narrative is defined in [Demo Scenarios](demo-scenarios.md). Use those
scenario names when reviewing screenshot diffs so each public image has a clear
fixture intent, dashboard story, and expected recovery state.

| Scenario | Primary asset | Review focus |
|----------|---------------|--------------|
| `dashboard-overview` | `Assets/window-dashboard.png` | First-glance cash, credit, savings, debt, sync health, and 365-day heatmap context |
| `transactions-review` | `Assets/window-transactions.png` | Categorized transaction list/search with review affordances; no raw Plaid payloads |
| `budgets-planning` | `Assets/window-budgets.png` | Spend vs. plan per category, safe-to-spend, recurring obligations; over/under emphasis not by color alone |
| `local-insights` | `Assets/window-insights.png` | Local-only insight receipt (deterministic/no-runtime state when no local AI configured) |
| `accounts-health` | `Assets/window-accounts.png` | Balances, utilization, connection status, and login-required item recovery without raw Plaid errors |

## macOS Permissions

`Scripts/screenshots.sh` uses the built-in render harness, which rasterizes the
window-first content off-screen. It needs **no Screen Recording or Accessibility
permission** and does not drive the live UI.

(The separate `Scripts/qa-appearance-matrix.sh` is also headless. Any remaining
UI-automation captures, if reintroduced, would require Screen Recording and
Accessibility for the terminal app running the script.)

## Expected Assets

These are the committed window-first screenshots `Scripts/screenshots.sh`
publishes into `Assets/` (and that README.md references):

| File | Purpose |
|------|---------|
| `Assets/window-dashboard.png` | Dashboard workspace — first-glance overview (hero) |
| `Assets/window-transactions.png` | Transactions workspace — categorized list/search |
| `Assets/window-budgets.png` | Budgets workspace — spend vs. plan, safe-to-spend |
| `Assets/window-insights.png` | Insights workspace — local-only insight receipt |
| `Assets/window-accounts.png` | Accounts workspace — balances, utilization, connection status |

## Review Checklist

- Screenshots match the current design system.
- Text is readable at README display sizes.
- No real personal finance data appears.
- Privacy Mask/App Lock screenshots show only generic copy or fixed
  placeholders for balances, account endings, transactions, utilization, and
  notifications.
- Empty/degraded states are represented where relevant.
- `window-accounts.png` shows the recovery fixture
  (`--screenshot-status-recovery`), not a real Plaid error.
- The Insights workspace shows local insight receipt text saying
  local-only/disabled when no local runtime is configured; it must not mention
  cloud AI fallback.
- Button labels and status copy match the current app.
- Screenshots do not include unrelated desktop windows or notifications.
- Captions and alt text claim only what is visible in the image. VoiceOver or
  below-the-fold privacy checks should be recorded as validation notes, not as
  screenshot-visible claims.

## When To Regenerate

Regenerate screenshots when a change affects:

- dashboard layout
- setup/onboarding
- status/recovery states
- local insight receipt or attention queue copy
- settings tabs
- local data copy
- notification controls
- Privacy Mask or App Lock controls, locked-state copy, masking copy, or
  notification privacy behavior
- design tokens
- README screenshot tables
