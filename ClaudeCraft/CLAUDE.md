# ClaudeCraft

Jeu voxel type Minecraft en GDScript avec Godot 4.6+, style pastel. Évolue vers un jeu de gestion/colonie inspiré de **The Settlers**.

## Lancer

**Exécutable Godot :** `D:\Program\Godot\Godot_v4.6.1-stable_win64.exe`

1. Ouvrir le projet dans Godot 4.6+
2. Ouvrir `scenes/main.tscn`
3. F5 pour lancer

**Config Godot :** Godot 4.6.1, Physics JoltPhysics3D, résolution 1920x1080 fullscreen, cible 60 FPS.

## Architecture GDScript (`scripts/`)

### Monde et rendu
- **`game_config.gd`** : config centrale (`const GC = preload()` partout). `ACTIVE_PACK` = "Faithful32". `get_block_texture_path()`, `get_item_texture_path()`. 8 aliases textures cross-pack
- **`block_registry.gd`** : 98 types de blocs (enum 0-97, dont architecturaux 83-97), couleurs pastel, dureté, textures par face. Agriculture, éclairage, stockage, végétation cross-mesh, blocs architecturaux (escaliers, dalles, portes, clôtures, vitres, échelles, trappes, barreaux)
- **`chunk.gd`** : 16x16x256, greedy meshing, AO, collision ConcavePolygon, torches/lanternes OmniLight3D (max 16/chunk), flora cross billboards, special shape mesh (dalles, escaliers, clôtures, portes, vitres, échelles, trappes). `_is_greedy_solid()` exclut blocs >=77 sauf STONE_BRICKS
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers), 11 noises, terrain MC 1.18 simplifié (continentalness + erosion + domain warping). Grottes spaghetti (~5% air), bedrock y=0-7. Minerais : charbon 6.3% (y<80), fer 5.2% (y<55), cuivre 3.1% (y<50), or (y<30), diamant (y<16)
- **`texture_manager.gd`** : Texture2DArray (102 layers), auto-détection résolution, fallback aliases, matériau cross-mesh séparé
- **`cloud_manager.gd`** : nuages procéduraux (FBM noise 4 octaves), plan 1024x1024 à y=160, vent animé, couleurs jour/aube/nuit, presets par mode de rendu
- **`weather_manager.gd`** v1.0.0 : système météo dynamique — 4 états (Clair/Nuageux/Pluie/Orage), transitions douces 8s, GPUParticles3D pluie (3000-6000 gouttes), éclairs+tonnerre, fog grisâtre, assombrissement soleil, audio pluie loop. F4 pour cycler
- **`structure_manager.gd`** : Autoload — structures JSON depuis `res://structures/`, RLE, thread-safe

### Village autonome (The Settlers)
- **`village_manager.gd`** : Autoload singleton — stockpile partagé, progression 4 phases (bois->pierre->fer->expansion), tool tier collectif, file de tâches par profession. Mine 3x3, forge, agriculture 5x5, place du village (puits + chemins), 11 blueprints, aplanissement berserker zone 41x41, construction parallèle, stockage coffres (Moulin/Forge/Caserne, 500 items/coffre). Craft batch x8, sable crafté (2 pavé -> 1 sable). Limites anti-AFK
- **`npc_villager.gd`** : PNJ avec professions et emploi du temps (14h travail/jour). Modèle Steve GLB + skin par profession (12 skins). Outils tenus (BoneAttachment3D, mesh extrudé 3D). Pathfinding avec détours, cassage blocs, téléport secours. Mode berserker pour mine. Bûcherons + leaf decay. Vitesse du jeu accélérée. Pause déjeuner 12h-13h. Faim DÉSACTIVÉE
- **`villager_profession.gd`** : 13 professions (BUCHERON, MENUISIER, FORGERON, BATISSEUR, FERMIER, BOULANGER, CHAMAN, MINEUR, NONE + ESPION, SOLDAT, GARDE, CAPITAINE), schedules, workstation mapping, skins, outils tenus
- **`poi_manager.gd`** : Points of Interest (workstations), claim/release, lookup O(1)
- **`village_inventory_ui.gd`** : UI village (F1) — phase, tier, population, faim, fermes, bâtiments avec progression, ressources, stockage bâtiments, villageois numérotés avec activité temps réel, clic = téléport

