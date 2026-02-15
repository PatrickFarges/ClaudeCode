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

### CompareSAPTable (`CompareSAPTable/`)
Application desktop Python 3 / Tkinter de comparaison de tables SAP et de schémas de paie (PCR). Réécriture complète depuis Free Pascal/Lazarus (PCRandTables v0.92b) vers Python, avec gain de performance majeur (~2 secondes au lieu de ~15 pour traiter toutes les tables). Compare deux ensembles de fichiers texte (PRE vs POST) et génère un rapport Excel avec les différences, les mots modifiés étant surlignés en rouge.

**Lancer :**
```bash
pip install xlsxwriter
python CompareSAPTable/main.py
```

**Dépendances :** xlsxwriter (obligatoire)

**Architecture (4 fichiers Python, ~1700 lignes) :**
- **`main.py` (~824 lignes) :** GUI Tkinter + orchestration
  - Classe `CompareSAPApp(tk.Tk)` : fenêtre principale 1280x720, toolbar (Execute/Save As/Clear/Options/About), champs PRE/POST avec Browse, grille 3 colonnes synchronisées (Table | Before | After) avec scrollbar partagée, panneau stats à droite
  - Classe `OptionsDialog(tk.Toplevel)` : config KeyValue pour schemas, override global, auto-save, affichage PIT, gestion des keycuts par table (ajout/suppression)
  - `load_config()` / `save_config_option()` : lecture/écriture `Options.ini` (compatible avec le format Pascal original, `:=` → `=`)
  - `resolve_keycut()` : résolution du nombre de caractères clé selon la table (TableCutNumber → GeneriqueFiles → override global)
  - `run_comparison()` : pipeline complet — mode fichier ou dossier, appariement par nom de fichier, extraction nom de table, comparaison, tri, colorisation
- **`comparator.py` (~442 lignes) :** Moteur de comparaison (portage fidèle de `compare_file.pas`)
  - `get_changes()` : chargement avec fallback encodage (UTF-8 → Latin-1 → CP1252), normalisation, dédoublonnage par set, exclusion des dates SAP
  - `get_score()` : scoring de similarité entre deux lignes — pondération quadratique sur les N premiers caractères (keycut), bonus mots communs après le keycut
  - `fill_scheme()` : matching greedy pour schémas PCR — groupement par nom de règle (4 premiers car.), gestion PIT (lignes avec numéro de ligne différent mais contenu identique), insertion/ajout des lignes non matchées
  - `_match_by_key()` : matching pour tables non-PCR — appariement par clé (N premiers caractères sans espaces)
  - `colorize_change()` : colorisation mot-par-mot — comparaison positionnelle, détection de mots déplacés (`_word_elsewhere`), gestion des longueurs différentes
- **`excel_writer.py` (~186 lignes) :** Export XLSX via xlsxwriter
  - Classe `ComparisonResult` : conteneur (table_name, pre_lines, post_lines, is_pcr, keycut)
  - `write_excel()` : en-tête configurable (Table | Before | After | Comments), sous-en-têtes par table/schéma en orange, texte riche `write_rich_string()` pour les mots différents en rouge
- **`win_dnd.py` (~244 lignes) :** Drag-and-drop natif Windows sans dépendance externe
  - Trampoline en code machine x64 pur (VirtualAlloc PAGE_EXECUTE_READWRITE) qui intercepte `WM_DROPFILES` sans toucher au GIL Python
  - Polling toutes les 50ms via `tk.after()` depuis le thread principal — lecture sûre du handle HDROP stocké en mémoire partagée
  - Gestion UIPI (ChangeWindowMessageFilterEx) pour les processus élevés

**Données de test incluses :**
- `PRE_Tables/` et `POST_Tables/` : ~85 fichiers de tables SAP (T030, T510, T512T, T512W, T5F*, Y00BA_TAB_*, V_T5F*, etc.)
- `PRE_Schema.txt` et `POST_Schema.txt` : schémas de paie complets (~4.6 Mo chacun)

