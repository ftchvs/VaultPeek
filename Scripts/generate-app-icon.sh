#!/usr/bin/env bash
# Regenerate Sources/PlaidBar/Resources/AppIcon.icns from code.
#
# Draws the 1024px master with CoreGraphics (rounded-rect macOS icon,
# SemanticColors.brand blue gradient, white dollar glyph over a rising
# sparkline), then emits every iconset size via sips and packs the
# .icns with iconutil. No binary design sources required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_ICNS="$PROJECT_DIR/Sources/PlaidBar/Resources/AppIcon.icns"
WORK_DIR="$(mktemp -d /tmp/plaidbar-appicon.XXXXXX)"
MASTER_PNG="$WORK_DIR/master-1024.png"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

trap 'rm -rf "$WORK_DIR"' EXIT

swift - "$MASTER_PNG" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvas = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap rep")
}
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple icon grid: 824x824 rounded rect centered on a 1024 canvas.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

// SemanticColors.brand is system blue; gradient keeps it recognizably so.
let topBlue = NSColor(calibratedRed: 0.36, green: 0.67, blue: 1.00, alpha: 1.0)
let bottomBlue = NSColor(calibratedRed: 0.00, green: 0.40, blue: 0.90, alpha: 1.0)
NSGradient(starting: bottomBlue, ending: topBlue)?.draw(in: platePath, angle: 90)

platePath.addClip()

// Rising sparkline across the lower third — the "chart" half of the motif.
let line = NSBezierPath()
line.move(to: NSPoint(x: 60, y: 268))
line.line(to: NSPoint(x: 280, y: 352))
line.line(to: NSPoint(x: 452, y: 286))
line.line(to: NSPoint(x: 640, y: 430))
line.line(to: NSPoint(x: 800, y: 372))
line.line(to: NSPoint(x: 980, y: 520))

let area = line.copy() as! NSBezierPath
area.line(to: NSPoint(x: 980, y: 60))
area.line(to: NSPoint(x: 60, y: 60))
area.close()
NSColor(calibratedWhite: 1.0, alpha: 0.22).setFill()
area.fill()

line.lineWidth = 26
line.lineJoinStyle = .round
line.lineCapStyle = .round
NSColor(calibratedWhite: 1.0, alpha: 0.85).setStroke()
line.stroke()

// Dollar glyph — must stay legible at 16pt, so it dominates the plate.
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -10)

let glyph = "$" as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 580, weight: .bold),
    .foregroundColor: NSColor.white,
    .shadow: shadow,
]
let glyphSize = glyph.size(withAttributes: attributes)
glyph.draw(
    at: NSPoint(x: (CGFloat(canvas) - glyphSize.width) / 2,
                y: (CGFloat(canvas) - glyphSize.height) / 2 + 60),
    withAttributes: attributes
)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER_PNG" \
        --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER_PNG" \
        --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Wrote $OUTPUT_ICNS"
