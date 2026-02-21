# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Règles de travail
- Ne JAMAIS demander confirmation avant d'agir
- Implémenter directement ce qui semble le plus logique
- Ne poser une question QUE si l'ambiguïté est vraiment bloquante et/ou que tu as besoin d'avoir plus de détails
- Préférer faire le choix qui te semble le plus sensé quitte à expliquer le pourquoi après coup (si jamais je demande)
- Je ne suis pas là pour te dire si tu peux utiliser ceci ou cela. Tu utilises ce dont tu as besoin sans avoir à demander
- Quand tu commit/sauvegarde, toujours faire les sauvegardes également sur le github privé https://github.com/PatrickFarges/
- Quand je parle de toi je ne dis pas "Claude Code" mais "cloclo" donc "cloclo" se réfère toujours à toi
- tu peut répondre/expliquer ou demander en anglais, ça ne me pose pas de problème, par contre 99% du temps je te parlerais en Français.

## Vue d'ensemble

**GitHub :** `PatrickFarges/ClaudeCode` (anciennement ClaudeCraft, renommé le 2026-02-13)
**Chemin local :** `D:\Program\ClaudeCode\` — chaque sous-dossier est un projet indépendant

Monorepo contenant plusieurs sous-projets indépendants liés aux outils RH/paie SAP et au développement de jeux. Langages : Python (outils RH) et GDScript (jeu Godot). Toutes les interfaces sont en français.

**Chaque projet a son propre `CLAUDE.md` avec la documentation détaillée.**

## Convention CLAUDE.md

- La documentation détaillée de chaque projet vit dans `<projet>/CLAUDE.md`, PAS dans ce fichier racine
- Ce fichier racine ne contient que les règles globales, l'index des projets et les notes techniques communes
- Quand tu modifies la doc d'un projet, édite le `CLAUDE.md` du sous-dossier concerné
- Quand tu crées un nouveau projet : ajouter une ligne au tableau ci-dessous + créer un `CLAUDE.md` dans le dossier du projet
- Ne JAMAIS remettre de la doc projet-spécifique dans ce fichier racine

## Projets

| Projet | Dossier | Description |
|--------|---------|-------------|
| **ComparePDF** | `ComparePDF/` | Comparaison de bulletins de paie PDF PRE vs POST → rapport Excel (Python/Tkinter) |
| **CompareSAPTable** | `CompareSAPTable/` | Comparaison de tables SAP et schémas PCR → rapport Excel (Python/Tkinter) |
| **ClaudeLauncher** | `ClaudeLauncher/` | Lanceur de jeux/applications style Steam/Playnite (Python/PyQt6) |
| **ClaudeCraft** | `ClaudeCraft/` | Jeu voxel type Minecraft en GDScript/Godot 4.5+, style pastel, évoluant vers The Settlers |
| **WagetypeCatalog** | `WagetypeCatalog/` | Catalogage des rubriques de paie SAP EuHReka (données uniquement) |
| **ClocloWebUi** | `ClocloWebUi/` | Interface web pour piloter plusieurs sessions Claude Code en parallèle (Python/aiohttp) |

## Notes techniques

- **GitHub :** `https://github.com/PatrickFarges/ClaudeCode` — remote `origin`, branche principale `master`
- **GitHub ComparePDF :** `https://github.com/PatrickFarges/ComparePDF` — repo séparé, synchronisé via `git subtree push --prefix=ComparePDF`
- **GitHub CLI (`gh`) :** installé (v2.86.0), authentifié sur GitHub
- **`.gitignore` racine :** `.claude/`, `__pycache__/`, `*.pyc`, fichiers système (`.DS_Store`, `Thumbs.db`)
- Plateforme cible : Windows (`os.startfile()`, `winreg`, fallback `xdg-open` pour Linux)
- Aucun système de build, framework de test ou linting dans aucun projet
- Projets Python autonomes — pas de virtualenv partagé
- Nombres format SAP/français partout : `1.234,56-` (virgule décimale, point milliers, `-` suffixe négatif)
- L'utilisateur parle français, toutes les interfaces et messages de commit sont en français
