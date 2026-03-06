# ClaudeCraft

Jeu voxel type Minecraft en GDScript avec Godot 4.6+, style pastel. Évolue vers un jeu de gestion/colonie inspiré de **The Settlers**.

## Lancer

1. Ouvrir le projet dans Godot 4.6+
2. Ouvrir `scenes/main.tscn`
3. F5 pour lancer

**Config Godot :** Godot 4.6.1, Physics JoltPhysics3D, résolution 1920x1080 fullscreen, cible 60 FPS.

## Architecture GDScript (`scripts/`)

### Monde et rendu
- **`game_config.gd`** : config centrale (`const GC = preload()` partout). `ACTIVE_PACK` = "Faithful32". Fonctions `get_block_texture_path()`, `get_item_texture_path()`. Système d'aliases textures (8 aliases cross-pack)
- **`block_registry.gd`** : 83 types de blocs (enum 0-82, dont IRON_SWORD/GOLD_SWORD/SHIELD/CHEST), couleurs pastel, dureté, textures par face, `is_workstation()`, `is_cross_mesh()`, `get_block_tint()`. Inclut agriculture (FARMLAND, WHEAT_STAGE_0→3, WHEAT_ITEM, BREAD), éclairage (TORCH), stockage (CHEST) et végétation décorative cross-mesh (SHORT_GRASS, FERN, DEAD_BUSH, DANDELION, POPPY, CORNFLOWER)
- **`chunk.gd`** : 16×16×256 blocs, greedy meshing, AO, collision ConcavePolygon, UV corrigés, rendu torches (OmniLight3D, max 16/chunk), flora mesh séparé (cross billboards pour herbe/fleurs, shader cull_disabled, pas de collision)
- **`chunk_generator.gd`** : génération procédurale threadée (4 workers, Mutex), 6 noises, arbres par biome, minerais souterrains, structures passe 4. **Grottes compactes** : tunnels spaghetti `abs(v1)+abs(v2) < 0.15` (~5% air), grandes salles très rares (`abs(v3) < 0.03`), bedrock solide y=0-7. **Minerais en veines** (indépendant des grottes, calibré Simplex réel) : charbon 6.3% (y<80), fer 5.2% (y<55), cuivre 3.1% (y<50), or rare (y<30), diamant très rare (y<16)
- **`texture_manager.gd`** : Texture2DArray (93 layers), auto-détection résolution, fallback aliases, `_force_opaque()`, matériau cross-mesh séparé (`get_cross_material()`, shader `cull_disabled` pour végétation)
- **`structure_manager.gd`** : Autoload — structures JSON depuis `res://structures/`, RLE, thread-safe

