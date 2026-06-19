# Accessibility

VaultPeek is a native macOS menu bar app. Accessibility work in this repo focuses
on VoiceOver, keyboard navigation, readable finance data, color-independent
status, and clear local-server errors.

## What we aim for

- Menu bar and popover controls are reachable by keyboard.
- Interactive controls have useful labels for VoiceOver.
- Focus states are visible.
- Account, transaction, spending, and credit-utilization states do not rely on
  color alone.
- Charts and gauges have text equivalents or summaries.
- Heatmap cells expose date, transaction count, and the current Spend/Net value
  through hover/help text instead of relying on color alone.
- Alerts and errors are written clearly and announced through standard macOS UI
  patterns where practical.
- Motion and loading states do not create barriers.
- Screenshots and docs include meaningful alt text.

## Reporting accessibility issues

Please open an accessibility issue if you find:

- unlabeled controls or confusing VoiceOver announcements
- keyboard traps or unreachable actions
- charts, gauges, or status indicators without text equivalents
- color-only balance, risk, or utilization meaning
- confusing focus order, loading, alert, or error behavior

Include macOS version, VaultPeek version or commit, VoiceOver/keyboard setup,
display settings, and steps to reproduce. Do not include real financial data,
access tokens, account numbers, or private transaction details.

## Contribution expectations

UI changes should include a keyboard pass, VoiceOver spot check, visible-focus
check, and color-independent review of balances, charts, warnings, and errors.
Use synthetic or sandbox financial data in screenshots, tests, and examples.

## App Store Accessibility Nutrition Labels

[docs/accessibility-nutrition-labels.md](docs/accessibility-nutrition-labels.md)
audits which App Store Accessibility Nutrition Label categories VaultPeek
supports today — mapping each (VoiceOver, Larger Text, Dark Interface,
Differentiate Without Color Alone, Reduced Motion, Sufficient Contrast, Voice
Control; Captions and Audio Descriptions are N/A) to `file:line` evidence and the
gaps to close before declaring it in App Store Connect.
