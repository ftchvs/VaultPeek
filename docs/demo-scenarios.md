# Demo Scenarios

VaultPeek demo and screenshot states must stay synthetic, privacy-safe, and
local-first. These scenarios define the product story that fixtures and README
screenshots should tell without requiring Plaid credentials or exposing real
financial data.

## Scenario Contract

Use these named scenarios when reviewing demo fixtures, screenshot changes, and
onboarding confidence.

| Scenario | Fixture intent | Dashboard story | Expected status and recovery state | Screenshot list |
|----------|----------------|-----------------|------------------------------------|-----------------|
| `steady-household-overview` | Four local demo accounts across checking, savings, and two credit cards; deterministic balance history; recurring income, rent, subscriptions, travel, shopping, groceries, and utility transactions. | The first popover view should answer cash on hand, savings cushion, credit exposure, debt risk, recent activity, 365-day spend/cashflow shape, and local-only insight receipt before a user opens details. | Demo mode is healthy. Local demo accounts are loaded, the server surface reports local demo readiness, the local insight receipt may show deterministic/no-runtime status, and no Plaid network call is required. | `Assets/dashboard.png` |
| `cash-runway-check` | Same synthetic household fixture with the checking account selected and the Cash filter active. | A user can confirm checking and savings balances, spot recent inflow/outflow, and inspect the selected checking account without leaving the dashboard surface. | Healthy demo state. Recovery controls should stay quiet because the scenario is about confidence, not failure. | `Assets/dashboard-cash.png`, `Assets/dashboard-savings.png` |
| `credit-pressure-review` | Same synthetic fixture with one low-utilization card and one high-utilization card; the selected card is the pressure point. | A user can see owed balances, utilization, available credit, pending card activity, and debt emphasis without turning the app into a budgeting workflow. | Healthy demo state for the normal credit capture. The row and detail copy should identify credit risk with text or shape, not color alone. | `Assets/dashboard-credit.png`, `Assets/dashboard-debt.png` |
| `reconnect-confidence-check` | Demo data plus `--screenshot-status-recovery`, which keeps one synthetic institution recovered and marks another synthetic institution as needing login. | A user can trust that VaultPeek preserves last-known local data while making item recovery visible and actionable. | Status should show one connected/recovered institution, one login-required institution, synced-item count context, stale or delayed sync context when applicable, and explicit reconnect/settings/refresh handoff. | `Assets/dashboard-status.png` |
| `first-run-sandbox-preflight` | Empty local app state with the screenshot preflight port and no real Plaid credentials in the capture. | A new contributor can see what VaultPeek checks before opening Plaid Link: local server reachability, expected environment, credential readiness, storage path, and linked item count. | Setup should fail closed until the local server and sandbox credentials are ready. It must not imply sandbox works without credentials. | `Assets/setup-sandbox-preflight.png` |

## Reduced-Noise Composition

- Keep the first screenshot signal dense and product-shaped: heatmap, account
  rows, selected-account detail, status strip, local insight receipt, and one
  clear action path.
- Use dashboard filters to focus the story instead of adding separate marketing
  or explanatory surfaces.
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
