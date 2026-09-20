# KarenOS

Application native macOS pour utiliser des modèles d'IA **en local** : téléchargement de modèles GGUF depuis Hugging Face, puis discussion avec eux, tout sur ta machine.

**Auteur : Martial Zinsou**

## Captures d'écran

![Mes modèles — bibliothèque et chat local](screenshots/1_modelles.png)

*Mes modèles : bibliothèque et chat en local.*

![Boutique — téléchargement de modèles GGUF depuis Hugging Face](screenshots/2_boutique.png)

*Boutique : parcours et installation de modèles GGUF depuis Hugging Face.*

![Compétences — rôle, contexte et obligations de résultats](screenshots/3_competences.png)

*Compétences : consignes réutilisables avec n'importe quel modèle.*

## Fonctionnalités

- **Boutique** : modèles GGUF sélectionnés (Qwen 0.5B à 3B, SmolLM, Phi-3…) + recherche sur Hugging Face avec indicateur de taille, licence et contexte.
- **Mes modèles** : modèles installés, chargement, discussion en streaming (réponses token par token).
- **Compétences** : consignes structurées (rôle, contexte, obligations de résultats) appliquées automatiquement quel que soit le modèle.
- **Moteur local** : utilise `llama-server` (llama.cpp) téléchargé automatiquement et embarqué dans l'app. Aucune donnée ne quitte l'ordinateur.

📘 **Documentation complète** — architecture, schémas d'inférence, flux des compétences, dépannage : [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) →

## Pré-requis

- macOS 13 ou plus récent
- Outils de ligne de commande (`xcode-select --install`). Xcode n'est pas obligatoire.

## Construire et lancer

```bash
Scripts/make-app.sh          # compile + assemble build/KarenOS.app
Scripts/make-app.sh --run    # compile puis ouvre l'app
Scripts/make-icon.sh         # (re)génère la belle icône Packaging/KarenOS.icns
```

## Utilisation

1. Ouvrir **Boutique** → choisir un modèle (les petits modèles sont en haut de liste) → **Installer**.
2. Aller dans **Mes modèles** → cliquer sur le modèle → le chat se charge automatiquement.
3. Écrire un message et discuter. Tout est local (512 tokens de contexte par défaut, modifiable dans le code).

Au premier lancement, l'app télécharge le moteur d'inférence (~8 Mo) et l'installe dans `~/Library/Application Support/KarenOS/`.

## Détails techniques

- 100 % Swift / SwiftUI, aucune dépendance externe.
- API Hugging Face (recherche, détails, téléchargement avec progression).
- `llama-server` (llama.cpp) lancé en sous-processus, interface HTTP de type OpenAI (`/v1/chat/completions`), streaming SSE.
- Compilation directe avec `swiftc` (pas d'Xcode requis).

## Notes

- Sur Mac Intel, l'inférence se fait sur CPU (`Accelerate`). Sur Apple Silicon, mêmes fonctions, GPU Metal via arm64.
- Les modèles vont directement dans `~/Library/Application Support/KarenOS/Models/`.