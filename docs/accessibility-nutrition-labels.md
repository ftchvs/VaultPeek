# Accessibility Nutrition Labels — readiness (AND-571)

App Store **Accessibility Nutrition Labels** let an app declare, per platform, which
accessibility features it supports on its product page. Apple's published categories
are: **VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without
Color Alone, Sufficient Contrast, Reduced Motion, Captions, and Audio Descriptions**
(App Store Connect → *Manage app accessibility* → *Overview of Accessibility Nutrition
Labels*).

This document is the audit that maps each label to **evidence in the VaultPeek code**
plus the **gaps** that must close before the label can be declared. It is a readiness
pass, not a declaration — a label should only be turned on in App Store Connect after
the gaps below are closed and a human verifies the behavior on a physical Mac with the
matching system setting enabled.

VaultPeek is macOS-only, so only the **macOS** column of the label set applies. Every
claim here is grounded in a `file:line` reference at the time of writing (commit base
`c4ba485`); re-verify line numbers if the files have moved.

## Scope and ground rules

- **Audit honesty.** A feature is only "Ready" if the code genuinely implements it
  *and* it is reachable in primary flows. Where support is partial or unverified, it
  is marked **Partial** or **Gap**, never "Ready".
- **Manual confirmation still required.** Static evidence (a `@ScaledMetric`, a
  `reduceMotion` gate, an `accessibilityLabel`) proves the wiring exists. Apple's
  criteria are behavioral — they require a human running VoiceOver / Larger Text /
  Reduce Motion on a real display. The relevant manual rows already live in
  [`docs/qa-matrix.md`](qa-matrix.md) ("Accessibility QA", "macOS 26 Platform QA
  (AND-515)").
- **Never color alone.** All status meaning is carried by text and/or shape in
  addition to color — see [`ACCESSIBILITY.md`](../ACCESSIBILITY.md) and the
  per-label evidence below.
- **Synthetic data only** when capturing any verification evidence (screenshots,
  VoiceOver transcripts).

## Readiness summary

| Label (macOS) | Status | One-line rationale |
|---|---|---|
| VoiceOver | **Ready — pending manual pass** | Interactive controls, icon-only buttons, charts, the menu-bar status item, and the live signal glyph all carry explicit, color-free `accessibilityLabel`/value text. |
| Larger Text (Dynamic Type) | **Ready — pending manual pass** | Hero/balance figures scale via `@ScaledMetric(relativeTo:)`; all other type is built on semantic styles that scale automatically; tabular alignment preserved with `monospacedDigit()`. |
| Dark Interface | **Ready — pending manual pass** | Full light/dark support with a user Appearance override; menu-bar glyph is a template image that tints per appearance. |
| Differentiate Without Color Alone | **Ready — pending manual pass** | Status/severity/selection are carried by text + SF Symbol glyph + shape, never hue alone (signal glyph, category status, heatmap selection ring, donut legend glyphs). |
| Reduced Motion | **Ready — pending manual pass** | A single `MotionTokens.animation(_:reduceMotion:)` gate returns `nil` under Reduce Motion; the env value is read app-wide and threaded into the detached-window controller. |
| Sufficient Contrast | **Partial** | Increase-Contrast precedence is modeled and the system setting always wins, plus an in-app Contrast picker; **no measured WCAG contrast ratios captured yet** over Liquid Glass. Needs a human contrast pass before declaring. |
| Voice Control | **Partial / Gap** | Standard SwiftUI controls expose names automatically, but custom/icon-only controls have **no explicit `accessibilityInputLabels`** verified; needs a Voice Control pass. |
| Captions | **N/A** | No prerecorded audio or video content in the app. |
| Audio Descriptions | **N/A** | No prerecorded video content in the app. |

The two "N/A" labels are intentionally left undeclared — they apply to media content
the app does not ship.

---

## VoiceOver — Ready, pending manual pass

**Apple criterion (summary).** Users can navigate and operate the app with VoiceOver;
controls have meaningful labels; status is announced, not implied visually.

**Evidence.**
- Icon-only and custom controls carry explicit labels/values/hints across Settings and
  setup, e.g. `Sources/PlaidBar/Settings/SettingsView.swift:136,162,181,189,197,205`
  and `Sources/PlaidBar/Views/SetupView.swift:144,635,637`.
- The menu-bar status item folds the live signal-meter description into one parent
  label so the meter is never silent:
  `Sources/PlaidBar/Views/MenuBarLabel.swift:73,81` consuming
  `SignalGlyphMeter.SignalGlyphRenderModel.accessibilityDescription`
  (`Sources/PlaidBarCore/Utilities/SignalGlyphMeter.swift:80`).
- Charts expose a combined text summary as their label:
  `Sources/PlaidBar/Views/Charts/SpendDonutChart.swift:62`,
  `BalanceTrendChart.swift:54`, `ProjectedBalanceChart.swift:89`,
  `IncomeCategoryFlowChart.swift:45,155`.
- Presentation models centralize spoken copy in Core (testable, `Sendable`), e.g.
  `Sources/PlaidBarCore/Models/AttentionQueue.swift:88`,
  `WeeklyReview.swift:203`, `DashboardNavBarModel.swift:116`,
  `SpendingHeatmap.swift:303`, `AppLockPresentation.swift:218,231`.
- Privacy Mask / App Lock labels use generic hidden-value copy instead of reading raw
  masked balances — `Sources/PlaidBarCore/Utilities/StrongMaskFormatter.swift:191`,
  `Sources/PlaidBarCore/Models/AppLockPresentation.swift`; covered by
  `Tests/PlaidBarCoreTests/AppLockPresentationTests.swift`,
  `PrivacyMaskPresentationTests.swift`.

**Gaps to close before declaring.**
- Run the manual VoiceOver pass in `docs/qa-matrix.md` ("VoiceOver labels", "Focus
  states", inspector/row announcement rows) on a physical Mac and attach a transcript.
- Charts use a single summary label rather than an `AXChartDescriptor`
  (`accessibilityChartDescriptor`) — see the Sufficient Contrast / charts note in
  "Cross-cutting gaps". This does not block VoiceOver readiness (the summary is
  spoken) but is the natural next enhancement.

## Larger Text (Dynamic Type) — Ready, pending manual pass

**Apple criterion (summary).** Text scales with the user's preferred text size,
including the Accessibility text sizes, without truncating or clipping essential
content.

**Evidence.**
- Hero figures scale with `@ScaledMetric(relativeTo: .largeTitle)` rather than a fixed
  `.system(size:)`: `Sources/PlaidBar/Theme/Typography.swift:54,67`.
- They clamp to `.dynamicTypeSize(.xSmall ... .accessibility3)` to stop before the
  layout-breaking AX4/AX5 steps: `Typography.swift:59,72`.
- All other type is built on semantic styles (`.caption`, `.callout`, `.caption2`),
  which scale with Dynamic Type automatically: `Typography.swift:83,95,103,111`.
- `monospacedDigit()` is applied to the font value so numeric columns stay tabular at
  every size: `Typography.swift:58,71,95`.
- Manual row already exists: `docs/qa-matrix.md` "Dynamic Type (AND-515)".

**Gaps to close before declaring.**
- The Dynamic Type manual row in `docs/qa-matrix.md` must be executed up to AX3 on a
  physical display, confirming no critical row truncates or clips its value. The
  deliberate AX4/AX5 clamp should be documented in the App Store note (the app caps at
  AX3 for layout integrity), since reviewers may test the top steps.

## Dark Interface — Ready, pending manual pass

**Apple criterion (summary).** The app provides a dark appearance.

**Evidence.**
- Full forced light/dark plus follow-system, with a user-facing Appearance picker:
  `Sources/PlaidBarCore/Models/AppearancePreferences.swift:13` (`AppAppearanceMode`),
  applied via `Sources/PlaidBar/App/PlaidBarApp.swift:86,108,113` and the
  `forcedAppColorScheme` modifier.
- The menu-bar signal glyph is a **template** `NSImage` (`isTemplate = true`), so macOS
  tints it natively in light, dark, and increased-contrast menu bars:
  `Sources/PlaidBar/Views/SignalGlyphImage.swift:25`.
- Both appearances are exercised in screenshot/QA flows:
  `docs/qa-matrix.md` (Appearance picker rows, macOS 26 Platform QA).

**Gaps to close before declaring.**
- None blocking. Confirm with the existing light/dark screenshot pass that no surface
  is illegible in dark mode over Liquid Glass.

## Differentiate Without Color Alone — Ready, pending manual pass

**Apple criterion (summary).** Meaning conveyed with color is also available through
shape, text, or another non-color cue.

**Evidence.**
- Menu-bar signal glyph carries severity by **shape** (an over-threshold cap) and
  staleness by a dashed/half-height treatment — never hue, because template images
  cannot tint: `Sources/PlaidBarCore/Utilities/SignalGlyphMeter.swift:13-30`,
  rendered in `Sources/PlaidBar/Views/SignalGlyphImage.swift:33-69`. Covered by
  `Tests/PlaidBarCoreTests/SignalGlyphMeterTests.swift`.
- Category status pairs color with `statusText` + an SF Symbol `statusIconName`:
  `Sources/PlaidBar/Views/CategoryStatusBar.swift:60,63`; spoken description in
  `accessibilityDescription(spentText:limitText:)` at line 33. Covered by
  `Tests/PlaidBarCoreTests/CategoryStatusBarModelTests.swift`.
- Heatmap selection uses a **stroke ring** (not fill hue) that reads in both
  appearances: `Sources/PlaidBar/Views/MainPopover.swift:1203-1211`; cells expose
  date / count / value via text (`SpendingHeatmap.swift:303`).
- Spend donut legend pairs each color swatch with a distinct **SF Symbol glyph** plus
  text title and share: `Sources/PlaidBar/Views/Charts/SpendDonutChart.swift:82-93`
  ("Legend (glyph + text, color-independent)").
- Policy is enforced repo-wide via `ACCESSIBILITY.md` and the CLAUDE.md "never color
  alone" convention.

**Gaps to close before declaring.**
- None structural. The manual "color-independent review" row in `docs/qa-matrix.md`
  should be run with the system **Differentiate Without Color** setting enabled to
  confirm nothing regressed.

## Reduced Motion — Ready, pending manual pass

**Apple criterion (summary).** Non-essential motion is reduced or removed when Reduce
Motion is on.

**Evidence.**
- Single gate: `MotionTokens.animation(_:reduceMotion:)` returns `nil` under Reduce
  Motion so animated value changes become instant:
  `Sources/PlaidBar/Theme/DesignTokens.swift:160`.
- The env value is read at the app root and threaded into AppKit:
  `Sources/PlaidBar/App/PlaidBarApp.swift:25` (`@Environment(\.accessibilityReduceMotion)`),
  passed into `DetachedDashboardCoordinator`/`DetachedDashboardWindowController`
  (`DetachedDashboardWindowController.swift:95,118,134,137`), which also re-reads
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  (`DetachedDashboardCoordinator.swift:95`).
- Numeric "roll", chart reveal, symbol replace, scroll-edge depth, and composition-bar
  animations all route through the gate:
  `Sources/PlaidBar/Theme/Typography.swift:40`,
  `Sources/PlaidBar/Views/MenuBarLabel.swift:47,54`,
  `WealthSummaryFlyout.swift` (`scrollEdgeDepth`/`rollingTabularNumber`),
  `BalanceCompositionBar.swift:59-63`, `CategoryStatusBar.swift:46`.
- The decorative-effects model also resolves motion off when the system or user asks:
  `Sources/PlaidBarCore/Models/AppearancePreferences.swift:107-116`
  (system Reduce Motion always wins).

**Gaps to close before declaring.**
- Run a manual Reduce Motion pass (System Settings → Accessibility → Display → Reduce
  motion) across the menu bar, popover open, drill-ins, and the detached window; add a
  row to `docs/qa-matrix.md` if one is not already present.

## Sufficient Contrast — Partial

**Apple criterion (summary).** Text and meaningful UI meet sufficient contrast ratios,
and Increase Contrast is respected.

**Evidence (what exists).**
- Increase-Contrast precedence is modeled and the **system setting always wins**:
  `Sources/PlaidBarCore/Models/AppearancePreferences.swift:78-81`
  (`resolvedIncreasedContrast(systemIncreaseContrast:)`), tested in
  `Tests/PlaidBarCoreTests/AppearancePreferencesTests.swift`.
- In-app Contrast picker (`Follow System` / `Standard` / `Increased`):
  `Sources/PlaidBar/Settings/SettingsView.swift:183-189`; the app reads the live
  system value via `@Environment(\.colorSchemeContrast)` (`SettingsView.swift:79`).
- macOS 26 Platform QA already has an "Increase Contrast" manual row:
  `docs/qa-matrix.md` (AND-515 section) — borders/separators strengthen, text meets
  contrast over glass, focus rings stay visible.

**Why it is only Partial / gaps to close before declaring.**
- **No measured WCAG contrast ratios** have been captured for VaultPeek's text and
  controls, especially **over Liquid Glass / translucent material** where the
  effective background varies. Apple's criterion is a measured threshold, not just
  "we respect the setting."
- Action: capture contrast measurements (e.g. with the Accessibility Inspector's
  contrast tool / a contrast checker) for primary text, secondary text, and key
  controls in light and dark, both with Increase Contrast off and on, over the glass
  surface. Record pass/fail per surface here before declaring the label.

## Voice Control — Partial / Gap

**Apple criterion (summary).** Users can operate the app by speaking control names;
controls expose usable names for voice targeting.

**Evidence (what exists).**
- Standard SwiftUI controls (Buttons with text titles, Pickers, Toggles) expose their
  visible label to Voice Control automatically, and many controls also carry explicit
  `accessibilityLabel`/`accessibilityValue` (see the VoiceOver evidence above), which
  Voice Control can target.

**Why it is only Partial / gaps to close before declaring.**
- **No explicit `accessibilityInputLabels`** is set anywhere in the codebase
  (verified: zero matches). Icon-only / custom-drawn controls (e.g. the menu-bar
  status item, heatmap cells, glyph buttons) rely on their `accessibilityLabel` as the
  spoken name, which is usually long and descriptive ("Signal meter 42 percent, within
  range") — not an ideal short Voice Control phrase.
- Action: run a Voice Control pass ("Show names"), identify controls whose names are
  awkward to speak, and add concise `accessibilityInputLabels` where needed. This is an
  implementation follow-up (out of scope for this audit) — track as a sibling issue
  under epic AND-562.

## Captions — N/A

VaultPeek ships no prerecorded audio or video content, so there is nothing to caption.
Leave undeclared.

## Audio Descriptions — N/A

VaultPeek ships no prerecorded video content, so there is no need for audio
descriptions. Leave undeclared.

---

## Cross-cutting gaps (not label-specific)

- **Charts lack `AXChartDescriptor`.** Every Swift Charts surface exposes a single
  combined text `accessibilityLabel` summary, but none implements
  `accessibilityChartDescriptor` (`AXChartDescriptor` with categorical/numeric axes and
  data points), so VoiceOver users cannot navigate individual data points or use Audio
  Graphs. Files: `Sources/PlaidBar/Views/Charts/{SpendDonutChart,BalanceTrendChart,
  ProjectedBalanceChart,IncomeCategoryFlowChart,AccountRowSparkline}.swift`. This does
  not block VoiceOver readiness (the summary is spoken) but is the highest-value
  accessibility enhancement available and should be a sibling issue under AND-562.
- **No automated contrast assertion.** Contrast is verified only by the manual QA
  rows; there is no measured ratio recorded. See the Sufficient Contrast section.

## How to declare a label (process)

1. Close the gaps listed for the target label above.
2. Run the matching manual row(s) in [`docs/qa-matrix.md`](qa-matrix.md) on a physical
   Mac with the corresponding system setting enabled, using synthetic/sandbox data.
3. Record the result (and any measurements) back into this file.
4. Only then enable the label in **App Store Connect → Manage app accessibility**, per
   platform (macOS).

## References

- App Store Connect → *Manage app accessibility* → *Overview of Accessibility
  Nutrition Labels* (categories and per-feature evaluation criteria).
- [`ACCESSIBILITY.md`](../ACCESSIBILITY.md) — repo accessibility policy and reporting.
- [`docs/qa-matrix.md`](qa-matrix.md) — Accessibility QA + macOS 26 Platform QA
  (AND-515) manual rows.
- Related: AND-515 (macOS 26 accessibility QA, Done); parent epic AND-562.
</content>
</invoke>
