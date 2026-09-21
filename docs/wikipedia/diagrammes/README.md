# Diagrammes UML — import sur Wikimedia Commons

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