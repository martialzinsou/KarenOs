# KarenOS — l'IA générative locale conçue pour le bureau

*Article technique et documentaire — septembre 2026*

**Auteur : Martial Zinsou**

<!--
    SEO — KarenOS · Référence projet : https://github.com/martialzinsou/KarenOs
    Canonical : https://github.com/martialzinsou/KarenOs/blob/main/docs/ARTICLE.md
    Auteur   : Martial Zinsou
    Fonction : Directeur des Systèmes d'Information (DSI / IT Director)
    Titre    : KarenOS — Article technique et documentaire avec interview du créateur
    Description : Article technique complet sur KarenOS : architecture, cycle de vie moteur, agents autonomes, multimodal, compétences, sécurité, distribution, modèles recommandés. Termine par une interview de Martial Zinsou, créateur du projet.
    Mots-clés : karenos, ia locale, macos, swift, swiftui, llama.cpp, agents ia, multimodal, interview, martial zinsou, dsi, it director, gouvernance it, ia souveraine
    Langue   : fr
    robots   : index, follow
    og:title : KarenOS — Article technique et interview du créateur
    og:description : Architecture, agents, multimodal, sécurité, distribution — et l'interview de Martial Zinsou.
    og:type : article
    og:url : https://github.com/martialzinsou/KarenOs/blob/main/docs/ARTICLE.md
    og:image : https://raw.githubusercontent.com/martialzinsou/KarenOs/main/docs/branding/karenos-logo.png
    twitter:card : summary_large_image
-->

## 1. Introduction

KarenOS est une application native pour **macOS** pensée comme une station d'**IA générative hors ligne**. L'utilisateur télécharge un modèle de langage au format **GGUF** depuis **Hugging Face**, puis dialogue avec lui localement : aucun prompt, aucune réponse, aucun fichier joint ne quitte la machine une fois le modèle chargé.

Le projet repose sur un choix d'ingénierie assumé : plutôt que de réinventer un moteur d'inférence, KarenOS s'appuie sur **[llama.cpp](https://github.com/ggml-org/llama.cpp)** et son serveur `llama-server`, lancé en sous-processus et exposant une interface compatible avec celle d'**OpenAI**. Ce parti pris garantit un modèle d'inférence éprouvé (AVX2, BLAS Apple, attention flash, cache KV quantifié) et une interopérabilité de bout en bout.

Deux espaces de déploiement sont couverts :

- **le poste de travail** : bundle `.app` macOS, torchère d'usage quotidien ;
- **le serveur d'entreprise** : image **conteneur Linux x86-64** publiée sur le *GitHub Container Registry*, construite automatiquement pour les équipes **DSI**.

---

## 2. Chronologie (documentaire)

