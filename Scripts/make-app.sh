# Auteur : Martial Zinsou
#  KarenOS
#  Par Martial Zinsou

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Cible de déploiement : macOS 11 (Big Sur) et suivants.
TARGET="${KARENOS_TARGET:-x86_64-apple-macos11.0}"
SDK="$(xcrun --show-sdk-path)"

echo "== Compilation (release, $TARGET) =="
BUILD_DIR="build/bin"
mkdir -p "$BUILD_DIR"

swiftc -O -parse-as-library \
  -target "$TARGET" \
  -sdk "$SDK" \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  -o "$BUILD_DIR/KarenOS" \
  Sources/KarenOS/*.swift

APP="build/KarenOS.app"

echo "== Assemblage du bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BUILD_DIR/KarenOS" "$APP/Contents/MacOS/KarenOS"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Packaging/KarenOS.icns ]; then
  cp Packaging/KarenOS.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -f docs/branding/karenos-logo.png ]; then
  cp docs/branding/karenos-logo.png "$APP/Contents/Resources/KarenOS-logo.png"
fi

# Moteur d'inférence embarqué, recompilé pour macOS 11 (voir docs/BIG-SUR.md).
# Prioritaire sur l'archive GitHub officielle, qui exige macOS 13.
if [ -x Packaging/engine/llama-server ]; then
  echo "== Moteur embarqué (llama.cpp, minos 11.0) =="
  mkdir -p "$APP/Contents/Resources/Engine"
  cp -R Packaging/engine/. "$APP/Contents/Resources/Engine/"
  chmod +x "$APP/Contents/Resources/Engine/llama-server"
fi

# macOS 11 ne fournit pas le runtime de concurrence Swift (async/await).
# On embarque la version rétro-déployable livrée avec les outils de développement ;
# macOS 12+ continue d'utiliser sa copie système.
CONCURRENCY_LIB=""
for candidate in \
  "/Library/Developer/CommandLineTools/usr/lib/swift-5.5/macosx/libswift_Concurrency.dylib" \
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/macosx/libswift_Concurrency.dylib" \
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswift_Concurrency.dylib"; do
  if [ -f "$candidate" ]; then CONCURRENCY_LIB="$candidate"; break; fi
done
if [ -n "$CONCURRENCY_LIB" ]; then
  echo "== Runtime de concurrence : $CONCURRENCY_LIB =="
  cp "$CONCURRENCY_LIB" "$APP/Contents/Frameworks/libswift_Concurrency.dylib"
  chmod u+w "$APP/Contents/Frameworks/libswift_Concurrency.dylib"
else
  echo "(runtime de concurrence introuvable — l'app exigera macOS 12+)"
fi

echo "== Signature ad-hoc =="
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(signature ignorée)"

echo "App prête : $APP"
if [ "${1:-}" = "--run" ]; then
  open "$APP"
fi
