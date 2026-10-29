# EngineCore — moteur d'inférence local KarenOS

Moteur Swift qui pilote directement l'API C de llama.cpp (b8967) : aucun
serveur HTTP, aucun processus enfant. `LlamaEngine` est un `actor` qui
possède les objets C (`llama_model`, `llama_context`, `llama_batch`) et
expose un `AsyncThrowingStream<String, Error>` consommable depuis le
MainActor.

```
SwiftUI / ChatView
      │  AsyncThrowingStream<String, Error>
      ▼
LlamaEngine (actor) ── buffers préalloués ── llama_sampler
      │
      ├── llama_model   (poids, mmap/mlock, offload GPU)
      ├── llama_context (KV cache, threads, abort_callback)
      └── llama_batch   (une allocation pour toute la session)
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `LlamaEngine.swift` | actor, configuration, erreurs, sampler, KV roulant, UTF-8 |
| `CLlama/include/llama.h` | API llama.cpp b8967 (MIT, ggml-org) |
| `CLlama/include/karen_llama_compat.h` | shim `llama_memory_seq_*` / legacy |
| `CLlama/module.modulemap` | module Swift `CLlama` |
| `EngineCLI/main.swift` | smoke tests : streaming, UTF-8, rolling, annulation, mémoire |

## Utilisation

```swift
// Production CPU/BLAS — profil validé (threads physiques, FA auto, KV f16).
let config = LlamaConfiguration.cpuProduction(
    modelPath: "/chemin/modele.gguf",
    contextSize: 8_192
)
let engine = try await LlamaEngine.load(configuration: config)

// Variante GPU : mêmes réglages, avec gpuLayers: -1 (toutes les couches)
// ou N, à condition qu'un backend GPU soit présent dans le binaire.
var gpuConfig = config
gpuConfig.gpuLayers = -1
```
let system = "Tu es KarenOS, un assistant local concis."
let keep = await engine.tokenCount(of: system)   // préfixe intouchable
let prompt = """
<|im_start|>system
\(system)<|im_end|>
<|im_start|>user
Explique le KV cache.<|im_end|>
<|im_start|>assistant
"""

for try await piece in await engine.stream(
    prompt: prompt,
    keepTokens: keep,
    parameters: .init(temperature: 0.7, topK: 40, topP: 0.95, minP: 0.05,
                      seed: .max, maxTokens: 512)
) {
    // piece arrive sur le MainActor : mise à jour SwiftUI directe.
}

let metrics = await engine.lastMetrics
// promptTokens, generatedTokens, reusedTokens, timeToFirstToken,
// tokensPerSecond, promptEvaluation, contextShiftCount

engine.cancel()                    // non isolé, immédiat
await engine.shutdown()            // libère modèle + contexte + buffers
```

`LlamaEngine` ne formate pas le prompt : le template de chat (ChatML,
Gemma, etc.) reste la responsabilité de l'appelant. `keepTokens` est le
nombre de tokens du préfixe système ; il se calcule avec
`tokenCount(of:)` et ne doit jamais être coupé par le KV roulant.

## Choix d'optimisation

### Isolation et concurrence

- Les pointeurs C vivent dans `LlamaResources`, classe **non Sendable**
  possédée par l'actor. Aucun pointeur ne traverse une frontière
  d'isolation.
- Le chargement du modèle (mmap, init backend, allocation KV) s'exécute
  dans un `Task.detached(priority: .userInitiated)` ; le MainActor ne
  bloque jamais.
- `cancel()` et `shutdownAsynchronously()` sont `nonisolated` et passent
  par un `CancelRelay` verrouillé : le bouton Stop fonctionne même quand
  l'actor est occupé.
- La boucle rend la main (`Task.yield()`) tous les 4 tokens et entre les
  chunks de prompt : arrêt, statistiques et refus d'une seconde requête
  restent réactifs sans casser la sérialisation.
- Compilé et vérifié avec `-strict-concurrency=complete` sur Swift 5.8.

### Zéro allocation par token

- `tokenBuffer` et `cachedTokens` : deux `UnsafeMutableBufferPointer`
  alloués une fois (`n_ctx + 1`).
- `llama_batch` : alloué une fois à l'initialisation, réutilisé pour
  chaque chunk et chaque token.
- `pieceBuffer` : 256 octets préalloués pour `llama_token_to_piece`.
- Le seul chemin froid qui alloue est un prompt plus long que le contexte
  (buffer temporaire pour tokeniser puis conserver système + queue).
