# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Règles de travail
- Ne JAMAIS demander confirmation avant d'agir
- Implémenter directement ce qui semble le plus logique
- Ne poser une question QUE si l'ambiguïté est vraiment bloquante et/ou que tu as beosin d'avoir plus de détails
- Préférer faire le choix qui te semble le plus sensé quite à expliquer le pourquoi après coup (si jamais je demande)
- Je ne suis pas là pour te dire si tu peux utiliser ceci ou cela. Tu utilises ce dont tu as besoin sans avoir à demander
- Quand tu commit/sauvegarde, toujours faire les sauvegardes également sur le github privé https://github.com/PatrickFarges/
- Quand je parle de toi je ne dis pas "Claude Code" mais "cloclo" donc "cloclo" se referre toujours à toi
- tu peut répondre/expliquer ou demander en anglais, ça ne me pose pas de problème, par contre 99% du temps je te parlerais en Français.

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
- **`block_registry.gd`** : registre centralisé des types de blocs (65 types, enum 0-64). **Blocs originaux (0-24)** : AIR, GRASS, DIRT, STONE, SAND, WOOD, LEAVES, SNOW, CACTUS, DARK_GRASS, GRAVEL, PLANKS, CRAFTING_TABLE, BRICK, SANDSTONE, WATER, COAL_ORE, IRON_ORE, GOLD_ORE, IRON_INGOT, GOLD_INGOT, FURNACE, STONE_TABLE, IRON_TABLE, GOLD_TABLE. **Variantes de pierre (25-31)** : COBBLESTONE, MOSSY_COBBLESTONE, ANDESITE, GRANITE, DIORITE, DEEPSLATE, SMOOTH_STONE. **Bois par essence (32-43)** : SPRUCE/BIRCH/JUNGLE/ACACIA/DARK_OAK/CHERRY _LOG et _PLANKS. **Feuillages (44-49)** : SPRUCE/BIRCH/JUNGLE/ACACIA/DARK_OAK/CHERRY _LEAVES. **Minerais (50-51)** : DIAMOND_ORE, COPPER_ORE. **Raffinés (52-55)** : DIAMOND_BLOCK, COPPER_BLOCK, COPPER_INGOT, COAL_BLOCK. **Naturels (56-60)** : CLAY, PODZOL, ICE, PACKED_ICE, MOSS_BLOCK. **Fonctionnels (61-64)** : GLASS, BOOKSHELF, HAY_BLOCK, BARREL. Chaque bloc a couleur pastel, dureté, textures par face. `is_workstation()` (const `WORKSTATION_BLOCKS` Dictionary avec BARREL). `get_block_tint()` retourne des tints par feuillage (cerisier rose, bouleau jaune-vert, etc.)
- **`chunk.gd`** : portion du monde (16×16×256 blocs), greedy meshing (faces visibles uniquement), Ambient Occlusion, variation luminosité par face, collision ConcavePolygon
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers max, Mutex), 6 noises Simplex/Perlin (terrain, élévation, température, humidité, cavernes, stone_var). **Arbres par biome** : forêt=chêne+30% chêne noir, plaines=bouleau (BIRCH_LOG/LEAVES), montagne=sapin (SPRUCE_LOG/LEAVES), désert=cactus+acacia rare. **Passe 1.5 souterraine** : DEEPSLATE sous y<16, veines d'ANDESITE/GRANITE/DIORITE (noise ranges), DIAMOND_ORE (y<16, rare), COPPER_ORE (y<50, commun). **Passe 1.7** : MOSS_BLOCK sur murs de grottes. **Passe 3** : ICE sur eau en montagne, CLAY près de l'eau, PODZOL en forêt dense (~15%). **Passe 4 structures** : applique les structures prédéfinies via `_apply_structures()` (test AABB + patch blocs)
- **`structure_manager.gd`** : Autoload — chargement des structures JSON depuis `res://structures/`, décompression RLE, résolution palette → BlockType, fournit `get_placement_data()` (snapshot thread-safe) au chunk_generator. Placements lus depuis `user://structures_placement.json` ou `res://structures/placements.json`
- **`world_manager.gd`** : orchestration chargement/déchargement chunks, `render_distance=4`, max 2 meshes/frame, hysteresis de déchargement, spawn mobs passifs (10% par chunk, max 20) et PNJ villageois (5% par chunk, max 20). Connecte StructureManager au ChunkGenerator au démarrage. **POI Manager** : instancie `POIManagerScript` pour tracker les workstations, scan des chunks au chargement (range y_min→y_max), cleanup au déchargement. **Professions** : assigne une profession déterministe par hash (`(hash_val * 7 + 3) % 9`) et le modèle GLB correspondant via `VProfession.get_model_for_profession()`. Passe `poi_manager` aux NPCs. Libère les POI claimés quand les NPCs sont despawn
- **`villager_profession.gd`** : données statiques des professions et emploi du temps. **Enum Profession** (9 valeurs) : NONE, BUCHERON, MENUISIER, FORGERON, BATISSEUR, FERMIER, BOULANGER, CHAMAN, MINEUR. **Enum Activity** (5 valeurs) : WANDER, WORK, GATHER, GO_HOME, SLEEP. **PROFESSION_DATA** : mapping profession → workstation BlockType (constantes entières locales BT_CRAFTING_TABLE=12, BT_FURNACE=21, BT_STONE_TABLE=22, BT_IRON_TABLE=23, BT_GOLD_TABLE=24, BT_BARREL=64), 2 modèles GLB par profession (répartis dans les 18 character-a→r), animation de travail, noms FR/EN. **SCHEDULE** : 8 plages horaires (0-6 SLEEP, 6-8 WANDER, 8-12 WORK, 12-14 GATHER, 14-17 WORK, 17-19 GATHER, 19-20 GO_HOME, 20-24 SLEEP). Fonctions statiques : `get_activity_for_hour()`, `get_workstation_block()`, `get_model_for_profession()`, `get_profession_name()`, `get_work_anim()`
- **`poi_manager.gd`** : gestionnaire de Points of Interest (workstations). **`poi_registry`** : Dictionary Vector3i → {block_type, claimed_by, chunk_pos}. **`WORKSTATION_TYPES`** : const Dictionary {12,21,22,23,24,64} pour lookup O(1) (inclut BARREL). `scan_chunk(chunk_pos, packed_blocks, y_min, y_max)` : scan limité au range vertical utile. `find_nearest_unclaimed(profession, world_pos)` : cherche le POI libre le plus proche pour la profession. `claim_poi()` / `release_poi()` : système de réservation (1 villageois = 1 POI). `remove_chunk_pois()` : cleanup au déchargement de chunk. Utilise `preload()` pour VillagerProfession et constantes locales CHUNK_SIZE/HEIGHT (évite dépendances class_name)
- **`npc_villager.gd`** : PNJ humanoïdes avec professions et emploi du temps. Utilise les 18 modèles GLB BlockPNJ (Kenney.nl, `character-a` à `character-r`), 2 modèles par profession. **Système de professions** : `var profession: int`, assigné au spawn par WorldManager, détermine le modèle GLB et le workstation cible. **Emploi du temps** : vérifie le schedule toutes les 2s via `_day_night.get_hour()`, dispatche vers 5 comportements : `_behavior_wander` (errance classique), `_behavior_sleep` (immobile la nuit), `_behavior_gather` (errance dans un rayon de 15 blocs autour de home), `_behavior_go_home` (marche vers spawn), `_behavior_work` (claim POI → marche vers workstation → animation de travail). **Navigation** : `_walk_toward(target, delta)` avec détour perpendiculaire anti-stuck (2s de blocage → déviation 2s). **POI** : `claimed_poi: Vector3i`, claim/release via `poi_manager`. **Mouvement commun** : `_apply_movement(delta)` factorisé (auto-jump, évitement eau/falaises, stuck detection). **Animations GLB** : 27 animations embarquées par modèle, loop forcé, transition walk↔idle↔attack selon état. `get_info_text()` retourne "Forgeron - Au travail" etc.
- **`passive_mob.gd`** : mobs animaux (SHEEP, COW, CHICKEN) en BoxMesh colorés, vagabondage (vitesse 1.5, timer 2-5s), spawn sur herbe et sable
- **`player.gd`** : contrôle FPS (CharacterBody3D), minage progressif (basé sur hardness, accéléré par les outils), placement de blocs (vérif AABB chevauchement), inventaire 9 slots hotbar + slots outils parallèles (`hotbar_tool_slots`) + slots nourriture parallèles (`hotbar_food_slots`), intégration HandItemRenderer pour le bras FPS. **Gestion hotbar** : `assign_hotbar_slot()` remplace le bloc ET efface l'outil/nourriture du slot (permet de remplacer un outil par un bloc depuis l'inventaire). Touches 1-9 autorisées quand inventaire ouvert pour changer de slot. **Système de nourriture** : `_handle_eating(delta)` — maintenir clic droit pour manger (2s), émet des particules rouges (`_spawn_eating_particles`), joue un son de mastication périodique, restaure 4 PV à la fin. `_is_food_slot()` vérifie si le slot actuel est alimentaire. `_update_hand_display()` passe la rotation/scale par outil au HandItemRenderer via `ToolRegistry.get_hand_rotation()` / `get_hand_scale()`
- **`hand_item_renderer.gd`** : rendu du bras et de l'item en main (vue FPS). Attaché comme enfant de Camera3D. Bras BoxMesh couleur peau (ARM_SIZE 0.15×0.55×0.15) masqué quand un item est tenu, visible uniquement mains vides. Cube texturé du bloc actif (BLOCK_SIZE 0.28, textures par face depuis TexturesPack avec tint) ou modèle 3D d'outil. Trois chemins de rendu : `update_held_item(BlockType)` pour les blocs, `update_held_tool_model(ArrayMesh)` pour JSON Blockbench, `update_held_tool_node(Node3D, hand_rotation, hand_scale)` pour GLB/glTF avec auto-scale AABB et rotation par outil. **GLB render** : layers 1+2 (visible caméra FPS + éclairé par DirectionalLight), auto-centrage basé sur AABB calculé récursivement (`_compute_model_aabb`). **Bobbing** : balancement avant/arrière (rotation X ±12°, ±20° au sprint) au rythme de la marche. **Swing** : animation Tween (-30° en X, 0.3s) au minage/placement. Cache de matériaux par texture+tint
- **`item_model_loader.gd`** : parseur Minecraft JSON model (Blockbench) → ArrayMesh Godot. Parse les `elements` (from/to en coords 0-16), UV mapping normalisé (pixels → 0-1) avec rotation UV (90/180/270), chargement textures PNG, rotations d'éléments (angle/axis/origin), application du transform `firstperson_righthand` (scale, rotation euler, translation). Groupement par texture pour minimiser les surfaces. Cache statique des modèles parsés
- **`tool_registry.gd`** : registre des outils disponibles (enum `ToolType` : NONE, STONE_AXE, STONE_PICKAXE, STONE_SHOVEL, STONE_HOE, STONE_HAMMER, DIAMOND_AXE, DIAMOND_PICKAXE, IRON_PICKAXE, STONE_SWORD, DIAMOND_SWORD, NETHERITE_SWORD, BOW, SHIELD). Chaque outil a un chemin vers son modèle (`.json` Blockbench ou `.glb`/`.gltf`), ses textures, un dictionnaire de multiplicateurs de minage par type de bloc, une durabilité, et pour les GLB : `hand_rotation` (Vector3 degrés) et `hand_scale` (float). **Mining speeds étendus** : les haches couvrent tous les types de bois (6 essences × log+planks) + bookshelf/barrel ; les pioches couvrent toutes les variantes de pierre + copper/diamond ore ; la pelle couvre clay/podzol/moss_block ; la houe couvre les 7 types de feuilles + hay_block. `get_tool_node()` détecte l'extension et retourne un Node3D prêt à l'emploi (GLB instantié ou JSON→MeshInstance3D). `get_hand_rotation()` / `get_hand_scale()` retournent les paramètres de tenue par outil (défaut : rotation diagonale -25/-135/45, scale 0.35). `get_tool_mesh()` pour accès direct ArrayMesh (JSON uniquement)
- **`craft_registry.gd`** : ~61 recettes craft réparties en 6 catégories. **Hand (tier 0)** : planches (7 recettes, 1 par essence de bois). **Furnace** : cuisson (pierre lisse, verre, lingots cuivre, diamant, brique). **Wood Table (tier 1)** : pavé, mousse, foin, bibliothèque, tonneau, blocs de charbon/cuivre, verre lot. **Stone Table (tier 2)** : andésite, granite, diorite, glace compactée, pierre lisse lot, deepslate. **Iron Table (tier 3)** : productions en masse. **Gold Table (tier 4)** : productions maximales
- **`audio_manager.gd`** : pool 8 AudioStreamPlayer2D + 6 3D, sons ambiants par biome avec crossfade. **Son manger** : `play_eat_sound()` joue `Audio/eating-effect-254996.mp3` avec pitch aléatoire. **Ambiance Forest par heure** : `forest_ambient_by_hour` mappe 7 plages horaires vers 11 fichiers MP3 réels (`Audio/Forest/`), remplaçant l'ambiance procédurale pour le biome Forêt. Détection de l'heure via `day_night_cycle.get_hour()`, crossfade automatique au changement de plage horaire. Les autres biomes gardent l'ambiance procédurale
- **`locale.gd`** : traductions FR/EN — 65 noms de blocs, ~61 noms de recettes, labels UI inventaire (7 onglets) et crafting
- **`texture_manager.gd`** : gestionnaire de texture array (80 layers, indices 0-79). Charge les PNG depuis `TexturesPack/Aurore Stone/assets/minecraft/textures/block/`, redimensionne en 16×16, génère une `Texture2DArray` pour le shader. Couvre toutes les variantes : 6 essences de bois (log top/side + planks), 7 types de feuilles, 7 variantes de pierre, minerais, naturels, décoratifs
- **`inventory_ui.gd`** : inventaire avec 7 onglets (TOUT, Terrain, Bois, Pierre, Minerais, Déco, Stations), grille 8 colonnes, tri par rareté. **Clic gauche ET droit** sur un bloc assigne au slot hotbar actif. Panneau 780px avec scroll