### Village autonome (The Settlers)
- **`village_manager.gd`** : Autoload singleton — stockpile partagé, progression 4 phases (bois→pierre→fer→expansion), tool tier collectif, file de tâches par profession. **Scan optimisé** : rayon 2 chunks, échantillonnage 1/2, cache 15s, early exit 20 résultats, évaluation 8s. **Mine 3×3** : escalier 3 large × 3 haut, recherche robuste 2 passes (plat puis fallback) avec angle aléatoire 360°, tolérance terrain 3 blocs, 60 tentatives/passe, fallback cardinal. Galerie en étoile 3×3 au fond, branches expansion 3×3, lookahead 20 blocs pour 2 mineurs simultanés. **Forge** : vérifie tier AVANT consommation des ressources (plus de gaspillage). **Agriculture** : ferme 5×5, recherche 3 passes progressives (30-50→25-55→22-60 blocs, min 30 blocs du centre village), angle aléatoire. **Place du village** : puits central 5×5 cobblestone (2 niveaux + 4 poteaux + toit croix) + 4 torches + 4 chemins cobblestone 3 blocs de large × 12 long. PNJ se rassemblent sur la place pendant la pause déjeuner (12h-13h). **11 blueprints** (9 JSON + 1 hardcoded mine + chapelle générée). **Aplanissement terrain BERSERKER** : zone 41×41 (`FLATTEN_RADIUS=20`), **2 bâtisseurs en parallèle**, mode berserker détruit colonnes entières au-dessus de `ref_y` (pas de pavage — fondations uniquement à la construction), protège workstations, re-scan max 3 passes, attente chargement chunks avant démarrage. **Construction parallèle** : `_try_queue_builds_for_phase` queue autant de bâtiments que de bâtisseurs disponibles (`slots = builders - active_builds`). `_find_build_site` utilise `ref_y+1` comme altitude (terrain plat garanti), 120 tentatives dans zone `VILLAGE_RADIUS`, anti-chevauchement structures terminées + en cours (queue + NPC) + workstations. Bâtisseur garde ses tâches build/flatten entre les sessions (nuit/socialisation). **Croissance village** : pop cap = 9 + 2×maisons, spawn villageois si 5+ pain, minimum bâtisseurs dynamique par phase (1→2→3). **Forge** : 3 recettes d'upgrade outils (vérifie tier avant craft). **Travail continu** : seuils stock bois 50, planches 1000. Mineurs continus toutes phases (plus de garde `total_stone < 40`). **Craft batch** : Planches, Pain, Verre, Lingot de fer jusqu'à 8× par tâche (menuisier craft 32 planches/cycle). `try_craft()` gère toutes les essences de bois via `consume_any_wood()` et toutes les variantes de planches via `consume_any_planks()`. **Sable** : crafté depuis le pavé (2 pavé → 1 sable, fourneau, batch ×8) — remplace la recherche de surface (désert hors portée chunks chargés). **Limites anti-AFK** : mine plan max 5000 blocs, purge >500 blocs minés, pause mine si stock saturé (pavé>2000+charbon>200+fer>80), saved_chunk_data max 100 chunks. **Stockage bâtiments** : coffres physiques (bloc CHEST) auto-placés dans les bâtiments à la construction. 3 bâtiments de stockage : Moulin (pain, blé), Forge (lingots fer/or/cuivre), Caserne (épées, boucliers). Capacité 500 items/coffre. `get_total_resource()` agrège stockpile + bâtiments. `consume_resources_anywhere()` consomme stockpile d'abord. `_route_craft_output()` redirige les crafts vers le bâtiment approprié. Production cappée quand bâtiment plein
- **`npc_villager.gd`** : PNJ avec professions et emploi du temps (14h travail/jour). **Modèle Steve GLB** unique avec skin par profession (12 skins 64×64 PNG, texture swap dynamique via `set_surface_override_material`, NEAREST filtering). **Outils tenus** : chaque PNJ tient visuellement l'outil de sa profession (BoneAttachment3D sur bones `rightItem`/`leftItem`), mesh extrudé 3D pixel-par-pixel (cache statique partagé), visible uniquement pendant WORK. **Pathfinding** : détection murs 2+ blocs, détours intelligents progressifs, abandon cible après 7 détours, cassage blocs mous (dureté ≤ 0.5), casse blocs durs après 2, téléport secours 25s, protection structures village. **Mode berserker** (`_berserker_walk_toward`) : casse TOUT immédiatement sur le chemin (0 détour), utilisé pour aller/revenir de la mine. **Bûcherons** : scan 3D exhaustif (rayon 4, early exit), dépouillent l'arbre entier. **Leaf decay Minecraft** : quand dernier tronc abattu, scan rayon 8, feuilles orphelines (aucun tronc à Manhattan ≤ 4) détruites en batch (pas ajoutées au stockpile). **Filtre inventaire berserker** (`_is_junk_block`) : terre, feuilles, herbe, podzol, mousse, gravier, farmland ignorés lors du cassage de passage. **Mineurs** : suit `mine_plan` pré-calculé via `get_next_mine_block()`, descend l'escalier via entrée de mine quand bloc profond (dy > 6), sauvegarde `_mine_resume_pos` pendant la balade pour retour direct au front, lookahead 20 blocs. **Bâtisseur flatten berserker** : `_execute_flatten(delta)` — `clear_column_above_ref_batched` modifie blocs directement dans chunk.blocks (1 rebuild/chunk au lieu de 50+), colonne + 4 voisins, tâche persistante entre activités. **Vitesse du jeu PNJ** : `_get_game_speed()` — timers minage/craft/build accélérés par multiplicateur, téléportation quand game_speed ≥ 2 et cible > 8 blocs, mineurs téléportés mine/blocs/surface, marche cappée ×3, scans/navigation en temps réel. **Pause déjeuner** : 12h-13h, PNJ convergent vers la place du village (`plaza_center`). **Système de faim** : DÉSACTIVÉ (drain 0.0) — en attente ferme fiable. Mécanisme prêt : drain 0.06/0.01, seuils 40/20. **Retour surface mineur** : remonte l'escalier en berserker (téléport en mode rapide)
- **`villager_profession.gd`** : 13 professions (BUCHERON, MENUISIER, FORGERON, BATISSEUR, FERMIER, BOULANGER, CHAMAN, MINEUR, NONE + ESPION, SOLDAT, GARDE, CAPITAINE), schedule 6 plages + MILITARY_SCHEDULE + SPY_SCHEDULE, workstation mapping, `get_skin_for_profession()` retourne le chemin du skin PNG, `PROFESSION_TOOLS` mapping + `get_held_tools()` pour les outils tenus par les PNJ
- **`poi_manager.gd`** : Points of Interest (workstations), claim/release, scan chunk, lookup O(1)
- **`village_inventory_ui.gd`** : UI gestion village (F1) — panel 680×760, phase, tier, **population X/Y**, **barre de faim** par villageois, **section fermes**, **bâtiments (X/Y)** avec progression en construction (blocs posés) et matériaux manquants pour le prochain, **prochain objectif + progression aplanissement (X/Y blocs, %) + progression place du village (X/Y blocs, %) + statut mine**, **ressources** (stockpile virtuel), **stockage bâtiments** (coffres par bâtiment : Moulin/Forge/Caserne avec capacité), **villageois numérotés** (Mineur 1, Mineur 2...) avec **activité temps réel**, **clic = téléport joueur**

