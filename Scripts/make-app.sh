#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Compilation (release) =="
BUILD_DIR="build/bin"
mkdir -p "$BUILD_DIR"

swiftc -O -parse-as-library \
  -o "$BUILD_DIR/KarenOS" \
  Sources/KarenOS/*.swift

APP="build/KarenOS.app"

echo "== Assemblage du bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/KarenOS" "$APP/Contents/MacOS/KarenOS"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Packaging/KarenOS.icns ]; then
  cp Packaging/KarenOS.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "== Signature ad-hoc =="
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(signature ignorée)"

echo "App prête : $APP"
if [ "${1:-}" = "--run" ]; then
  open "$APP"
fi