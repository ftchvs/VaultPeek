import AppKit
import PlaidBarCore

/// The VaultPeek menu-bar mark for `MenuBarIconStyle.vault`, drawn in code as a
/// monochrome **template** `NSImage` so it inherits native menu-bar rendering —
/// it tints correctly in light, dark, and increased-contrast menu bars and
/// against dynamic wallpapers, exactly like an SF Symbol. There is no vault SF
/// Symbol, and bundling an asset would mean an SPM resource bundle + packaging
/// changes; a code-drawn template avoids both while staying fully accessible.
///
/// SF Symbols 7 review (AND-514, macOS 26 catalog, 8302 symbols audited
/// 2026-06-18): the catalog still ships no `safe`/`vault`/`strongbox` glyph.
/// The nearest neighbours — `lock`, `lock.shield`, `shield`,
/// `building.columns`, `banknote`, `dial.*` — read as a padlock, a bank
/// building, a banknote, or a dial, none of which depict the vault-dial mark
/// that ties the menu bar to the app icon. A padlock would also collide with
/// the degraded login/auth glyph ladder. No strong (or even weak) match
/// exists, so the custom template is kept deliberately rather than forced onto
/// an off-brand system symbol. Re-audit when SF Symbols ships a safe/vault
/// glyph; switching `MenuBarIconStyle.vault` to a system symbol would then let
/// this type be deprecated and the bespoke drawing deleted.
///
/// The shape is a deliberately bolder, simplified vault dial than the app icon:
/// a thick door ring plus a four-spoke wheel handle, sized to read at the ~16pt
/// menu-bar glyph size where fine detail (bolts, concentric rings) would
/// dissolve. State is still never carried by color alone — the degraded glyph
/// ladder (SF Symbols) overrides this mark, per the menu-bar status rules.
///
/// `@MainActor`-isolated because it caches and vends `NSImage`, a non-`Sendable`
/// AppKit class; the only callers are main-actor SwiftUI views, so isolating the
/// glyph API keeps the cached image out of shared global state and satisfies the
/// strict-concurrency build gate.
@MainActor
enum VaultMenuBarGlyph {
    /// Default glyph height, matched to the SF Symbol menu-bar glyphs it sits
    /// beside in `MenuBarLabel`.
    static let defaultPointSize: CGFloat = 16

    /// A cached template image at the default size. Cached because the menu-bar
    /// label rebuilds on every status change and the geometry never varies.
    static let image: NSImage = makeImage(pointSize: defaultPointSize)

    /// Draws the vault-dial glyph at the requested point size. Template images
    /// are resolution-independent, so the single drawing handler serves every
    /// backing scale the menu bar requests.
    static func makeImage(pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VaultPeek"
        return image
    }

    private static func draw(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        NSColor.black.set() // Template: actual tint is applied by the menu bar.

        // Door ring — the dominant shape that reads as a safe/vault at a glance.
        let ringLineWidth = side * 0.11
        let ringRadius = side * 0.40 - ringLineWidth / 2
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        ring.lineWidth = ringLineWidth
        ring.stroke()

        // Central hub of the handle.
        let hubRadius = side * 0.10
        NSBezierPath(ovalIn: NSRect(
            x: center.x - hubRadius,
            y: center.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        )).fill()

        // Four spokes radiating from the hub — the vault wheel handle. Drawn at
        // 45° offsets so they sit clear of the (invisible at this size) ring
        // gaps and stay symmetric.
        let spokeWidth = side * 0.085
        let spokeInner = hubRadius * 0.6
        let spokeOuter = side * 0.30
        for step in 0 ..< 4 {
            let angle = CGFloat(step) * (.pi / 2) + (.pi / 4)
            let dx = cos(angle)
            let dy = sin(angle)
            let spoke = NSBezierPath()
            spoke.move(to: NSPoint(x: center.x + dx * spokeInner,
                                   y: center.y + dy * spokeInner))
            spoke.line(to: NSPoint(x: center.x + dx * spokeOuter,
                                   y: center.y + dy * spokeOuter))
            spoke.lineWidth = spokeWidth
            spoke.lineCapStyle = .round
            spoke.stroke()
        }
    }
}
