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
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers, Mutex), 6 noises, arbres par biome, minerais souterrains, structures passe 4. **Grottes compactes** : tunnels spaghetti `abs(v1)+abs(v2) < 0.15` (~5% air), grandes salles très rares (`abs(v3) < 0.03`), bedrock solide y=0-7. **Minerais en veines** (indépendant des grottes, calibré Simplex réel) : charbon 6.3% (y<80), fer 5.2% (y<55), cuivre 3.1% (y<50), or rare (y<30), diamant très rare (y<16)
- **`texture_manager.gd`** : Texture2DArray (86 layers), auto-détection résolution, fallback aliases, `_force_opaque()`
- **`structure_manager.gd`** : Autoload — structures JSON depuis `res://structures/`, RLE, thread-safe

### Village autonome (The Settlers)
- **`village_manager.gd`** : Autoload singleton — stockpile partagé, progression 4 phases (bois→pierre→fer→expansion), tool tier collectif, file de tâches par profession. **Scan optimisé** : rayon 2 chunks, échantillonnage 1/2, cache 15s, early exit 20 résultats, évaluation 8s. **Mine 3×3** : escalier 3 large × 3 haut, recherche robuste 2 passes (plat puis fallback) avec angle aléatoire 360°, tolérance terrain 3 blocs, 60 tentatives/passe, fallback cardinal. Galerie en étoile 3×3 au fond, branches expansion 3×3, lookahead 20 blocs pour 2 mineurs simultanés. **Forge** : vérifie tier AVANT consommation des ressources (plus de gaspillage). **Agriculture** : ferme 5×5, recherche 3 passes progressives (15-35→8-45→5-50 blocs), angle aléatoire. Chemin croix cobblestone, **8 blueprints** (phase 1 tout en planches, pas besoin de pierre). **Aplanissement terrain** : zone 37×37 (`VILLAGE_RADIUS=18`), altitude médiane comme référence (`village_ref_y`), `_generate_flatten_plan()` génère break (dessus) + place cobblestone (dessous), protège les workstations, phase gating bloque builds/chemin tant que pas terminé. **Construction** : `_find_build_site` utilise `ref_y+1` comme altitude (terrain plat garanti), 60 tentatives dans zone `VILLAGE_RADIUS`, anti-chevauchement structures + workstations. Bâtisseur garde ses tâches build/flatten entre les sessions (nuit/socialisation). **Croissance village** : pop cap = 9 + 2×maisons, spawn villageois si 5+ pain. **Forge** : 3 recettes d'upgrade outils (vérifie tier avant craft). **Travail continu** : seuils stock bois 50, planches 200, pierre 40. **Craft batch** : Planches et Pain jusqu'à 8× par tâche (menuisier craft 32 planches/cycle). `try_craft()` gère toutes les essences de bois via `consume_any_wood()` et toutes les variantes de planches via `consume_any_planks()`. **Récolte sable** : tâche "mine" surface, tout villageois libre, rayon 48, sans distance min village. **Limites anti-AFK** : mine plan max 5000 blocs, purge >500 blocs minés, pause mine si stock saturé (pierre>200+charbon>80+fer>30), saved_chunk_data max 100 chunks
- **`npc_villager.gd`** : PNJ avec professions et emploi du temps (14h travail/jour). 18 modèles GLB Kenney.nl. **Pathfinding** : détection murs 2+ blocs, détours intelligents progressifs, abandon cible après 7 détours, cassage blocs mous (dureté ≤ 0.5), casse blocs durs après 2, téléport secours 25s, protection structures village. **Mode berserker** (`_berserker_walk_toward`) : casse TOUT immédiatement sur le chemin (0 détour), utilisé pour aller/revenir de la mine. **Bûcherons** : scan 3D exhaustif (rayon 4, early exit), dépouillent l'arbre entier, feuilles batchées (1 rebuild/chunk). **Mineurs** : suit `mine_plan` pré-calculé via `get_next_mine_block()`, descend l'escalier via entrée de mine quand bloc profond (dy > 6), sauvegarde `_mine_resume_pos` pendant la balade pour retour direct au front, lookahead 20 blocs. **Bâtisseur flatten** : `_execute_flatten(delta)` — marche vers chaque bloc du plan, casse (break) ou pose cobblestone (place), batch ×8 blocs/0.08s, rend la tâche si pierre insuffisante (reprend auto quand mineurs fournissent), tâche persistante entre activités. **Système de faim** : DÉSACTIVÉ (drain 0.0) — en attente ferme fiable. Mécanisme prêt : drain 0.06/0.01, seuils 40/20, pause déjeuner 12h-13h. **Retour surface mineur** : remonte l'escalier en berserker
- **`villager_profession.gd`** : 9 professions (BUCHERON, MENUISIER, FORGERON, BATISSEUR, FERMIER, BOULANGER, CHAMAN, MINEUR, NONE), schedule 6 plages, workstation mapping
- **`poi_manager.gd`** : Points of Interest (workstations), claim/release, scan chunk, lookup O(1)
- **`village_inventory_ui.gd`** : UI gestion village (F1) — panel 700×900, phase, tier, **population X/Y**, **barre de faim** par villageois, **section fermes**, **bâtiments (X/Y)** avec progression en construction (blocs posés) et matériaux manquants pour le prochain, **prochain objectif + progression aplanissement (X/Y blocs, %) + statut mine**, ressources, **villageois numérotés** (Mineur 1, Mineur 2...) avec **activité temps réel**, **clic = téléport joueur**

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
- **`world_manager.gd`** : chunks render_distance=4, village 9 PNJ (professions fixes : 2 bûcherons, 2 mineurs, 1 forgeron, 1 bâtisseur, 1 menuisier, 1 fermier, 1 boulanger), POI manager, déchargement Dictionary-set O(1). Ancien flatten cosmétique remplacé par le système bâtisseur. *(Pas de spawn animaux — retiré v12.0.0)*
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