### Guerre et village ennemi (Phase 4)
- **`enemy_village.gd`** : village ennemi simulé (pas de chunks réels), progression abstraite Phase 0->3, production militaire auto
- **`war_manager.gd`** : espionnage, armée en marche, combat résolu. Phases PEACE->ESPIONAGE->PREPARATION->WAR->VICTORY/DEFEAT
- **`generate_castle.py`** : générateur Python de 4 structures château JSON

### Moteur d'animation Bedrock (Phase 22)
- **`molang_evaluator.gd`** v1.0.0 : parser récursif descent + évaluateur AST Molang. 20+ fonctions math (sin/cos/lerp/clamp...), variables/queries, ternaire, cache AST, support 'this'
- **`bedrock_anim_player.gd`** v1.0.0 : charge les animations JSON Bedrock, évalue Molang par frame, applique aux bones Skeleton3D. Supporte keyframes timeline, expressions statiques, pre_animation scripts, animation controllers (machines à états)
- **`bedrock_entity_loader.gd`** v1.0.0 : charge les entity definitions Bedrock, résout les aliases animation/controller, auto-configure BedrockAnimPlayer
- **`bedrock_anim_engine.py`** v1.0.0 : portage Python du moteur (Molang + AnimPlayer) pour character_viewer et mob_gallery

### Armures
- **`armor_manager.gd`** v2.0.0 : BoneAttachment3D. 5 matériaux x 4 pièces. Textures Bedrock 64x32. PNJ militaires auto-armurés. Joueur : touche P

### Combat
- **`arrow_entity.gd`** : flèche arc — gravité, dégâts 6.0, critique, knockback
- **`passive_mob.gd`** v3.1.0 : 57 mobs depuis `data/mob_database.json`. 3 comportements (passive/neutral/hostile). Brûlure soleil, faim animale, prédation, pack behavior, when_hit configurable. Tables spawn précalculées par biome+heure. IA pathfinding (détection murs, stuck detection, repos périodique)

### Joueur et UI
- **`player.gd`** : FPS CharacterBody3D, minage progressif, hotbar 9 slots + outils + nourriture, arc, placement blocs. Zoom FOV Alt+Molette 70-110. Vue 3e personne F5
- **`hand_item_renderer.gd`** : bras FPS — 3 rendus (bloc, outil extrudé, GLB). Swing, bobbing, arc
- **`tool_registry.gd`** : 18 outils, 5 tiers (bois->netherite)
- **`craft_registry.gd`** : ~85 recettes, 6 catégories. Blocs architecturaux, armes, outils
- **`hotbar_ui.gd`** / **`inventory_ui.gd`** : hotbar 9 slots + inventaire paginé (items possédés uniquement). **`crafting_ui.gd`** v3.0.0 : drag & drop MC, grille 3x3, détection auto recette shapeless
- **`audio_manager.gd`** : sons 65 blocs, ambiance forêt, sons MC (dig/step/glass/doors/chest/lantern)
- **`locale.gd`** : traductions FR/EN

### Utilitaires
- **`world_manager.gd`** : chunks render_distance=6, village 9 PNJ (professions fixes), POI manager
- **`day_night_cycle.gd`** : cycle jour/nuit, 4 vitesses (Lent 35min / Normal 20min / Rapide 15min / Très rapide 1min), Ctrl+Molette
- **`save_manager.gd`** / **`health_ui.gd`** : sauvegarde, UI santé

## Biomes

