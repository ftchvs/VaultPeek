---
title: VaultPeek Free / Plus / Managed Entitlement Matrix
status: accepted
linear: [AND-392]
date: 2026-06-14
---

# VaultPeek Free / Plus / Managed Entitlement Matrix

This is the canonical entitlement matrix for implementation and support copy.
It supersedes the earlier Personal/Plus draft naming in
`pricing-and-launch.md` and `subscription-entitlements.md`.

This document does **not** approve Stripe, hosted broker, entitlement-token, or
provider-token-custody implementation. Those remain gated by
`approval-gates.md`. Until that infrastructure exists, these are product rules
and model constants only.

## Plan Matrix

| Plan | Price | Managed live institutions | What is included | What is not included |
|---|---:|---:|---|---|
| Free | $0 | 0 | Demo fixtures, all local-first app surfaces on sample data, and bring-your-own Plaid keys for users who run their own local Plaid setup. BYO connections are free, local, ungated, and do not count against a managed plan. | No VaultPeek-managed bank linking, no hosted entitlement check, no Stripe subscription, no provider-cost subsidy. |
| Plus | $15/month or $129/year early-access | 8 | VaultPeek-managed bank linking for up to 8 institutions once the broker is approved and built. Existing core surfaces are included: balances, transactions, spending, credit utilization, recurring obligations, budgets/safe-to-spend, local insights, reconnect, and unlink. | No unlimited institutions, no lifetime deal, no free live-bank trial, no unreleased premium feature promise. |
| Managed | Custom written quote; starts from Plus | Written quote; default 8 until an order explicitly says otherwise | Plus entitlements plus hands-on setup and operational support from Felipe/Otto for onboarding, connection-health triage, billing coordination, and managed-item cleanup. | Not accountancy, financial advice, tax advice, bank support, guaranteed institution uptime, or a promise that VaultPeek can bypass Plaid/provider/bank outages. |

## Managed Tier Responsibility Boundary

Felipe/Otto manage:

- VaultPeek's provider production relationship, broker operations, and Stripe
  product/portal configuration once approved.
- Onboarding help, connection-health triage, and clear next steps when an
  institution needs reauth or provider support.
- Subscription lifecycle handling, including disabling future managed sync/link
  at lapse and driving managed-item cleanup.
- Support copy that explains what VaultPeek stores, what transits managed
  infrastructure, and what remains only on the user's Mac.

The user still owns:

- Bank credentials, MFA, consent screens, and any bank-side permission changes.
- Their Mac, app install, local database, Keychain, backups, and local deletion.
- Choosing which institutions stay live after a downgrade or cap reduction.
- Keeping the app online often enough for entitlement refresh and item cleanup.
- Deciding whether to use Free BYO mode instead of the managed service.

## Grace And Billing States

Entitlement state and Stripe subscription status are separate. Offline grace is
for connectivity failures only; it is not a hidden extension after cancellation.

| State | Sync existing managed institutions | Add managed institution | Cached local data | Support copy |
|---|---|---|---|---|
| Demo trial | Not applicable; no live managed institutions | No | Demo data only | "Try the full interface with sample data. No card, signup, or bank login." |
| Active Plus/Managed | Yes, for live institutions within the cap | Yes, until the cap is reached | Fully readable | "Your plan is active." |
| Payment failed / past due | Yes during Stripe dunning, up to 14 days | No new managed institutions | Fully readable | "Update billing to keep live sync from pausing." |
| Canceled, before period end | Yes until the paid-through date | No new managed institutions | Fully readable | "Your plan remains active until DATE." |
| Expired / canceled after period end | No managed sync; update-link for cleanup/recovery may still be offered | No | Fully readable forever unless the user deletes it locally | "Live sync has paused. Your downloaded data stays on your Mac." |
| Offline token expired | Yes during the 14-day connectivity grace after the 30-day token TTL | No new managed institutions during grace | Fully readable | "Subscription check is overdue; get online before live sync pauses." |
| Offline grace elapsed | No managed sync until refresh succeeds | No | Fully readable | "Live sync is paused until VaultPeek can verify the subscription." |

Payment-failed dunning may be shortened by Stripe or owner policy, but support
copy must never promise more than 14 days. A successful payment or entitlement
refresh restores normal Plus/Managed behavior without deleting local data.

## Downgrades And Institution Caps

- Free has a managed institution limit of 0. Downgrading to Free pauses all
  managed institutions and blocks new managed links. BYO connections remain
  outside the entitlement system.
- Plus has a managed institution limit of 8.
- Managed uses the written order's institution limit; if no limit is written,
  it inherits Plus's 8-institution limit.
- Downgrades never delete local accounts, transactions, balances, screenshots,
  or logs. Cached data remains readable.
- If active managed institutions exceed the new limit, VaultPeek enters an
  `over_limit` state. The user chooses which institutions stay live. Until they
  choose, the most recently synced institutions up to the limit stay live and
  the rest are paused.
- Paused institutions keep their local history visible, but scheduled managed
  sync and new data refresh stop for those institutions.
- Reconnect/update-link flows for an existing selected-live institution are not
  blocked by the add-institution cap because repair does not add a new
  institution.
- Add-account actions stay visible but disabled with text and an icon explaining
  the limit; color must not be the only signal.

## Implementation Guardrails

- The app target may call only the local `PlaidBarServer` API for Plaid-backed
  data.
- Plaid `client_secret`, access tokens, public tokens, raw Plaid payloads, real
  account IDs, transaction IDs, balances, local SQLite data, logs, and
  screenshots must not be copied into app code, docs, tests, or generated
  artifacts.
- Provider secrets and provider-token custody remain server-side. Free BYO mode
  remains local and ungated.
- Plan claims must map to built app surfaces or explicitly say "once the broker
  is approved and built." Do not promise advanced alerts, monthly financial
  review, realtime balance refresh, multi-Mac sync, tax/accounting service, or
  financial advice until those features exist.
