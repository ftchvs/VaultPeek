# Apple Docs Verification (via sosumi.ai)

Companion to [04-platform-research.md](04-platform-research.md). These are the
authoritative Apple Developer Documentation pages, retrieved through
**sosumi.ai** (an Apple-docs→markdown proxy; the `sosumi` MCP is not connected in
this workspace, so the pages were fetched over the web at `sosumi.ai/<path>`).
They confirm the recommended architecture and add a few specifics.

## MenuBarExtra — `sosumi.ai/documentation/swiftui/menubarextra`
- Generic scene `MenuBarExtra<Label, Content>`; inits `init(_:content:)`,
  `init(_:systemImage:content:)`, `init(_:isInserted:content:)`.
- `.window` style via `menuBarExtraStyle(.window)` → "a popover-like window from
  the menu bar icon." This is exactly the glance surface VaultPeek keeps.
- **Combines with `WindowGroup` in the same `@main` body** — confirms the hybrid
  scene graph (primary window + menu-bar glance) is the supported pattern.
- No-dock utility posture via `LSUIElement = true` (VaultPeek already does this;
  Epic 1/9 must keep it consistent with the activation-policy helper).
- Availability: **macOS 13.0+** (the scene type itself is not new to macOS 26).

## NavigationSplitView — `sosumi.ai/documentation/swiftui/navigationsplitview`
- **2-column:** `init(sidebar:detail:)`. **3-column:** `init(sidebar:content:detail:)`
  (first column drives second, second drives third). Directly validates the
  per-destination 2-col/3-col policy in [05-information-architecture.md](05-information-architecture.md).
- Programmatic column control: `init(columnVisibility:...)` with
  `NavigationSplitViewVisibility`; `init(preferredCompactColumn:...)` with
  `NavigationSplitViewColumn` for the collapsed/narrow case (use this for the
  screen-fallback ladder the old three-column popover contract needed).
- Roles: **Sidebar** (leading) · **Content** (middle, 3-col only) · **Detail**
  (trailing). Availability: **macOS 13.0+**.

## Adopting Liquid Glass — `sosumi.ai/documentation/technologyoverviews/adopting-liquid-glass`
- Apply to **navigation/chrome only**: "tab and sidebars float in this Liquid
  Glass layer to help people focus on the underlying content." Confirms guardrail 5
  / Epic 10 / risk **R-08**.
- Explicit warning against custom backgrounds on controls/data and against
  overuse — "overusing this material… can provide a subpar user experience."
- APIs: SwiftUI **`glassEffect(_:in:)`** + **`GlassEffectContainer`** (perf +
  morphing); UIKit `UIGlassEffect`; **AppKit `NSGlassEffectView`**. The AppKit
  symbol matters for VaultPeek — today it uses `NSVisualEffectView`; evaluate
  `NSGlassEffectView` where chrome is AppKit-hosted.
- Accessibility: the material adapts to **Reduce Transparency / Reduce Motion**;
  standard components adapt automatically, **custom elements must be tested**
  across those settings (R-08). VaultPeek's custom translucency = self-managed
  fallback required.

## Net effect on the plan
No changes to the recommendation. Three refinements folded into the epics:
1. The hybrid `MenuBarExtra + WindowGroup`/`Window` scene graph is Apple's
   documented pattern (Epic 1).
2. Use `preferredCompactColumn` (`NavigationSplitViewColumn`) for narrow-width
   collapse instead of bespoke overlay logic (Epic 2).
3. Consider `NSGlassEffectView` for AppKit-hosted chrome, alongside the SwiftUI
   `glassEffect`/`GlassEffectContainer` path (Epic 10).
