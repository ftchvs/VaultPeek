# VaultPeek Icon Review (Vault Mark)

Review of the VaultPeek app icon and menu-bar mark after adopting the
vault-dial brand glyph. The product is literally named **VaultPeek**, so the
vault is the on-brand mark — it ties the Dock/Finder icon to the name and to
the in-app "private, glanceable" promise. Updated 2026-06-18. Supersedes the
earlier rename-pass review that kept the `$`/sparkline icon.

## What the Icon Is Now

The app icon is built by `Scripts/generate-app-icon.sh` from a single master
asset, `Assets/app-icon-source.png` (a full-bleed 1024 px vault-door glyph,
white on black):

- The script bakes in a continuous-corner (squircle) mask at ~22.4% of the
  canvas — macOS does **not** round `.icns` corners for the Dock, so a
  full-bleed black plate would otherwise read as a hard square.
- It emits every iconset size via `sips` and packs
  `Sources/PlaidBar/Resources/AppIcon.icns` with `iconutil`.
- It also exports `Assets/app-icon.png` (a 512 px rounded preview) used as the
  README hero, so the repo's public face stays in lockstep with the shipped
  icon (replacing the old icons8 money-bag hotlink).

Two clarifications that still matter for this review:

1. **The menu bar does not show the app icon.** The menu bar item renders a
   monochrome glyph — an SF Symbol for most styles, or a code-drawn template
   image for the new Vault style (see `MenuBarLabel.swift` /
   `VaultMenuBarGlyph.swift`). Degraded states swap in fixed SF Symbols
   (`exclamationmark.triangle`, `network.slash`, `exclamationmark.octagon`).
   The app icon's small-size duty is the Dock, Finder, Launchpad, the DMG
   window, notification banners, and System Settings lists.
2. **The README hero is now the real icon.** It points at `Assets/app-icon.png`
   exported by the generator — no third-party image dependency.

## Fit With VaultPeek Positioning

| Criterion | Assessment |
|-----------|------------|
| Private/glanceable finance | Good fit. The vault dial reads as "your money, secured and local-first," which is exactly VaultPeek's promise — and unlike the prior `$`, it encodes the privacy story directly. |
| Name/mark coherence | Strong. The mark is the product name made literal; Dock recognition no longer depends on a generic `$`. |
| Avoids generic banking imagery | Yes. No bank columns, piggy bank, or coin stacks. |
| Crypto-vault connotation | Accepted, deliberately. The earlier review avoided a vault to keep distance from HashiCorp Vault / crypto-custody imagery. With the product named VaultPeek, the vault is now the intended brand association, not a cliché to dodge. Distance from HashiCorp Vault is carried by name/positioning, not by avoiding the shape. |
| Native macOS feel | Good. Full-bleed dark plate with a baked-in squircle mask matches modern dark app icons; the glyph keeps generous internal margin. |
| Plaid/PlaidBar baggage | None. The mark never referenced Plaid's brand or the PlaidBar wordmark. |

## Small-Size and Contrast Check (Honest)

- **App icon at 16 px:** the vault is a high-contrast white silhouette on a
  black plate, so it survives downscaling far better than the prior thin `$`
  stem and ~0.4 px sparkline. The concentric rings and bolt dots blur together
  below ~32 px, degrading to a recognizable "white disc/dial on black" — an
  acceptable, still-distinct degradation. Treat the fine ring detail as
  decorative at the smallest sizes, not as a carrier of meaning.
- **Menu-bar Vault glyph:** deliberately a **bolder, simplified** vault than the
  app icon — a thick door ring plus a four-spoke wheel handle, drawn to read at
  the ~16 pt menu-bar size where the app icon's bolts and concentric rings would
  dissolve. It is a template image, so the menu bar tints it like an SF Symbol
  in light, dark, and increased-contrast menu bars and over dynamic wallpapers.
  State is still carried by glyph shape + attention text, never color: the
  degraded SF Symbol ladder overrides the Vault mark.
- **Contrast:** white-on-black is maximal contrast in both light and dark Dock
  contexts. WCAG text ratios do not formally apply to app icons, but the mark
  clears the bar trivially.

## Recommendation: Adopt

Adopt the vault mark. It matches VaultPeek's name and positioning better than
the prior `$`/sparkline, encodes the privacy story directly, survives small
sizes via a bold high-contrast silhouette, carries no Plaid/PlaidBar baggage,
and remains reproducible from a single committed master via
`Scripts/generate-app-icon.sh`.

### What Would Trigger Revisiting

- Public or paid distribution at scale (App Store presence, marketing site) —
  worth professional icon work and a custom SF Symbol export for the menu bar
  at that point.
- Evidence the vault reads as crypto-custody to target users rather than
  "private personal finance."
- macOS icon-style guidance changes (e.g., broader Liquid Glass icon
  treatments) that make a flat dark plate look dated next to system apps.

## Menu Bar Icon Styles (AND-377)

Settings → Menu bar exposes a **Menu bar icon** preference that changes only the
healthy/default glyph, via `MenuBarIconStyle` (PlaidBarCore). All styles render
monochrome and template-style so they stay non-color-only:

| Style | Healthy glyph | Source |
|-------|---------------|--------|
| Dollar (default) | `dollarsign.circle` | SF Symbol |
| Minimal | `centsign.circle` | SF Symbol |
| Chart | `chart.line.uptrend.xyaxis.circle` | SF Symbol |
| Vault | vault-dial mark | Code-drawn template image (`VaultMenuBarGlyph`) |

The degraded-state ladder (`exclamationmark.octagon` error, `network.slash`
offline, `exclamationmark.triangle` warning/login/stale) is fixed and overrides
the chosen style, so state is always carried by glyph shape + attention text,
never by the icon style or color.

**Why the Vault style is a code-drawn template, not an SF Symbol or bundled
asset.** There is no vault SF Symbol, and the app target has no SPM resource
bundle (packaging copies resources by hand), so bundling an asset catalog would
mean build + packaging changes. A code-drawn `NSImage` with `isTemplate = true`
inherits native menu-bar tinting (light/dark/high-contrast/wallpaper) with no
bundle, and `MenuBarStatusPresentation` signals it via a sentinel
(`MenuBarIconStyle.customGlyphToken`) that is never passed to
`Image(systemName:)`. A full-color menu-bar mark remains rejected: macOS menu
bar items are template images, and a forced colored glyph risks contrast
failures against dynamic materials and must never be the sole status signal.