- `llama_batch_free`, `llama_free`, `llama_model_free` sont appelés dans
  le `deinit` de `LlamaResources`, avec un drapeau `finished` qui évite
  tout double-free en cas d'échec partiel du chargement.

### Ingestion par chunks

- Le prompt est décodé par tranches de `min(n_batch, tokens restants)`.
- `batch.logits[i]` vaut 1 **uniquement** sur le dernier token du dernier
  chunk : llama.cpp ne calcule pas la projection du vocabulaire pour les
  tokens intermédiaires, ce qui réduit fortement le temps d'ingestion.
- `n_batch` borne le batch logique, `n_ubatch` la mémoire de pic ; les
  deux sont réglables (`batchSize`, `microBatchSize`).
- Les positions sont explicites (`batch.pos`), jamais laissées à la
  détection automatique : indispensable après un décalage de KV.

### KV cache roulant

Quand `tokensInContext + 1` atteint `n_ctx - 1` :

1. on conserve `[0, n_keep)` (préfixe système) ;
2. on supprime `[n_keep, n_keep + moitié)` via
   `llama_memory_seq_rm` ;
3. on décale les positions restantes de `-moitié` via
   `llama_memory_seq_add` : aucune copie de tenseur, seules les
   métadonnées et le cache RoPE changent ;
4. on met à jour le miroir `cachedTokens` avec `memmove`.

Entre deux requêtes, le plus long préfixe commun entre le prompt et le KV
est réutilisé ; si le préfixe système a changé, le contexte est vidé. Un
prompt plus long que le budget (`n_ctx - réserve de génération`) est
ramené à « système + queue la plus récente ».

Si une architecture refuse la suppression partielle (modèles récurrents),
le moteur vide le KV et renvoie une erreur explicite plutôt que de
corrompre l'état.

### Échantillonnage

Chaîne `llama_sampler_chain` : top-k → top-p → min-p → température →
distribution (ou greedy si `temperature <= 0`). Chaque sampler est
possédé par la chaîne ; `llama_sampler_free` libère l'ensemble.
`llama_sampler_accept` est appelé après chaque token pour les samplers à
état. Une graine `UInt32.max` tire une graine aléatoire par requête.

### UTF-8

Un token n'est pas un caractère : un emoji peut être réparti sur 2 à 4
tokens. `UTF8Accumulator` conserve les octets incomplets, valide chaque
séquence avec `String(bytes:encoding:)` et ne rend une `String` que
lorsqu'un caractère complet est disponible. Les octets invalides
deviennent U+FFFD ; le flush final ne perd aucun octet.

### Annulation

- `CancelBox` : drapeau verrouillé + époque. Une annulation tardive d'une
  ancienne requête ne peut pas tuer la suivante.
- `ggml_abort_callback` pointe sur `AbortFlag` et interrompt un
  `llama_decode` CPU en cours ; sur Metal, l'abandon est pris en compte
  entre deux tokens (limite documentée par llama.cpp).
- `AsyncThrowingStream.onTermination` annule la boîte et la tâche : fermer
  la vue ou cliquer Stop ne laisse pas de génération fantôme.

## Notes API b8967

- `llama_kv_cache_seq_rm/add/clear` n'existent plus : l'API passe par
  `llama_memory_seq_rm/add` et `llama_get_memory(ctx)`.
  `karen_llama_compat.h` encapsule ce changement et garde une branche
  `KAREN_LLAMA_LEGACY_KV` pour les versions antérieures.
- `llama_model_params.n_gpu_layers` : une valeur **négative** signifie
  toutes les couches (utiliser `-1`, pas `999`).
- `llama_batch_free` prend la structure **par valeur**.
- `llama_model_free` remplace `llama_free_model` ; `llama_init_from_model`
  remplace `llama_new_context_with_model`.
- Les headers fournis sont ceux de b8967 ; pour une autre version,
  remplacez `CLlama/include` et recompilez le shim si l'API mémoire change.

## Compilation et tests

```bash
./Scripts/build-engine-cli.sh
./build/bin/karen-engine-cli utf8
KARENOS_MODEL="$HOME/Library/Application Support/KarenOS/Models/.../modele.gguf" \
  ./build/bin/karen-engine-cli all
```

Le CLI cherche `LLAMA_ENGINE_DIR` (par défaut
`~/Library/Application Support/KarenOS/Engine/llama-b8967`) et ne modifie
pas le build de l'application (`Scripts/make-app.sh` ignore `EngineCore`).

