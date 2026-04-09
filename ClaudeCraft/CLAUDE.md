# ClaudeCraft

Jeu voxel type Minecraft en GDScript avec Godot 4.6+, style pastel. Évolue vers un jeu de gestion/colonie inspiré de **The Settlers**.

## Lancer

**Exécutable Godot :** `D:\Program\Godot\Godot_v4.6.1-stable_win64.exe`

1. Ouvrir le projet dans Godot 4.6+
2. Ouvrir `scenes/main.tscn`
3. F5 pour lancer

**Config :** Godot 4.6.1, JoltPhysics3D, 1920x1080 fullscreen, 60 FPS.

## Architecture GDScript (`scripts/`)

### Monde et rendu
- **`game_config.gd`** : config centrale (`const GC = preload()`). `ACTIVE_PACK` = "Faithful32"
- **`block_registry.gd`** : 98 types de blocs (dont architecturaux 83-97), couleurs pastel, dureté, textures par face
- **`chunk.gd`** : 16x16x256, greedy meshing, AO, collision ConcavePolygon, torches OmniLight3D (max 16/chunk), flora cross billboards, special shape mesh, water shader
- **`chunk_generator.gd`** : génération threadée (4 workers), terrain MC 1.18 (continentalness + erosion + domain warping), grottes spaghetti, minerais
- **`texture_manager.gd`** : Texture2DArray (102 layers), auto-détection résolution, fallback aliases
- **`cloud_manager.gd`** : nuages procéduraux FBM 4 octaves, vent animé, presets par mode rendu
- **`weather_manager.gd`** : météo dynamique 4 états (Clair/Nuageux/Pluie/Orage), GPUParticles3D, éclairs, F4 cycle
- **`structure_manager.gd`** : Autoload, structures JSON RLE, thread-safe
- **`fluid_flow_manager.gd`** : Autoload, moteur de propagation eau/lave BFS tick-based 200ms, gravité d'abord puis horizontal max 7 blocs, détection plaine 3x3 anti-Waterworld, hook sur break_block
- **`shaders/`** : 5 shaders custom — `block_texture_array` (blocs solides), `block_texture_array_cross` (végétation + vent), `water` (unshaded bleu + shimmer), `clouds` (FBM), `rain` (étirement drops)

### Village autonome (The Settlers)
- **`village_manager.gd`** : stockpile partagé, 4 phases progression, 11 blueprints, mine 3x3, forge, agriculture, construction parallèle, stockage coffres
- **`npc_villager.gd`** : PNJ Steve GLB + 12 skins, outils tenus BoneAttachment3D, pathfinding, berserker mine, leaf decay, pause déjeuner
- **`villager_profession.gd`** : 13 professions, schedules, workstation mapping
- **`poi_manager.gd`** / **`village_inventory_ui.gd`** : POI claim/release, UI village F1

### Guerre (Phase 4)
- **`enemy_village.gd`** / **`war_manager.gd`** : village ennemi simulé, espionnage, armée, combat. Phases PEACE→WAR→VICTORY/DEFEAT

### Moteur d'animation Bedrock (Phase 22)
- **`molang_evaluator.gd`** : parser AST Molang, 20+ fonctions math, variables/queries, ternaire, cache AST
- **`bedrock_anim_player.gd`** : animations JSON Bedrock, évalue Molang/frame, keyframes timeline, controllers (machines à états)
- **`bedrock_entity_loader.gd`** : charge entity definitions, résout aliases, auto-configure BedrockAnimPlayer
- **`bedrock_anim_engine.py`** : portage Python pour character_viewer et mob_gallery
- **Convention rotation :** Bedrock left-hand → GLB right-hand = `-rot_deg.x, -rot_deg.y, +rot_deg.z` (confirmé fonctionnel)

