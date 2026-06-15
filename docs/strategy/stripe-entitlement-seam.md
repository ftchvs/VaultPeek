# Stripe entitlement seam notes

AND-348 adds the first backend Stripe-shaped subscription entitlement seam for the managed-link path. The implementation is intentionally metadata-only and local-testable: it does not require Stripe credentials, does not call Stripe over the network, and does not move billing or Plaid secrets into the SwiftUI app.

## Server endpoints

Authenticated `/api/billing/*` endpoints now include:

- `POST /api/billing/checkout` — creates a Stripe-shaped subscription checkout session response for paid managed plans.
- `POST /api/billing/portal` — creates a Stripe-shaped customer portal session response for card updates, cancellation, and invoices.
- `POST /api/billing/webhook` — accepts a bounded normalized webhook projection and updates local subscription status/plan/trial metadata idempotently by event ID.
- `GET /api/billing/entitlement` — returns the safe entitlement view used by clients: plan, subscription status, institution limit, active managed institution count, trial end, allowed feature identifiers, and managed-link eligibility.

The existing `GET/PUT /api/billing/subscription` endpoint remains for already-normalized local lifecycle state.

## Institution limits and cancellation

The managed-link broker from AND-414 remains the enforcement point for future bank linking:

- Free / missing subscription: managed linking blocked.
- Plus active/trialing: managed linking allowed up to the managed institution limit.
- Past due / canceled / expired: future managed linking is blocked.
- Existing local data is not deleted by cancellation or degraded subscription state.
- BYO/demo/local connections remain ungated.

## Privacy/security boundary

The entitlement API and webhook store only normalized metadata:

- event ID and type
- subscription status and plan
- current period/trial dates
- safe plan/count/features summary

Never store or return Stripe secrets, webhook signatures, raw Stripe payloads, customer email, card/payment-method details, invoices, Plaid public tokens, Plaid access tokens, client secrets, raw Plaid payloads, account IDs, balances, transactions, database paths, logs, or screenshots.

## Follow-up needed for production Stripe

This PR creates the tested API and entitlement contract. A production Stripe integration still needs real Checkout/Portal session creation, webhook signature verification, Stripe product/price IDs, and durable webhook event storage in the hosted bridge environment.