| Date | Étape |
|---|---|
| 2025 | Début du développement, exploration des formats GGUF et de l'API payante d'OpenAI — constat : les modèles locaux atteignent un niveau exploitable pour une fraction du coût. |
| 2025 | Première version du moteur embarqué via `llama.cpp` ; décision d'exposer une API compatible OpenAI plutôt qu'un protocole propriétaire. |
| 2026 | Ajout des **agents autonomes** (boucle, actions shell, lancement d'applications) puis du **multimodal** (vision, dictée vocale locale). |
| Été 2026 | Optimisation du moteur (flash attention, cache KV quantifié), compilation croisée de `llama-server` pour Linux x86-64 via **Zig**, publication de l'image conteneur. |
| Septembre 2026 | **Version 1.0.0** : documentation bilingue, release publique avec archive macOS, image GHCR, page Wikipédia d'ébauche. |

---

## 3. Architecture technique

### 3.1 Vue d'ensemble

KarenOS est écrite en **Swift / SwiftUI** et compilée avec `swiftc -O` en binaire natif (sans environnement de développement graphique). L'état applicatif est centralisé dans cinq « stores » observables (Combine) :

| Store | Rôle |
|---|---|
| `ModelStore` | Registre des modèles installés et de leur état de téléchargement. |
| `EngineManager` | Cycle de vie du moteur `llama-server` (binaire, port, santé). |
| `SkillStore` | Compétences réutilisables injectées dans le prompt système. |
| `AgentStore` | Définition des agents. |
| `AgentRunner` | Exécution des missions. |

```
┌─────────────── KarenOSApp ───────────────┐
│  ModelStore   EngineManager   SkillStore │
│  AgentStore   AgentRunner                │
└──────┬───────────────────────────┬───────┘
       │ sous-processus             │ IPC local
┌──────▼──────────┐     ┌──────────▼─────────┐
│ llama-server    │     │ ChatService        │
│ (binaire local) │◄────│ (API OpenAI / SSE) │
└─────────────────┘     └────────────────────┘
```

### 3.2 Cycle de vie du moteur

Le chargement d'un modèle est une séquence strictement contrôlée :

1. le binaire `llama-server` (inclus dans le bundle ou téléchargé depuis les releases de llama.cpp) est extrait dans le répertoire applicatif ;
2. il est lancé avec le fichier **GGUF** sélectionné et écouté sur **`127.0.0.1`** sur un **port libre** ;
3. l'application interroge `GET /health` **toutes les 0,8 seconde** ;
4. le modèle est déclaré prêt uniquement après **150 sondages consécutifs réussis** — soit un délai maximal de **120 secondes** (timeout) ;
5. si un fichier **`*.mmproj`** est présent, le mode **vision** est activé automatiquement.

```
idle ──► installingEngine ──► ready ──► loading ──► running
          │                      ▲         │           │
          └──► failed ───────────┴─────────┴──► failed  │
                          (nouvelle tentative)   ▲──────┘
```

Une fois `running`, les requêtes passent par `POST /v1/chat/completions` avec **streaming** (`text/event-stream`), chaque token étant décodé et affiché en temps réel — protocole compatible avec les clients OpenAI standard.

### 3.3 Optimisations du moteur

| Optimisation | Effet |
|---|---|
| AVX2 | Instruction set pour les CPU x86-64 modernes. |
| BLAS Apple | Accélération sur processeurs Apple Silicon (via Accelerate). |
| Attention flash | Réduction de l'usage mémoire lors des longues conversations. |
| Cache KV quantifié | Conversations longues plus économes en mémoire vive. |
| `--mlock` | Verrou du modèle en mémoire physique, sans occurrence disque après chargement. |

### 3.4 Agents autonomes

Un agent est une mission **répétable** paramétrée par :

- un **déclencheur** : manuel, au lancement, ou à intervalle fixe ;
- une **boucle de résolution** à base d'appels de chat locales ;
- des **conditions d'arrêt** (nombre de cycles, verdict, interruption) ;
- un **journal d'exécution** persistant.

Chaque mission peut **exécuter des commandes** dans l'interpréteur de commandes de l'utilisateur (`/bin/zsh -lc`) — capacité explicitement activée **par agent**, plafonnée à **30 actions** par mission et **30 secondes** par commande. Cette limite combinée (déclenchements + périmètre) constitue la ligne de défense principale face aux effets de bord d'un modèle ouvert.

### 3.5 Multimodal

- **Pièces jointes** : image, vidéo, audio et fichiers arbitraires sont ingérés par lot.
- **Vision** : si un projecteur multimodal (`*.mmproj`) est installé, les images sont analysées en local.
- **Dictée vocale** : transcription via le framework **Speech** d'Apple (locale), sans clé cloud.
- **Garde-fou** : un modèle strictement textuel reçoit une consigne lui interdisant d'*inventer* des messages d'erreur sur de fausses capacités vision ; les pièces jointes ne sont jamais transmises à un modèle incapable de les traiter.

### 3.6 Compétences (skills)

Les compétences sont des consignes **réutilisables** structurées en **rôle**, **contexte** et **obligations de résultats**, injectables dans le prompt système de n'importe quel modèle. Elles permettent de spécialiser un même moteur (assistant juridique, relecteur technique, réviseur de code…) sans re-téléchargement.

---

## 4. Persistance et données locales

| Ressource | Emplacement |
|---|---|
| Modèles GGUF + projecteurs | `~/Library/Application Support/KarenOS/models/` |
| Compétences | `~/Library/Application Support/KarenOS/skills/` |
| Agents et journaux | `~/Library/Application Support/KarenOS/agents/` + `*.agentlog` |

Les données restent dans le domaine utilisateur : aucune télémétrie, aucun compte, aucune synchronisation forcée. La suppression d'un modèle efface également les fichiers associés sur disque.

---

## 5. Sécurité

- **Réseau** : le moteur n'écoute que sur `127.0.0.1`, sur un port dynamique (aucune exposition réseau).
- **Mémoire** : verrouillage `--mlock` pour éviter l'échange disque du modèle chargé.
- **Exécution** : les actions shell sont optionnelles, nommées `ACTION:`, bornées en **durée** et en **nombre**.
- **Origine des binaires** : le moteur est soit fourni avec l'application (release vérifiée), soit reconstruit en CI de façon déterministe (multi-stage Debian) pour l'image conteneur.
- **Licence** : **MIT** ; aucune partie propriétaire n'est incluse.

---

## 6. Distribution

- **Application macOS** : `KarenOS.app`, archive `KarenOS-1.0.0-macOS.zip` (≈ 2,8 Mo), signature ad-hoc.
- **Image serveur** : `ghcr.io/martialzinsou/karenos/karenos-llama-server:1.0.0` (Linux x86-64), construite par GitHub Actions à chaque tag `v*`, consommable par un simple `docker run` en intranet.

```bash
# DSI — déploiement serveur minimal
docker run -d -p 8080:8080 \
  -v "$PWD/models:/models" \
  ghcr.io/martialzinsou/karenos/karenos-llama-server:1.0.0 \
  --model /models/llama-3.2-1b-instruct.gguf
```

---

## 7. Modèles recommandés

| Modèle | Volume | Usage typique |
|---|---|---|
| Qwen2.5-0,5B / 1,5B / 3B | 0,5–3 Go | Chat rapide sur machines modestes |
| SmolLM2 | < 1 Go | Démarrage instantané |
| Phi-3-mini | ~ 2 Go | Qualité / poids équilibré |

---

## 8. Interview — Martial Zinsou, créateur de KarenOS

> *Réalisée en septembre 2026, au moment de la sortie de la version 1.0.0.*

**— L'idée de KarenOS est partie de quoi ?**

> D'une frustration très concrète. En 2025, appeler un LLM commercial depuis un outil bureau, c'est trois écueils : le coût, la latence, et surtout la donnée qui transite ailleurs. J'ai commencé à tester les modèles GGUF sur un MacBook un soir, par curiosité technique. Le résultat m'a surpris : des modèles de 1 à 3 gigaoctets tenaient déjà dans la mémoire vive d'une machine ordinaire et le rendu était exploitable pour un assistant de rédaction, de relecture, de code. KarenOS est le produit de cette séance-là : donner à un bureau, sans abonnement, ce qu'une infrastructure cloud facturait cher.

**— Pourquoi t'appuyer sur llama.cpp plutôt qu'écrire ton propre moteur ?**

> Parce que c'est la décision la plus raisonnable, pas la plus gratifiante. llama.cpp est un projet exceptionnellement maîtrisé, et le serveur `llama-server` expose déjà presque tout ce dont j'avais besoin. Réécrire une inférence pour le plaisir, c'est prendre des mois pour faire moins bien... Je me suis concentré sur ce qui apporte vraiment quelque chose à l'utilisateur : la **sélection de modèles**, le **pilotage par agents**, le **multimodal**, l'**expérience d'installation**. Le moteur, je le branche, je l'optimise, je ne le réinvente pas. Le jour où un moteur meilleur sortira, KarenOS pourra le switcher sans impacter son interface, parce que le contrat entre les deux est l'API OpenAI.

**— Le choix du local, est-ce une forme de position politique ?**

> Je préfère dire une position d'ingénieur. Le cloud est formidable pour le distribué, mais dès qu'il s'agit de traitement d'avalanche de documents personnels ou de données d'entreprise sensibles, le local a un argument décisif : rien ne sort. Pour un DSI, « rien ne sort » est une phrase qu'on aime entendre. Et il y a une réalité bien plus prosaïque : un MacBook équipé de un à deux gigaoctets de modèle tourne en continu sans coût marginal. L'indépendance ici n'est pas un slogan, c'est une architecture.

**— Les agents avec exécution shell, c'est le point le plus… comment dire ?**

> Le plus dangereux, oui, disons-le. Donner à un modèle la possibilité de lancer `/bin/zsh -lc`, c'est lui donner une clé. C'est pour ça que la fonctionnalité est **désactivée par défaut**, activée **agent par agent**, et bornée deux fois : trente secondes par commande, trente actions par mission. La philosophie, c'est la délégation surveillée : l'agent propose, le journal témoigne, l'utilisateur contrôle. Un agent sans limites, ce n'est plus un outil, c'est un risque — et ça, j'ai refusé de le livrer.

**— Le mode vision et la dictée vocale locale, c'était une demande que tu t'étais faite à toi-même ?**

> Exactement. Je me suis dit : si mon assistant ne peut pas « voir » une image ni écouter ma voix sans appeler un service cloud, il n'est pas vraiment personnel. Le framework Speech d'Apple fait très bien la transcription localement. Pour la vision, tant qu'un projecteur `*.mmproj` est présent, il suffit de joindre l'image — aucune configuration. La cohérence du produit passe par ces petits riens : que tout se passe sur la machine, de bout en bout.

**— Et la partie serveur, l'image conteneur pour les DSI ?**

> C'est la fondation « entreprise » qui complète le bureau. On a compilé `llama-server` en croisé pour Linux x86-64 avec Zig, puis on a embarqué cette build dans une image réduite multi-stage. Résultat : une DSI peut déployer son propre serveur d'inférence en intranet en une commande, avec le modèle de son choix monté en volume. Le même moteur, les mêmes formats, de la machine individuelle au rack.

**— Un regret, un choix que tu referais différemment ?**

> La version « contrôle du débit » de départ. J'ai longtemps hésité entre un moteur maison et l'intégration de llama.cpp. Si je pouvais revenir, je brancherais l'écosystème plus tôt et je passerais plus de temps sur les agents — c'est là que se joue, à mon sens, la vraie valeur : transformer un chat agréable en un outil qui **fait des choses**.

**— Le mot de la fin pour un futur utilisateur ?**

> Sache que ton ordinateur peut aujourd'hui héberger un assistant de bonne tenue, qui travaille pour toi, sans publicité, sans compte, sans surveillance. KarenOS, c'est ça : rendre la souveraineté numérique trivialement installable. Et tout est en MIT — ouvre le code, améliore-le, prends-le. C'est un outil, pas un mur.

---

*KarenOS — MIT License. Dépôt : [github.com/martialzinsou/KarenOs](https://github.com/martialzinsou/KarenOs)*