### Armures / Combat
- **`armor_manager.gd`** : BoneAttachment3D, 5 matériaux x 4 pièces, textures Bedrock 64x32, touche P
- **`arrow_entity.gd`** : flèche arc, gravité, dégâts 6.0, critique, knockback
- **`passive_mob.gd`** : 57 mobs depuis `mob_database.json`, 3 comportements, spawn par biome+heure, IA pathfinding

### Joueur et UI
- **`player.gd`** : FPS CharacterBody3D, minage, hotbar 9 slots, arc, placement blocs, sprint, zoom FOV Alt+Molette, vue 3e personne F5
- **`hand_item_renderer.gd`** : bras FPS, 3 rendus (bloc/outil/GLB), swing, bobbing, arc
- **`tool_registry.gd`** / **`craft_registry.gd`** : 18 outils 5 tiers, ~85 recettes 6 catégories
- **`hotbar_ui.gd`** / **`inventory_ui.gd`** / **`crafting_ui.gd`** : hotbar, inventaire paginé, craft drag & drop MC grille 3x3
- **`audio_manager.gd`** : sons 65 blocs, ambiance forêt, sons MC

### Utilitaires
- **`world_manager.gd`** : chunks render_distance=6, village 9 PNJ, POI manager
- **`day_night_cycle.gd`** : cycle jour/nuit, 4 vitesses, Ctrl+Molette
- **`save_manager.gd`** / **`health_ui.gd`** / **`locale.gd`** : sauvegarde, santé, traductions FR/EN

## Biomes

**7 biomes :** Désert, Forêt, Montagne, Plaines, Océan (continental<0.35), Plage (0.35-0.45), Rivière

## Données (`data/`)

- **`mob_database.json`** : 57 mobs (spawn, biomes, comportement, stats, drops, Bedrock paths)
- **`animations/`** : 83 fichiers JSON animation Bedrock
- **`animation_controllers/`** : 51 fichiers JSON machines à états
- **`entity_definitions/`** : 147 fichiers JSON entités

## Structures (`structures/`)

Format JSON : palette + RLE layer-first. `KEEP`=terrain intact, `AIR`=creuser. Pipeline : `.schem` → `convert_schem.py` → JSON

## AnimaTweaks (`AnimaTweaks/`)

Pack animations Bedrock améliorées (ICEy v4.0). **100% format Bedrock**. Sprint (arms+legs séparés, body lean+torsion), walk, tiptoe, sneak, jump, swim, idle, emotes. Seuils vitesse : idle 0-0.8, tiptoe 0.8-2.5, walk 2.5-4.0, sprint 4.0+.

Certaines animations vanilla (`bow_and_arrow`, `charging`, `sleeping`) dépendent de variables runtime non disponibles dans le viewer — pas cassées, juste incomplètes hors contexte jeu.

## Outils Python

- **`scripts/convert_schem.py`** : convertisseur `.schem` → JSON, 260+ mappings blocs
- **`scripts/structure_viewer.py`** : éditeur 3D PyQt6/PyOpenGL, 73 blocs, undo/redo
- **`scripts/bedrock_to_glb.py`** : convertisseur Bedrock → GLB, mesh skinné 28 bones, 8 animations
- **`scripts/character_viewer.py`** (v2.1.0) : visualiseur GLB, skin swap, armures, animations Bedrock. Touches : N=toggle rotation X, 1-4=vues preset, F=flèche direction faciale
- **`scripts/mob_gallery.py`** : galerie 3D mobs, rotation auto, animations Bedrock
- **`scripts/minecraft_import.py`** / **`scripts/download_mc_sounds.py`** : extracteur client.jar, téléchargeur sons MC

## Packs de textures (`TexturesPack/`)

`Faithful32/` (actif, 32x32, 2610 PNG) | `Faithful64x64/` | `Aurore Stone/` (16x16). Changer `ACTIVE_PACK` dans `game_config.gd`.

## Assets

- `Audio/` : ~334 fichiers (dont `Forest/` 11 MP3 ambiance)
- `assets/PlayerModel/` : `steve.glb` (28 bones), `skins/` (10 PNG), `skins/professions/` (12 skins)

