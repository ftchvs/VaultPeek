---
title: Managed Bank-Link Consent, Audit, and Escalation Boundaries
status: proposed
linear: AND-394
date: 2026-06-14
---

# Managed Bank-Link Consent, Audit, and Escalation Boundaries

**Design document only. Nothing in this document authorizes implementation or
support-assisted bank linking.** This document defines the consent language,
support audit trail, escalation rules, and data-minimization boundary required
before VaultPeek can sell optional managed bank linking.

Managed linking changes VaultPeek's privacy promise: financial data may transit
a VaultPeek stateless proxy, but it must never be stored by VaultPeek-hosted
systems. The architecture boundary is defined in
[`managed-link-architecture.md`](managed-link-architecture.md). This document
adds the operational boundary for humans helping users through setup.

## 1. User consent language

Managed-link consent must be explicit, separate from generic terms acceptance,
and shown before Plaid Hosted Link opens.

### Required plain-language copy

Use this wording as the baseline for the product surface:

> VaultPeek can help you connect your bank through our managed bridge. You will
> enter bank credentials and MFA codes only in Plaid or your bank's own secure
> screens. VaultPeek support cannot see, request, type, store, or recover your
> bank username, password, MFA code, Plaid token, account number, balances, or
> transactions.
>
> In managed mode, VaultPeek creates the Plaid link session and relays account
> and transaction sync responses through a stateless service so the app can
> work without your own Plaid developer keys. VaultPeek does not store your
> balances, transactions, account numbers, or raw Plaid payloads on our
> servers. Your dashboard data remains stored on your Mac.
>
> A support helper may guide you verbally or by chat through VaultPeek screens,
> confirm safe setup status, and record a support audit note. They cannot take
> control of your bank session, ask for financial secrets, bypass MFA, or remove
> an account without your explicit action or written confirmation.

### Consent checkboxes

The setup flow must require affirmative consent for each statement:

- I understand that managed sync data transits VaultPeek's stateless bridge but
  is not stored by VaultPeek servers.
- I will enter bank credentials and MFA only in Plaid or my bank's own secure
  screens, never in a support chat, email, ticket, or screen share.
- I understand that a support helper can guide me through VaultPeek setup but
  cannot ask for, receive, type, or store my bank credentials, MFA codes, Plaid
  tokens, account IDs, balances, transactions, screenshots with financial data,
  or local database files.
- I understand that removing a bank connection requires my explicit action in
  the app or my written confirmation through a private support channel.

### Helper capability boundary

Support-assisted setup means the helper may:

- Explain what each VaultPeek setup screen means.
- Confirm non-sensitive readiness words such as signed in, entitled, link
  started, link completed, reconnect required, or removed.
- Ask the user to read sanitized in-app error text.
- Ask the user to describe `/api/status` readiness metadata in words.
- Record a support audit event using the safe fields in Section 2.

The helper must not:

- Ask for or accept bank usernames, passwords, MFA codes, security answers, card
  numbers, account/routing numbers, Plaid credentials, Plaid tokens, item IDs,
  account IDs, transaction IDs, balances, raw Plaid payloads, local SQLite
  files, Keychain contents, server config contents, unredacted logs, or
  screenshots containing real financial data.
- Operate the user's bank or Plaid session, including by remote control.
- Paste credentials into any screen on the user's behalf.
- Promise that VaultPeek can fix Plaid institution coverage, bank-side MFA,
  bank outages, or Plaid production decisions.
- Continue a support flow after a secret is exposed without first switching to
  the exposure response in Section 3.

## 2. Support-assisted setup audit trail

Every support-assisted managed-link session must create an operator audit event.
The audit trail is for accountability and dispute resolution; it is not a
debugging dump.

### Required audit events

Record one event for each of these lifecycle points when support is involved:

- `managed_link_help_started`
- `managed_link_consent_confirmed`
- `managed_link_session_started`
- `managed_link_session_completed`
- `managed_link_reconnect_guided`
- `managed_link_account_removal_requested`
- `managed_link_account_removal_confirmed`
- `managed_link_help_ended`
- `managed_link_secret_exposure_reported`
- `managed_link_escalated`

### Allowed audit fields

Audit records may contain only:

- Timestamp.
- Operator ID.
- User support ID or hashed user ID.
- Ticket ID.
- Managed plan tier.
- Safe lifecycle event name.
- Consent version.
- Device/app version.
- Non-sensitive result status: completed, user_abandoned, retry_later,
  escalated, failed_safe.
- Escalation category from Section 3.
- Short operator note using the safe-note rule below.

Safe-note rule: notes may describe actions and outcomes, not financial facts or
provider identifiers. Example: `User completed Plaid-hosted flow and app showed
link complete.` Do not include institution names unless product/legal approves
them as non-sensitive in the final policy; the default is to omit them.

### Forbidden audit fields

Audit records must not contain:

- Bank credentials, MFA codes, security answers, account/routing/card numbers.
- Plaid `client_secret`, `client_id`, `access_token`, `public_token`, `item_id`,
  `account_id`, `transaction_id`, or raw Plaid request/response payloads.
- Balances, transaction details, account names, account masks, merchant names,
  holdings, liabilities, or screenshots.
- Local paths that reveal usernames unless normalized, local SQLite contents,
  Keychain contents, unredacted logs, environment dumps, or `server.conf`
  contents.

### Retention and access

- Retain support-assisted audit events for 13 months unless legal approves a
  different production retention schedule.
- Restrict access to operators with a support need and maintain access logs.
- Store audit events separately from proxy logs. Proxy logs remain
  metadata-only and must not include request or response bodies.
- Audit export for a user request must be reviewed for forbidden fields before
  release.

## 3. Escalation rules

Escalation exists to keep support from solving sensitive problems by collecting
secrets. If a case cannot proceed without a forbidden input, stop the support
flow and escalate the category; do not request the input.

| Scenario | Boundary | Operator action | Escalation |
|---|---|---|---|
| User wants help entering bank credentials | Credentials are entered only by the user in Plaid or bank-hosted screens. | Explain the boundary and stay on VaultPeek screens. | Escalate only if VaultPeek copy implies support can handle credentials. |
| User offers or pastes credentials, MFA, tokens, account IDs, balances, transactions, logs, screenshots, or local DB files | Treat as private-data exposure. | Tell the user not to send more, avoid retaining the content, and advise rotation/revocation where applicable. | `managed_link_secret_exposure_reported` to security/private vulnerability path. |
| MFA challenge appears | Support cannot ask for, see, type, store, or bypass MFA. | Tell the user to complete MFA directly with Plaid/bank or cancel. | Escalate to product only if VaultPeek UI misroutes or loops after successful MFA. |
| Plaid Link fails before completion | No item should exist unless Plaid completed exchange. | Ask the user to start a fresh link and read sanitized error text only. | Escalate to engineering with safe repro if repeatable in sandbox/demo or sanitized managed event IDs. |
| Reconnect required | Bank/Plaid requires fresh authorization. | Guide user to the app's reconnect action. | Escalate to Plaid/provider category if institution-specific and repeatable. |
| Institution unsupported or Plaid outage | VaultPeek cannot change institution coverage. | Direct to Plaid/bank status or support as appropriate. | Product/provider escalation for trend tracking, not credential collection. |
| User requests account removal | Removal must be user-initiated in app or confirmed in writing. | Guide in-app removal. If app access is unavailable, collect written confirmation without financial identifiers. | Escalate to operations for registry cleanup; Plaid administrative removal is allowed only through approved owner runbook. |
| Lost device with managed Item still billed | Device-held token may be unavailable. | Confirm user identity and written removal request without account data. | Operations escalation for orphan-item runbook and Plaid support/dashboard removal. |
| Chargeback, legal, law enforcement, or data-subject request | Support cannot improvise. | Preserve the ticket and stop bank-link help. | Legal/owner escalation. |

## 4. Account removal consent

Account removal is sensitive because it changes bank-link state and billing.

Required removal rules:

- Prefer in-app removal by the user. The local server should call provider
  removal with the device-held token, delete the local Keychain entry, then
  update the managed registry as described in `managed-link-architecture.md`.
- If the user cannot access the app, require written confirmation from the
  authenticated support identity. The confirmation should name the action
  without naming account numbers, balances, transactions, or raw IDs.
- Support may record `managed_link_account_removal_requested` and
  `managed_link_account_removal_confirmed` audit events.
- Support must not ask the user for provider tokens or raw account identifiers
  to perform removal.
- If removal cannot complete without a device-held token, escalate to the
  orphan-item runbook. Do not ask the user to export local databases or
  Keychain entries.

## 5. Pre-sale acceptance criteria

Managed linking can be sold only when all of the following are true:

- Product consent copy includes the required capabilities, limitations, transit
  boundary, and no-secrets support rule.
- Support runbooks link to this document and train operators that "cannot
  diagnose without a secret" means escalate, not collect the secret.
- Audit logging supports the event names and allowed fields above, with tests or
  schema review showing forbidden fields are not accepted.
- Managed proxy logs are metadata-only and body logging is disabled by design.
- Account removal has a user-initiated path, a written-confirmation fallback,
  and an orphan-item escalation path.
- Privacy, support, and security public docs distinguish BYO local-first mode
  from managed transit-only mode before any managed surface ships.
- A review gate blocks launch if support channels, docs, tests, fixtures, or
  generated artifacts include real credentials, tokens, raw Plaid payloads,
  real account IDs, transaction IDs, balances, local SQLite data, logs, or
  screenshots.

## 6. Open decisions

- Final legal wording for consent and support-assisted setup.
- Whether institution names are permitted in support audit notes. Default:
  no, until explicitly approved.
- Production audit retention period if 13 months is not the desired policy.
- Exact identity verification standard for out-of-app account removal.