### Guerre et village ennemi (Phase 4)
- **`enemy_village.gd`** : village ennemi simulé (pas de chunks réels), progression abstraite Phase 0→3 avec timers (production 10s, build 45s, phase 300s), stockpile virtuel, production militaire auto (épées, soldats), spawné uniquement en Phase 4
- **`war_manager.gd`** : orchestrateur de guerre — espionnage (4 espions cardinaux, 8 blocs/s, portée 1200), armée en marche (4 blocs/s, résolution combat force vs défense), attaque ennemie possible, phases PEACE→ESPIONAGE→PREPARATION→WAR→VICTORY/DEFEAT
- **`generate_castle.py`** : générateur Python de 4 structures château JSON (rempart, tour_defense, donjon, caserne) avec palette commune 12 blocs

### Combat
- **`arrow_entity.gd`** : flèche arc — gravité 20m/s², drag, dégâts 6.0, critique, knockback, particules, Label3D dégâts
- **`passive_mob.gd`** : *(inactif — plus de spawn)* code encore présent mais non utilisé. Les animaux ont été retirés pour se concentrer sur la gestion de village

### Joueur et UI
- **`player.gd`** : FPS CharacterBody3D, minage progressif (`BASE_MINING_TIME=5.0` × dureté/outil), hotbar 9 slots + outils + nourriture, arc (charge MC), placement blocs. **Zoom FOV** : Alt+Molette 70°→110° (step 5°), sprint ajoute +10° delta
- **`hand_item_renderer.gd`** : bras FPS — 3 rendus (bloc texturé, outil extrudé 3D pixel par pixel, modèle GLB). Swing sinusoïdal MC, bobbing, rendu arc
- **`tool_registry.gd`** : 18 outils, 5 tiers (bois→netherite), PICK_BOOST=2.0, CROSS_TOOL_MULT=1.3, listes blocs par type
- **`craft_registry.gd`** : ~70 recettes, 6 catégories (Hand, Furnace, Wood/Stone/Iron/Gold Table). **Forge** : 3 recettes `_tool_tier` (bois/pierre/fer). **Torche** : 1 coal + 1 planks → 4 torches. **Armes** : Épée fer, Épée or, Bouclier. **Coffre** : 8 planches → 1 CHEST (wood_table). **Sable** : 2 pavé → 1 sable (fourneau)
- **`hotbar_ui.gd`** / **`inventory_ui.gd`** : hotbar 9 slots + inventaire 7 onglets, textures réelles
- **`audio_manager.gd`** : pool audio, sons 65 blocs, ambiance forêt par heure, chargement null-safe
- **`locale.gd`** : traductions FR/EN