## Mesures réalisées

Machine de test : Mac Intel x86_64, macOS 13.7.8, llama.cpp b8967
**BLAS/Accelerate uniquement** (pas de backend Metal sur cette machine).
Les chiffres GPU/Metal ci-dessous ne sont donc pas mesurés ici.

| Test | Résultat |
|---|---|
| SmolLM2 360M Q8_0, ctx 1024, prompt 51 tokens, profil production | chargement 0,15 s · TTFT 0,38–0,65 s · 25,7–42,6 tok/s selon l'état thermique |
| Qwen2.5 0.5B Q4_K_M, ctx 1024 | chargement 0,61 s · TTFT 1,55 s · 6,6 tok/s (mesuré sous charge) |
| Gemma 4 E4B Q4_0 (4,3 Go), ctx 1024 | chargement 16,2 s · 0,7 tok/s · RSS ~2 Go (mmap, mesuré sous charge) |
| Contexte 256, prompt 1290 tokens | 192 tokens conservés · 1 décalage KV · 71 tokens générés |
| 3 cycles chargement/libération | RSS après shutdown stable (23 Mo), croissance −1 Mo |
| Réutilisation multi-tour | 24 tokens réutilisés sur 25 au second tour |
| Emoji 😀 coupé en 3 fragments | reconstruit en une seule `String` |

Le TTFT inclut la tokenisation et l'ingestion du prompt ; le débit
`tokensPerSecond` exclut le premier token. Sur Apple Silicon, `gpuLayers:
-1` offload toutes les couches sur Metal si le binaire llama.cpp fourni
contient `libggml-metal` ; sinon le moteur reste CPU.

### Profil de production CPU/BLAS

`LlamaConfiguration.cpuProduction(modelPath:contextSize:)` verrouille le
chemin validé sur cette machine : `gpuLayers = 0`, threads = cœurs
**physiques** (`hw.physicalcpu`, plafonné à 8), Flash Attention
automatique, KV f16, mmap activé, mlock désactivé. L'application
`EngineManager` applique la même règle à `llama-server` (`-t` et `-tb`).

Le réglage des threads est le levier le plus important. Sur le
i7-4850HQ (4 cœurs physiques, 8 logiques), `llama-bench` en série
interleavée donne :

| Threads | pp512 (t/s) | tg128 (t/s) |
|---:|---:|---:|
| 2 | 182,5 | 35,2 |
| 4 | 164,1 | **40,0** |
| 6 | 150,5 | 38,6 |
| 8 | 132,5 | 24,8 |

Quatre threads donnent le meilleur décodage ; les huit threads logiques
coûtent ~38 % en `tg` et ~19 % en `pp` par contention mémoire. C'était le
réglage de l'app avant correction (`activeProcessorCount`). Flash
Attention activée sur CPU gagne 5–10 % sur `pp` et `tg` ; le KV q8_0
réduit l'empreinte mais coûte ~20 % sur le prefill, sans gain mesurable
en décodage.

Les passages exécutés pendant qu'un `llama-server` orphelin de 4,6 Go
tournait encore donnaient 4,5–11,7 tok/s ; la même suite, une fois le
processus terminé et le profil production appliqué, oscille entre 25,7
et 42,6 tok/s selon l'état thermique. L'écart mesure la sensibilité du
débit CPU à la contention et à la température, pas une régression du
moteur : les sept scénarios passent dans tous les cas.

## Limites assumées

- **Texte uniquement** : pas de `mtmd`/vision dans ce module. KarenOS
  conserve `llama-server` pour les modèles avec `.mmproj` tant que le
  pont multimodal n'est pas ajouté.
- **Une génération par moteur** ; la seconde requête reçoit `.busy`.
  Pour du parallélisme, créer plusieurs `LlamaEngine` (attention à la
  VRAM) ou passer à `n_seq_max > 1`.
- **Pas de stop-strings arbitraires** : les fins de tour reposent sur les
  tokens EOG du vocabulaire (`<|im_end|>`, `<|endoftext|>`…).
- **Pas de pénalité de répétition** dans la chaîne par défaut ; ajouter
  `llama_sampler_init_penalties` si nécessaire.
- **NPU/Neural Engine** : non exposé par llama.cpp ; réservé à macOS.
- Le moteur ne remplace pas encore `ChatService` dans l'app : il est prêt
  à être branché derrière un adaptateur, avec le même
  `ResourceGovernor` autour de la boucle de streaming.
