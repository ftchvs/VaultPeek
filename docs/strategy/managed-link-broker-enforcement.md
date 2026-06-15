---
title: Managed Link Broker Enforcement Notes
status: implementation-note
linear: AND-414
date: 2026-06-14
---

# Managed Link Broker Enforcement Notes

AND-414 introduces the first server-side enforcement path for managed bank
linking. The implementation is deliberately narrow: it adds authenticated
localhost API endpoints for managed link-session creation and a secret-free
entitlement summary. It does not add Stripe Checkout, a customer portal, hosted
sync jobs, or any provider-secret handoff to the SwiftUI app.

## Implemented server boundary

- `GET /api/link/managed/entitlement` returns plan/status/institution count,
  institution limit, whether another managed link can be created, and a safe
  block reason when creation is unavailable.
- `POST /api/link/managed/create` checks that summary before asking Plaid for a
  Hosted Link session. Blocked requests return HTTP 402 with the same summary
  and do not call Plaid.
- Existing `/api/link/create` and `/api/link/update/{itemId}` remain the BYO
  and repair paths. Demo and BYO-key mode are not gated by managed-plan limits.
- OAuth callback handling checks managed entitlement again before exchanging a
  Hosted Link result, so a user cannot exceed the limit if their entitlement or
  active count changes between session creation and callback completion.

All of these routes sit under `/api`, so they inherit the existing local bearer
token authentication. The managed endpoints are for the backend/server boundary;
the SwiftUI app receives only the hosted URL plus entitlement/institution
summary state.

## Institution counting

Linked items now carry an `origin` marker:

- `managed` counts toward the managed institution limit.
- `byo` is the default for existing and local-user-created items.

Counts are derived from active stored managed items, keyed by institution ID
when available and by item ID as a fallback. Deleting an item removes it from
the count naturally. BYO items stay outside the count even when a managed
subscription exists.

Current self-serve limits:

- Free: 0 managed institutions.
- Plus: 8 managed institutions.

Past-due, canceled, and expired billing states block new managed link creation.
They do not delete local rows, Keychain entries, cached financial data, or BYO
connections.

## Token and provider-secret handling

The managed entitlement summary intentionally contains no provider secrets,
Plaid public tokens, Plaid access tokens, account IDs, balances, transaction
data, raw provider payloads, local database paths, or screenshots.

The server remains responsible for:

- Creating Hosted Link sessions.
- Holding the Plaid client credentials in server configuration only.
- Exchanging Hosted Link results server-side.
- Storing access-token bytes through the server token vault, with SQLite holding
  only token references.
- Marking managed items with `origin = managed` at storage time.

The SwiftUI app must not receive or persist Plaid provider secrets, public
tokens, access tokens, or raw Plaid payloads. It may receive only the hosted
bank-link URL and the secret-free entitlement/institution summary.

## Remaining scope

AND-414 does not implement hosted identity, live Stripe Checkout/Portal, signed
remote entitlement documents, or the future blind data-plane relay. Those remain
separate work items and must preserve the same division: local financial data
and token custody stay out of app UI surfaces and documentation artifacts, while
server enforcement owns managed-plan limits.
