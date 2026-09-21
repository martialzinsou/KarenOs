# KarenOS

<!--
    SEO — KarenOS · Référence projet : https://github.com/martialzinsou/KarenOs
    Auteur   : Martial Zinsou
    Titre    : KarenOS
    Description : Application native macOS d'IA générative 100% locale : téléchargement de modèles GGUF depuis Hugging Face, chat en streaming avec llama.cpp, agents autonomes et multimodal (Swift / SwiftUI).
    Mots-clés : karenos, ia locale, ia hors ligne, macos, swift, swiftui, llama.cpp, gguf, hugging face, agents ia autonomes, multimodal, chatbot local, martial zinsou
    Langue   : fr
-->


Application native macOS pour utiliser des modèles d'IA **en local** : téléchargement de modèles GGUF depuis Hugging Face, puis discussion avec eux, tout sur ta machine.

**Auteur : Martial Zinsou**

## Captures d'écran

![Mes modèles — bibliothèque et chat local](screenshots/1_modelles.png)

*Mes modèles : bibliothèque et chat en local.*

![Boutique — téléchargement de modèles GGUF depuis Hugging Face](screenshots/2_boutique.png)

*Boutique : parcours et installation de modèles GGUF depuis Hugging Face.*

![Compétences — rôle, contexte et obligations de résultats](screenshots/3_competences.png)

*Compétences : consignes réutilisables avec n'importe quel modèle.*

![Agents — missions autonomes, déclencheur, boucle et conditions de fin](screenshots/4_agents.png)

*Agents : missions autonomes sur un modèle choisi, avec déclencheur, boucle infinie et conditions de fin.*

## Fonctionnalités

- **Boutique** : modèles GGUF sélectionnés (Qwen 0.5B à 3B, SmolLM, Phi-3…) + recherche sur Hugging Face avec indicateur de taille, licence et contexte.
- **Mes modèles** : modèles installés, chargement, discussion en streaming (réponses token par token).
- **Agents** : missions autonomes — décrivez la mission, choisissez le modèle, le **déclencheur** (manuel, au lancement, toutes les X secondes), la **boucle infinie** et des **conditions de fin** (nombre d'itérations, durée, mot-clé de réussite). Le modèle est chargé automatiquement puis le précédent est restauré.
- **Multimodal** : joignez des **images, vidéos, fichiers audio** à vos messages et **dictez votre voix** (reconnaissance vocale locale). En présence d'un modèle vision (`*.mmproj`), les images sont réellement analysées par le modèle.
- **Compétences** : consignes structurées (rôle, contexte, obligations de résultats) appliquées automatiquement quel que soit le modèle.
- **Moteur local** : utilise `llama-server` (llama.cpp) téléchargé automatiquement et embarqué dans l'app. Aucune donnée ne quitte l'ordinateur.

📘 **Documentation complète** — architecture, schémas d'inférence, flux des compétences, dépannage : [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) → &nbsp; **🇺🇸 English (US) :** [DOCUMENTATION_EN.md](docs/DOCUMENTATION_EN.md) →

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
3. Écrire un message et discuter. Tout est local (contexte de 2048 tokens, réponse limitée à 512 tokens par défaut, modifiable dans le code).

Au premier lancement, l'app télécharge le moteur d'inférence (~8 Mo) et l'installe dans `~/Library/Application Support/KarenOS/`.

## Détails techniques

- 100 % Swift / SwiftUI, aucune dépendance externe.
- API Hugging Face (recherche, détails, téléchargement avec progression).
- `llama-server` (llama.cpp) lancé en sous-processus, interface HTTP de type OpenAI (`/v1/chat/completions`), streaming SSE.
- Compilation directe avec `swiftc` (pas d'Xcode requis).

## Notes

- Sur Mac Intel, l'inférence se fait sur CPU (`Accelerate`). Sur Apple Silicon, mêmes fonctions, GPU Metal via arm64.
- Les modèles vont directement dans `~/Library/Application Support/KarenOS/Models/`.