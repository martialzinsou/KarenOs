# Diagrammes UML — import sur Wikimedia Commons

**Auteur : Martial Zinsou**

<!--
    SEO — KarenOS · Référence projet : https://github.com/martialzinsou/KarenOs
    Canonical : https://github.com/martialzinsou/KarenOs/blob/main/docs/wikipedia/diagrammes/README.md
    Auteur   : Martial Zinsou
    Fonction : Directeur des Systèmes d'Information (DSI / IT Director)
    Titre    : Diagrammes UML KarenOS — Import Wikimedia Commons
    Description : 8 diagrammes UML (SVG) de KarenOS générés via Mermaid/Kroki : composants/déploiement, cas d'utilisation, classes, séquences inférence/chargement, machines à états moteur/agent, activité agent. Pour import sur Wikimedia Commons.
    Mots-clés : karenos, uml, diagrammes, svg, wikimedia commons, mermaid, kroki, architecture, dsi
    Langue   : fr
    robots   : index, follow
    og:title : Diagrammes UML KarenOS pour Wikimedia Commons
    og:description : 8 diagrammes UML (classes, séquences, états, activité) prêts pour import Commons.
    og:type : article
    og:url : https://github.com/martialzinsou/KarenOs/blob/main/docs/wikipedia/diagrammes/README.md
    og:image : https://raw.githubusercontent.com/martialzinsou/KarenOs/main/docs/branding/karenos-logo.png
    twitter:card : summary_large_image
-->

Ces 8 SVG sont générés depuis les sources [Mermaid](../../WIKIPEDIA.md) du projet
(sections techniques). Ils sont destinés à être **téléversés sur Wikimedia Commons**
puis référencés dans le brouillon Wikipedia (`docs/wikipedia/Brouillon_KarenOS.wiki`).

## Import (une seule fois, par Martial Zinsou)

1. Se connecter à <https://commons.wikimedia.org/wiki/Special:UploadWizard> (compte `directionDSI`).
2. Glisser-déposer les 8 `.svg`.
3. Description en français, ex. « Diagramme de classes de KarenOS, application macOS d'IA locale ».
4. Source : « œuvre propre ».
5. Licence : **CC BY-SA 4.0** ou **MIT** (concordance avec la licence du projet GitHub).
6. Catégorie : `Category:UML diagrams`.
7. Conserver exactement les noms de fichiers ci-dessous (le brouillon les référence tels quels).

## Fichiers

| Fichier à téléverser | Diagramme |
|---|---|
| `karenos-composants-deploiement.svg` | Composants et déploiement (Mac local ↔ conteneur serveur) |
| `karenos-cas-utilisation.svg` | Diagramme de cas d'utilisation |
| `karenos-classes.svg` | Diagramme de classes |
| `karenos-sequence-inference.svg` | Séquence : inférence en streaming |
| `karenos-sequence-chargement.svg` | Séquence : chargement du moteur (`/health`, 120 s) |
| `karenos-etats-moteur.svg` | Machine à états du moteur llama-server |
| `karenos-etats-agent.svg` | États d'une mission d'agent |
| `karenos-activite-agent.svg` | Boucle d'exécution d'un agent (déclencheurs, conditions de fin) |

## Après l'import

Le brouillon `Brouillon_KarenOS.wiki` référence déjà ces noms :
`[[Fichier:karenos-*.svg|vignette|…]]`. Il suffit de coller le brouillon dans
`Utilisateur:directionDSI/KarenOS` une fois les fichiers en ligne.

## Régénération

Redémarrée ensuite via l'API Kroki (depuis ce dossier) :

```bash
python3 render_svg.py
```