---
title: ADR - Future iOS/Native Link Decision
status: proposed
linear: [AND-413]
date: 2026-06-14
---

# ADR: Future iOS/Native Link Decision

**Design decision only. Nothing in this document authorizes an iOS app, LinkKit
integration, hosted bridge, production Plaid approval, or a change to the v1.0
macOS linking path.**

## Context

VaultPeek today is a macOS menu bar app with a local companion server. The app
target calls only the local `PlaidBarServer` API for Plaid-backed data, and
provider credentials plus access-token bytes stay inside the server/keychain
boundary. The current macOS link flow uses Plaid Hosted Link opened externally;
there is no LinkKit dependency in `Package.swift`, and the managed-link strategy
docs intentionally avoid embedded SDK work for the Mac app.

Plaid's iOS Link docs describe LinkKit as the native iOS integration path. The
current Plaid docs recommend Swift Package Manager via
`https://github.com/plaid/plaid-link-ios-spm` for Swift integrations, list
LinkKit 7.x as requiring Xcode 16.1 and iOS 15 or greater, and require
Universal Links for OAuth redirect URIs. Plaid's Hosted Link docs describe
Hosted Link as the Plaid-hosted frontend path, recommended when the official
mobile or web SDKs cannot be used, including webview-based mobile apps or flows
that do not own the frontend.

Sources checked on 2026-06-14:

- Plaid iOS Link docs: https://plaid.com/docs/link/ios/
- Plaid Hosted Link docs: https://plaid.com/docs/link/hosted-link/
- Existing VaultPeek docs:
  [`managed-link-architecture.md`](managed-link-architecture.md),
  [`consumer-experience-roadmap.md`](consumer-experience-roadmap.md)

## Decision

For any future first-party iOS or native mobile VaultPeek companion, the default
decision is **LinkKit 7.x via Swift Package Manager**, not inheriting the macOS
Hosted Link flow by default.

Hosted Link remains acceptable only as a deliberate fallback when the future
surface cannot integrate LinkKit, does not control the frontend, is implemented
as a webview-style shell, or is running a non-native handoff flow where the
Plaid-hosted frontend is the product choice. That exception must be documented
in a follow-up ADR before implementation.

The v1.0 macOS product remains **Hosted Link-only**. This ADR does not add
LinkKit to the current Swift package, does not add an iOS target, and does not
change the existing local server link routes.

Native LinkKit implementation is **non-v1.0** and is a prerequisite only for a
future iOS/native companion once that companion becomes an approved roadmap
item.

## Tradeoffs

| Option | Fit | Benefits | Costs / risks |
|---|---|---|---|
| **LinkKit 7.x via `plaid-link-ios-spm`** | Best fit for a first-party native iOS app | Native SDK path, lower browser handoff friction, official SwiftUI/UIKit integration, OAuth return flow can land directly in the app through Universal Links | Adds mobile target dependency and SDK update process; requires Apple Associated Domains, AASA hosting, Plaid Dashboard redirect registration, and App Store-style release cadence for SDK updates |
| **Hosted Link** | Best fit for macOS external-browser flow and fallback mobile flows where SDK integration is impossible | No embedded SDK, Plaid-hosted frontend, works for browser or secure web context flows, matches current macOS implementation | Less native mobile UX; Hosted Link completion and webhook/session handling differ from LinkKit callbacks; mobile Hosted Link can require additional handoff plumbing and should not be chosen only because it exists on macOS |

## Required Prerequisites For Native LinkKit

Before any iOS/native LinkKit implementation starts, VaultPeek must have:

1. A real iOS/native target decision with minimum deployment target **iOS 15+**
   for LinkKit 7.x and an Xcode toolchain compatible with Plaid's current
   requirement, checked again at implementation time.
2. A Swift Package Manager dependency on
   `https://github.com/plaid/plaid-link-ios-spm`, selecting the `LinkKit`
   product and tracking Plaid's recommended update cadence. LinkKit updates
   require shipping a new app build.
3. An Associated Domains entitlement with an `applinks:` domain owned by
   VaultPeek.
4. A valid `apple-app-site-association` file hosted over HTTPS at the required
   `.well-known` location for that domain, with no redirects and with a path
   component that matches the Plaid redirect route.
5. A Plaid Dashboard allowed redirect URI matching the Universal Link used by
   `/link/token/create`.
6. Link-token creation through the trusted server boundary. The app must request
   a one-time `link_token` from the local server or approved managed broker; it
   must not contain Plaid `client_secret` or provider access tokens.
7. For iOS LinkKit OAuth flows, `/link/token/create` must include the registered
   `redirect_uri`; that URI must be a Universal Link. **Do not use custom URL
   schemes as Plaid OAuth redirect URIs.**
8. A privacy review confirming that LinkKit callbacks do not move raw Plaid
   payloads, real account IDs, transaction IDs, balances, public tokens, access
   tokens, or screenshots into SwiftUI app state, docs, tests, logs, or
   generated artifacts. The only allowed token handoff is the short-lived public
   token flowing immediately to the local server or approved broker for exchange
   inside the trusted boundary.

## Privacy And Token Boundary

The future native app must preserve the same rule as the macOS app: the app
target may call only VaultPeek's local server or approved managed-broker API for
Plaid-backed data. Plaid secrets and access-token custody stay server-side or in
the local server's keychain storage. LinkKit may be present in the native UI
process to present Link, but it is not a license to store provider tokens or raw
Plaid metadata in app state.

For BYO-keys mode, the token exchange remains local. For a future managed mode,
the managed-link architecture still applies: the broker may mint link tokens and
perform exchange, but it must preserve the documented no-storage financial-data
posture and device-custody decision unless a later approved ADR changes that
boundary.

## Consequences

- v1.0 macOS keeps the existing Hosted Link path and no LinkKit dependency.
- Future iOS/native planning must budget Apple Associated Domains and AASA
  hosting work as part of the LinkKit implementation, not as release cleanup.
- SDK currency becomes a product maintenance obligation; Plaid's iOS SDK update
  guidance should be checked during mobile planning and then recorded in the
  mobile release checklist.
- Hosted Link remains documented as the macOS and fallback webview/non-owned
  frontend option, not the default native mobile strategy.

## Acceptance Criteria Trace

- **LinkKit vs Hosted Link tradeoff documented:** see "Tradeoffs."
- **OAuth Universal Link/AASA/Plaid Dashboard setup listed:** see "Required
  Prerequisites For Native LinkKit."
- **v1.0 macOS remains Hosted Link-only:** see "Decision" and "Consequences."
- **Mobile deferred / native LinkKit non-v1.0:** see "Decision" and the
  roadmap note in [`post-mvp-roadmap.md`](../post-mvp-roadmap.md).
