---
title: VaultPeek Privacy-Preserving Launch Metrics Plan
status: proposed
linear: [AND-396]
date: 2026-06-13
---

# VaultPeek Privacy-Preserving Launch Metrics Plan

> **Design/process document only. Nothing in this plan instruments the app, the
> local server, or any user's data.** Every metric below is collected from a
> surface that is *already public* (the GitHub repository, a release page) or
> from something a person *deliberately sends us* (a support email). If a metric
> would require code inside `PlaidBar`, `PlaidBarServer`, or `PlaidBarCore` to
> observe and report user behavior, it is out of scope by construction — see
> §4, Non-goals / red lines.

This plan answers one question: **how does VaultPeek learn whether a launch is
working without breaking the promise that makes VaultPeek worth shipping?**

## 1. The constraint comes first

VaultPeek's privacy posture is not a feature; it is the product. The
documentation states this in three places, and this plan is subordinate to all
three:

- `docs/privacy.md`: *"It has no hosted VaultPeek backend, no analytics, no
  telemetry, and no tracking."* The "What Does Not Leave Your Mac" section
  enumerates the absence of analytics, telemetry, and advertising pixels.
- `SECURITY.md`, Security Model: *"VaultPeek has no hosted backend, analytics,
  telemetry, or tracking."*
- `docs/v1.0-roadmap.md`, Product Boundaries → **Resist**: lists "Telemetry by
  default" as a direction that stays out of scope "unless the project
  deliberately changes identity," and the Local First principle names "Adding
  analytics, telemetry, or remote state by default" as explicit **bad product
  behavior**.

The README repeats the public claim verbatim: *"VaultPeek has no cloud backend,
no analytics, no telemetry, and no tracking. Your financial data never leaves
your machine."* (`README.md`).

A launch-metrics program that contradicted any of these would not be a
measurement decision — it would be an identity change, gated the same way the
managed-tier hosted footprint is gated in `docs/strategy/pricing-and-launch.md`
(§9, D1) and `docs/strategy/approval-gates.md`. **This plan does not request
that gate.** It is designed to need zero new code in the shipped product.

### 1.1 Where this plan is allowed to operate

VaultPeek is distributed privately as an ad-hoc-signed, drag-install
`VaultPeek-<version>.dmg` from a private GitHub repository, with GitHub releases
as the eventual download host (`docs/release.md`, `README.md` Installation).
That distribution shape defines the entire measurable surface:

- The **GitHub repository** (stars, forks, watchers, issues, pull requests,
  labels, traffic) — public-by-API metadata about the project, never about a
  user's finances.
- The **GitHub release assets** (DMG download counts) — a count of how many
  times an artifact was fetched, with no identity attached.
- **Support contact volume** — messages a human chose to send us.
- **Manual cohort notes** — what the maintainer observes and writes down by hand
  when privately distributing to licensed users.

That is the whole list. There is no fifth category, and there is deliberately no
in-app source.

## 2. Metrics catalog

Every row names a **public or explicit source**, the **collection method**
(manual or public API only), the **cadence**, and the **decision it informs**.
No row requires instrumentation, financial-data access, or background reporting
from any VaultPeek process.

### 2.1 Repository interest signals

| Metric | Public/explicit source | Collection method | Cadence | Decision it informs |
|---|---|---|---|---|
| Stars | GitHub repo (`github.com/ftchvs/VaultPeek`) | Public GitHub REST/GraphQL API (read-only) or the repo's Insights tab, read manually | Weekly | Is top-of-funnel awareness growing after a launch post? Flat stars after outreach = the message isn't landing. |
| Forks | GitHub repo | Public GitHub API or Insights, manual | Weekly | Developer/contributor pull. High forks vs stars suggests the BYO-keys/source audience (the trust anchor in `docs/strategy/pricing-and-launch.md` §4) is who's showing up. |
| Watchers | GitHub repo | Public GitHub API or Insights, manual | Weekly | Sustained-interest signal — who wants release notifications, distinct from a one-time star. |
| Repository traffic (views, unique visitors, clones) | GitHub repo **Insights → Traffic** (owner-only, but it is GitHub-side metadata, not app instrumentation) | Read manually from Insights; GitHub retains a 14-day window, so it must be recorded on cadence or it is lost | Weekly | Did a specific launch channel (HN, a newsletter, a post) drive repo visits? Correlate spikes to outreach dates. |

