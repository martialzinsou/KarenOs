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

// Fond dégradé arrondi
let colors = [NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.95, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.60, green: 0.25, blue: 0.90, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let path = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
ctx.restoreGState()

// Monogramme "K"
let text = "K" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 640, weight: .bold),
    .foregroundColor: NSColor.white
]
let ts = text.size(withAttributes: attrs)
let origin = CGPoint(x: (CGFloat(size) - ts.width) / 2, y: (CGFloat(size) - ts.height) / 2)
ctx.saveGState()
// CoreText drawing
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "K", attributes: attrs))
ctx.textPosition = CGPoint(x: origin.x, y: origin.y)
CTLineDraw(line, ctx)
ctx.restoreGState()

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
echo "Icône : Packaging/KarenOS.icns"