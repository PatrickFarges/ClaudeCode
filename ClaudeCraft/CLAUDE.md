# ClaudeCraft

Jeu voxel type Minecraft en GDScript avec Godot 4.5+, style pastel. Évolue vers un jeu de gestion/colonie inspiré de **The Settlers**.

## Lancer

1. Ouvrir le projet dans Godot 4.5+
2. Ouvrir `scenes/main.tscn`
3. F5 pour lancer

**Config Godot :** Physics JoltPhysics3D, résolution 1920x1080 fullscreen, cible 60 FPS.

## Architecture GDScript (`scripts/`)

### Monde et rendu
- **`game_config.gd`** : config centrale (`const GC = preload()` partout). `ACTIVE_PACK` = "Faithful32". Fonctions `get_block_texture_path()`, `get_item_texture_path()`. Système d'aliases textures (8 aliases cross-pack)
- **`block_registry.gd`** : 73 types de blocs (enum 0-72), couleurs pastel, dureté, textures par face, `is_workstation()`, `get_block_tint()`. Inclut agriculture (FARMLAND, WHEAT_STAGE_0→3, WHEAT_ITEM, BREAD) et éclairage (TORCH)
- **`chunk.gd`** : 16×16×256 blocs, greedy meshing, AO, collision ConcavePolygon, UV corrigés, rendu torches (OmniLight3D, max 16/chunk)
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers, Mutex), 6 noises, arbres par biome, minerais souterrains, structures passe 4
- **`texture_manager.gd`** : Texture2DArray (86 layers), auto-détection résolution, fallback aliases, `_force_opaque()`
- **`structure_manager.gd`** : Autoload — structures JSON depuis `res://structures/`, RLE, thread-safe

### Village autonome (The Settlers)
- **`village_manager.gd`** : Autoload singleton — stockpile partagé, progression 4 phases (bois→pierre→fer→expansion), tool tier collectif, file de tâches par profession. **Scan optimisé** : rayon 2 chunks, échantillonnage 1/2, cache 15s, early exit 20 résultats, évaluation 8s. **Mine** : entrée à 30-40 blocs du centre, escalier descendant, `find_nearest_surface_block` filtre < 30 blocs. Chemin croix cobblestone, **8 blueprints bâtiments**. **Agriculture** : ferme 5×5 à 20-30 blocs du centre, croissance blé 30s/stage×4, récolte auto, recette Pain. **Croissance village** : pop cap = 8 + 2×maisons, spawn villageois si 5+ pain. **Forge** : 3 recettes d'upgrade outils (`_tool_tier`), `get_tool_tier_label()` pour labels PNJ. **Travail continu** : seuils stock bois 50, pierre 40 — tâches toujours disponibles
- **`npc_villager.gd`** : PNJ avec professions et emploi du temps (14h travail/jour). 18 modèles GLB Kenney.nl. **Pathfinding** : détection murs 2+ blocs (`_wall_impassable`), détours intelligents progressifs (perp→diag→arrière→aléatoire), abandon cible après 7 détours, cassage blocs mous (dureté ≤ 0.5) immédiat, casse blocs durs après 10 détours, téléport secours 25s. Protection structures village (`_is_in_village_structure`). **Bûcherons** : `_find_nearest_trunk_around()` scan 3D exhaustif (rayon 4, early exit), dépouillent l'arbre entier puis enchaînent le plus proche. `_harvest_leaves_around()` nettoyage 3D (max 50 blocs/appel). **Mineurs** : distance min 30 blocs du village (`MIN_MINE_DISTANCE_FROM_VILLAGE`). Label3D profession+tâche avec **tier matériau**. **Système de faim** : `hunger` 100→0, drain 0.06/s travail 0.01/s repos (~2 jours in-game), seuil manger 40, ralenti sous 20, arrêt à 0, pause déjeuner 12h-13h. **Retour surface mineur** : `_mine_entry_pos` + `_returning_to_surface` — remonte l'escalier au lieu de téléporter
- **`villager_profession.gd`** : 9 professions (BUCHERON, MENUISIER, FORGERON, BATISSEUR, FERMIER, BOULANGER, CHAMAN, MINEUR, NONE), schedule 6 plages, workstation mapping
- **`poi_manager.gd`** : Points of Interest (workstations), claim/release, scan chunk, lookup O(1)
- **`village_inventory_ui.gd`** : UI gestion village (F1) — phase, tier, **population X/Y**, **barre de faim** par villageois (vert/jaune/rouge), **section fermes**, **liste bâtiments**, **prochain objectif**, ressources, liste villageois avec activité

### Combat
- **`arrow_entity.gd`** : flèche arc — gravité 20m/s², drag, dégâts 6.0, critique, knockback, particules, Label3D dégâts
- **`passive_mob.gd`** : *(inactif — plus de spawn)* code encore présent mais non utilisé. Les animaux ont été retirés pour se concentrer sur la gestion de village

