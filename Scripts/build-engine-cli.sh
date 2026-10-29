#!/usr/bin/env bash
# KarenOS — auteur : Martial Zinsou
# Compile le moteur C API (EngineCore) et son CLI de validation.
# Le binaire de llama.cpp fourni avec KarenOS (llama-b8967) est requis.
set -euo pipefail
cd "$(dirname "$0")/.."

# Priorité au moteur embarqué (emis pour macOS 11), sinon archive officielle.
if [ -n "${LLAMA_ENGINE_DIR:-}" ]; then
  ENGINE_DIR="$LLAMA_ENGINE_DIR"
elif [ -f Packaging/engine/libllama.dylib ]; then
  ENGINE_DIR="Packaging/engine"
else
  ENGINE_DIR="$HOME/Library/Application Support/KarenOS/Engine/llama-b8967"
fi
ARCH="$(uname -m)"
TARGET="${KARENOS_TARGET:-${ARCH}-apple-macos11.0}"
OUT="build/bin/karen-engine-cli"

if [ ! -f "$ENGINE_DIR/libllama.dylib" ]; then
  echo "Moteur introuvable : $ENGINE_DIR"
  echo "Définissez LLAMA_ENGINE_DIR ou lancez KarenOS une première fois."
  exit 1
fi

mkdir -p build/bin
echo "== Compilation du moteur (C API) =="
swiftc -O \
  -target "$TARGET" \
  -I EngineCore/CLlama \
  -L "$ENGINE_DIR" \
  -lllama \
  -Xlinker -rpath -Xlinker "$ENGINE_DIR" \
  EngineCore/LlamaEngine.swift \
  EngineCore/EngineCLI/main.swift \
  -o "$OUT"

echo "CLI prêt : $OUT"
if [ "${1:-}" = "--run" ]; then
  shift
  "$OUT" "${@:-all}"
fi
