# Launch QA Matrix

Launch-scoped companion to [`docs/qa-matrix.md`](qa-matrix.md). Where the general
QA matrix defines the full 1.0 release-candidate check surface (automated gates,
manual product/accessibility/visual/security QA, and the exit criteria), this
file is narrower: it enumerates the **end-to-end launch scenarios** a first-time
user actually walks through — fresh install, missing credentials, migrating from
PlaidBar, offline, restart/duplicate-instance, billing plan state, and the
Gatekeeper open path — and pins each to a concrete verification class.

This document **does not restate** the automated-gates table. Those gates
(`swift build`, strict-concurrency, `swift test`, `./Scripts/smoke-sandbox.sh`,
`./Scripts/verify-version-alignment.sh`, packaging/DMG validation, the release
aggregate, screenshots, appearance matrix) live in
[`docs/qa-matrix.md` → "Automated Gates"](qa-matrix.md#automated-gates) and are
the source of truth for them. Where a launch scenario is covered by one of those
gates, this matrix references it rather than redefining the command.

> **Honesty note — "create AND run" (AND-388).** This file **creates** the
> launch QA matrix and records what the agentic loop can verify on its own. It is
> not a record of a completed full pass. Full execution is blocked on inputs the
> loop does not hold: sandbox/production rows need Felipe's `PLAID_CLIENT_ID` /
> `PLAID_SECRET`; the Stripe/billing row is gated and unbuilt (AND-393); and the
> Gatekeeper-clean and clean-machine rows are manual, on hardware. Every row's
> **Verification class** column says exactly which of those applies. Do not read
> a green-looking row as "passed on a real launch build" unless a dated pass log
> (see "Evidence to attach per pass") backs it.

## Verification classes

| Class | Meaning |
|-------|---------|
| `Automatable` | A gate or unit test already covers the behavior, or could in CI, with no creds and no human. |
| `Demo-runnable now` | The loop can exercise it via `swift run PlaidBar --demo` / `swift build` / `swift test` with no Plaid creds, no server credentials, no human. |
| `Needs Plaid creds` | Requires Felipe's `PLAID_CLIENT_ID` / `PLAID_SECRET` (sandbox or production). The loop cannot perform it. |
| `Needs Stripe (gated)` | Billing is not implemented (AND-393). Cannot be verified; behavior must not be asserted. |
| `Manual on clean machine` | Requires a human on real hardware / a fresh macOS profile (Gatekeeper, drag-install, on-screen translucency). |

---

## Launch scenarios

### 1. Fresh install → sandbox path → first money snapshot

| Field | Detail |
|-------|--------|
| **Precondition** | Clean data dir (no `~/.vaultpeek/`, no `~/.plaidbar/`); sandbox `PLAID_CLIENT_ID` / `PLAID_SECRET` exported. |
| **Steps** | `export PLAID_CLIENT_ID=… PLAID_SECRET=…` → `./Scripts/run.sh --sandbox` → open the menu bar popover → complete Plaid Hosted Link in the browser → return → **Check Connection**. |
| **Expected result** | `run.sh` reports `Server ready: sandbox | … | credentials ready`; setup preflight shows server online + sandbox + credentials present; Plaid Link opens; after return, the app verifies the linked item, loads accounts, runs a transaction sync, and opens the dashboard with the first balances/activity (matches `qa-matrix.md` "Sandbox setup" / "Sandbox return"). A fresh `~/.vaultpeek/` is created with `0700` dir / `0600` files and a `plaidbar-sandbox.sqlite` store. |
| **How to verify** | Structural half (server boot, auth-gating, `/api/status` contract, `0700`/`0600` perms, restart recovery, credential-less setup state) is exactly what `./Scripts/smoke-sandbox.sh` asserts headlessly — run it. The interactive Link → dashboard half is the manual product flow in `qa-matrix.md`. |
| **Verification class** | `Needs Plaid creds` (smoke + interactive both require sandbox creds). The `/api/status` key contract and auth-gating sub-checks are also `Automatable` via the contract test (see `qa-matrix.md` "Status contract test"). |

### 2. Fresh install → production credentials missing → readable blocked state

| Field | Detail |
|-------|--------|
| **Precondition** | Clean data dir; **no** `PLAID_CLIENT_ID` / `PLAID_SECRET` (or only one set — e.g. `PLAID_CLIENT_ID` present, `PLAID_SECRET` blank). |
| **Steps** | Launch the server credential-less (`PlaidBarServer` in a clean data dir), open the app, attempt to reach a Plaid-backed surface. |
| **Expected result** | Server boots into **setup state**, not a crash: `/health` and `/api/status` stay up; `/api/status` reports `credentialsConfigured=false`; Plaid-backed routes return **HTTP 503** whose body names the missing variable(s) (`PLAID_CLIENT_ID`, `PLAID_SECRET`, or the single one missing). App preflight shows a readable "missing credentials" block, not a generic failure (matches `qa-matrix.md` "Missing credentials"; troubleshooting "Production Mode Reports Missing Credentials (503)"). |
| **How to verify** | `./Scripts/smoke-sandbox.sh` already boots a second server credential-less in an isolated data dir and asserts: reachable `/health` + `/api/status`, `credentialsConfigured=false`, a `503` on `/api/accounts`, and that the body names both `PLAID_CLIENT_ID` and `PLAID_SECRET`. The partial-credential single-variable message is described in troubleshooting; the app-side readable block is the manual preflight check. |
| **Verification class** | `Automatable` for the server-side setup-state contract (covered by `smoke-sandbox.sh`, which itself runs credential-less so no real creds are needed for *this* half). App preflight presentation is `Demo-runnable now`-adjacent but the true production-mode wording check is a manual product-QA pass. |

### 3. Existing PlaidBar data → VaultPeek migration (`~/.plaidbar/` → `~/.vaultpeek/`) → local data intact

| Field | Detail |
|-------|--------|
| **Precondition** | A populated `~/.plaidbar/` (auth-token, `server.conf`, `plaidbar-*.sqlite` + sidecars, account/transaction caches, pending-link sessions, `server.log`); `~/.vaultpeek/` absent or partially present. |
| **Steps** | Launch VaultPeek (app or server) with default data dir. On startup `LocalDataStore.prepareStorageDirectory` → `migrateLegacyDefaultStorageIfNeeded` runs. |
| **Expected result** | Missing files are **copied forward** from `~/.plaidbar/` into `~/.vaultpeek/`; any file that already exists in `~/.vaultpeek/` is **preserved and never overwritten**; `~/.plaidbar/` is left in place for rollback. Path-scoped account/transaction caches are **remapped** so their stored `storagePath` points at `~/.vaultpeek/`. SQLite sidecars (`-wal`/`-shm`/`-journal`) stay with their owning database. Keychain Plaid access tokens keep service `PlaidBar.PlaidAccessToken`, so SQLite `keychain:<item_id>` references stay valid. If a prior local reset wrote the `.legacy-migration-reset` marker, reset-eligible legacy data is **not** copied back. Copied files land at `0700` dir / `0600` files. (Matches `qa-matrix.md` Security "Legacy storage migration"; troubleshooting "Default Storage Did Not Migrate".) |
| **How to verify** | Unit tests in `Tests/PlaidBarCoreTests/PlaidBarCoreTests.swift` exercise exactly this: copies legacy files without overwriting current data, remaps path-scoped caches, does not restore reset-cleared legacy data, keeps SQLite sidecars with their owning database, plus the reset tests. Code: `Sources/PlaidBarCore/Utilities/LocalDataStore.swift` (`migrateLegacyDefaultStorageIfNeeded`, `writeLegacyMigrationResetMarker`, `remappedLegacyContext`). |
| **Verification class** | `Automatable` (run `swift test --filter PlaidBarCoreTests`). A real on-disk migration with a populated legacy dir is a `Manual on clean machine` confirmation but the behavior contract is fully unit-covered. |

### 4. Offline launch with cached data

| Field | Detail |
|-------|--------|
| **Precondition** | A prior sandbox/production session has written account/transaction caches into the data dir; on this launch the local server is unreachable (down, wrong port, or Plaid unreachable). |
| **Steps** | Launch the app while the server is offline; observe the dashboard and Status surface. |
| **Expected result** | The app does not blank out: surfaces with cached content keep rendering it (`hasContent(for:)` drives the per-surface load presenter), while empty surfaces show skeletons during the first in-flight fetch rather than premature "offline/empty" copy. Status maps the unreachable server to an `.offline` recovery presentation with a readable explanation and one primary recovery action (matches `qa-matrix.md` "Server offline"; troubleshooting "App Says Server Is Offline"). Demo mode is unaffected — it loads fixtures synchronously and never depends on the server. |
| **How to verify** | The recovery-state mapping is pure logic in `PlaidBarCore` (`ServerConnectionPresentation.evaluate`, `DashboardLoadState.evaluate`) called from `AppState` — covered by unit tests over those presenters. The cached-render-while-offline behavior is best shown live: demo mode proves the no-server rendering path now; the cached-then-offline transition with real cached data needs creds to have populated the cache first. |
| **Verification class** | `Demo-runnable now` for the no-server rendering and recovery-copy structure; the cache-populated-then-offline transition is `Needs Plaid creds` to set up the cache. Presenter logic is `Automatable`. |

### 5. Server restart / app restart / duplicate-instance guard

| Field | Detail |
|-------|--------|
| **Precondition** | A running VaultPeek app + server in the same data dir. |
| **Steps** | (a) Restart the **server** under the app while keeping the same data dir. (b) Restart the **app**. (c) Launch a **second** server/app instance (or leave a legacy `PlaidBar.app` installed) contending for the same default port 8484. |
| **Expected result** | (a) After a server restart the auth-token is **unchanged** (the app holds it across restarts) and `/api/status` reports the **same** `environment`, `storagePath`, `itemCount`, `syncedItemCount`. The bundled server is reparent-watchdogged: if the app dies the app-managed server shuts itself down (`startParentWatchdog` in `Sources/PlaidBarServer/App.swift`), so a crashed app never orphans a server holding token access. (b) `ServerProcessService` only ever manages a server it spawned, probes `/health` before deciding to spawn, and leaves an externally started server alone — so an app restart re-attaches without double-launching. (c) Duplicate/legacy instances on the same port conflict; the documented resolution is to quit the duplicate VaultPeek processes and quit+delete any legacy `PlaidBar.app` (same bundle id + port 8484). (Matches troubleshooting "App Says Server Is Offline" duplicate/legacy section; support-runbook §3 "Duplicate / legacy instance conflicts".) |
| **How to verify** | `./Scripts/smoke-sandbox.sh` directly asserts the server-restart-recovery contract: it kills and reboots the server against the same data dir and checks the auth-token is identical and the status fields are preserved. App-restart re-attach and the spawn-only-mine / `/health`-probe logic are in `ServerProcessService.swift`. The duplicate/legacy-instance conflict is a manual reproduction (it depends on two installed bundles / two processes). |
| **Verification class** | `Needs Plaid creds` for the smoke-driven restart-recovery assertion (smoke needs sandbox creds). The watchdog and spawn-guard logic are `Automatable`/code-inspectable. The duplicate-instance / legacy-app conflict is `Manual on clean machine`. |

### 6. Stripe plan state changes (free / Plus / Managed / canceled / expired)

| Field | Detail |
|-------|--------|
| **Precondition** | — |
| **Steps** | — |
| **Expected result** | **TBD — billing is not implemented (AND-393).** There is no Stripe integration, no charging, and no subscription enforcement in the product today. The in-app plan picker is a **preview only**: selecting a plan charges nothing, grants nothing, and changes no behavior (per `docs/privacy.md` "Managed Bank Linking (Planned — Not Yet Available)" and `docs/support-runbook.md` §2). Every connection today is bring-your-own Plaid keys or demo data. **Do not assert or test free/Plus/Managed/canceled/expired transitions, refund windows, or entitlement gating — none of that behavior exists.** |
| **How to verify** | Not verifiable. When billing lands (AND-393), this row must be rewritten with the real plan-state transitions, entitlement checks, and refund/cancellation handling, and re-classed. Until then the only true claim is "no billing exists." |
| **Verification class** | `Needs Stripe (gated)` — gated and unbuilt; behavior intentionally **not** asserted. |

### 7. Gatekeeper / app open path (ad-hoc-signed → right-click → Open; notarization deferred)

| Field | Detail |
|-------|--------|
| **Precondition** | A packaged DMG built by `Scripts/package-dmg.sh` (ad-hoc-signed, **not** notarized, no Developer ID), downloaded over a browser so the quarantine bit is set, on a Mac that has never run a dev build. |
| **Steps** | Open the DMG → drag `VaultPeek.app` to Applications → first launch. A plain double-click is expected to be blocked by Gatekeeper; the one-time workaround is **right-click (Control-click) → Open**, then confirm. After the first time it opens normally. |
| **Expected result** | First launch requires right-click → Open (ad-hoc-signed build). After confirming, the menu bar item appears, demo mode renders, the bundled server starts, and `~/.vaultpeek/` is created with private permissions. Release notes / README / About must say "ad-hoc signed, right-click → Open" and must **not** claim "notarized" (per `docs/release.md` and `docs/distribution.md` "What May Be Claimed, When" — notarization/Developer ID/Sparkle are PREP ONLY, not performed). |
| **How to verify** | Bundle/DMG **structure** is gated automatically (`./Scripts/package-app.sh` + `./Scripts/validate-app-bundle.sh`, and `./Scripts/package-dmg.sh` for release candidates — see `qa-matrix.md` "App bundle / DMG package validation"). The actual Gatekeeper behavior and clean-machine open path are the manual procedure in `docs/distribution.md` "Gatekeeper Verification (clean machine, hard requirement)": `spctl --assess`, `stapler validate` (will not pass until notarized), then the human download → drag-install → launch pass. |
| **Verification class** | `Manual on clean machine` for the Gatekeeper open behavior. Bundle/DMG packaging validity is `Automatable` via the packaging gates. |

---

## What this run can verify autonomously vs what needs Felipe

The agentic loop **can** verify, with no credentials and no human:

- **Demo end-to-end** — `swift run PlaidBar --demo` renders the dashboard from fixtures with no Plaid, no server credentials, no network. Covers the no-server rendering path (scenario 4) and is the safe surface for UI/visual checks.
- **Build / strict-concurrency / tests** — `swift build`, the strict-concurrency build, and `swift test` (see `qa-matrix.md` automated gates).
- **Migration, reset-marker, no-overwrite, cache-remap, sidecar, Keychain-service behavior** — fully unit-covered in `Tests/PlaidBarCoreTests/PlaidBarCoreTests.swift` (scenario 3). Run `swift test --filter PlaidBarCoreTests`.
- **Recovery / load-state / status-contract presenters** — pure `PlaidBarCore` logic (offline mapping, per-surface skeleton-vs-content, `ServerStatus` key contract) is unit-testable (scenarios 2 app-side, 4).
- **Offline / restart *structure*** — `ServerProcessService` spawn-guard and the parent-watchdog are code-inspectable; the restart-recovery *contract* is asserted by `smoke-sandbox.sh` (but that script needs sandbox creds — see below).
- **Packaging validity** — bundle/DMG structure via the packaging gates (scenario 7 structural half).

The loop **cannot** complete and needs **Felipe**:

- **Sandbox rows (1, 2 server-live, 5 smoke)** — `./Scripts/run.sh --sandbox` and `./Scripts/smoke-sandbox.sh` both hard-require `PLAID_CLIENT_ID` / `PLAID_SECRET` (the scripts exit 1 without them). The interactive Link → dashboard flow needs a real sandbox session.
- **Production rows (2 production wording)** — requires production-approved Plaid creds.
- **Stripe / billing (6)** — `Needs Stripe (gated)`; not implemented (AND-393). Nothing to run.
- **Gatekeeper-clean and clean-machine (7, and the real on-disk migration in 3)** — a human on a fresh macOS profile / Retina hardware; plus the Reduce-Transparency and on-screen translucency halves of the visual matrix (see `qa-matrix.md` "Known limits of the headless path").

## Evidence to attach per pass

For each launch-QA pass, attach a short, **secret-free** evidence bundle (mirrors
`docs/support-runbook.md` §4 "DO ask for" and the `SECURITY.md` data-handling
boundaries — never include tokens, IDs, balances, or unredacted logs):

- **Build identity** — app version + build number (from `version.env` /
  `/api/status` `version`) and the commit SHA the pass ran against. A
  `./Scripts/verify-version-alignment.sh` line confirms version metadata is
  aligned.
- **Mode** — demo / sandbox / production, stated explicitly per row.
- **Command output** — the relevant gate output: `swift test` summary,
  `./Scripts/smoke-sandbox.sh` "passed" lines (it prints environment, item count,
  storage path, and the restart/setup-state confirmations — all secret-free),
  packaging/validation output.
- **Screenshots** — demo or sandbox data **only**; in-app error banners are safe
  because `UserFacingError.sanitizedDetail` already redacts tokens/IDs/balances.
  Never attach production screenshots with real balances.
- **`/api/status` described in words** — environment, item/synced counts, last
  sync, credentials y/n, sync-ready y/n. The endpoint is contractually
  secret-free (`ServerStatus`), so its JSON is safe to attach verbatim.
- **What was NOT run** — list the rows skipped for missing creds / gated billing
  / manual-on-hardware, so a reader never mistakes the pass for a full
  execution (see the "create AND run" honesty note above).

Per-pass results roll up against the Release Candidate Exit Criteria in
[`docs/qa-matrix.md`](qa-matrix.md#release-candidate-exit-criteria) and the final
gate set in `docs/release-checklist.md`.
