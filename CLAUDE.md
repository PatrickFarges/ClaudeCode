# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Vue d'ensemble

**GitHub :** `PatrickFarges/ClaudeCode` (anciennement ClaudeCraft, renommé le 2026-02-13)
**Chemin local :** `D:\Program\ClaudeCode\` — chaque sous-dossier est un projet indépendant

Monorepo contenant plusieurs sous-projets indépendants liés aux outils RH/paie SAP et au développement de jeux. Langages : Python (outils RH) et GDScript (jeu Godot). Toutes les interfaces sont en français.

## Projets

---

### ComparePDF (`ComparePDF/`)
Application desktop Python 3 / Tkinter qui compare deux PDF de bulletins de paie (PRE vs POST) et génère un rapport Excel coloré des écarts.

**Lancer :**
```bash
pip install pypdf openpyxl
python ComparePDF/Compare_PDF_V4.py
```

**Architecture (fichier unique `Compare_PDF_V4.py`, ~800 lignes) :**
- **Lignes 1-30 :** Config couleurs hex pour l'export Excel (PRE/POST/DELTA)
- **Lignes 31-154 :** Logique métier — extraction texte PDF groupé par matricule, parsing nombres FR (`1.234,56-` style SAP), calcul deltas
- **Lignes 156-252 :** Moteur de comparaison — parsing flexible (2 regex: avec/sans code rubrique), classification SUPPRIME/AJOUTE/IMPACT BRUT/RECALCUL
- **Lignes 254-403 :** Génération Excel — en-têtes multi-niveaux, sections colorées, regroupement par matricule
- **Lignes 408-762 :** Classe GUI `ComparePDFApp` — sélection fichiers, comparaison threadée, barre de progression
- **Lignes 767-800 :** Point d'entrée avec vérification dépendances

**Concepts métier :**
- Matricule : ID salarié (4-10 chiffres), regex : `(?:Matricule|Matr\.|Pers\.No\.)\s*[:.]?\s*(\d{4,10})`
- Ligne de paie : CODE (4 car.) + LIBELLE + VALEURS (Base, Tx Sal, Mt Sal, Tx Pat, Mt Pat)
- Format numérique français : virgule = décimale, point = milliers, `-` en fin = négatif
- "Mode détaillé" : affiche les RECALCUL pour régularisations rétroactives (occurrence > 1)

---

### ComparePCR (`ComparePCR/`)
Outil CLI Python de comparaison de schémas de paie SAP (Payroll Calculation Rules). Compare deux fichiers texte PRE/POST et génère un rapport Excel avec différences mot-par-mot colorisées.

**Lancer :**
```bash
pip install xlsxwriter
python ComparePCR/compare_files.py PRE_Schema.txt POST_Schema.txt [output.xlsx]
```

**Architecture (2 scripts + 1 config) :**
- **`compare_files.py` (~180 lignes) :** Point d'entrée CLI, charge `Options.ini`, valide fichiers, appelle le moteur
- **`hrsp_compare_final.py` (~580 lignes) :** Moteur de comparaison
  - Classe `HRSPComparer` : dédoublonnage, extraction clé (N premiers caractères), calcul de similarité (algo greedy matching), groupage par règle PCR
  - Classe `ExcelGenerator` : rapport XLSX avec texte riche (mots différents en rouge)
- **`Options.ini` :** Configuration des tables SAP — suffixes à supprimer (`[DeleteFileNamePart]`), nombre de caractères clés par table (`[TableCutNumber]` : PCR=9, T030=17, T510=10, etc.)

**Concepts métier :**
- Fichiers PCR : règles de paie SAP avec structure `RULE_ID (4 car.) | LINE_NUM | OPERATION | PARAMS`
- Keycut : nombre de caractères pour identifier la clé unique d'une ligne (configurable par table)
- Matching par similarité : algorithme greedy, pas de comparaison ligne-à-ligne stricte

---

### ClaudeLauncher (`ClaudeLauncher/`)
Lanceur de jeux/applications style Steam/Playnite, avec interface PyQt6 et images SteamGridDB.

**Lancer :**
```bash
pip install -r ClaudeLauncher/requirements.txt
python ClaudeLauncher/claudelauncher_v7.0.py
```

**Dépendances :** PyQt6 >= 6.6.0, requests >= 2.31.0, Pillow >= 10.0.0

**Architecture (fichier unique `claudelauncher_v7.0.py`, ~2240 lignes, 4 classes) :**
- **`ImageDownloader(QThread)`** : téléchargement asynchrone images SteamGridDB, cache local MD5 dans `~/.claudelauncher/images/`, recherche intelligente avec variantes du nom
- **`CustomImageDownloader(QThread)`** : téléchargement d'images personnalisées depuis URL avec cache MD5
- **`ProgramScanner(QThread)`** : scan multi-sources (Registry Windows, Steam `.acf`, Epic Games manifests, dossiers custom, tous les disques), classification jeux vs apps (blacklist, publishers, chemins)
- **`ClaudeLauncher(QMainWindow)`** : UI 4 onglets (Jeux, Applications, Favoris, Plus utilisés), persistance JSON dans `~/.claudelauncher/` (13 fichiers config), lancement programmes, menu contextuel (renommer, favoris, masquer, tags, images, forcer catégorie, modifier exe/arguments), barre de recherche par nom/tag, carrousel d'images personnalisées

**Config runtime :** `~/.claudelauncher/` — `favorites.json`, `launch_stats.json`, `hidden_programs.json`, `api_keys.json` (clé SteamGridDB), `overrides.json`, `custom_exes.json`, `custom_args.json`, `last_tab.json`, `custom_tags.json`, `custom_images.json`, etc.

---

### ClaudeCraft (`ClaudeCraft/`)
Jeu voxel type Minecraft en GDScript avec Godot 4.5+, style pastel.

**Lancer :**
1. Ouvrir le projet dans Godot 4.5+
2. Ouvrir `scenes/main.tscn`
3. F5 pour lancer

**Config Godot :** Physics JoltPhysics3D, résolution 1920x1080 fullscreen, cible 60 FPS.

**Architecture GDScript (`scripts/`) :**
- **`block_registry.gd`** : registre centralisé des types de blocs (15 types : AIR, GRASS, DIRT, STONE, SAND, WOOD, LEAVES, SNOW, CACTUS, PLANKS, BRICK...) avec couleurs pastel et dureté
- **`chunk.gd`** : portion du monde (16×16×256 blocs), greedy meshing (faces visibles uniquement), Ambient Occlusion, variation luminosité par face, collision ConcavePolygon
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers max, Mutex), 5 noises Simplex/Perlin (terrain, élévation, température, humidité, cavernes), arbres 3D procéduraux (chêne, bouleau, pin, cactus)
- **`world_manager.gd`** : orchestration chargement/déchargement chunks, `render_distance=4`, max 2 meshes/frame, hysteresis de déchargement, spawn mobs passifs (10% par chunk, max 20) et PNJ villageois (5% par chunk, max 10)
- **`npc_villager.gd`** : PNJ humanoïdes utilisant les 18 modèles GLB BlockPNJ (Kenney.nl, `character-a` à `character-r`). Chargement statique des modèles, vagabondage (vitesse 2.0, timer 3-8s, 50% move), évitement eau/falaises, rotation vers direction de déplacement. Spawn uniquement sur GRASS/DARK_GRASS (pas sable). Script indépendant de PassiveMob (preload via `const NpcVillagerScene = preload(...)` dans world_manager). **Animations GLB activées** : 27 animations embarquées par modèle (walk, idle, sprint, attack, sit, die, etc.), recherche récursive de l'AnimationPlayer, loop forcé (`Animation.LOOP_LINEAR`), transition walk↔idle selon l'état de mouvement. **Auto-jump** : détection bloc solide devant les pieds + espace libre au-dessus → saut automatique (velocity.y=5.0) avec maintien du mouvement horizontal en l'air. **Anti-blocage** : si le PNJ ne bouge pas de >0.3 unités en 1s, changement de direction automatique
- **`passive_mob.gd`** : mobs animaux (SHEEP, COW, CHICKEN) en BoxMesh colorés, vagabondage (vitesse 1.5, timer 2-5s), spawn sur herbe et sable
- **`player.gd`** : contrôle FPS (CharacterBody3D), minage progressif (basé sur hardness), placement de blocs (vérif AABB chevauchement), inventaire 9 slots hotbar
- **`craft_registry.gd`** : recettes craft main (C) et table (près d'une CRAFTING_TABLE)
- **`audio_manager.gd`** : pool 8 AudioStreamPlayer2D + 6 3D, sons ambiants par biome avec crossfade
- **`locale.gd`** : traductions FR/EN

**4 biomes procéduraux :** Désert (temp>0.65, humid<0.35), Forêt (temp 0.45-0.7, humid>0.55), Montagne (temp<0.35), Plaines (défaut)

**Scène principale (`scenes/main.tscn`) :** WorldManager + Player (spawn à y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers (Hotbar, Crosshair, Inventory, Crafting, VersionHUD, AudioManager)

**Assets :** `Audio/` (~334 fichiers OGG/MP3), `BlockPNJ/` et `MiniPNJ/` (modèles 3D FBX/GLB/OBJ, personnages Kenney.nl), `NPC/` (dossier PNJ)

**Documentation embarquée :** `ARCHITECTURE.md`, `QUICKSTART.md`, `BIOMES.md`, `MOVEMENT.md`, `MULTITHREADING.md`, `PERFORMANCE.md`

---

### WagetypeCatalog (`WagetypeCatalog/`)
Projet de catalogage des rubriques de paie SAP EuHReka. Pas de code exécutable — uniquement des données sources et un fichier Excel consolidé.

**Contenu :**
- **`WageType_Catalog_EuHReka_GROUPED.xlsx`** : catalogue consolidé et groupé des wage types
- **`Tables pour creer le Wagetype Catalog/`** : ~25 fichiers texte de tables SAP sources (T512T = catalogue rubriques ~12K lignes, T52C0 = mapping paie→compta ~69K lignes, T030 = config codes ~13K lignes, Y00BA_TAB_* = mappings comptes symboliques/comptables)

**Pipeline de données :** Rubriques (T512T/T512W) → Comptes symboliques (Y00BA_TAB_FISADF/FISAAC) → Comptes comptables (T52C0/T52C1) → Grand Livre FI

---

### ClocloWebUi (`ClocloWebUi/`)
Interface web locale (127.0.0.1:8420) pour piloter plusieurs sessions Claude Code en parallèle, une par projet du monorepo. Remplace le terminal CLI par un navigateur avec sidebar de navigation.

**Lancer :**
```bash
pip install -r ClocloWebUi/requirements.txt
python ClocloWebUi/server.py
# Ouvrir http://127.0.0.1:8420
```

**Dépendances :** aiohttp >= 3.9, pywinpty >= 2.0

**Architecture (3 fichiers) :**
- **`server.py` (~300 lignes) :** Backend aiohttp async
  - `scan_projects()` : scan `D:\Program\ClaudeCode`, parse CLAUDE.md via regex pour extraire descriptions
  - `Session` : wrapper PTY pywinpty (spawn `claude.exe`, read pump via `asyncio.run_in_executor`, write, resize, kill). Buffer circulaire 128 KB (`_output_buffer`) rejoué à chaque attach pour ne pas perdre l'historique au refresh
  - `SessionManager` : dict de sessions par nom de projet, lazy creation (PTY spawn au premier clic)
  - Routes : `GET /` (index.html), `GET /api/projects` (JSON), `WS /ws` (terminal I/O)
  - Cleanup : kill de tous les PTY au shutdown
  - **Detail clé :** supprime toutes les variables d'env contenant `CLAUDE` avant spawn pour éviter la détection "nested session"
- **`static/index.html` (~200 lignes) :** SPA avec xterm.js + sidebar projets
  - CDN : `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0` (attention : les anciennes versions `@5.3.0`/`@0.8.0` retournent 404 sur jsdelivr)
  - Un seul `Terminal` xterm.js réutilisé, `term.reset()` au switch projet
  - WebSocket unique `/ws`, auto-reconnexion toutes les 2s
  - Protocole JSON + base64 : `attach`, `input`, `resize`, `detach` (client→serveur) / `output`, `attached`, `exited` (serveur→client)
  - Décodage sortie : `atob()` → `Uint8Array` → `term.write(bytes)` pour UTF-8 correct (pas `atob` direct qui donne du latin1 cassé)
- **`static/style.css` (~170 lignes) :** Thème Tokyo Night (#1a1b26), layout flexbox, sidebar 320px

**Problèmes résolus durant le développement :**
1. CDN xterm.js 404 → corrigé vers `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0`
2. Caractères Unicode cassés (ââââ) → décodage base64 en `Uint8Array` au lieu de string `atob()`
3. Terminal vide au refresh → buffer de replay 128 KB côté serveur, rejoué à chaque `attach`

---

## Notes techniques

- **GitHub :** `https://github.com/PatrickFarges/ClaudeCode` — remote `origin`, branche principale `master`
- **GitHub ComparePDF :** `https://github.com/PatrickFarges/ComparePDF` — repo séparé, synchronisé via `git subtree push --prefix=ComparePDF`
- **GitHub CLI (`gh`) :** installé (v2.86.0), authentifié sur GitHub
- Plateforme cible : Windows (`os.startfile()`, `winreg`, fallback `xdg-open` pour Linux)
- Aucun système de build, framework de test ou linting dans aucun projet
- Projets Python autonomes — pas de virtualenv partagé
- Nombres format SAP/français partout : `1.234,56-` (virgule décimale, point milliers, `-` suffixe négatif)
- L'utilisateur parle français, toutes les interfaces et messages de commit sont en français