**7 biomes procéduraux :** Désert (0), Forêt (1), Montagne (2), Plaines (3), Océan (4, continental<0.35), Plage (5, continental 0.35-0.45), Rivière (6, river noise bande étroite)

## Scène principale (`scenes/main.tscn`)

WorldManager + Player (spawn y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers

## Données (`data/`)

- **`mob_database.json`** : 57 mobs avec métadonnées complètes (spawn, biomes, comportement, stats, faim, prédation, drops, Bedrock paths)
- **`animations/`** : 83 fichiers JSON d'animation Bedrock (humanoid, mobs, équipement)
- **`animation_controllers/`** : 51 fichiers JSON de machines à états (move, attack, look_at_target...)
- **`entity_definitions/`** : 147 fichiers JSON de définition d'entités (bindings animations/controllers/pre_animation)

## Structures prédéfinies (`structures/`)

Format JSON : palette + RLE layer-first. `KEEP`=terrain intact, `AIR`=creuser. Pipeline : `.schem` -> `convert_schem.py` -> JSON -> `placements.json`

## Outils Python

- **`scripts/convert_schem.py`** (~940 lignes) : convertisseur `.schem` -> JSON ClaudeCraft, 260+ mappings blocs
- **`scripts/structure_viewer.py`** (v2.3.0, ~3200 lignes) : éditeur + visualiseur 3D PyQt6/PyOpenGL, 73 blocs, undo/redo, sélection rectangulaire, AO, sauvegarde rapide
- **`scripts/bedrock_to_glb.py`** (v1.2.0) : convertisseur Bedrock -> GLB, mesh skinné 28 bones, 8 animations
- **`scripts/character_viewer.py`** (v2.0.0) : visualiseur personnage GLB, skin swap, armures overlay, **animations Bedrock natives** (Molang + JSON)
- **`scripts/minecraft_import.py`** : extracteur client.jar -> 8 JSON dans `minecraft_data/`
- **`scripts/download_mc_sounds.py`** : téléchargeur sons MC, 3998 MP3
- **`scripts/mob_gallery.py`** (v2.0.0) : galerie 3D mobs, rotation auto, **animations Bedrock natives** (Molang + JSON)

## Packs de textures (`TexturesPack/`)

- `Faithful32/` : **pack actif** (32x32, 2610 PNG, couverture 100%)
- `Faithful64x64/` : alternatif (64x64)
- `Aurore Stone/` : alternatif (16x16)

Changer `ACTIVE_PACK` dans `game_config.gd` pour switcher. Résolution auto-détectée.

## Assets

- `Audio/` : ~334 fichiers (dont `Forest/` 11 MP3 ambiance par heure)
- `BlockPNJ/` : 18 modèles GLB Kenney.nl (conservés mais plus utilisés)
- `assets/PlayerModel/` : `steve.glb` (28 bones, 8 anims), `skins/` (10 PNG), `skins/professions/` (12 skins métiers)
- `assets/Deco/` : apple.glb
- `assets/Lobbys/` : .schem Minecraft à convertir

## Direction du projet

**Version actuelle : v21.0.0**

### Phases terminées (résumé)

| Phases | Version | Contenu principal |
|--------|---------|-------------------|
| 1-3b | v10-v11 | Monde voxel, biomes, 65 blocs, 80 textures, craft, outils 3D, arc/combat, village autonome |
| 4-4.1 | v11.x | Grand ménage, GLB natif, 6 animaux Quaternius |
| 5-5.9 | v12.x | The Settlers : farming, faim, forge, mine 3x3, boulanger, construction batch, flatten berserker |
| 6-6.4 | v13.x | Vrais bâtiments MC (11 blueprints JSON), éditeur structures 3D, chapelle, place du village |
| 7-7.3 | v14.x | Flatten berserker refonte, vitesse du temps 4 niveaux, leaf decay MC, fix FPS, chemins+torches village |
| 8-8.3 | v15.x | Phase 4 guerre (village ennemi, espions, armée), Steve GLB + 12 skins, 8 anims, bâtisseurs parallèles, zoom FOV |
| 9-9.5 | v16.x | Coffres bâtiments, fix économie, outils tenus PNJ, végétation cross-mesh (6 types) |
| 10 | v17.0 | Terrain MC 1.18 (continentalness+erosion), 5 presets rendu (F2) |
| 11-11.5 | v18.x | 15 blocs architecturaux, mob_converter fixes, vrais sons MC, vue 3e personne F5 |
| 12-12.1 | v19.0-19.1 | Système mobs intelligent (57 mobs JSON), 65 mobs Bedrock convertis |
| 13 | v19.2 | Armures in-game (5 matériaux x 4 pièces) |
| 14 | v19.3 | Océans, plages, rivières (3 biomes), effet sous-marin, boussole |
| 15 | v19.4 | Fixes critiques audit (nourriture, attaque, coords, UI) |
| 16-16.1 | v19.5-19.6 | GUI MC Faithful32 (HUD, inventaire, crafting), fix chute terrain |
| 17-17.0.1 | v19.7 | IA mobs (pathfinding murs/stuck), pagination inventaire, fix traverse sable |
| 18 | v20.0 | Craft MC drag & drop, inventaire items possédés uniquement |
| 18.1 | v20.1.1 | Fix tints herbe/feuilles délavés — couleurs Bedrock #79BA24, réduction émission cross-mesh |
| 19 | v20.2.0 | Nuages procéduraux (FBM noise, vent, couleurs jour/nuit, presets par mode rendu) |
| 20 | v20.3.0 | Système météo dynamique (4 états, pluie GPU particles, éclairs/tonnerre, fog, F4 cycle) |
| 21 | v20.5.0 | LOD distant (chunks >3 = solides uniquement), collision lazy (throttle 1/frame), render_distance 4→6, fix textures export, fix arc squelette vertex colors, mobs passifs réduits 1/3 |
| 22 | v21.0.0 | **Moteur d'animation Bedrock** : évaluateur Molang complet, chargeur JSON Bedrock (83 anims, 51 controllers, 147 entity defs), BedrockAnimPlayer remplace AnimationPlayer, intégration npc_villager + passive_mob, Python engine pour viewers, character_viewer v2.0 + mob_gallery v2.0 |

### En cours / À venir

| Phase | Statut | Contenu |
|-------|--------|---------|
| 9.4 | WIP | v16.1.0 — **Outils tenus PNJ** : mesh extrudé 3D pixel-par-pixel, fix moonwalk (+PI atan2), fix jambes écartées (deterministic + epsilon rotation). **TODO** : agrandir outils x2-3, positionner sur le bras, bone tracking |
| 22 | **FAIT** | **Moteur d'animation Bedrock** v21.0.0 : évaluateur Molang complet (GDScript + Python), BedrockAnimPlayer remplace AnimationPlayer Godot, 83 animations + 51 controllers + 147 entity defs copiés dans `data/`, intégration npc_villager + passive_mob, character_viewer v2.0 + mob_gallery v2.0. Walk/idle automatiques par move controller, attack/mine par variable.attack_time |
| 18.1 | A venir | Livre de recettes (guide craftable), comportements spécifiques mobs (creeper explosion, skeleton archer), mini-boss x1.6, nouveaux biomes (marécage, forêt géante) |

**Packs GLB utilisés** : Steve GLB (Bedrock converti, 28 bones, 4 anims) pour tous les PNJ. **PNJ futurs** : KayKit Adventurers (161 anims travail)

**Données MC disponibles :** 2390 blocs, 1283 items, 1396 recettes dans `minecraft_data/`

## Sources MC locales

- Java 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar`
- Bedrock : `D:\Games\Minecraft - Bedrock Edition\data\`
- MC 1.12 source (MCP940) : `D:\Projets\Source code of minecraft 1.12\mcp940-master\`