**4 biomes procéduraux :** Désert (temp>0.65, humid<0.35), Forêt (temp 0.45-0.7, humid>0.55), Montagne (temp<0.35), Plaines (défaut)

**Scène principale (`scenes/main.tscn`) :** WorldManager + Player (spawn à y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers (Hotbar, Crosshair, Inventory, Crafting, VersionHUD, AudioManager)

**Système de structures prédéfinies (`structures/`) :**
Permet de placer des constructions (villages, tours, cabanes...) n'importe où dans le monde généré. Les structures sont appliquées pendant la génération des chunks (passe 4), donc zéro coût en rendu.

- **Format structure JSON :** palette de noms de blocs + données RLE en ordre layer-first (`index = y * sx * sz + z * sx + x`). Bloc spécial `KEEP` (valeur 255) = ne pas toucher le terrain. `AIR` = creuser.
- **`structures/placements.json`** : liste de `{"structure": "nom", "position": [x, y, z]}` indiquant où placer chaque structure en coordonnées monde
- **`scripts/convert_schem.py`** (~940 lignes) : convertisseur `.schem` (Sponge Schematic v2/v3) → JSON ClaudeCraft. Parseur NBT maison (zéro dépendance), décodage varint, mapping intelligent Minecraft→ClaudeCraft (260+ blocs explicites incluant les 6 essences de bois, 7 variantes de pierre, minerais cuivre/diamant, + ~60 règles par pattern pour escaliers, dalles, laines, végétation...). Usage : `python scripts/convert_schem.py fichier.schem [--info] [--output chemin.json]`
- **Pipeline** : asset `.schem` → `convert_schem.py` → `structures/nom.json` → ajouter dans `placements.json` → apparaît automatiquement dans le monde

**Structure Viewer (`scripts/structure_viewer.py`, ~1920 lignes) :**
Application desktop PyQt6/PyOpenGL de visualisation 3D de structures voxel et de modèles 3D (GLB/OBJ). Zéro dépendance supplémentaire pour le parsing GLB/OBJ (parseurs maison avec numpy).

```bash
pip install PyQt6 PyOpenGL numpy
python scripts/structure_viewer.py
python scripts/structure_viewer.py "assets/Weapon/GLB/diamond_axe_minecraft.glb"
```

- **Formats voxel** : `.json` (ClaudeCraft), `.schem` (Sponge Schematic), `.litematic` (Litematica) — rendu face-culled avec couleurs pastel ClaudeCraft
- **Formats mesh** : `.glb` (glTF Binary), `.obj` (Wavefront OBJ) — rendu triangle avec éclairage directionnel simulé
- **Parseur GLB maison** (~180 lignes) : header 12 octets + chunks JSON/BIN, `_read_accessor()` numpy (FLOAT/UINT/UBYTE avec stride), traversée récursive des nœuds avec accumulation des transforms 4x4 (quaternion→matrice), couleur par submesh : COLOR_0 > baseColorFactor > KHR_materials_pbrSpecularGlossiness > gris défaut
- **Parseur OBJ** (~70 lignes) : vertex colors Kenney (`v x y z r g b`), lecture `.mtl` pour couleur Kd, triangulation fan, fallback encodage UTF-8→Latin-1→CP1252
- **Classes données** : `SubMesh` (positions/normals/indices numpy + couleur), `MeshData` (bbox, centre, dimensions, `origin_analysis()` : centre/bas-centre/coin/décalé)
- **Rendu mesh OpenGL** : 2 display lists (filled + wireframe), `glDisable(GL_CULL_FACE)` pour meshes double-sided, wireframe overlay avec `GL_POLYGON_OFFSET_LINE`
- **Grille mesh** : centrée sur l'origine (pas sur le mesh), espacement adaptatif (0.1/0.5/1/5/10 selon la taille)
- **File browser** : navigateur de fichiers intégré, icône rose (`#f38ba8`) pour meshes vs bleu (`#89b4fa`) pour voxels
- **Panneau info mesh** : dimensions, bbox min/max, centre, analyse d'origine, vertices/triangles, sous-objets avec couleurs
- **Contrôles** : clic droit=rotation, clic gauche=pan X/Y, Ctrl+clic gauche=pan Z, molette=zoom, R=reset, F=face, T=dessus, W=wireframe, I=infos, Ctrl+O=ouvrir, Ctrl+S=exporter JSON (voxel uniquement)
- **Config persistante** : `~/.claudecraft_viewer_config.json` (dernier répertoire)

**Assets :** `Audio/` (~334 fichiers OGG/MP3, dont `Audio/Forest/` 11 MP3 d'ambiance par heure du jour), `BlockPNJ/` et `MiniPNJ/` (modèles 3D FBX/GLB/OBJ, personnages Kenney.nl), `NPC/` (dossier PNJ), `assets/Lobbys/` (assets Minecraft .schem/.mca à convertir), `assets/Weapon/` (modèles JSON Blockbench d'armes/outils : Stone Tools 5 outils + textures 64x64 ; `GLB/` 13 modèles GLB Sketchfab : diamond_axe, diamond-pickaxe, iron_pickaxe, stone_sword, diamond_sword, netherite_sword, bow, shield, arrow, etc.), `assets/Deco/` (apple.glb pour la nourriture), `TexturesPack/Aurore Stone/` (pack de textures Minecraft complet, structure `assets/minecraft/textures/{block,item,entity}/`, ~3520 PNG, utilisé pour les textures de blocs en main et dans le monde)

**Pipeline de données Minecraft (`scripts/minecraft_import.py`, ~700 lignes) :**
Extracteur complet qui parse le `client.jar` Java Edition 1.21.11 (`D:\Games\Minecraft - 1.21.11\client.jar`) et les assets Bedrock Edition (`D:\Games\Minecraft - Bedrock Edition\data\`), puis génère 8 fichiers JSON consolidés dans `minecraft_data/`.

```bash
python scripts/minecraft_import.py
```

| Fichier de sortie | Contenu | Volume |
|-------------------|---------|--------|
| `minecraft_blocks.json` | Modèles de blocs : nom, type (cube_all/cube_column/stairs/slab/...), parent, textures résolues, disponibilité TexturesPack | 2 390 blocs (2 144 avec textures) |
| `minecraft_items.json` | Modèles d'items : nom, type (flat/block/handheld), parent, textures | 1 283 items |
| `minecraft_recipes.json` | Recettes (crafting_shaped, crafting_shapeless, smelting, blasting, smoking, campfire_cooking, stonecutting), tags résolus | 1 396 recettes |
| `minecraft_blockstates.json` | Mapping état → modèle (orientation, allumé/éteint, ouvert/fermé...) | 1 168 blockstates |
| `minecraft_textures.json` | Inventaire de toutes les textures MC, catégorisées (block/item/entity), avec flag `in_texturepack` | 2 518 textures (2 516 dispo) |
| `minecraft_entities_bedrock.json` | Modèles d'entités 3D Bedrock (.geo.json) : bones, géométrie, texture dimensions | 113 entités |
| `minecraft_animations_bedrock.json` | Animations d'entités Bedrock : walk, idle, attack, etc. avec durée et loop | 325 animations (83 fichiers) |
| `minecraft_tags.json` | Tags/groupes d'items et blocs (#minecraft:planks, #minecraft:logs, #minecraft:stone_tool_materials...) | 402 tags |

**Classification des blocs par template parent :**
- `cube_all` (283) : un cube, même texture sur 6 faces — stone, diamond_block, gold_block...
- `cube_column` (89) : texture top/bottom + side — oak_log, quartz_pillar...
- `cube_bottom_top` (27) : texture top + bottom + side — grass_block, sandstone...
- `orientable` (48) : texture front + side + top — furnace, dispenser, dropper...
- `stairs` (162), `slab` (116), `wall` (119), `fence` (90), `door` (157), `cross` (118 = fleurs/herbes)...

**Sources de données Minecraft locales :**
- Java Edition 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar` (31 Mo, extrait vers `minecraft_data/client_jar/`)
- Bedrock Edition : `D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla\` (modèles entités, animations, textures)
- TexturesPack : `TexturesPack/Aurore Stone/assets/minecraft/textures/` (1114 block, 792 item, 615 entity PNG)

**Note importante :** `minecraft_data/` est dans `.gitignore` (trop volumineux). Régénérable à tout moment via `python scripts/minecraft_import.py`.

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

## Direction du projet — ClaudeCraft "The Settlers"

**Vision :** ClaudeCraft évolue d'un Minecraft-like vers un jeu de gestion/colonie inspiré de **The Settlers** (chaînes de production, villageois autonomes, construction, économie). Minecraft sert de base pour la simplicité du rendu voxel et l'immense catalogue de blocs/items/recettes réutilisables sans effort de design.

**Phase 1 (fait) :** Monde voxel, biomes, minage, craft, outils, nourriture
**Phase 2 (fait) :** Professions villageoises (9 métiers), emploi du temps jour/nuit, POI workstations, navigation vers cibles
**Phase 3a (fait) :** Premier import Minecraft — 65 blocs (25→65), 80 textures (30→80), ~61 recettes (30→61), bois par biome (6 essences), minerais souterrains (diamant, cuivre), variantes de pierre (7 types), blocs naturels (argile, glace, podzol, mousse), tints feuillages par essence, BARREL workstation
**Phase 3b (à venir) :** Import étendu (centaines de blocs), chaînes de production, bâtiments fonctionnels
**Phase 4 (à venir) :** Transport de ressources, économie villageoise, construction automatique

**Données Minecraft disponibles :** 2390 blocs, 1283 items, 1396 recettes, 113 entités 3D, 325 animations — tout extrait et prêt à l'emploi dans `minecraft_data/`.

---

### Prochain chantier — Éditeur de structures ClaudeCraft

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
