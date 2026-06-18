import AppKit
import PlaidBarCore

/// Draws the AND-485 signal glyph as a monochrome **template** `NSImage`, so the
/// menu bar tints it natively in light, dark, and increased-contrast modes (the
/// same `isTemplate = true` path a status-item icon uses). All meaning is in the
/// SHAPE — fill height for the value, a cap for over-threshold, a dashed/half
/// treatment for stale — never color, because template images cannot carry tint.
enum SignalGlyphImage {
    /// Menu-bar glyph metrics tuned to sit on the ~18pt status-item baseline.
    private static let size = NSSize(width: 16, height: 14)
    private static let barWidth: CGFloat = 4.5
    private static let barSpacing: CGFloat = 3
    private static let inset: CGFloat = 1.5

    /// Builds the template image for a render model. Returns `nil` for the empty
    /// model so the caller can fall back to the plain icon.
    static func make(model: SignalGlyphMeter.SignalGlyphRenderModel) -> NSImage? {
        guard !model.isEmpty else { return nil }

        let image = NSImage(size: size, flipped: false) { rect in
            draw(model: model, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(for: model)
        return image
    }

    /// A two-bar meter: a faint "track" bar and a filled "value" bar. The value
    /// bar's height encodes the magnitude; an over-threshold model adds a cap
    /// notch above the fill so severity reads without color.
    private static func draw(model: SignalGlyphMeter.SignalGlyphRenderModel, in rect: NSRect) {
        let usableHeight = rect.height - inset * 2
        let bottom = rect.minY + inset
        let leftX = rect.minX + inset
        let rightX = leftX + barWidth + barSpacing

        // Stale signals draw at a reduced alpha + half-height value bar so the
        // glyph reads as "dimmed/uncertain" — a shape+opacity cue, not a hue.
        let isStale = model.staleness == .stale
        let trackAlpha: CGFloat = isStale ? 0.18 : 0.28
        let valueAlpha: CGFloat = isStale ? 0.55 : 1.0
        let fill = CGFloat(model.fillFraction) * (isStale ? 0.5 : 1.0)

        // Track bar (left): a constant faint full-height bar for scale reference.
        NSColor.black.withAlphaComponent(trackAlpha).setFill()
        roundedBar(x: leftX, bottom: bottom, height: usableHeight).fill()

        // Value bar (right): height = fill fraction.
        let valueHeight = max(usableHeight * fill, 1)
        NSColor.black.withAlphaComponent(valueAlpha).setFill()
        roundedBar(x: rightX, bottom: bottom, height: valueHeight).fill()

        // Over-threshold cap: a short detached segment above the value bar, so
        // an over-limit signal is legible purely by shape in a monochrome bar.
        if model.severity == .overThreshold {
            let capHeight: CGFloat = 2
            let capBottom = min(bottom + valueHeight + 1.5, rect.maxY - capHeight - inset + capHeight)
            let capY = min(capBottom, rect.maxY - capHeight)
            let cap = NSBezierPath(
                roundedRect: NSRect(x: rightX, y: capY, width: barWidth, height: capHeight),
                xRadius: 1,
                yRadius: 1
            )
            NSColor.black.withAlphaComponent(valueAlpha).setFill()
            cap.fill()
        }
    }

    private static func roundedBar(x: CGFloat, bottom: CGFloat, height: CGFloat) -> NSBezierPath {
        NSBezierPath(
            roundedRect: NSRect(x: x, y: bottom, width: barWidth, height: height),
            xRadius: 1.5,
            yRadius: 1.5
        )
    }

    /// VoiceOver text for the glyph: conveys the same value+state the shape does,
    /// so the meter is not color- or sight-only.
    private static func accessibilityDescription(for model: SignalGlyphMeter.SignalGlyphRenderModel) -> String {
        let percent = Int((model.fillFraction * 100).rounded())
        let level = model.severity == .overThreshold ? "over threshold" : "within range"
        let stale = model.staleness == .stale ? ", data is stale" : ""
        return "Signal meter \(percent) percent, \(level)\(stale)"
    }
}
