# Screenshots

PlaidBar screenshots are part of the product contract. They should show the
current design system, realistic states, and public-safe data.

## Public-Safe Rule

Only use demo, sandbox, or synthetic financial data in screenshots.

Do not publish screenshots containing:

- real account balances
- real merchant names
- real transaction history
- Plaid item IDs or account IDs
- terminal output containing credentials or tokens

## Generate Screenshots

From the repository root:

```bash
./Scripts/screenshots.sh
```

The script launches PlaidBar locally and captures:

- sandbox setup preflight
- dashboard overview
- dashboard Cash filter
- dashboard Credit filter
- dashboard Savings filter
- dashboard Debt filter
- dashboard Status filter
- Settings > General / Local Data
- Settings > Accounts
- Settings > Notifications
- Settings > About

## macOS Permissions

The screenshot script uses macOS UI automation. Terminal needs:

- Screen Recording permission
- Accessibility permission

If captures fail, open System Settings and confirm permissions for the terminal
app running the script.

## Expected Assets

| File | Purpose |
|------|---------|
| `Assets/setup-sandbox-preflight.png` | Setup readiness before Plaid Link |
| `Assets/dashboard.png` | Main dashboard overview |
| `Assets/dashboard-cash.png` | Cash-focused account state |
| `Assets/dashboard-credit.png` | Credit-focused account state |
| `Assets/dashboard-savings.png` | Savings-focused account state |
| `Assets/dashboard-debt.png` | Debt-focused account state |
| `Assets/dashboard-status.png` | Status and recovery-focused state |
| `Assets/settings-local-data.png` | Local data controls |
| `Assets/settings-accounts.png` | Linked items and account management |
| `Assets/settings-notifications.png` | Notification permission and thresholds |
| `Assets/settings-about.png` | Version, support, privacy, security, roadmap, and release links |

## Review Checklist

- Screenshots match the current design system.
- Text is readable at README display sizes.
- No real personal finance data appears.
- Empty/degraded states are represented where relevant.
- Button labels and status copy match the current app.
- Settings screenshots show useful controls, not blank tabs.
- Screenshots do not include unrelated desktop windows or notifications.

## When To Regenerate

Regenerate screenshots when a change affects:

- dashboard layout
- setup/onboarding
- status/recovery states
- settings tabs
- local data copy
- notification controls
- design tokens
- README screenshot tables