### Utilitaires
- **`world_manager.gd`** : chunks render_distance=6, village 9 PNJ (professions fixes : 1 bûcheron, 2 mineurs, 1 forgeron, 2 bâtisseurs, 1 menuisier, 1 fermier, 1 boulanger), POI manager, déchargement Dictionary-set O(1). Ancien flatten cosmétique remplacé par le système bâtisseur. *(Pas de spawn animaux — retiré v12.0.0)*
- **`day_night_cycle.gd`** : cycle jour/nuit 600s, **vitesse du temps** 4 niveaux (Lent ×0.5 / Normal ×1 / Rapide ×2 / Très rapide ×10), Ctrl+Molette dans le HUD
- **`save_manager.gd`** / **`health_ui.gd`** : sauvegarde, UI santé

## Biomes

**4 biomes procéduraux :** Désert (temp>0.65, humid<0.35), Forêt (temp 0.45-0.7, humid>0.55), Montagne (temp<0.35), Plaines (défaut)

## Scène principale (`scenes/main.tscn`)

WorldManager + Player (spawn y=80) + WorldEnvironment (SSAO, ciel pastel) + DirectionalLight3D + UI layers

## Structures prédéfinies (`structures/`)

Format JSON : palette + RLE layer-first. `KEEP`=terrain intact, `AIR`=creuser. Pipeline : `.schem` → `convert_schem.py` → JSON → `placements.json`

## Outils Python

- **`scripts/convert_schem.py`** (~940 lignes) : convertisseur `.schem` → JSON ClaudeCraft, parseur NBT maison, 260+ mappings blocs
- **`scripts/structure_viewer.py`** (v2.0.0, ~2600 lignes) : **éditeur + visualiseur 3D** PyQt6/PyOpenGL — 73 types de blocs, palette couleurs latérale, placement/suppression clic (raycasting AABB), undo/redo (Ctrl+Z/Y), curseur 3D transparent, export JSON. Toggle "Editer" (Ctrl+E) avec feedback visuel (texte vert + bordure verte viewport). Modes : visu (charge .json/.schem/.litematic/.glb/.obj) + éditeur (Ctrl+N nouveau, Ctrl+E toggle)
- **`scripts/bedrock_to_glb.py`** (v1.2.0, ~870 lignes) : convertisseur Minecraft Bedrock Edition → GLB. Extrait `geometry.humanoid.custom` depuis `mobs.json`, génère mesh skinné (28 bones, 288 vertices, 144 triangles), **8 animations bakées** (walk, idle, attack, mine, sit, sleep, attack2, cheer). Support channels rotation + translation. 2 matériaux (base opaque + overlay BLEND pour hat/sleeves/pants/jacket). Box UV Bedrock, scale 1/16. Copie 10 skins PNG. `--no-overlay` pour exclure les couches overlay
- **`scripts/character_viewer.py`** (v1.3.0, ~970 lignes) : visualiseur de personnage GLB PyQt6/PyOpenGL — skin swap (liste avec preview face, scan récursif sous-dossiers `professions/`), animation playback (sélecteur, play/pause, vitesse), squelette (bones jaunes + joints rouges), wireframe. Caméra orbitale (souris), grille, 2 lumières (key + fill). Rendu CPU skinning avec **channels rotation + translation**, alpha blend pour overlays transparents, fullscreen écran principal
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
- `assets/PlayerModel/` : modèle joueur Bedrock converti — `steve.glb` (28 bones, 8 anims : walk, idle, attack, mine, sit, sleep, attack2, cheer), `skins/` (10 PNG 64×64 : steve, alex, ari, kai, noor, etc.), `skins/professions/` (12 skins métiers : lumberjack, carpenter, blacksmith, builder, farmer, baker, shaman, miner, spy, soldier, guard, captain)
- `assets/Deco/` : apple.glb (nourriture)
- `assets/Lobbys/` : .schem Minecraft à convertir

## Direction du projet