**Version actuelle : v12.9.0**

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
| 5.2 | Fait | v12.2.0 — Fix mine/ferme bloqués (recherche robuste multi-passes, fallback), faim désactivée, bâtiments phase 1 tout planches, construction sans chemin, UI village agrandie (700×900, villageois numérotés, activité temps réel, téléport clic) |
| 5.3 | Fait | v12.3.0 — Mine 3×3 (3 large × 3 haut), mode berserker mineurs (casse tout sur le chemin), position de reprise après balade, mineur 2 descend l'escalier, grottes compactes (~5% air, tunnels spaghetti), bedrock solide y=0-7, forgeron anti-doublon fourneau, feuilles batchées (fix FPS) |
| 5.4 | Fait | v12.4.0 — Minerais calibrés sur distribution Simplex réelle (fer 5.2%, charbon 6.3%, cuivre 3.1%), veines indépendantes des grottes, progression village débloquée jusqu'à Phase 3 (Âge du Fer) |
| 5.5 | Fait | v12.5.0 — Boulanger (9e PNJ, craft Pain quand blé dispo), menuisier craft planches en continu (Phase 2+, seuil 80), déblocage bâtisseur, pop cap base 9 |
| 5.6 | Fait | v12.6.0 — Fix construction bâtiments : craft batch (Planches/Pain ×8 par tâche), seuil planches 200, site terrain ±3 blocs, bâtisseur garde tâche build la nuit, forge vérifie tier avant craft, UI bâtiments (X/Y) avec progression et matériaux manquants |
| 5.6.1 | Fait | v12.6.1 — Fix bâtiments phase 2+ bloqués par le verre : craft proactif "Verre" (sable+charbon) en phase 2/3, forgeron craft batch Verre et Lingot de fer (×8) |
| 5.7 | Fait | v12.7.0 — Récolte de sable (tout villageois, rayon 48, sans distance min village) pour débloquer le verre. Limites anti-AFK : mine plan plafonnée à 5000 blocs, purge blocs minés, pause mine si stock saturé (pierre>200, charbon>80, fer>30), saved_chunk_data plafonné à 100 chunks |
| 5.8 | Fait | v12.8.0 — Aplanissement terrain village 37×37 (`VILLAGE_RADIUS=18`). Altitude médiane comme référence, bâtisseur casse au-dessus et comble en cobblestone en dessous. Phase gating : pas de builds/chemin tant que le terrain n'est pas plat. `_find_build_site` simplifié (`ref_y+1`, zone bornée, anti-overlap workstations). UI progression aplanissement (X/Y blocs, %). Ancien flatten cosmétique (13×13, break only) supprimé |
| 5.9 | Fait | v12.9.0 — Bâtisseur turbo : flatten batch ×8 blocs/tick (0.08s), construction batch ×4 blocs/tick (0.15s), chemin batch ×6 blocs/tick (0.1s). Terrain aplani ~10× plus vite, bâtiments construits ~5× plus vite |
| 6 | À venir | Système de faim actif, animaux (viande/œufs), chaînes de production avancées, économie village |

**Packs GLB utilisés (CC0)** : Kenney.nl (18 modèles PNJ villageois). **PNJ futurs** : KayKit Adventurers (161 anims travail)

**Données MC disponibles :** 2390 blocs, 1283 items, 1396 recettes dans `minecraft_data/`

## Sources MC locales

- Java 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar`
- Bedrock : `D:\Games\Minecraft - Bedrock Edition\data\`
- MC 1.12 source (MCP940) : `D:\Projets\Source code of minecraft 1.12\mcp940-master\`
