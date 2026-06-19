# Risk Register — Window-First Migration

Likelihood (L) / Impact (I): Low / Med / High. Sourced from the archaeology
([03](03-archaeology.md)), architecture audit ([01](01-current-state-architecture.md)),
and platform research ([04](04-platform-research.md)).

| ID | Risk | L | I | Mitigation | Owner/Epic |
|----|------|---|---|------------|-----------|
| **R-01** | **Activation-policy thrash.** `.accessory↔.regular` is the most-repeatedly-patched area in repo history; window-primary changes its semantics and stale refcounting can strip the dock icon or wedge the window. | High | High | Window-primary *simplifies* this; replace the refcount coordinator with one tested `@MainActor` helper; integration test the accessory→regular→accessory cycle. | Epic 3 |
| **R-02** | **`AppState` decomposition overruns.** 4,213-LOC, ~67-prop, non-`Sendable` god object with hard single-surface flags; the split is the highest-uncertainty work. | Med | High | Decompose incrementally behind the flag; extract per-window `@Observable` nav/selection models first; keep `AppState` as a façade until callers migrate; lean on strict-concurrency CI to catch leaks. | Epic 2/3 |
| **R-03** | **Translucency host surgery regressions.** True read-through required abandoning the `MenuBarExtra` host for a non-opaque `NSWindow` + behind-window `NSVisualEffectView`; SwiftUI-native glass did *not* read through (C4 spike). | Med | Med | Reuse the already-shipped window vibrancy approach verbatim; do not re-attempt SwiftUI-only glass for read-through; snapshot-test appearance. | Epic 1/10 |
| **R-04** | **Appearance cascade / first-paint flash.** `NSApp.appearance` must be the single authoritative owner set before first paint or windows flash wrong theme. | Med | Med | Centralize appearance ownership in the shell scene init; assert in a launch test. | Epic 1 |
| **R-05** | **Doc/code divergence regenerates.** The next agent "reverts" window work citing stale "popover-primary" docs (this is *why* we are here). | High | High | Gate 0 updates all doctrine in lockstep; ADR-001 linked from CLAUDE.md/GOAL.md/decision log; no code epic before doctrine merges. | Gate 0 |
| **R-06** | **Glance re-bloat.** "Menu-bar-first" already eroded once; the reduced glance silently re-accretes workflows and VaultPeek becomes "a slower Copilot with a menu-bar icon," forfeiting the local-first+glanceable moat. | Med | High | Guardrail 1 (glance = read+route only) encoded as a contract doc + PR-review checklist; Epic 9 defines the allowed glance surface explicitly. | Epic 9 |
| **R-07** | **macOS 27 / WWDC26 API misuse.** Reorderable containers, toolbar-overflow, sectioned `@Query`, `ResultsObserver`/`HistoryObserver` are macOS 27 *beta* (June 2026); using them unguarded breaks the macOS 26 floor. | Med | High | macOS 26 "Tahoe" is the hard floor; gate every macOS 27 symbol behind `if #available(macOS 27,*)`; CI builds against the macOS 26 SDK. | All |
| **R-08** | **Accessibility degradation under Liquid Glass.** Custom translucency + charts can fail VoiceOver/Reduce-Transparency, blocking the Accessibility Nutrition Label claim. | Med | High | `reduceTransparency` solid fallback on every glass/`NSVisualEffectView` surface; `AXChartDescriptor` audio graph on every chart (already shipped for trend/donut/heatmap — extend coverage). | Epic 10/7 |
| **R-09** | **Parity gap at popover removal.** Removing the popover (Epic 9) before the window truly matches strands users mid-workflow. | Low | High | Dual-run behind a flag through Epics 1–8; Epic 9 gated on an explicit parity sign-off checklist. | Epic 9 |
| **R-10** | **Per-window state correctness.** UI filter/selection lives in view-level `@AppStorage` today, which cannot represent two windows with different selections. | Med | Med | Move selection/filter into `NavigationModel` scoped per window scene; test two simultaneous windows. | Epic 2 |
| **R-11** | **Widget/App-Group store contention.** Sharing the SwiftData store with the widget across an App Group can race the app's writes. | Low | Med | Read-only widget access to a snapshot; reuse the disposable read-model cache; document write ownership. | Epic 8 |
| **R-12** | **Scope creep into the security boundary.** A tempting "while we're here" change to the server/auth during UI work. | Low | High | ADR-001 explicitly fences Core + server + boundary out of scope; reject such changes in review. | All |
| **R-13** | **`openSettings()` from `.accessory` regression** reported on macOS 26. | Low | Med | Validate on hardware early in Epic 1; fall back to programmatic Settings window if needed. | Epic 1 |

## Top 3 to watch

1. **R-05 doc/code divergence** — the root cause of this whole exercise; fix at Gate 0 or the work gets reverted.
2. **R-01 activation-policy thrash** — historically the most fragile code; concentrated in Epic 3.
3. **R-06 glance re-bloat** — the strategic failure mode that quietly destroys the moat even if every epic "succeeds."
