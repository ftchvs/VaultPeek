# Demo Scenarios

VaultPeek demo and screenshot states must stay synthetic, privacy-safe, and
local-first. These scenarios define the product story that fixtures and README
screenshots should tell without requiring Plaid credentials or exposing real
financial data.

## Scenario Contract

Use these named scenarios when reviewing demo fixtures, screenshot changes, and
onboarding confidence.

Each scenario maps to one published window-first workspace screenshot
(`Scripts/screenshots.sh` renders these via `--render-window-first`).

| Scenario | Fixture intent | Workspace story | Expected status and recovery state | Screenshot |
|----------|----------------|-----------------|------------------------------------|------------|
| `dashboard-overview` | Four local demo accounts across checking, savings, and two credit cards; deterministic balance history; recurring income, rent, subscriptions, travel, shopping, groceries, and utility transactions. | The Dashboard workspace should answer cash on hand, savings cushion, credit exposure, debt risk, recent activity, 365-day spend/cashflow shape, and local-only insight context before a user opens details. | Demo mode is healthy. Local demo accounts are loaded, the server surface reports local demo readiness, and no Plaid network call is required. | `Assets/window-dashboard.png` |
| `transactions-review` | Same synthetic household fixture; the Transactions workspace lists categorized demo activity. | A user can scan, search, and review categorized transactions — recurring income, rent, subscriptions, travel, shopping, groceries, utilities — with the category/review affordances visible. | Healthy demo state. No raw Plaid payloads, item IDs, or real merchant data appear. | `Assets/window-transactions.png` |
| `budgets-planning` | Same synthetic fixture with category budgets and a recurring-commitment baseline. | The Budgets workspace shows spend vs. plan per category, safe-to-spend, and recurring obligations without turning the app into a heavy budgeting workflow. | Healthy demo state. Over/under-budget emphasis is conveyed with text or shape, not color alone. | `Assets/window-budgets.png` |
| `local-insights` | Same synthetic fixture; demo transactions present so the local insight receipt renders. | The Insights workspace shows the local-only insight receipt: source-row count, window, top category, recurring estimate, and category hints. | The receipt is deterministic/local-only and shows the disabled/no-runtime state when no local AI runtime is configured. It must not imply cloud AI or send transaction data off-device. | `Assets/window-insights.png` |
| `accounts-health` | Demo data plus `--screenshot-status-recovery`, which keeps one synthetic institution recovered and marks another as needing login. | The Accounts workspace shows balances, utilization, available credit, and connection status while preserving last-known local data and making item recovery visible and actionable. | One connected/recovered institution, one login-required institution, synced-item context, stale/delayed sync context when applicable, and an explicit reconnect/refresh handoff. | `Assets/window-accounts.png` |

## Reduced-Noise Composition

- Keep the first screenshot signal dense and product-shaped: heatmap, account
  rows, selected-account detail, status strip, local insight receipt, and one
  clear action path.
- Let each window-first workspace tell one focused story instead of adding
  separate marketing or explanatory surfaces.
- Prefer one selected account per scenario so screenshots show drill-in
  behavior without expanding every row.
- Keep recovery screenshots limited to one actionable degraded state; avoid
  stacking unrelated failures that would make the app look broken.
- Show Settings only when it proves trust or recovery: local data controls,
  linked item health, notification permissions, or support links.
- Avoid terminal windows, notifications, desktop clutter, real bank names beyond
  synthetic demo fixtures, raw Plaid identifiers, account IDs, tokens, and
  credential-like strings.

## Fixture Boundaries

- Demo mode must not call Plaid.
- Screenshot data must be demo, sandbox, or synthetic only.
- Local insight receipt content must remain deterministic/local-only unless a
  configured local runtime is part of the explicit screenshot scenario; never
  capture or imply cloud AI over private transactions.
- Public screenshots must not include real balances, real transaction history,
  Plaid item IDs, account IDs, access tokens, local bearer tokens, or Plaid
  credentials.
- If a scenario needs a degraded item, use a synthetic status fixture such as
  `--screenshot-status-recovery`; do not capture a real Plaid error.
- If fixture values change, update the scenario table and README screenshot
  captions in the same slice so the public story stays traceable.
