# Release-Candidate Checklist

The final gate set before tagging a release. Every item must be checked, with a
documented exception where noted, before `./Scripts/release.sh --publish` runs.
`docs/qa-matrix.md` holds the detailed scenario tables this checklist points
at; `docs/release.md` holds the runbook ordering; `docs/distribution.md` holds
the (not yet performed) signing and notarization runbook.

## Version And Tag Hygiene

- [ ] `./Scripts/verify-version-alignment.sh` passes (`version.env`,
  `Info.plist`, and `PlaidBarConstants.appVersion` agree).
- [ ] The target tag `v<VERSION>` does not already exist locally or on origin
  (`Scripts/release.sh` enforces both).
- [ ] `docs/release-notes.md` has a curated section for this version that
  describes only shipped behavior and explicitly lists deferred work.
- [ ] No doc, About copy, or release note claims notarization, appcast, or
  public distribution properties that have not been verified end to end.

## Build And Test Gates

- [ ] `git diff --check` is clean.
- [ ] `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --disable-keychain` passes.
- [ ] `swift build -c release --disable-keychain` passes.
- [ ] `swift test --skip-update --disable-keychain` passes locally, or the
  toolchain exception below is documented in the release-prep PR.
- [ ] `bash -n Scripts/*.sh Scripts/plaidbar-run` passes.
- [ ] GitHub CI is green on the release-prep PR head SHA.

### Known Toolchain Baseline (recorded 2026-06-12)

- The package requires `swift-tools-version: 6.0`. Targets compile in Swift 5
  language mode under the Swift 6 toolchain with strict concurrency complete.
- CI is the canonical baseline: GitHub Actions `macos-15` runner with
  `/Applications/Xcode_16.app` selected (Swift 6 toolchain). Local development
  machines may run newer toolchains (Swift 6.3.x has been verified to build
  and test); newer-toolchain success does not replace a green CI run on the
  pinned baseline.
- Some local toolchains fail `swift test` with `no such module 'Testing'`
  (Swift Testing interop missing). That failure mode is documented in
  `docs/troubleshooting.md`; `PLAIDBAR_RELEASE_SKIP_TESTS=1` exists in
  `Scripts/release.sh` only for that documented mismatch, and CI must still
  pass tests before publishing.
- `Package.swift` probes known Xcode/CLT paths for `lib_TestingInterop.dylib`
  to link Swift Testing; a toolchain outside those paths needs `DEVELOPER_DIR`
  set.

## Packaging And Distribution

- [ ] `./Scripts/package-dmg.sh` builds the DMG and `./Scripts/validate-app-bundle.sh`
  passes (binaries, icon, Info.plist keys, Sparkle rpath, signature verify).
- [ ] The DMG was opened and the app launched on a machine other than the build
  machine, including the documented right-click > Open first-launch step for
  the ad-hoc-signed build.
- [ ] Distribution claims match reality: privately distributed, ad-hoc-signed
  DMG. Developer ID signing, notarization, Gatekeeper-clean launch, and the
  Sparkle update channel remain deferred until `docs/distribution.md` is
  executed and verified.
- [ ] Release artifacts have recorded SHA-256 checksums.

## Privacy And Security

- [ ] Secret scan over the release diff and docs: no real Plaid credentials,
  access tokens, account IDs, transaction exports, or private keys.
- [ ] `/api/status` contract test passes: readiness metadata only, no secrets,
  no account identifiers, no balances.
- [ ] `/api/*` auth middleware tests pass (missing/invalid bearer rejected).
- [ ] Data directory and `auth-token` private-permission checks pass where the
  platform supports them.
- [ ] All screenshots, fixtures, examples, and docs use demo, sandbox, or
  synthetic data only.

## Accessibility

- [ ] Keyboard-only pass through setup, dashboard filters, account drill-in,
  refresh, reconnect, and settings (no pointer-only dead ends).
- [ ] VoiceOver spot-check on icon-only buttons, charts, and status surfaces.
- [ ] Balance, risk, utilization, error, and chart meaning never rely on color
  alone (text, icon, or shape backup present).
- [ ] Appearance matrix pass recorded in `docs/qa-matrix.md` (light/dark
  headless renders; Reduce Transparency halves need human eyes and must be
  marked honestly if not run).

## Clean-Profile Setup

- [ ] Sandbox setup succeeds from a clean temporary profile:
  `PLAIDBAR_DATA_DIR=$(mktemp -d) ./Scripts/run.sh --sandbox`.
- [ ] Production setup was checked from a clean profile (separate storage from
  sandbox, explicit Plaid production-approval copy), or the release-prep PR
  documents why production mode is out of scope for this release.

## Merge And Publish Gates

- [ ] All required GitHub checks are green on the exact head SHA before any
  merge attempt. A failing, pending, cancelled, missing, or ambiguous required
  check blocks merge — including infrastructure outages (a check that cannot
  run is not a green check).
- [ ] A human-readable safety pass of the final diff happened before merge:
  secrets, private financial data, generated artifacts, scope creep, and
  destructive behavior.
- [ ] `otto-openclaw-merge-gate` is green on the release-prep PR.
- [ ] Publish runs only from clean, up-to-date `main`:
  `./Scripts/release.sh --publish`.
- [ ] Rollback path is documented and the prior good tag/DMG is known
  (`docs/release.md` -> Rollback): the last clean `v<version>` and its verified
  `VaultPeek-<version>.dmg` checksum are identified before publishing.
- [ ] After publishing, the progress ledger and backlog checklist record the
  completed task IDs.
