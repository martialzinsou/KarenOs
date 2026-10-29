# KarenOS sur macOS 11 (Big Sur)

KarenOS est compilé avec `-target x86_64-apple-macos11.0` et fonctionne dès
**macOS 11.0**, sans rien installer d'autre que l'application.

Trois éléments ont été nécessaires :

1. **Interface SwiftUI** : les API macOS 12/13 ont été remplacées par leurs
   équivalents macOS 11 (voir tableau ci-dessous).
2. **Runtime de concurrence Swift** : Big Sur ne fournit pas
   `libswift_Concurrency.dylib`. Une copie rétro-déployable est embarquée dans
   `Contents/Frameworks` et résolue via `@rpath`.
3. **Moteur llama.cpp** : l'archive officielle `llama-b8967-bin-macos-x64`
   exige macOS 13 (`LC_BUILD_VERSION minos 13.0`, `libllama` 13.3). Un moteur
   recompilé pour macOS 11 est embarqué dans `Contents/Resources/Engine`.

## Interface : substitutions appliquées

| API macOS 12/13 | Remplacement macOS 11 |
|---|---|
| `.foregroundStyle(.secondary)` | `.foregroundColor(.secondary)` |
| `.foregroundStyle(.tertiary)` | `.foregroundColor(Color.secondary.opacity(0.7))` |
| `Color(nsColor: .x)` | `Color(NSColor.x)` |
| `.overlay(alignment: .x) { … }` | `.overlay(…, alignment: .x)` |
| `AnyShapeStyle` | `LinearGradient` (dégradés) ou `Color` |
| `Grid` / `GridRow` | `HStack` + largeur fixe |
| `.task { }` / `.task(id:)` | `.onAppear { Task { } }` / `.onChange(of:)` |
| `@Environment(\.dismiss)` | `@Environment(\.presentationMode)` |
| `Window(id:)` + `openWindow` | feuilles (`.sheet(item:)`) rattachées à la fenêtre principale |
| `TimelineView` | `Timer.publish` + `@State` |
| `TextField(axis: .vertical)` | `TextField` simple ligne |
| `URLSession.bytes(for:)` | client SSE `URLSessionDataDelegate` (`ChatService.swift`) |
| `URLSession.download(from:)` | `downloadTask(with:completionHandler:)` + continuation |
| `Button(role: .destructive)` | `Button` simple |
| `.textSelection`, `.menuIndicator`, `.scrollContentBackground`, `.tint` | retirés / `.accentColor` |

## Moteur embarqué : provenance et reconstruction

Le binaire livré dans `Packaging/engine/` provient de llama.cpp **b8967**,
compilé sur Intel avec cet ensemble de drapeaux :

```bash
git clone --depth 1 --branch b8967 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build-bigsur \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_CURL=OFF \
  -DGGML_METAL=OFF \
  -DGGML_ACCELERATE=ON \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple \
  -DGGML_NATIVE=OFF
cmake --build build-bigsur --target llama-server -j 4
```

Points importants :

- `GGML_NATIVE=OFF` : le binaire reste portable sur tous les Mac Intel.
  `-march=native` produirait un exécutable Haswell qui plante (`SIGILL`) sur
  les Mac Pro 2013 et les CPU sans AVX2. Le dispatch AVX2/FMA est fait au
  runtime par les noyaux *llamafile sgemm*.
- `GGML_METAL=OFF` : le backend Metal des builds x64 officiels ne cible pas
  les GPU Intel Iris/GeForce de Big Sur ; BLAS/Accelerate reste le chemin le
  plus rapide sur ces machines.
- Les dylibs doivent être rendues déplaçables :

```bash
cd Packaging/engine
install_name_tool -rpath <build-dir>/bin @executable_path llama-server
for f in lib*.dylib; do
  install_name_tool -rpath <build-dir>/bin @loader_path "$f"
done
codesign --force --sign - llama-server lib*.dylib
```

Vérification :

```bash
otool -l Packaging/engine/llama-server | grep -A3 LC_BUILD_VERSION   # minos 11.0
otool -l Packaging/engine/libggml-cpu.0.dylib | grep -A3 LC_BUILD_VERSION
Packaging/engine/llama-server --list-devices                          # BLAS: Accelerate
```

Mesures obtenues sur le MacBook Pro 11,3 (i7-4850HQ, 4 threads,
BLAS/Accelerate, `--reasoning off`) :

| Modèle | Débit (tg128) |
|---|---|
| SmolLM2 360M Q8_0 | 43,8 – 46,3 tok/s |
| Gemma 4 E4B Q4_K_M (≈5 Go) | 4,9 – 5,1 tok/s |

## Vérifier l'ensemble

L'app expose deux harnais de développement, inactifs sans variable
d'environnement :

```bash
# Test de bout en bout : chargement + streaming via ChatService, puis quitter.
KARENOS_SMOKE_MODEL="HuggingFaceTB/SmolLM2-360M-Instruct-GGUF" \
KARENOS_SMOKE_OUT=/tmp/karen_smoke.txt \
  build/KarenOS.app/Contents/MacOS/KarenOS
cat /tmp/karen_smoke.txt

# Captures des quatre onglets + feuilles À propos / Aide.
KARENOS_SNAPSHOT_DIR=/tmp/karen_snap KARENOS_SNAPSHOT_MIN=1 \
  build/KarenOS.app/Contents/MacOS/KarenOS
```

Le rapport du smoke test indique le chemin du binaire effectivement lancé
(`Contents/Resources/Engine/llama-server` quand le moteur embarqué est présent),
le temps de chargement, le TTFT, la réponse complète et un verdict `OK` ou
`ÉCHEC`.

## Arrêt du moteur

À la fermeture, `EngineManager` arrête `llama-server` en **SIGTERM**, attend
1,5 s, puis envoie **SIGKILL** s'il ne s'est pas terminé : son arrêt
« gracieux » peut s'enliser et laisser plusieurs Go de RAM occupés (observé
après un second SIGINT). L'arrêt est déclenché par la vue racine *et* par un
observateur de `NSApplication.willTerminateNotification` enregistré dans
`EngineManager`, pour couvrir le cas où l'interface n'est plus vivante. Après
le smoke test, `pgrep -fl llama-server` doit ne rien renvoyer.

## Limites connues sur Big Sur

- L'app et le moteur embarqué sont **x86_64** : sur Apple Silicon ils
  s'exécutent via Rosetta 2.
- Les fenêtres « À propos » et « Aide » sont des **feuilles** (macOS 11 n'a ni
  `Window(id:)` ni `openWindow`).
- Le champ de saisie du chat est monoligne ; l'envoi se fait par le bouton ou
  `⌘↩`.
