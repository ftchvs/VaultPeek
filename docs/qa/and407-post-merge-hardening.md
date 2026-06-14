# AND-407 — Post-merge hardening evidence

**Linear:** [AND-407](https://linear.app/andeslab/issue/AND-407) · parent epic
[AND-386](https://linear.app/andeslab/issue/AND-386) · **Run: 2026-06-14**

Post-merge hardening pass over the behaviors shipped by PR #351 (Hosted Link fix
+ detachable dashboard + consumer-prod foundation), #352 (pre-push gate), and
#354 (transaction sync unknown `item_id` → 404). No real Plaid secrets, tokens,
payloads, account IDs, balances, or screenshots are recorded here.

## 1. Repo state

| Check | Result |
|---|---|
| `origin/main` HEAD | `1a35430a208bc386872be88451b2e92815d0f56b` — the #354 merge commit ✅ |
| Open PlaidBar PRs (`gh pr list --state open`) | none ✅ |

## 2. Repo-native local gates

| Gate | Command | Result |
|---|---|---|
| Secret/strict-build gate self-test | `./Scripts/pre-push-gate.sh --selftest` | **PASS** (positives detected, no false positives) |
| Strict-concurrency build | `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` | **Build complete!** (clean, no warnings-as-errors) |
| Test suite | `swift test` | **670 tests passed**, 0 failures |

> Note: the gates must run outside the command sandbox — SwiftPM's nested
> `sandbox-exec` fails with `sandbox_apply: Operation not permitted` inside it.
> This is an environment constraint, not a code issue.

## 3. Hosted Link regression (PR #351)

- **Live sandbox preflight** (`./Scripts/smoke-sandbox.sh`, sandbox creds from
  `~/.vaultpeek/server.conf`): **PASS** — server boots on `127.0.0.1`,
  `/health` OK, unauthenticated `/api` rejected, `/api/status` returns
  `environment=sandbox`, items=0, isolated temp data dir. No redirect-uri 500.
- **Restart recovery:** **PASS** — same auth token and readiness state after
  restart against the same data dir.
- **Fail-closed setup state:** **PASS** — a credential-less server boots, reports
  `credentialsConfigured=false`, and Plaid-backed routes 503 naming the missing
  `PLAID_CLIENT_ID`/`PLAID_SECRET`. This is the evidence that the
  production/managed-bank-link foundation **remains fail-closed** until provider
  credentials are explicitly configured.
- **Named regression tests** (green in §2): `LinkTokenRequestTests` —
  *"Create link-token body omits redirect_uri but keeps hosted_link"*,
  *"Update link-token body omits redirect_uri and includes access_token"*,
  *"Explicit redirectUri still encodes (non-Hosted-Link callers)"*;
  `ConsumerFoundationTests` — *"Entitlement evaluation allows even in
  .hostedBridge mode (inert)"*, *"Hosted-bridge deployment selects the inert
  request-supplied stub"*. These directly guard the #351 500 fix.

## 4. Transaction sync error UX (PR #354)

The unknown-explicit-`item_id` → 404 and empty-store → 200 behaviors shipped in
#354 with their own server tests, all green in the §2 run (`PlaidBarServerTests`,
`Token and storage safety` suite). Token/payload/path leakage is guarded by the
`Token and storage safety` suite and *"An unknown code … collapses to
PLAID_ERROR, never echoed."*

## 5. Detachable dashboard (PR #351) — partial

- **Code present and compiling** (§2 strict build): `DetachedDashboardCoordinator`,
  `DetachedDashboardWindowController`, `DetachedDashboardPreferences`,
  `DashboardPresentation`, `PopoverGeometry`.
- **Green suites:** *"Three-column popover geometry"*, *"Popover transparency
  presets"*, *"Menu bar icon style"*.

**Remaining manual verification (interactive macOS session required):** detach
from popover, drag across desktop, app-switch survival, menu-bar item raises the
panel, re-dock, Escape/keyboard behavior, Reduce Motion behavior, and the
no-color-alone finance/risk check. This hands-on pass was **not** performed in
this automated session, so **AND-384 is left In Review** (not reconciled to Done)
pending that interactive pass.

## Outcome

Automated hardening pass is **clean**: repo state verified, all local gates
green, Hosted Link / setup-state / restart behaviors verified live in sandbox,
sync-error and token-safety behaviors covered by green tests. The only residual
is the hands-on detached-window GUI pass (AND-384).