### Joueur et UI
- **`player.gd`** : FPS CharacterBody3D, minage progressif (`BASE_MINING_TIME=5.0` × dureté/outil), hotbar 9 slots + outils + nourriture, arc (charge MC), placement blocs
- **`hand_item_renderer.gd`** : bras FPS — 3 rendus (bloc texturé, outil extrudé 3D pixel par pixel, modèle GLB). Swing sinusoïdal MC, bobbing, rendu arc
- **`tool_registry.gd`** : 18 outils, 5 tiers (bois→netherite), PICK_BOOST=2.0, CROSS_TOOL_MULT=1.3, listes blocs par type
- **`craft_registry.gd`** : ~65 recettes, 6 catégories (Hand, Furnace, Wood/Stone/Iron/Gold Table). **Forge** : 3 recettes `_tool_tier` (bois/pierre/fer). **Torche** : 1 coal + 1 planks → 4 torches
- **`hotbar_ui.gd`** / **`inventory_ui.gd`** : hotbar 9 slots + inventaire 7 onglets, textures réelles
- **`audio_manager.gd`** : pool audio, sons 65 blocs, ambiance forêt par heure, chargement null-safe
- **`locale.gd`** : traductions FR/EN

### Utilitaires
- **`world_manager.gd`** : chunks render_distance=4, village 8 PNJ (professions fixes : 2 bûcherons, 2 mineurs, 1 forgeron, 1 bâtisseur, 1 menuisier, 1 fermier), POI manager, déchargement Dictionary-set O(1). *(Pas de spawn animaux — retiré v12.0.0)*
- **`day_night_cycle.gd`** / **`save_manager.gd`** / **`health_ui.gd`** : cycle jour/nuit, sauvegarde, UI santé

## Biomes

**4 biomes procéduraux :** Désert (temp>0.65, humid<0.35), Forêt (temp 0.45-0.7, humid>0.55), Montagne (temp<0.35), Plaines (défaut)

## Scène principale (`scenes/main.tscn`)

WorldManager + Player (spawn y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers

## Structures prédéfinies (`structures/`)

Format JSON : palette + RLE layer-first. `KEEP`=terrain intact, `AIR`=creuser. Pipeline : `.schem` → `convert_schem.py` → JSON → `placements.json`

## Outils Python

- **`scripts/convert_schem.py`** (~940 lignes) : convertisseur `.schem` → JSON ClaudeCraft, parseur NBT maison, 260+ mappings blocs
- **`scripts/structure_viewer.py`** (~1920 lignes) : visu 3D PyQt6/PyOpenGL — voxel (.json/.schem/.litematic) + mesh (.glb/.obj), parseurs maison
- **`scripts/minecraft_import.py`** (~700 lignes) : extracteur client.jar → 8 JSON (2390 blocs, 1283 items, 1396 recettes, etc.) dans `minecraft_data/` (gitignored)

## Packs de textures (`TexturesPack/`)

- `Faithful32/` : **pack actif** (32x32, 2610 PNG, couverture 100%)
- `Faithful64x64/` : alternatif (64x64)
- `Aurore Stone/` : alternatif (16x16)

Changer `ACTIVE_PACK` dans `game_config.gd` pour switcher. Résolution auto-détectée.

## Assets

- `Audio/` : ~334 fichiers (dont `Forest/` 11 MP3 ambiance par heure)
- `BlockPNJ/` : 18 modèles GLB Kenney.nl (PNJ villageois)
- `assets/Animals/GLB/` : 6 GLB animés Quaternius (CC0) — *(non utilisés depuis v12.0.0, conservés pour usage futur éventuel)*
- `assets/Deco/` : apple.glb (nourriture)
- `assets/Lobbys/` : .schem Minecraft à convertir

## Direction du projet

**Version actuelle : v12.1.0**

| Phase | Statut | Contenu |
|-------|--------|---------|
| 1 | Fait | Monde voxel, biomes, minage, craft, outils, nourriture |
| 2 | Fait | Professions villageoises, emploi du temps, POI workstations |
| 3a | Fait | 65 blocs, 80 textures, 61 recettes, outils 3D extrudés, arc/combat |
| 3b | Fait | Village autonome (stockpile, mine, construction, professions fixes) |
| 4 | Fait | Grand ménage v11.0.0 — suppression Bedrock, GLB natif, optimisations perf |
| 4.1 | Fait | v11.1.0 — 6 GLB animaux Quaternius (CC0) téléchargés, convertis FBX→GLB *(retirés du spawn en v12.0.0)* |
| 5 | Fait | v12.0.0 — Gestion village The Settlers : farming (blé 5×5, 4 stages, récolte auto), faim villageois (drain/seuils/pause déjeuner), 5 nouveaux bâtiments (Ferme, Forge, Entrepôt, Maison, Entrée de mine), croissance village (pop cap dynamique + spawn villageois), UI enrichie (pop, faim, fermes, bâtiments, objectifs) |
| 5.1 | Fait | v12.1.0 — Forge (3 recettes upgrade outils, forgeron actif), Torches (bloc TORCH + OmniLight3D, max 16/chunk), Labels outils avec tier matériau (Hache Bois, Pioche Fer...), Retour surface mineurs (remonte l'escalier au lieu de téléporter) |
| 6 | À venir | Chaînes de production avancées, transport ressources, économie |

**Packs GLB utilisés (CC0)** : Kenney.nl (18 modèles PNJ villageois). **PNJ futurs** : KayKit Adventurers (161 anims travail)

**Données MC disponibles :** 2390 blocs, 1283 items, 1396 recettes dans `minecraft_data/`

## Sources MC locales

- Java 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar`
- Bedrock : `D:\Games\Minecraft - Bedrock Edition\data\`
- MC 1.12 source (MCP940) : `D:\Projets\Source code of minecraft 1.12\mcp940-master\`