## Direction du projet

**Version actuelle : v21.5.1**

### Phases terminées

| Phases | Version | Contenu principal |
|--------|---------|-------------------|
| 1-5 | v10-v12 | Monde voxel, biomes, blocs, craft, outils, arc/combat, village The Settlers (farming, faim, forge, mine, boulanger) |
| 6-8 | v13-v15 | Bâtiments MC (11 blueprints), éditeur structures, guerre (village ennemi, espions), Steve GLB 12 skins |
| 9-11 | v16-v18 | Coffres, outils tenus PNJ, végétation cross-mesh, terrain MC 1.18, blocs architecturaux, sons MC, vue 3e personne |
| 12-14 | v19.0-v19.3 | Système mobs (57 mobs JSON), armures (5 matériaux), océans/plages/rivières |
| 15-18 | v19.4-v20.0 | Fixes audit, GUI MC Faithful32, IA mobs pathfinding, craft drag & drop MC |
| 19-21 | v20.1-v20.5 | Fix tints, nuages procéduraux, météo dynamique, LOD distant, collision lazy |
| 22 | v21.0.0 | **Moteur animation Bedrock** : Molang, JSON Bedrock (83 anims, 51 controllers, 147 entity defs), character_viewer v2.1 + mob_gallery v2.0 |
| - | v21.1.0 | **Optimisation massive** : PackedByteArray flat chunks, Semaphore workers, greedy mask flat, keyframe pre-sort, dirty flags UI, caches statiques (18 fichiers, 25+ fixes) |

| - | v21.2.0 | **Fenêtre de recettes** : recipe_book_ui.gd, 5 onglets catégories, filtre fabricables, recherche, auto-craft, intégré inventaire+craft |
| - | v21.3.0 | **Shaders** : water shader (vagues, fresnel, UV scrolling, reflets), vent sur végétation cross |
| - | v21.4.0 | **Eau Vivante Phase 1** : `fluid_flow_manager.gd` autoload, BFS tick-based 200ms, gravité + propagation horizontale max 7 blocs, anti-Waterworld (plaine 3x3), trigger sur break_block |
| - | v21.5.0 | **Eau Vivante Phase 2 — Bucket** : ToolType BUCKET_EMPTY/WATER/LAVA, clic droit pour remplir depuis eau source ou verser (schedule_source sur FluidFlowManager), swap auto du ToolType dans le slot, hache de pierre du spawn remplacée par un seau vide (slot 5) pour tests rapides. Lave non implémentée (bloc LAVA absent du registry). |
| - | v21.5.1 | **Fix anims walk mobs legacy (scripts.animate support)** : `bedrock_entity_loader.gd` lit désormais `desc.scripts.animate` (bloc Bedrock historique utilisé par cow/pig/sheep/chicken) et crée un controller synthétique `__auto.<entity>.move`. Flag `clamp_weight` ajouté dans `bedrock_anim_player.gd` pour clamper les conditions Molang continues (ex `query.modified_move_speed`) à [0,1] sans régresser les controllers existants (llama). |
| - | v21.4.1 | **Eau Vivante Phase 1.1** : tick 0.4s + délai 0.8s avant fill (feel progressif), faces latérales + bottom du water mesh (colonnes/cascades visibles), overlay sous-marin 45% → 72% opacité |

### À venir

| Phase | Contenu |
|-------|---------|
| - | Livre de recettes avancé (recettes JSON MC 1.21), comportements mobs, mini-boss, nouveaux biomes |
| - | Livre de recettes, comportements mobs (creeper explosion, skeleton archer), mini-boss, nouveaux biomes |

**Données MC disponibles :** 2390 blocs, 1283 items, 1396 recettes dans `minecraft_data/`

## Sources MC locales

- Java 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar`
- Bedrock : `D:\Games\Minecraft - Bedrock Edition\data\`
