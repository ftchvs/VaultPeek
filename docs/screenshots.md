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

The script launches VaultPeek locally and captures:

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

The dashboard surface also includes a below-the-fold local insight receipt when
demo transactions are available. Peekaboo/AX validation should see that receipt
even when the public screenshot stays focused on the first-glance dashboard
area. The receipt is intentionally local-only: it shows source-row count,
window, top category, recurring estimate, category hints, and the
disabled/no-runtime state when no local AI runtime is configured. It must not
imply cloud AI processing or send transaction data off-device.

The Status capture uses demo data with `--screenshot-status-recovery`. That
fixture keeps the regular demo dashboard healthy, while the Status filter shows
one recovered institution and one institution that needs login/reconnect.

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

| Scenario | Primary assets | Review focus |
|----------|----------------|--------------|
| `steady-household-overview` | `Assets/dashboard.png` | First-glance cash, credit, savings, debt, sync health, and heatmap context; validate below-fold local insight receipt separately |
| `cash-runway-check` | `Assets/dashboard-cash.png`, `Assets/dashboard-savings.png` | Depository balances, selected-account detail, and quiet healthy status |
| `credit-pressure-review` | `Assets/dashboard-credit.png`, `Assets/dashboard-debt.png` | Utilization, available credit, owed balances, and non-budgeting debt emphasis |
| `reconnect-confidence-check` | `Assets/dashboard-status.png` | Login-required item recovery without raw Plaid payloads or real errors |
| `first-run-sandbox-preflight` | `Assets/setup-sandbox-preflight.png` | Fail-closed setup readiness before Plaid Link opens |

## macOS Permissions

The screenshot script uses macOS UI automation. Terminal needs:

- Screen Recording permission
- Accessibility permission

If captures fail, open System Settings and confirm permissions for the terminal
app running the script.

The script captures PlaidBar windows by their macOS window ID after the app is
opened into each screenshot state. This avoids stale display-rectangle captures
when the menu-bar popover is positioned outside the active display bounds.

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
- Privacy Mask/App Lock screenshots show only generic copy or fixed
  placeholders for balances, account endings, transactions, utilization, and
  notifications.
- Empty/degraded states are represented where relevant.
- `dashboard-status.png` shows the recovery fixture, not a real Plaid error.
- Peekaboo/AX validation can find local insight receipt text saying
  local-only/disabled when no local runtime is configured; it must not mention
  cloud AI fallback.
- Button labels and status copy match the current app.
- Settings screenshots show useful controls, not blank tabs.
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
