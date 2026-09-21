# Auteur : Martial Zinsou
#  KarenOS
#  Par Martial Zinsou

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p /tmp/karenos-icon
SRC="/tmp/karenos-icon/icon.swift"
cat > "$SRC" <<'EOF'
import AppKit

let size = 1024
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
) else { fatalError("ctx") }

// --- Squircle blanc (style icône Meta) ---
let bgPath = CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960),
                    cornerWidth: 215, cornerHeight: 215, transform: nil)
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(bgPath)
ctx.fillPath()

// --- Monogramme "K" en ruban : dégradé bleu -> cyan appliqué sur le tracé ---
let kPath = CGMutablePath()
kPath.move(to: CGPoint(x: 520, y: 224))                      // jambe (C vire 800)
kPath.addCurve(to: CGPoint(x: 500, y: 784),
               control1: CGPoint(x: 470, y: 404),
               control2: CGPoint(x: 470, y: 594))
kPath.move(to: CGPoint(x: 505, y: 554))                      // bras supérieur
kPath.addCurve(to: CGPoint(x: 800, y: 834),
               control1: CGPoint(x: 600, y: 644),
               control2: CGPoint(x: 680, y: 704))
kPath.move(to: CGPoint(x: 505, y: 504))                      // bras inférieur
kPath.addCurve(to: CGPoint(x: 830, y: 172),
               control1: CGPoint(x: 640, y: 384),
               control2: CGPoint(x: 740, y: 264))

let gradientColors = [
    NSColor(calibratedRed: 0.039, green: 0.506, blue: 1.0, alpha: 1).cgColor,    // #0A81FF
    NSColor(calibratedRed: 0.0,   green: 0.776, blue: 1.0, alpha: 1).cgColor,    // #00C6FF
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: gradientColors, locations: [0, 1])!

ctx.saveGState()
ctx.addPath(kPath)
ctx.setLineWidth(170)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: CGFloat(size)),
                       end: CGPoint(x: CGFloat(size), y: 0),
                       options: [])
ctx.restoreGState()

// --- Export ---
let out = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: out)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "/tmp/karenos-icon/KarenOS-1024.png"))
print("icon 1024 généré")
EOF
swift "$SRC"

ICONSET=/tmp/karenos-icon/KarenOS.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16   /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32   /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32   /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64   /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 /tmp/karenos-icon/KarenOS-1024.png --out "$ICONSET/icon_512x512.png" >/dev/null
cp /tmp/karenos-icon/KarenOS-1024.png "$ICONSET/icon_512x512@2x.png"
rm -rf Packaging/KarenOS.icns
iconutil -c icns "$ICONSET" -o Packaging/KarenOS.icns

cp /tmp/karenos-icon/KarenOS-1024.png docs/branding/karenos-logo.png
echo "Icône : Packaging/KarenOS.icns + docs/branding/karenos-logo.png"