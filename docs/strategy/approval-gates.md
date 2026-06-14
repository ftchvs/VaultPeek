---
title: Strategy Approval Gates for Managed Consumer Work
status: proposed
linear: [AND-344, AND-345, AND-346, AND-347, AND-348, AND-349, AND-392, AND-394]
date: 2026-06-14
---

# Strategy Approval Gates for Managed Consumer Work

This is the review checklist for deciding when implementation may start on the
managed consumer track. It does not authorize code changes by itself. No hosted
backend, billing, provider-token custody, managed-link, public pricing, or
privacy-promise change should be implemented until the relevant gates below are
approved and linked from the implementation issue or PR.

Use the companion strategy docs as the source of truth. This checklist only
records what reviewers must approve.

## Gate checklist

| Gate | Linear | Source doc | Approval required before implementation |
|---|---|---|---|
| Plaid pricing and COGS | AND-344 | `docs/strategy/provider-costs.md` | Replace estimate-only Plaid rates with a dated dashboard quote or written sales quote for Transactions, Balance, Liabilities, Investments, Auth, Identity, and Hosted Link delivery treatment. Confirm PAYG vs committed terms, Growth minimums, `/item/remove` billing shutoff, and whether URL-handoff Hosted Link has a fee. Do not include screenshots that expose secrets, account data, or private dashboard details. |
| Teller evaluation | AND-345 | `docs/strategy/teller-evaluation.md` | Decide whether Teller is experimental-only, fallback/secondary, or declined. Approval requires the PoC exit criteria, coverage review for target institutions, legal/native Connect answer, production cost confirmation, balance-call avoidance plan, and trust/SOC 2 answer. |
| Provider abstraction | AND-346 | `docs/strategy/provider-abstraction.md` | Approve the smallest server-side abstraction scope before adding interfaces or migrations. The approved scope must preserve local BYO behavior, keep raw provider payloads out of UI/logs, count provider Items/enrollments for plan limits, and define strict-concurrency expectations. |
| Managed broker architecture | AND-347 | `docs/strategy/managed-link-architecture.md` | Explicit go/no-go on the hosted footprint: link-token broker, public-token exchange, stateless blind proxy, item registry, disconnect/removal, webhook stance, and no-body-log proxy rules. Approval must accept the privacy-promise change that managed financial data transits VaultPeek infrastructure but is never stored there. |
| Managed consent operations | AND-394 | `docs/strategy/managed-link-consent-operations.md` | Approve exact consent copy, support-helper boundaries, audit event schema, forbidden audit fields, escalation rules for credentials/MFA/failed links/account removal, and the rule that support channels never collect raw credentials or financial secrets. |
| Entitlement matrix | AND-392 | `docs/strategy/entitlement-matrix.md` | Canonical Free / Plus / Managed limits, prices, grace states, downgrade behavior, and support-copy boundaries are locked here. This approval does not authorize Stripe, broker, provider-token custody, or hosted enforcement implementation by itself. |
| Stripe entitlements and institution limits | AND-348 | `docs/strategy/subscription-entitlements.md` + `docs/strategy/entitlement-matrix.md` | Resolve signer architecture, BYO ungated behavior, tax/distribution posture, and rename timing before any Stripe, entitlement, device activation, or institution-limit code. Use AND-392 for the locked plan matrix and lifecycle semantics. |
| Pricing bundles and launch copy | AND-349 | `docs/strategy/pricing-and-launch.md` + `docs/strategy/entitlement-matrix.md` | Approve public packaging and copy only after Plaid pricing and Teller comparison are real enough to support margins. Use AND-392 for Free/Plus/Managed caps and prices; keep no unlimited or lifetime plans, BYO-free promise, trial/refund policy, distribution channel, price-lock stance, and amended privacy copy aligned. |
| Privacy promise change | Cross-doc | `README.md`, `SECURITY.md`, `docs/privacy.md`, and the strategy docs above | Before any managed public or product surface ships, approve exact wording that distinguishes BYO local-only mode from managed mode. Managed copy must say what the broker stores, what transits it, what is never stored, and what happens on cancellation. |

## Implementation entry rule

A PR may start implementation only when its PR description or linked Linear
issue includes an approval record with:

- Gate names approved.
- Approver and date.
- Source doc section or follow-up decision link reviewed.
- Remaining constraints that still bind the implementation.
- Privacy impact statement, especially for hosted services or managed data
  transit.

If a PR touches hosted backend code, Stripe billing, provider-token custody,
managed link/session behavior, public pricing copy, or the product privacy
promise without that record, reviewers should block it as premature.

## Approval record template

```text
Gate approval:
- Date:
- Approver:
- Gates:
- Decision:
- Evidence reviewed:
- Source docs updated:
- Implementation now allowed:
- Remaining constraints:
```

## Unresolved gates as of 2026-06-12

- Plaid pricing remains estimate-based until a dashboard or sales quote is
  captured without private screenshots.
- Teller remains experimental until the PoC and sales/support questions are
  answered.
- Managed broker work remains deferred until the go/no-go gates in
  `managed-link-architecture.md` pass.
- Managed support-assisted setup remains deferred until the consent, audit, and
  escalation gates in `managed-link-consent-operations.md` pass.
- Stripe entitlement implementation remains deferred until the remaining
  architecture gates in `subscription-entitlements.md` are resolved; the plan
  matrix itself is locked in `entitlement-matrix.md`.
- Public paid pricing and launch copy remain provisional until Plaid/Teller
  economics, distribution, and privacy wording are approved.