Note: GitHub's traffic view is the one source with a retention cliff (14 days).
It is still public-surface metadata *about the repo*, not about app usage —
nothing in VaultPeek reports it. Capture it on the weekly cadence or accept the
gap.

### 2.2 Adoption / install signals

| Metric | Public/explicit source | Collection method | Cadence | Decision it informs |
|---|---|---|---|---|
| Release download count (per asset, per tag) | GitHub **release assets** — each `VaultPeek-<version>.dmg` exposes a `download_count` field | Public GitHub Releases API (`GET /repos/.../releases`), read-only; or the release page UI | Per release, then weekly | The closest honest proxy for installs. Downloads-per-release vs stars shows how many interested people actually pulled the build. A new patch with near-zero downloads = a distribution or comms problem, not necessarily a product one. |

This is a **download count, not an install or usage count.** A download is not a
launch, a launch is not a retained user, and we cannot — and will not — close
that gap from the client side (see §3). The number is a ceiling on adoption, not
a measurement of it. Because distribution is also private/manual to licensed
users (`docs/release.md`, "Distribute the resulting DMG privately to licensed
users"), some installs never touch a GitHub release asset at all; those are
counted in §2.4 instead.

### 2.3 Engagement / friction signals (issues, PRs, labels)

| Metric | Public/explicit source | Collection method | Cadence | Decision it informs |
|---|---|---|---|---|
| New issues opened | GitHub Issues | Public GitHub API or Issues tab, manual | Weekly | Are users hitting the documented failure modes? VaultPeek treats recovery states as first-class (`docs/v1.0-roadmap.md`, Horizon 3); a cluster of issues on one recovery path is a direct backlog signal. |
| Issue label distribution | GitHub issue labels (e.g. `bug`, `setup`, `design`, design-backlog labels) | Public GitHub API or filtered Issues view, manual | Per triage / weekly | Where is friction concentrated — setup, sync, design, accessibility? Label counts steer which Horizon gets the next slice. |
| Issue close time / open backlog size | GitHub Issues | Public GitHub API or Insights, manual | Weekly | Maintainer responsiveness and whether launch interest is outrunning maintenance capacity. |
| PR activity (opened/merged, contributor count) | GitHub Pull Requests | Public GitHub API or Insights, manual | Weekly | Is the repo "approachable to authorized internal collaborators" (`docs/v1.0-roadmap.md`, Long-Term Success Signals)? Outside-contributor PRs validate the "ideal contributor" journey. |

Important boundary: per `SECURITY.md` and `docs/privacy.md`, security-sensitive
reports must **not** flow through public issues — they use private vulnerability
reporting. So security reports are deliberately *excluded* from the public-issue
metrics above and are noted only in the qualitative support log (§2.4), without
detail, to avoid leaking the existence or shape of a vulnerability.

### 2.4 Support and cohort signals (explicit human contact)

| Metric | Public/explicit source | Collection method | Cadence | Decision it informs |
|---|---|---|---|---|
| Support contact volume | Inbound messages via the contact path in `SECURITY.md` / the GitHub profile (email, private reports) | Manual tally; the person chose to write to us | Weekly | Support-per-download is the friction-cost-per-user proxy. Rising contact volume after a release = a regression or a docs gap. |
| Support topic breakdown | The content of those messages | Manual categorization (setup, Plaid link, server health, billing-preview confusion, etc.) | Per triage | Which `docs/troubleshooting.md` paths need work; whether the plan-picker "preview" copy (`docs/privacy.md`, Managed Bank Linking) is confusing people into thinking billing is live. |
| Manual cohort notes | The maintainer's own record of private distribution to licensed users | Hand-written notes (who received a DMG, when, on what version, any verbal feedback) | Per distribution event | Closes the gap the GitHub download count cannot: who *actually* got a private build, since private distribution bypasses release-asset counters (`docs/release.md`). This is the only "who" data in the plan, and it exists only because the maintainer handed someone a build in person/over a channel and wrote it down. |

Manual cohort notes are explicitly a **maintainer-side ledger**, not user data
pulled from the product. They contain what the maintainer chose to record about
their own distribution actions — never anything read from a user's machine,
balances, transactions, or app state.

## 3. What we deliberately cannot know (and why that's the point)

A normal launch dashboard answers: how many daily active users, what's
retention, which feature has the highest engagement, where do users drop off in
onboarding, what's the crash rate. **VaultPeek cannot answer any of these, and
that inability is the product working as designed.**

We cannot know, and will not build the ability to know:

- **Whether someone who downloaded the DMG ever launched it.** No app process
  reports a launch. A download is the last observable event.
- **Daily/weekly/monthly active users.** There is no heartbeat, ping, or session
  beacon — that would be the "phones home" red line in §4.
- **Retention or churn curves.** No per-install identity exists to follow over
  time. (Managed-tier *subscription* state would live in a future Stripe
  entitlement service per `docs/strategy/subscription-entitlements.md`, which by
  design sees only an email/license id and a tier — never usage — and does not
  exist today.)
- **Which features are used, in what order, how often.** No event tracking,
  anonymous or otherwise (see §4).
- **Onboarding funnel drop-off.** We see GitHub stars and downloads at the top;
  we see support messages and issues at the bottom; the middle — what happens
  inside the popover — is invisible by design.
- **Crash frequency or stack traces**, unless a user chooses to file an issue or
  send a report. There is no automatic crash upload.

This is the bargain VaultPeek makes with its users, stated in `docs/privacy.md`
("no analytics… no tracking") and `docs/v1.0-roadmap.md` ("Privacy Trust Must Be
Clear… privacy and security claims that match the code"). The moment we could
measure in-app behavior, the claim "your financial data never leaves your
machine" would carry an asterisk — and the entire local-first positioning in
`docs/strategy/pricing-and-launch.md` ("the only finance dashboard whose honest
answer to 'where is my data?' is 'on your Mac'") would be a lie. We accept blunt,
public, lagging metrics precisely so that the privacy claim stays
unconditional and true. The measurement blindness *is* the trust.

The accepted consequence: every metric in §2 is a **proxy**, every proxy is
**lagging**, and the funnel has a permanent hole in its middle. We compensate
with qualitative depth (support conversations, manual cohort notes) rather than
quantitative breadth, and we never close the hole by instrumenting the app.

## 4. Non-goals / red lines

These are not "things we are deferring." They are directions this plan exists to
**forbid**. Adopting any of them would require the same explicit
identity-change approval gate as the managed hosted footprint
(`docs/strategy/approval-gates.md`; `docs/v1.0-roadmap.md` "Resist"), plus a
rewrite of `docs/privacy.md`, `SECURITY.md`, and the README privacy claim — and
this plan recommends against all of them.

- **No in-app event tracking.** No counters, no funnels, no "screen viewed,"
  no button-tap logging — not in `PlaidBar`, not in `PlaidBarServer`, not in
  `PlaidBarCore`. Including the "anonymous" kind. The red line is **no
  phone-home at all**, not "no personally-identified phone-home." An anonymous
  beacon is still a beacon.
- **No financial-data collection or aggregates.** We never collect, transmit,
  or aggregate balances, transaction counts, account counts per user, net
  worth, spend totals, utilization, or any value derived from a user's
  finances — not even bucketed, hashed, or rounded. This is the strict reading
  of `docs/privacy.md`'s "What Does Not Leave Your Mac." Note that `/api/status`
  is already constrained to readiness metadata and is **local-only** behind
  `APITokenMiddleware` bound to `127.0.0.1` (`SECURITY.md`); nothing in this
  plan reads or forwards it off-device.
- **No silent analytics.** No analytics SDK, no behavioral logging that runs
  without the user's knowledge, no "improve the product" data path that defaults
  to on. There is no on/off toggle to add here because there is nothing to
  toggle.
- **No crash auto-upload without explicit, opt-in consent.** VaultPeek does not
  auto-upload crashes today and this plan does not add that. If a diagnostic
  report path is ever introduced, it must be explicit, opt-in, off by default,
  show the user exactly what would be sent, and be documented in `SECURITY.md`
  first — the same discipline `docs/strategy/consumer-experience-roadmap.md`
  applies to PDF export ("redacted by default… a preview of
  exactly what will be included; no automatic or background sharing paths").
- **No device or usage fingerprinting.** No install id, device id, hardware
  hash, IP-based geo, or "unique installs" counter generated by the app. The
  GitHub download count is a server-side artifact tally, not a client
  fingerprint, and that distinction is the whole reason it is allowed.
- **No third-party analytics SDKs.** No Firebase/GA/Amplitude/Mixpanel/Sentry
  auto-capture/PostHog/etc. linked into either executable. The dependency set
  stays as documented in `README.md` (Hummingbird, Fluent/SQLite, Sparkle for
  future updates) — no measurement dependency is added.
- **Nothing that phones home.** The companion server binds to `127.0.0.1` only
  (`SECURITY.md`); the only outbound network calls the product makes are to
  **Plaid**, only in sandbox/production mode, only for the operations
  enumerated in `docs/privacy.md` ("What Leaves Your Mac"). This plan adds zero
  new outbound calls.

### 4.1 Sources this plan deliberately does NOT use

- **Homebrew install analytics — NOT AVAILABLE.** The AND-396 scope mentions
  Homebrew analytics as a candidate source. It does not exist for VaultPeek:
  Homebrew distribution is **discontinued**. Per `docs/release.md`, "the public
  tap has been retired and `Formula/plaidbar.rb` removed"; per `README.md`,
  "Public Homebrew tap distribution has been discontinued." There is no tap,
  therefore no `brew install` events, therefore no Homebrew analytics to read.
  We state this explicitly rather than proposing a source that cannot return
  data. The DMG download count (§2.2) is the analogous adoption proxy.
- **App Store analytics — NOT AVAILABLE.** VaultPeek is distributed as a private
  DMG, not via the Mac App Store (`docs/release.md`;
  `docs/strategy/pricing-and-launch.md` keeps distribution direct). There is
  no App Store Connect funnel to read.
- **No in-app metric source — BY DESIGN.** Per §1 and §4, there is no
  product-side telemetry to draw from. Its absence is the plan's central
  constraint, not an oversight.

## 5. Operating cadence

A lightweight, mostly-manual rhythm — consistent with a privately distributed,
single-maintainer product:

- **Per release:** record release tag, DMG `download_count` baseline, and a note
  of which channels announced it. Snapshot GitHub traffic (14-day window) so it
  is not lost.
- **Weekly:** read stars / forks / watchers / traffic / open-issue and PR counts
  / label distribution from the GitHub API or Insights (read-only); tally
  support contact volume and topics; append manual cohort notes for any private
  distribution that occurred.
- **Per triage:** classify new issues and support topics into the active
  Horizon (`docs/v1.0-roadmap.md`) they implicate; feed that into backlog
  prioritization (Linear team `AND`, per the repo's collaboration rules).

All collection is read-only against public/owner GitHub surfaces or
hand-recorded from explicit human contact. No automated pipeline touches a
user's machine, and no script in this plan runs inside the shipped product.

## 6. Acceptance check (AND-396)

> The plan does not require in-app tracking, financial data collection, or
> silent analytics.

Satisfied by construction:

- **No in-app tracking** — every §2 metric reads a public GitHub surface or
  explicit human contact; §4 forbids product-side instrumentation, including
  anonymous, as a red line. No code is added to `PlaidBar`, `PlaidBarServer`, or
  `PlaidBarCore`.
- **No financial-data collection** — §4 forbids collecting or aggregating any
  balance, transaction, or derived financial value; §3 documents that
  in-app/financial behavior is deliberately unknowable.
- **No silent analytics** — §4 forbids analytics SDKs and any default-on,
  unknown-to-the-user data path; §5's cadence is entirely read-only/manual and
  external to the product.

Consistency with `docs/privacy.md`, `SECURITY.md`, and the no-telemetry "Resist"
stance in `docs/v1.0-roadmap.md` is maintained throughout: this plan changes how
the *maintainer reads public signals*, and changes nothing about what the
*product does*.
