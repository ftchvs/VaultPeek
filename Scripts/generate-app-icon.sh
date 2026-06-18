#!/usr/bin/env bash
# Regenerate Sources/PlaidBar/Resources/AppIcon.icns from the VaultPeek master.
#
# The master art is Assets/app-icon-source.png — a full-bleed 1024px vault-door
# glyph (white on black), the literal VaultPeek mark. macOS does NOT round
# .icns corners for the Dock, so this script bakes in a continuous rounded
# (squircle) mask, then emits every iconset size via sips and packs the .icns
# with iconutil. It also exports Assets/app-icon.png (a 512px rounded preview)
# for the README hero, so the repo's public face matches the shipped icon.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_PNG="$PROJECT_DIR/Assets/app-icon-source.png"
OUTPUT_ICNS="$PROJECT_DIR/Sources/PlaidBar/Resources/AppIcon.icns"
README_PNG="$PROJECT_DIR/Assets/app-icon.png"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plaidbar-appicon.XXXXXX")"
MASTER_PNG="$WORK_DIR/master-1024.png"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -f "$SOURCE_PNG" ]; then
    echo "Missing icon master at $SOURCE_PNG" >&2
    exit 1
fi

swift - "$SOURCE_PNG" "$MASTER_PNG" <<'SWIFT'
import AppKit

let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let canvas = 1024

guard let source = NSImage(contentsOfFile: sourcePath) else {
    fatalError("Could not load icon master at \(sourcePath)")
}

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

// Full-bleed continuous-corner (squircle) mask. macOS app icons must bake in
// their own corners; ~22.4% of the canvas is the platform's rounded-rect
// radius, and `.continuous` style matches the system squircle silhouette so
// the dark plate doesn't read as a hard square in the Dock.
let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let radius = CGFloat(canvas) * 0.2237
let mask = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
mask.addClip()

// The master is already a finished full-bleed composition (white vault on a
// black field), so it fills the masked canvas 1:1 — only the corners change.
source.draw(in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue])

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

# README hero export — a rounded 512px preview kept in lockstep with the icon.
sips -z 512 512 "$MASTER_PNG" --out "$README_PNG" >/dev/null

echo "Wrote $OUTPUT_ICNS"
echo "Wrote $README_PNG"