**Version actuelle : v16.6.0**

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
| 5.8 | Fait | v12.8.0 — Aplanissement terrain village (`FLATTEN_RADIUS=20`, zone 41×41). Altitude médiane comme référence, bâtisseur casse au-dessus et comble en cobblestone en dessous. Phase gating : pas de builds/chemin tant que le terrain n'est pas plat. `_find_build_site` simplifié (`ref_y+1`, zone `VILLAGE_RADIUS=45`, anti-overlap workstations). UI progression aplanissement (X/Y blocs, %). Ancien flatten cosmétique (13×13, break only) supprimé |
| 5.9 | Fait | v12.9.0 — Bâtisseur turbo : flatten batch ×8 blocs/tick (0.08s), construction batch ×4 blocs/tick (0.15s), chemin batch ×6 blocs/tick (0.1s). Terrain aplani ~10× plus vite, bâtiments construits ~5× plus vite |
| 6.0 | Fait | v13.0.0 — **Vrais bâtiments Minecraft** : blueprints chargés depuis JSON (structures .schematic converties). Cabane=Survival House, Ferme=Wood House, Forge=Fantasy Forge, Maison=Spruce House 2, Entrepôt=Guard Outpost, Guilde=Spruce House. `convert_schem.py` supporte MCEdit/Alpha (IDs numériques pré-1.13, 256 blocs + metadata couleurs). Village agrandi `VILLAGE_RADIUS=45` (zone 91×91). Filtrage terrain automatique, matériaux simplifiés (bois/pierre/verre). 22 structures converties en stock |
| 6.1 | Fait | v13.1.0 — Taverne (Medieval Tavern Inn, 19×19×31) et Moulin (Windmill, 35×49×35) ajoutés comme blueprints Phase 2. 10 bâtiments au total |
| 6.2 | Fait | v13.2.0 — **Éditeur de structures 3D** (`structure_viewer.py` v2.0.0) : 73 blocs pastel, palette latérale swatches, placement/suppression clic (raycasting AABB), curseur 3D transparent, undo/redo (Ctrl+Z/Y), toggle Editer (Ctrl+E) avec texte vert + bordure verte viewport, Ctrl+N nouveau, export JSON. Palette cachée en mode visu, visible en mode édition |
| 6.3 | Fait | v13.3.0 — **Chapelle de village** : église médiévale 13×18×21 générée (pierre, clocher carré, vitraux, rosace, autel, bancs, torches). Blueprint Phase 2, 11 bâtiments au total. Script `generate_church.py` |
| 6.4 | Fait | v13.4.0 — **Place du village** : puits central 5×5 + 4 torches + 4 chemins cobblestone 3 large × 12 long. PNJ convergent vers la place pendant la pause déjeuner (12h-13h). UI progression place |
| 7.0 | Fait | v14.0.0 — **Refonte flatten berserker + vitesse du temps**. Bâtisseur en mode berserker pour aplanir (détruit colonnes entières, pas de pavage). `FLATTEN_RADIUS=20` (zone 41×41) séparé de `VILLAGE_RADIUS=45`. Attente chargement chunks avant flatten. Re-scan 3 passes. Ferme à 30+ blocs du centre. Vitesse du temps : Ctrl+Molette 4 niveaux (Lent ×0.5 / Normal ×1 / Rapide ×2 / Très rapide ×10) |
| 7.1 | Fait | v14.1.0 — **Fix FPS + leaf decay Minecraft**. `clear_column_above_ref_batched` : modifie blocs directement dans chunk.blocks sans rebuild, rebuild 1 seule fois par chunk affecté (élimine 50+ rebuilds/colonne). Leaf decay : scan rayon 8, identifie feuilles orphelines (aucun tronc à distance Manhattan ≤ 4), destruction batch. Fix workstations sur feuilles : `find_flat_spot_near_center` utilise `ref_y+1` au lieu de `_find_surface_y` |
| 7.1.1 | Fait | v14.1.1 — Fix flatten drops (plus de cobblestone/feuilles dans l'inventaire), seuil planches 500, mineurs continus phase 3 |
| 7.2 | Fait | v14.2.0 — **Fix économie village**. Seuils mine relevés (pavé 2000, charbon 200, fer 80). Filtre inventaire `_is_junk_block` (enum-safe) — terre, feuilles, herbe, podzol, mousse, gravier filtrés partout (berserker + mine galerie + mine surface). Fix IDs junk (enum au lieu de magic numbers). `_has_task_of_type` vérifie queue + villageois actifs (fix doublons craft). `_add_harvest_tasks` compte villageois actifs. Craft échoué : tâche supprimée + cooldown 5s (fix spam forgeron). Sable : rayon 72, 2 tâches, tout villageois. Planches seuil 1000. Mineurs continus toutes phases. Fonderie fer phase 3. Flatten 2 bâtisseurs parallèles |
| 7.3 | Fait | v14.3.0 — **Chemins larges + torches village**. Chemins plaza élargis à 5 blocs de large (au lieu de 3). Routes automatiques de 3 blocs de large entre chaque bâtiment et la plaza (tracé en L, torches tous les 6 blocs). Place de 7 blocs autour de la chapelle (cobblestone + 4 torches coins). Craft proactif de torches (1 charbon + 1 planche = 4 torches, seuil 32, menuisier, phases 1-3). Torches consomment du stock (plus gratuites) |
| 8 | Fait | v15.0.0 — **Phase 4 — Âge Médiéval**. Village ennemi simulé (`enemy_village.gd`) à 400-600 blocs, progression abstraite Phase 0→3. `war_manager.gd` : 4 espions simulés (timer, 1200 blocs max), recrutement soldats (épée + pain), armée en marche (timer distance), combat résolu. 4 nouveaux items (IRON_SWORD, GOLD_SWORD, SHIELD) + 3 recettes forge. 4 nouvelles professions (ESPION, SOLDAT, GARDE, CAPITAINE) avec schedules militaires. 4 blueprints château générés (`generate_castle.py`) : rempart 3×7×12, tour défense 7×12×7, donjon 15×16×15, caserne 11×8×9. Phase 4 évalue : construction château, forge épées/boucliers. UI militaire (guerre, ennemi, épées). Attaque ennemie possible. Aussi : chemins plaza 5 large, routes bâtiment→plaza 3 large + torches, place chapelle 7 blocs, craft torches proactif, leaf decay amélioré + nettoyage périodique 30s |
| 8.1 | Fait | v15.1.0 — **Modèle Steve avec skins par profession**. Remplacement des 18 modèles Kenney par le modèle Steve GLB unique (28 bones, 4 anims). 12 skins de profession 64×64 PNG (bûcheron, menuisier, forgeron, bâtisseur, fermier, boulanger, chaman, mineur + espion, soldat, garde, capitaine). Texture swap dynamique via `set_surface_override_material` (NEAREST filtering). Character viewer v1.2.0 : scan récursif sous-dossiers skins |
| 8.1.1 | Fait | v15.1.1 — **Fix bâtisseur bloqué** à 96/513 blocs. Teleport dédié `_build_walk_timer` après 8s (contourne le stuck detection cassé par les détours) |
| 8.1.2 | Fait | v15.1.2 — **8 animations Steve** (walk, idle, attack, mine, sit, sleep, attack2, cheer). Fix animations inversées (moonwalk, attaque arrière). Support channels translation (sit au sol). Character viewer v1.3.0 : translation animée, fullscreen écran principal |
| 8.2 | Fait | v15.2.0 — **Bâtisseurs parallèles**. `_try_queue_builds_for_phase` queue autant de bâtiments que de bâtisseurs disponibles (slots = builders - active_builds). Anti-chevauchement constructions en cours (queue + NPC actifs, marge 4 blocs). 2 bâtisseurs dès le spawn initial (1 bûcheron → 1 bâtisseur). Besoin en bâtisseurs dynamique par phase : 1 (Phase 0-1), 2 (Phase 2), 3 (Phase 3+). Déblocage Phase 4 accéléré |
| 8.2.1 | Fait | v15.2.1 — **Fix file de construction + mine cap**. `_try_queue_build` retourne bool — les bâtiments chers (Taverne 1747 planches) ne bloquent plus les pas chers (Tour de guet 35 planches). Mine cap : max 50 expansions pour empêcher le plan de croître à 82000+ blocs dans les zones de grottes/chunks non chargés |
| 8.3 | Fait | v15.3.0 — **Zoom FOV + render distance**. Alt+Molette : zoom FOV 70°→110° (step 5°, 9 paliers), sprint conserve le delta +10°. Render distance 5→6 (~85 chunks, +39%). Contrôles molette : Molette=hotbar, Ctrl+Molette=vitesse du temps, Alt+Molette=zoom FOV |
| 9 | Fait | v16.0.0 — **Stockage bâtiments (coffres)**. Bloc CHEST (77e type, textures barrel). Coffres physiques auto-placés dans les bâtiments à la construction. 3 bâtiments de stockage : Moulin (pain, blé), Forge (lingots), Caserne (armes). Capacité 500 items/coffre. `get_total_resource()` agrège stockpile + bâtiments, `consume_resources_anywhere()`, `_route_craft_output()` redirige les crafts. Production cappée quand bâtiment plein (fix spam 1257 pains). Recette : 8 planches → 1 coffre. UI village optimisée : panel 680×760 (fix débordement 1080p), nouvelle section "Stockage bâtiments" avec capacité et items par bâtiment |
| 9.1 | Fait | v16.0.1 — **Fix forgeron bloqué**. `get_next_task_for()` 2 passes : spécialiste d'abord, générique ensuite (fix forgeron prenant sable au lieu de craft). Teleport craft : PNJ >6 blocs sous workstation → téléporté (fix forgeron au fond de mine). `get_resource_count()` → `get_total_resource()` pour blé et lingots dans évaluation de phases |
| 9.2 | Fait | v16.0.2 — **Fix mine/production**. Mine auto-reset : quand 200 expansions atteintes ET plan vide, reset compteur et descend 5 blocs. `MINE_MAX_EXPANSIONS` 50→200. `_is_building_full()` cap 200 items en stockpile quand bâtiment pas encore construit (fix 8238 pains) |
| 9.3 | Fait | v16.0.3 — **Fix sable introuvable**. Recette "Sable" (2 pavé → 1 sable, fourneau) remplace la recherche de sable en surface (6 PNJ bloqués sur "Cherche sable..." pendant des jours, désert hors de portée des chunks chargés). Craft batch ×8. Supprime la dépendance au biome désert |
| 9.4 | WIP | v16.1.0 — **Outils tenus + fix animations PNJ**. Mesh extrudé 3D pixel-par-pixel, position fixe sur le modèle (pas encore de bone tracking — à améliorer : taille ×2-3 et position bras). **Fix moonwalk** : `+PI` sur les 3 `atan2` de rotation. **Fix jambes écartées** : `AnimationPlayer.deterministic=true` + `reset_bone_poses()` + epsilon rotation (0.01°) dans le GLB pour forcer les tracks bones majeurs (Godot optimise les tracks identity). `PROFESSION_TOOLS` mapping dans `villager_profession.gd`, `_build_npc_tool_mesh()` + `_attach_tool_fixed()` + `_set_tools_visible()` dans `npc_villager.gd`. bedrock_to_glb v1.2.0 : `FORCE_TRACK_BONES` + `EPSILON_QUAT`. **TODO** : agrandir outils ×2-3, positionner sur le bras, bone tracking si possible |
| 9.5 | Fait | v16.6.0 — **Végétation décorative cross-mesh**. 6 nouveaux types de blocs (SHORT_GRASS, FERN, DEAD_BUSH, DANDELION, POPPY, CORNFLOWER). Cross billboards : 2 quads verticaux en X au centre du bloc, shader cull_disabled + alpha_scissor. Flora mesh séparé par chunk (comme water mesh). Génération par biome : herbe ~25-30% sur GRASS/DARK_GRASS, fougères ~8% en forêt, fleurs ~2% (pissenlit/coquelicot/bleuet), buissons morts ~8% sur sable. Textures Faithful32 (32×32 avec transparence alpha). Pas de collision, hardness 0 (casse instantanée). Junk filter PNJ mis à jour. Surface detection village ignore la végétation |
| 10 | À venir | Système de faim actif, chaînes de production, combat PNJ visuel |

**Packs GLB utilisés** : Steve GLB (modèle Bedrock converti, 28 bones, 4 anims) pour tous les PNJ avec skins par profession. Kenney.nl (18 modèles BlockPNJ — conservés mais plus utilisés). **PNJ futurs** : KayKit Adventurers (161 anims travail)

**Données MC disponibles :** 2390 blocs, 1283 items, 1396 recettes dans `minecraft_data/`

## Sources MC locales

- Java 1.21.11 : `D:\Games\Minecraft - 1.21.11\client.jar`
- Bedrock : `D:\Games\Minecraft - Bedrock Edition\data\`
- MC 1.12 source (MCP940) : `D:\Projets\Source code of minecraft 1.12\mcp940-master\`