**Config (`Options.ini`, ~270 lignes) :**
- `[DeleteFileNamePart]` : 8 suffixes à supprimer des noms de fichiers (_DP9_BEFORE, _ED5_AFTER, etc.)
- `[TableCutNumber]` : ~85 tables avec leur keycut spécifique (PCR=9, T030=17, T510=10, CSKS=63, etc.) — valeur 1000 = comparer la ligne entière
- `[GeneriqueFiles]` : keycuts génériques par pattern de nom (Generique=10, RunPosting=19, Results=8, etc.)
- `[GenOptions]` : auto-save, affichage PIT identiques, override global des keycuts
- `[ColorDifference]` : couleur des différences (rouge par défaut)
- `[StandardFont]` : police Calibri 11pt

**Présentation du résultat :**
- Colonne A : nom de la table SAP (ou nom de la règle PCR sur 4 caractères)
- Colonne B : lignes supprimées/modifiées (version PRE), mots changés en rouge
- Colonne C : lignes ajoutées/modifiées (version POST), mots changés en rouge
- Colonne D : commentaires / transports (à remplir manuellement)

**Historique :** Réécriture de `ComparePCRandTables/PCRandTables.exe` (Free Pascal/Lazarus, v0.92b, ~2048 lignes Pascal dans `compare_file.pas` + `analyseprepost.pas`) en Python. Le code source Pascal original et l'exécutable sont conservés dans le sous-dossier `ComparePCRandTables/`.

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
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers max, Mutex), 5 noises Simplex/Perlin (terrain, élévation, température, humidité, cavernes), arbres 3D procéduraux (chêne, bouleau, pin, cactus). **Passe 4 structures** : après eau, applique les structures prédéfinies via `_apply_structures()` (test AABB + patch blocs)
- **`structure_manager.gd`** : Autoload — chargement des structures JSON depuis `res://structures/`, décompression RLE, résolution palette → BlockType, fournit `get_placement_data()` (snapshot thread-safe) au chunk_generator. Placements lus depuis `user://structures_placement.json` ou `res://structures/placements.json`
- **`world_manager.gd`** : orchestration chargement/déchargement chunks, `render_distance=4`, max 2 meshes/frame, hysteresis de déchargement, spawn mobs passifs (10% par chunk, max 20) et PNJ villageois (5% par chunk, max 10). Connecte StructureManager au ChunkGenerator au démarrage
- **`npc_villager.gd`** : PNJ humanoïdes utilisant les 18 modèles GLB BlockPNJ (Kenney.nl, `character-a` à `character-r`). Chargement statique des modèles, vagabondage (vitesse 2.0, timer 3-8s, 50% move), évitement eau/falaises, rotation vers direction de déplacement. Spawn uniquement sur GRASS/DARK_GRASS (pas sable). Script indépendant de PassiveMob (preload via `const NpcVillagerScene = preload(...)` dans world_manager). **Animations GLB activées** : 27 animations embarquées par modèle (walk, idle, sprint, attack, sit, die, etc.), recherche récursive de l'AnimationPlayer, loop forcé (`Animation.LOOP_LINEAR`), transition walk↔idle selon l'état de mouvement. **Auto-jump** : détection bloc solide devant les pieds + espace libre au-dessus → saut automatique (velocity.y=5.0) avec maintien du mouvement horizontal en l'air. **Anti-blocage** : si le PNJ ne bouge pas de >0.3 unités en 1s, changement de direction automatique
- **`passive_mob.gd`** : mobs animaux (SHEEP, COW, CHICKEN) en BoxMesh colorés, vagabondage (vitesse 1.5, timer 2-5s), spawn sur herbe et sable
- **`player.gd`** : contrôle FPS (CharacterBody3D), minage progressif (basé sur hardness), placement de blocs (vérif AABB chevauchement), inventaire 9 slots hotbar
- **`craft_registry.gd`** : recettes craft main (C) et table (près d'une CRAFTING_TABLE)
- **`audio_manager.gd`** : pool 8 AudioStreamPlayer2D + 6 3D, sons ambiants par biome avec crossfade
- **`locale.gd`** : traductions FR/EN

**4 biomes procéduraux :** Désert (temp>0.65, humid<0.35), Forêt (temp 0.45-0.7, humid>0.55), Montagne (temp<0.35), Plaines (défaut)

**Scène principale (`scenes/main.tscn`) :** WorldManager + Player (spawn à y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers (Hotbar, Crosshair, Inventory, Crafting, VersionHUD, AudioManager)

**Système de structures prédéfinies (`structures/`) :**
Permet de placer des constructions (villages, tours, cabanes...) n'importe où dans le monde généré. Les structures sont appliquées pendant la génération des chunks (passe 4), donc zéro coût en rendu.

- **Format structure JSON :** palette de noms de blocs + données RLE en ordre layer-first (`index = y * sx * sz + z * sx + x`). Bloc spécial `KEEP` (valeur 255) = ne pas toucher le terrain. `AIR` = creuser.
- **`structures/placements.json`** : liste de `{"structure": "nom", "position": [x, y, z]}` indiquant où placer chaque structure en coordonnées monde
- **`scripts/convert_schem.py`** (~940 lignes) : convertisseur `.schem` (Sponge Schematic v2/v3) → JSON ClaudeCraft. Parseur NBT maison (zéro dépendance), décodage varint, mapping intelligent Minecraft→ClaudeCraft (200+ blocs explicites + ~60 règles par pattern pour escaliers, dalles, laines, végétation...). Usage : `python scripts/convert_schem.py fichier.schem [--info] [--output chemin.json]`
- **Pipeline** : asset `.schem` → `convert_schem.py` → `structures/nom.json` → ajouter dans `placements.json` → apparaît automatiquement dans le monde

**Assets :** `Audio/` (~334 fichiers OGG/MP3), `BlockPNJ/` et `MiniPNJ/` (modèles 3D FBX/GLB/OBJ, personnages Kenney.nl), `NPC/` (dossier PNJ), `assets/Lobbys/` (assets Minecraft .schem/.mca à convertir)

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
- **`.gitignore` racine :** `.claude/`, `__pycache__/`, `*.pyc`, fichiers système (`.DS_Store`, `Thumbs.db`)
- Plateforme cible : Windows (`os.startfile()`, `winreg`, fallback `xdg-open` pour Linux)
- Aucun système de build, framework de test ou linting dans aucun projet
- Projets Python autonomes — pas de virtualenv partagé
- Nombres format SAP/français partout : `1.234,56-` (virgule décimale, point milliers, `-` suffixe négatif)
- L'utilisateur parle français, toutes les interfaces et messages de commit sont en français

## Prochain chantier — Éditeur de structures ClaudeCraft

**Objectif :** Application desktop (Python/Tkinter ou PyQt) pour charger, convertir, visualiser en 3D et modifier des assets de structures pour ClaudeCraft.

**Workflow prévu :**
1. **Charger** un asset Minecraft `.schem` OU un asset ClaudeCraft `.json` déjà converti
2. **Convertir** automatiquement le `.schem` → format JSON ClaudeCraft (via le moteur de `convert_schem.py`)
3. **Visualiser en 3D** la structure sous tous les angles (rotation, zoom, pan) — rendu voxel des blocs avec les couleurs pastel ClaudeCraft
4. **Modifier** la structure : ajouter/supprimer des cubes individuels, déplacer des éléments (arbres, etc.), changer le type de bloc
5. **Enregistrer** l'asset modifié au format JSON ClaudeCraft dans `structures/`

**Contexte existant :**
- `scripts/convert_schem.py` (~940 lignes) : parseur NBT + convertisseur .schem → JSON, à réutiliser comme moteur de conversion
- `scripts/block_registry.gd` : référence des types de blocs et couleurs pastel (à porter en Python pour le rendu)
- `structures/` : dossier cible pour les assets finaux
- `assets/Lobbys/` : assets Minecraft source de test (Natural Lobby 203x104x203, Factions Spawn 203x256x203)
- Structures de taille variable : de petites cabanes (5x12x5) à de grands villages (200x250x200)
