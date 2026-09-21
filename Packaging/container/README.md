# KarenOS llama-server (conteneur)

**Auteur : Martial Zinsou**

Le composant portable de KarenOS : le **moteur d'inférence** `llama-server`
(llama.cpp), compilé pour **Linux x86_64 (AVX2)**. Il permet de faire tourner
l'IA générative de KarenOS sur un serveur de l'infrastructure (intranet,
souveraineté des données) tout en gardant l'interface macOS sur le poste.

Il est publié automatiquement sur le **GitHub Container Registry** par l'action
`.github/workflows/container.yml` à chaque nouveau tag `v*` du dépôt.

## Image

```
ghcr.io/martialzinsou/karenos/karenos-llama-server:latest
```

## Utilisation (poste de travail / serveur avec Docker)

Le modèle GGUF est monté depuis l'hôte ; rien ne transite par le cloud :

```bash
docker run --rm -p 8080:8080 \
  -v "$PWD/models:/models" \
  -e GGML_N_CTX=2048 \
  ghcr.io/martialzinsou/karenos/karenos-llama-server:latest \
  -m /models/karenos-smol.gguf --host 0.0.0.0 --port 8080
```

Puis brancher l'app macOS de KarenOS sur `http://<serveur>:8080`.

## Options utiles (DSI)

- `-t N` : nombre de threads (cœurs physiques du serveur).
- `--flash-attn on -ctk q8_0 -ctv q8_0` : cache KV compressé (mémoire + débit).
- `--mlock` : verrouille le modèle en RAM (lancer avec `--cap-add=IPC_LOCK`).
- `--n-gpu-layers 0` : CPU uniquement (par défaut dans cette image).

## Build local

```bash
docker build -f Packaging/container/Dockerfile -t karenos-llama-server .
```

## Redistribution

Le binaire Linux `llama-server` (ELF x86-64, glibc) est croisé depuis macOS avec
Zig (`zig cc -target x86_64-linux-gnu`), révision `a3e5b96` de llama.cpp — la
même que le moteur macOS de KarenOS.