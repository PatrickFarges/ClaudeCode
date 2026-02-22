extends Node

# VillageManager — cerveau centralisé du village autonome
# Gère le stockpile partagé, la file de tâches, la progression technologique
# et les blueprints de bâtiments. Les villageois exécutent les tâches assignées.

const VProfession = preload("res://scripts/villager_profession.gd")

const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256

# === STOCKPILE PARTAGÉ ===
# Dictionary { BlockType(int) -> int(count) }
var stockpile: Dictionary = {}

# === PROGRESSION ===
# Phase 0: mains nues -> bois -> planches -> crafting_table
# Phase 1: age du bois (crafting_table) -> pierre -> furnace
# Phase 2: age de la pierre (furnace) -> fer -> stone_table
# Phase 3: age du fer -> expansion
var village_phase: int = 0
var village_tool_tier: int = 0  # 0=mains, 1=bois, 2=pierre, 3=fer

const TOOL_TIER_MULTIPLIER = {
	0: 1.0,
	1: 1.667,
	2: 2.0,
	3: 2.5,
}

# === CENTRE DU VILLAGE ===
var village_center: Vector3 = Vector3.ZERO
var _center_set: bool = false

# === FILE DE TÂCHES ===
# Array de Dictionaries, triée par priorité (plus bas = plus urgent)
var task_queue: Array = []

# === VILLAGEOIS ===
var villagers: Array = []  # refs vers les NpcVillager

# === POSITIONS CLAIMED ===
# Dictionary { Vector3i -> true } — blocs réservés par un villageois
var claimed_positions: Dictionary = {}
const HARVEST_EXCLUSION_RADIUS = 6.0  # distance min entre arbres claimés

# === WORKSTATIONS PLACÉES ===
var placed_workstations: Dictionary = {}  # { BlockType -> Vector3i }

# === CACHE DE SCAN ===
var _scan_cache: Dictionary = {}  # { BlockType -> { "results": Array, "time": float } }
const SCAN_CACHE_DURATION = 8.0  # durée cache scan — plus long pour éviter les rescans coûteux

# === MINE / GALERIE ===
var mine_plan: Array = []          # Array de Vector3i — blocs à creuser dans l'ordre (du haut vers le bas)
var mine_front_index: int = 0      # front de la mine — plus loin qu'un mineur a creusé
var mine_entrance: Vector3i = Vector3i(-9999, -9999, -9999)
var _mine_initialized: bool = false
var _mine_gallery_center: Vector3i = Vector3i.ZERO  # centre de la galerie actuelle
var _mine_gallery_y: int = 45      # profondeur galerie actuelle
var _mine_expansion_dir: int = 0   # direction de la prochaine expansion (0-3)

# === TIMER ===
var _eval_timer: float = 0.0
const EVAL_INTERVAL = 5.0  # évaluation toutes les 5s (au lieu de 3)

# === REFS ===
var world_manager = null

# === BLUEPRINTS ===
# Bâtiments que le village peut construire
# Chaque blueprint: { name, size: Vector3i, materials: { BlockType->count }, block_list: [[x,y,z,BlockType], ...] }
var BLUEPRINTS: Array = []

# === BÂTIMENTS CONSTRUITS ===
var built_structures: Array = []  # Array de { "name": String, "origin": Vector3i }

# === CHEMIN DU VILLAGE ===
var _path_built: bool = false  # true quand le chemin en croix est posé
var _path_blocks: Array = []   # blocs du chemin à poser [Vector3i, ...]
var _path_index: int = 0       # progression dans la pose du chemin

func _ready():
	_init_blueprints()
	print("VillageManager: initialisé")

func _process(delta):
	if not world_manager:
		world_manager = get_tree().get_first_node_in_group("world_manager")
		return

	_eval_timer += delta
	if _eval_timer >= EVAL_INTERVAL:
		_eval_timer = 0.0
		_evaluate_needs()

# ============================================================
# CENTRE DU VILLAGE
# ============================================================

func set_village_center(pos: Vector3):
	village_center = pos
	_center_set = true
	print("VillageManager: centre du village à %s" % str(pos))

# ============================================================
# STOCKPILE
# ============================================================

func add_resource(block_type: int, count: int = 1):
	stockpile[block_type] = stockpile.get(block_type, 0) + count

func has_resources(block_type: int, count: int = 1) -> bool:
	return stockpile.get(block_type, 0) >= count

func consume_resources(block_type: int, count: int) -> bool:
	var have = stockpile.get(block_type, 0)
	if have < count:
		return false
	stockpile[block_type] = have - count
	if stockpile[block_type] == 0:
		stockpile.erase(block_type)
	return true

func get_resource_count(block_type: int) -> int:
	return stockpile.get(block_type, 0)

func get_total_wood() -> int:
	# Compte tous les types de bûches
	var total = 0
	for bt in [5, 32, 33, 34, 35, 36, 42]:  # WOOD, SPRUCE_LOG, BIRCH_LOG, JUNGLE_LOG, ACACIA_LOG, DARK_OAK_LOG, CHERRY_LOG
		total += stockpile.get(bt, 0)
	return total

func get_total_planks() -> int:
	var total = 0
	for bt in [11, 37, 38, 39, 40, 41, 43]:  # PLANKS + variantes
		total += stockpile.get(bt, 0)
	return total

func consume_any_wood(count: int) -> bool:
	var wood_types = [5, 32, 33, 34, 35, 36, 42]
	var remaining = count
	for bt in wood_types:
		var have = stockpile.get(bt, 0)
		if have > 0:
			var take = mini(have, remaining)
			stockpile[bt] = have - take
			if stockpile[bt] == 0:
				stockpile.erase(bt)
			remaining -= take
			if remaining <= 0:
				return true
	return remaining <= 0

func consume_any_planks(count: int) -> bool:
	var plank_types = [11, 37, 38, 39, 40, 41, 43]
	var remaining = count
	for bt in plank_types:
		var have = stockpile.get(bt, 0)
		if have > 0:
			var take = mini(have, remaining)
			stockpile[bt] = have - take
			if stockpile[bt] == 0:
				stockpile.erase(bt)
			remaining -= take
			if remaining <= 0:
				return true
	return remaining <= 0

# ============================================================
# ÉVALUATION DES BESOINS (boucle principale)
# ============================================================

func _evaluate_needs():
	# Ne pas empiler les tâches s'il y en a déjà beaucoup
	if task_queue.size() > 15:
		return

	match village_phase:
		0:
			_evaluate_phase_0()
		1:
			_evaluate_phase_1()
		2:
			_evaluate_phase_2()
		3:
			_evaluate_phase_3()

func _evaluate_phase_0():
	# Phase 0: Bootstrap — récolter bois, crafter planches, crafter crafting_table
	var total_wood = get_total_wood()
	var total_planks = get_total_planks()

	# Besoin de 10 bois pour démarrer — bûcherons ET fermier y participent
	if total_wood < 10 and total_planks < 4:
		if task_queue.size() == 0:
			print("VillageManager: Phase 0 — bois=%d planches=%d → ajout tâches récolte" % [total_wood, total_planks])
		_add_harvest_tasks(5, 4)  # Bûcherons
		# Le fermier aide aussi à récolter du bois au bootstrap
		_add_task({
			"type": "harvest",
			"target_block": 5,
			"priority": 20,
			"required_profession": VProfession.Profession.FERMIER,
		})
		return

	# Crafter des planches si on a du bois (menuisier ou forgeron peut le faire)
	if total_wood >= 1 and total_planks < 8:
		_add_task({
			"type": "craft",
			"recipe_name": "Planches",
			"priority": 10,
			"required_profession": VProfession.Profession.MENUISIER,
		})

	# Crafter la crafting table si on a 4 planches
	if total_planks >= 4 and not placed_workstations.has(12):  # CRAFTING_TABLE
		if not _has_task_of_type("craft", "Table de Craft"):
			_add_task({
				"type": "craft",
				"recipe_name": "Table de Craft",
				"priority": 5,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Placer la crafting table si on en a une
	if get_resource_count(12) >= 1 and not placed_workstations.has(12):
		_add_task({
			"type": "place_workstation",
			"target_block": 12,  # CRAFTING_TABLE
			"priority": 3,
			"required_profession": VProfession.Profession.BATISSEUR,
		})

	# Si crafting table placée -> phase 1
	if placed_workstations.has(12):
		village_phase = 1
		village_tool_tier = 1
		print("VillageManager: === PHASE 1 — ÂGE DU BOIS ===  (tier %s)" % village_tool_tier)

func _evaluate_phase_1():
	# Phase 1: Récolter plus de bois + pierre, crafter furnace, construire
	var total_wood = get_total_wood()
	var total_planks = get_total_planks()
	var total_stone = get_resource_count(3)  # STONE
	var total_cobble = get_resource_count(25)  # COBBLESTONE

	# Toujours maintenir du bois en stock
	if total_wood < 20:
		_add_harvest_tasks(5, 4)  # plus de bois

	# Le menuisier transforme le bois en planches en continu
	if total_wood >= 2 and total_planks < 30:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Commencer à miner (galerie souterraine)
	if total_stone < 20:
		_add_mine_gallery_tasks(2)

	# Crafter le fourneau (8 stone)
	if total_stone >= 8 and not placed_workstations.has(21):  # FURNACE
		if not _has_task_of_type("craft", "Fourneau"):
			_add_task({
				"type": "craft",
				"recipe_name": "Fourneau",
				"priority": 8,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Placer le fourneau
	if get_resource_count(21) >= 1 and not placed_workstations.has(21):
		_add_task({
			"type": "place_workstation",
			"target_block": 21,  # FURNACE
			"priority": 5,
			"required_profession": VProfession.Profession.BATISSEUR,
		})

	# D'abord construire le chemin en croix autour du centre
	if not _path_built and get_resource_count(25) >= 5:  # COBBLESTONE
		_try_queue_path()

	# Construire la première cabane si on a les matériaux
	if _path_built and placed_workstations.has(21) and built_structures.size() == 0:
		_try_queue_build(0)  # Blueprint 0 = cabane

	# Si furnace placée -> phase 2
	if placed_workstations.has(21):
		village_phase = 2
		village_tool_tier = 2
		print("VillageManager: === PHASE 2 — ÂGE DE LA PIERRE === (tier %s)" % village_tool_tier)

func _evaluate_phase_2():
	# Phase 2: Miner charbon/fer, fondre, crafter stone_table
	var total_wood = get_total_wood()
	var total_stone = get_resource_count(3)
	var total_coal = get_resource_count(16)   # COAL_ORE
	var total_iron_ore = get_resource_count(17)  # IRON_ORE
	var total_iron = get_resource_count(19)   # IRON_INGOT

	# Maintenir le stock
	if total_wood < 15:
		_add_harvest_tasks(5, 3)

	# Miner en galerie (pierre + charbon + fer trouvés automatiquement)
	if total_stone < 15 or total_coal < 8 or (total_iron_ore < 4 and total_iron < 4):
		_add_mine_gallery_tasks(2)

	# Fondre le fer (recette furnace: 1 iron_ore + 1 coal_ore -> 1 iron_ingot)
	if total_iron_ore >= 1 and total_coal >= 1 and total_iron < 4:
		if not _has_task_of_type("craft", "Lingot de fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Lingot de fer",
				"priority": 10,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Crafter stone_table (4 stone + 4 planks)
	if total_iron >= 4 and total_stone >= 4 and not placed_workstations.has(22):
		if not _has_task_of_type("craft", "Table en pierre"):
			_add_task({
				"type": "craft",
				"recipe_name": "Table en pierre",
				"priority": 8,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Placer stone_table
	if get_resource_count(22) >= 1 and not placed_workstations.has(22):
		_add_task({
			"type": "place_workstation",
			"target_block": 22,  # STONE_TABLE
			"priority": 5,
			"required_profession": VProfession.Profession.BATISSEUR,
		})

	# Chemin si pas encore fait
	if not _path_built and get_resource_count(25) >= 5:
		_try_queue_path()

	# Construire plus de bâtiments
	if _path_built and built_structures.size() < 2:
		_try_queue_build(1)  # Blueprint 1 = atelier

	# Si stone_table placée -> phase 3
	if placed_workstations.has(22):
		village_phase = 3
		village_tool_tier = 3
		print("VillageManager: === PHASE 3 — ÂGE DU FER === (tier %s)" % village_tool_tier)

func _evaluate_phase_3():
	# Phase 3: Expansion continue
	var total_wood = get_total_wood()
	var total_stone = get_resource_count(3)

	if total_wood < 20:
		_add_harvest_tasks(5, 3)
	if total_stone < 20:
		_add_mine_gallery_tasks(2)

	# Construire plus
	if built_structures.size() < BLUEPRINTS.size():
		_try_queue_build(built_structures.size())

# ============================================================
# GESTION DES TÂCHES
# ============================================================

func _add_task(task: Dictionary):
	task_queue.append(task)
	task_queue.sort_custom(func(a, b): return a.get("priority", 50) < b.get("priority", 50))

func _has_task_of_type(type: String, recipe_name: String = "") -> bool:
	for t in task_queue:
		if t["type"] == type:
			if recipe_name != "" and t.get("recipe_name", "") != recipe_name:
				continue
			return true
	return false

func _add_harvest_tasks(block_type: int, count: int):
	# Tous les types de bois sont acceptables
	var wood_types = [5, 32, 33, 34, 35, 36, 42]  # WOOD + toutes les essences
	var existing = 0
	for t in task_queue:
		if t["type"] == "harvest" and t.get("target_block", -1) in wood_types:
			existing += 1
	if existing >= count:
		return

	for i in range(count - existing):
		_add_task({
			"type": "harvest",
			"target_block": block_type,
			"priority": 20,
			"required_profession": VProfession.Profession.BUCHERON,
		})

func _add_mine_tasks(block_type: int, count: int):
	var existing = 0
	for t in task_queue:
		if t["type"] == "mine" and t.get("target_block", -1) == block_type:
			existing += 1
	if existing >= count:
		return

	for i in range(count - existing):
		_add_task({
			"type": "mine",
			"target_block": block_type,
			"priority": 25,
			"required_profession": VProfession.Profession.MINEUR,
		})

func get_next_task_for(prof: int) -> Dictionary:
	# Cherche la première tâche compatible avec la profession du villageois
	for i in range(task_queue.size()):
		var task = task_queue[i]
		var req = task.get("required_profession", -1)
		if req == -1 or req == prof:
			task_queue.remove_at(i)
			return task
	return {}

func get_next_task() -> Dictionary:
	if task_queue.size() == 0:
		return {}
	return task_queue.pop_front()

func return_task(task: Dictionary):
	# Remettre une tâche non terminée dans la queue
	task_queue.push_front(task)

# ============================================================
# SCAN DE BLOCS
# ============================================================

func _is_too_close_to_claimed(pos: Vector3i, exclusion_radius: float) -> bool:
	# Vérifie si une position est trop proche d'une position déjà claimée
	if exclusion_radius <= 0:
		return claimed_positions.has(pos)
	var pos_v3 = Vector3(pos.x, pos.y, pos.z)
	for claimed_pos in claimed_positions:
		var d = pos_v3.distance_to(Vector3(claimed_pos.x, claimed_pos.y, claimed_pos.z))
		if d < exclusion_radius:
			return true
	return false

func find_nearest_block(block_type: int, from_pos: Vector3, radius: float = 32.0, exclusion_radius: float = 0.0) -> Vector3i:
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	# Check cache
	var now = Time.get_ticks_msec() / 1000.0
	var cache_key = block_type
	if _scan_cache.has(cache_key):
		var cached = _scan_cache[cache_key]
		if now - cached["time"] < SCAN_CACHE_DURATION:
			# Chercher le plus proche non-claimé dans le cache
			var best = Vector3i(-9999, -9999, -9999)
			var best_dist = INF
			for pos in cached["results"]:
				if _is_too_close_to_claimed(pos, exclusion_radius):
					continue
				var d = from_pos.distance_to(Vector3(pos.x, pos.y, pos.z))
				if d < best_dist:
					best_dist = d
					best = pos
			if best != Vector3i(-9999, -9999, -9999):
				return best

	# Scan les chunks chargés
	var results: Array = []
	var from_chunk = Vector3i(
		floori(from_pos.x / CHUNK_SIZE),
		0,
		floori(from_pos.z / CHUNK_SIZE)
	)
	var chunk_radius = ceili(radius / CHUNK_SIZE) + 1

	# Blocs bois acceptables pour les tâches harvest
	var acceptable_types: Array = [block_type]
	if block_type == 5:  # WOOD -> accepter toutes les essences
		acceptable_types = [5, 32, 33, 34, 35, 36, 42]

	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var chunk_pos = Vector3i(cx, 0, cz)
			if not world_manager.chunks.has(chunk_pos):
				continue

			var chunk = world_manager.chunks[chunk_pos]
			var blocks = chunk.blocks

			# Scan du PackedByteArray
			for lx in range(CHUNK_SIZE):
				var x_off = lx * CHUNK_SIZE * CHUNK_HEIGHT
				for lz in range(CHUNK_SIZE):
					var xz_off = x_off + lz * CHUNK_HEIGHT
					# Limiter le scan vertical au range utile
					var y_start = maxi(chunk.y_min, 1)
					var y_end = mini(chunk.y_max + 1, CHUNK_HEIGHT)
					for ly in range(y_start, y_end):
						var bt = blocks[xz_off + ly]
						if bt in acceptable_types:
							var world_pos = Vector3i(
								cx * CHUNK_SIZE + lx,
								ly,
								cz * CHUNK_SIZE + lz
							)
							var d = from_pos.distance_to(Vector3(world_pos.x, world_pos.y, world_pos.z))
							if d <= radius:
								results.append(world_pos)

	# Mettre en cache
	_scan_cache[cache_key] = { "results": results, "time": now }

	# Trouver le plus proche non-claimé (avec exclusion radius)
	var best = Vector3i(-9999, -9999, -9999)
	var best_dist = INF
	for pos in results:
		if _is_too_close_to_claimed(pos, exclusion_radius):
			continue
		var d = from_pos.distance_to(Vector3(pos.x, pos.y, pos.z))
		if d < best_dist:
			best_dist = d
			best = pos

	return best

func find_nearest_surface_block(block_type: int, from_pos: Vector3, radius: float = 32.0) -> Vector3i:
	# Comme find_nearest_block mais ne retourne que les blocs en surface
	# (avec AIR au-dessus)
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	var from_chunk = Vector3i(
		floori(from_pos.x / CHUNK_SIZE),
		0,
		floori(from_pos.z / CHUNK_SIZE)
	)
	var chunk_radius = ceili(radius / CHUNK_SIZE) + 1
	var best = Vector3i(-9999, -9999, -9999)
	var best_dist = INF

	var acceptable_types: Array = [block_type]
	if block_type == 5:
		acceptable_types = [5, 32, 33, 34, 35, 36, 42]

	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var chunk_pos = Vector3i(cx, 0, cz)
			if not world_manager.chunks.has(chunk_pos):
				continue

			var chunk = world_manager.chunks[chunk_pos]
			var blocks_data = chunk.blocks

			for lx in range(CHUNK_SIZE):
				var x_off = lx * CHUNK_SIZE * CHUNK_HEIGHT
				for lz in range(CHUNK_SIZE):
					var xz_off = x_off + lz * CHUNK_HEIGHT
					var y_start = maxi(chunk.y_min, 1)
					var y_end = mini(chunk.y_max + 1, CHUNK_HEIGHT - 1)
					for ly in range(y_start, y_end):
						var bt = blocks_data[xz_off + ly]
						if bt in acceptable_types:
							# Vérifier qu'il y a de l'air au-dessus
							if blocks_data[xz_off + ly + 1] == 0:  # AIR
								var world_pos = Vector3i(
									cx * CHUNK_SIZE + lx,
									ly,
									cz * CHUNK_SIZE + lz
								)
								if claimed_positions.has(world_pos):
									continue
								var d = from_pos.distance_to(Vector3(world_pos.x, world_pos.y, world_pos.z))
								if d <= radius and d < best_dist:
									best_dist = d
									best = world_pos

	return best

func claim_position(pos: Vector3i):
	claimed_positions[pos] = true

func release_position(pos: Vector3i):
	claimed_positions.erase(pos)

func invalidate_scan_cache():
	_scan_cache.clear()

# ============================================================
# SYSTÈME DE MINE (galeries souterraines)
# ============================================================

func _init_mine():
	# Trouver un spot d'entrée PROCHE du village center et à altitude similaire
	if _mine_initialized:
		return
	if not world_manager:
		return

	var center_y = int(village_center.y)
	var best_pos = Vector3i(-9999, -9999, -9999)
	var best_y_diff = 999

	# Chercher un spot PROCHE (2-4 blocs) dont le surface_y est proche du centre
	for attempt in range(15):
		var dx = randi_range(2, 4) * (1 if randf() > 0.5 else -1)
		var dz = randi_range(2, 4) * (1 if randf() > 0.5 else -1)
		var cx = int(village_center.x) + dx
		var cz = int(village_center.z) + dz
		var surface_y = _find_surface_y(cx, cz)
		if surface_y < 0:
			continue
		var y_diff = abs(surface_y - center_y)
		if y_diff < best_y_diff:
			best_y_diff = y_diff
			best_pos = Vector3i(cx, surface_y, cz)

	if best_pos == Vector3i(-9999, -9999, -9999):
		return

	mine_entrance = best_pos
	_mine_initialized = true

	# Générer le plan de mine — escalier DROIT descendant (2 blocs de large)
	# IMPORTANT: l'ordre des blocs est SÉQUENTIEL — chaque bloc n'est minable
	# que si le précédent a été miné (top-down). Le feet block est TOUJOURS premier
	# car il a de l'AIR au-dessus (surface), puis le head block est ajouté pour
	# permettre au villageois de passer (2 blocs de haut).
	mine_plan.clear()
	mine_front_index = 0

	var target_y = maxi(center_y - 30, 20)  # descendre de 30 blocs max, minimum y=20
	_mine_gallery_y = target_y

	# Phase 1: Escalier droit — descend de 1/pas en X
	# Chaque marche = [bloc pieds, bloc tête] — ordre séquentiel garanti
	var pos = mine_entrance
	var dir_x = 1
	var steps = 0
	while pos.y > target_y:
		# Mine le sol (pieds) — toujours accessible car AIR au-dessus ou bloc précédent déjà miné
		mine_plan.append(Vector3i(pos.x, pos.y, pos.z))
		# Mine la tête (le bloc au-dessus du sol d'en dessous) — pour créer le passage
		mine_plan.append(Vector3i(pos.x, pos.y + 1, pos.z))
		# Descendre d'une marche
		pos = Vector3i(pos.x + dir_x, pos.y - 1, pos.z)
		steps += 1
		# Zigzag tous les 5 pas pour rester compact
		if steps % 5 == 0:
			dir_x = -dir_x
			pos = Vector3i(pos.x, pos.y, pos.z + 1)

	# Phase 2: Galerie en étoile au fond — 4 branches de 8 blocs
	_mine_gallery_center = Vector3i(pos.x, target_y, pos.z)
	var gc = _mine_gallery_center
	var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for dir in dirs:
		for i in range(1, 9):
			mine_plan.append(Vector3i(gc.x + dir[0] * i, target_y, gc.z + dir[1] * i))
			mine_plan.append(Vector3i(gc.x + dir[0] * i, target_y + 1, gc.z + dir[1] * i))

	_mine_expansion_dir = 0
	print("VillageManager: mine planifiée — %d blocs à creuser depuis %s" % [mine_plan.size(), str(mine_entrance)])

func get_next_mine_block() -> Vector3i:
	# Retourne le prochain bloc SÉQUENTIEL dans le plan de mine
	# La mine est creusée de haut en bas — chaque bloc devient accessible
	# dès que le précédent est miné (escalier top-down)
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	# Avancer le front sur les blocs déjà AIR (creusés ou naturellement vides)
	while mine_front_index < mine_plan.size():
		var pos = mine_plan[mine_front_index]
		var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
		if bt == BlockRegistry.BlockType.AIR or bt == BlockRegistry.BlockType.WATER:
			mine_front_index += 1
			continue
		# Bloc solide trouvé — le retourner s'il n'est pas déjà claimé
		if not claimed_positions.has(pos):
			return pos
		# Claimé par un autre mineur — chercher le prochain
		# (max 4 blocs d'avance pour que les mineurs creusent côte à côte)
		var lookahead = 0
		for i in range(mine_front_index + 1, mine_plan.size()):
			var p = mine_plan[i]
			var b = world_manager.get_block_at_position(Vector3(p.x, p.y, p.z))
			if b == BlockRegistry.BlockType.AIR or b == BlockRegistry.BlockType.WATER:
				continue
			if not claimed_positions.has(p):
				return p
			lookahead += 1
			if lookahead >= 4:
				break
		return Vector3i(-9999, -9999, -9999)

	# Plan épuisé → étendre la mine
	_expand_mine()
	# Réessayer une fois
	if mine_front_index < mine_plan.size():
		var pos = mine_plan[mine_front_index]
		var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER:
			if not claimed_positions.has(pos):
				return pos
	return Vector3i(-9999, -9999, -9999)

func _expand_mine():
	# Étendre la mine — nouvelles branches latérales depuis le centre de la galerie
	# IMPORTANT: les nouvelles branches partent TOUJOURS du centre de la galerie
	# (qui est connecté à l'escalier), donc elles sont toujours accessibles
	_mine_expansion_dir += 1
	var branch_len = 10
	var old_size = mine_plan.size()
	var y = _mine_gallery_y
	var gc = _mine_gallery_center

	if _mine_expansion_dir % 6 == 0 and _mine_gallery_y > 15:
		# Tous les 6 expansions : descendre de 5 blocs via un nouvel escalier
		var new_y = maxi(_mine_gallery_y - 5, 10)
		# Escalier depuis le centre actuel vers le nouveau niveau
		var pos = gc
		var dx = 1
		while pos.y > new_y:
			mine_plan.append(Vector3i(pos.x, pos.y, pos.z))
			mine_plan.append(Vector3i(pos.x, pos.y + 1, pos.z))
			pos = Vector3i(pos.x + dx, pos.y - 1, pos.z)
		_mine_gallery_y = new_y
		_mine_gallery_center = pos
		# 4 branches depuis le nouveau centre
		var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
		for dir in dirs:
			for i in range(1, branch_len + 1):
				mine_plan.append(Vector3i(pos.x + dir[0] * i, new_y, pos.z + dir[1] * i))
				mine_plan.append(Vector3i(pos.x + dir[0] * i, new_y + 1, pos.z + dir[1] * i))
	else:
		# Nouvelle branche latérale au même niveau — décalée à chaque expansion
		var offset = _mine_expansion_dir * 2
		var dir_idx = _mine_expansion_dir % 4
		var dx = [1, -1, 0, 0][dir_idx]
		var dz = [0, 0, 1, -1][dir_idx]
		# Perpendiculaire pour décaler le départ
		var perp_dx = -dz if dz != 0 else 0
		var perp_dz = dx if dx != 0 else 0
		# Branche CONNECTÉE : part du centre + offset perpendiculaire
		# D'abord un couloir du centre vers le point de départ de la branche
		var start_x = gc.x + perp_dx * offset
		var start_z = gc.z + perp_dz * offset
		# Couloir de connexion (du centre vers le start)
		var conn_len = abs(offset)
		if conn_len > 0:
			var conn_dx = 1 if start_x > gc.x else (-1 if start_x < gc.x else 0)
			var conn_dz = 1 if start_z > gc.z else (-1 if start_z < gc.z else 0)
			for i in range(1, conn_len + 1):
				mine_plan.append(Vector3i(gc.x + conn_dx * i, y, gc.z + conn_dz * i))
				mine_plan.append(Vector3i(gc.x + conn_dx * i, y + 1, gc.z + conn_dz * i))
		# Branche elle-même
		for i in range(branch_len):
			mine_plan.append(Vector3i(start_x + dx * i, y, start_z + dz * i))
			mine_plan.append(Vector3i(start_x + dx * i, y + 1, start_z + dz * i))

	print("VillageManager: mine étendue — +%d blocs (total %d, y=%d)" % [mine_plan.size() - old_size, mine_plan.size(), _mine_gallery_y])

func _is_block_accessible(pos: Vector3i) -> bool:
	# Un bloc est accessible s'il a au moins un voisin AIR (on peut l'atteindre)
	var neighbors = [
		Vector3i(pos.x + 1, pos.y, pos.z), Vector3i(pos.x - 1, pos.y, pos.z),
		Vector3i(pos.x, pos.y + 1, pos.z), Vector3i(pos.x, pos.y - 1, pos.z),
		Vector3i(pos.x, pos.y, pos.z + 1), Vector3i(pos.x, pos.y, pos.z - 1),
	]
	for n in neighbors:
		var bt = world_manager.get_block_at_position(Vector3(n.x, n.y, n.z))
		if bt == BlockRegistry.BlockType.AIR:
			return true
	return false

const MAX_MINERS = 2  # max 2 mineurs simultanés (tunnel 2 blocs de large)

func _add_mine_gallery_tasks(count: int):
	# Ajouter des tâches de minage en galerie (limité à MAX_MINERS)
	if not _mine_initialized:
		_init_mine()
	if not _mine_initialized:
		return

	var capped = mini(count, MAX_MINERS)
	var existing = 0
	for t in task_queue:
		if t["type"] == "mine_gallery":
			existing += 1
	# Aussi compter les villageois déjà en train de miner
	for v in villagers:
		if v.current_task.get("type", "") == "mine_gallery":
			existing += 1
	if existing >= capped:
		return

	for i in range(capped - existing):
		_add_task({
			"type": "mine_gallery",
			"priority": 22,
			"required_profession": VProfession.Profession.MINEUR,
		})

# ============================================================
# CRAFTING VILLAGEOIS
# ============================================================

func try_craft(recipe_name: String) -> bool:
	# Chercher la recette par nom
	var recipes = CraftRegistry.get_all_recipes()
	for recipe in recipes:
		if recipe["name"] == recipe_name:
			# Vérifier qu'on a les inputs dans le stockpile
			var can = true
			for input_item in recipe["inputs"]:
				var bt = input_item[0]
				var needed = input_item[1]
				# Pour les planches, accepter toutes les variantes
				if bt == 11:  # PLANKS
					if get_total_planks() < needed:
						can = false
						break
				elif bt == 5:  # WOOD
					if get_total_wood() < needed:
						can = false
						break
				else:
					if not has_resources(bt, needed):
						can = false
						break
			if not can:
				return false

			# Consommer les inputs
			for input_item in recipe["inputs"]:
				var bt = input_item[0]
				var needed = input_item[1]
				if bt == 11:
					consume_any_planks(needed)
				elif bt == 5:
					consume_any_wood(needed)
				else:
					consume_resources(bt, needed)

			# Produire l'output
			add_resource(recipe["output_type"], recipe["output_count"])
			print("VillageManager: crafté %s x%d" % [recipe_name, recipe["output_count"]])
			return true

	return false

# ============================================================
# PLACEMENT DE WORKSTATION
# ============================================================

func find_flat_spot_near_center(radius: float = 8.0) -> Vector3i:
	# Trouver un spot plat près du centre du village
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var r = int(radius)

	for attempt in range(20):
		var tx = cx + randi_range(-r, r)
		var tz = cz + randi_range(-r, r)

		# Trouver la surface
		var surface_y = _find_surface_y(tx, tz)
		if surface_y < 0:
			continue

		# Vérifier que c'est plat (bloc solide dessous, air dessus)
		var pos = Vector3i(tx, surface_y + 1, tz)
		var block_below = world_manager.get_block_at_position(Vector3(tx, surface_y, tz))
		var block_at = world_manager.get_block_at_position(Vector3(tx, surface_y + 1, tz))
		var block_above = world_manager.get_block_at_position(Vector3(tx, surface_y + 2, tz))

		if block_below != BlockRegistry.BlockType.AIR and block_below != BlockRegistry.BlockType.WATER \
			and block_at == BlockRegistry.BlockType.AIR and block_above == BlockRegistry.BlockType.AIR:
			# Pas déjà occupé
			if not claimed_positions.has(pos):
				return pos

	return Vector3i(-9999, -9999, -9999)

func _find_surface_y(wx: int, wz: int) -> int:
	# Trouver le Y de surface à une position monde
	for y in range(CHUNK_HEIGHT - 1, 0, -1):
		var bt = world_manager.get_block_at_position(Vector3(wx, y, wz))
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER:
			return y
	return -1

func place_workstation_at(block_type: int, pos: Vector3i):
	if world_manager:
		world_manager.place_block_at_position(Vector3(pos.x, pos.y, pos.z), block_type as BlockRegistry.BlockType)
		placed_workstations[block_type] = pos
		invalidate_scan_cache()
		print("VillageManager: workstation %d placée à %s" % [block_type, str(pos)])

		# Scanner le chunk pour les POI
		if world_manager.poi_manager:
			var chunk_pos = Vector3i(
				floori(float(pos.x) / CHUNK_SIZE),
				0,
				floori(float(pos.z) / CHUNK_SIZE)
			)
			if world_manager.chunks.has(chunk_pos):
				var chunk = world_manager.chunks[chunk_pos]
				world_manager.poi_manager.scan_chunk(chunk_pos, chunk.blocks, chunk.y_min, chunk.y_max)

# ============================================================
# CONSTRUCTION
# ============================================================

func _try_queue_build(blueprint_index: int):
	if blueprint_index >= BLUEPRINTS.size():
		return

	# Vérifier qu'on n'a pas déjà cette construction en queue
	for t in task_queue:
		if t["type"] == "build" and t.get("blueprint_index", -1) == blueprint_index:
			return

	var bp = BLUEPRINTS[blueprint_index]

	# Vérifier si on a assez de matériaux
	var can_build = true
	for bt in bp["materials"]:
		var needed = bp["materials"][bt]
		if bt == 11:  # PLANKS
			if get_total_planks() < needed:
				can_build = false
				break
		else:
			if not has_resources(bt, needed):
				can_build = false
				break

	if not can_build:
		# Ajouter des tâches de récolte pour les matériaux manquants
		for bt in bp["materials"]:
			var needed = bp["materials"][bt]
			var have = 0
			if bt == 11:
				have = get_total_planks()
			else:
				have = get_resource_count(bt)
			if have < needed:
				var deficit = needed - have
				if bt == 11:  # Planks -> récolter du bois
					_add_harvest_tasks(5, ceili(float(deficit) / 4.0))
				elif bt == 3 or bt == 25:  # Stone/Cobble -> mine en galerie (pas en surface)
					_add_mine_gallery_tasks(2)
				elif bt == 61:  # Glass -> miner du sable en surface
					_add_mine_tasks(4, mini(deficit, 4))  # SAND max 4 tasks
		return

	# Trouver un emplacement
	var origin = _find_build_site(bp)
	if origin == Vector3i(-9999, -9999, -9999):
		return

	# Consommer les matériaux
	for bt in bp["materials"]:
		var needed = bp["materials"][bt]
		if bt == 11:
			consume_any_planks(needed)
		else:
			consume_resources(bt, needed)

	_add_task({
		"type": "build",
		"blueprint_index": blueprint_index,
		"origin": origin,
		"block_list": bp["block_list"].duplicate(true),
		"block_index": 0,
		"priority": 15,
		"required_profession": VProfession.Profession.BATISSEUR,
	})
	print("VillageManager: construction de '%s' à %s" % [bp["name"], str(origin)])

func _find_build_site(blueprint: Dictionary) -> Vector3i:
	# Trouver un terrain plat assez grand pour le bâtiment
	var size = blueprint["size"]
	var cx = int(village_center.x)
	var cz = int(village_center.z)

	for attempt in range(30):
		var tx = cx + randi_range(-20, 20)
		var tz = cz + randi_range(-20, 20)

		# Vérifier que le terrain est ~plat sur toute la surface
		var first_y = _find_surface_y(tx, tz)
		if first_y < 0:
			continue

		var flat = true
		for bx in range(size.x):
			for bz in range(size.z):
				var sy = _find_surface_y(tx + bx, tz + bz)
				if abs(sy - first_y) > 1:
					flat = false
					break
			if not flat:
				break

		if not flat:
			continue

		# Pas de chevauchement avec les constructions existantes
		var overlap = false
		for built in built_structures:
			var bo = built["origin"]
			var bs = built["size"]
			if tx < bo.x + bs.x and tx + size.x > bo.x \
				and tz < bo.z + bs.z and tz + size.z > bo.z:
				overlap = true
				break

		if overlap:
			continue

		return Vector3i(tx, first_y + 1, tz)

	return Vector3i(-9999, -9999, -9999)

func register_built_structure(name: String, origin: Vector3i, size: Vector3i):
	built_structures.append({ "name": name, "origin": origin, "size": size })
	print("VillageManager: structure '%s' terminée à %s" % [name, str(origin)])

# ============================================================
# CHEMIN DU VILLAGE (croix de pavés autour du centre)
# ============================================================

func _try_queue_path():
	if _path_built:
		return
	# Vérifier qu'il n'y a pas déjà une tâche de chemin
	for t in task_queue:
		if t["type"] == "build_path":
			return
	for v in villagers:
		if v.current_task.get("type", "") == "build_path":
			return

	# Générer le plan du chemin : croix de 8 blocs dans chaque direction
	if _path_blocks.size() == 0:
		var cx = int(village_center.x)
		var cz = int(village_center.z)
		# Croix : 4 branches de 8 blocs depuis le centre
		var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
		for dir in dirs:
			for i in range(1, 9):
				var wx = cx + dir[0] * i
				var wz = cz + dir[1] * i
				var sy = _find_surface_y(wx, wz)
				if sy > 0:
					_path_blocks.append(Vector3i(wx, sy, wz))
		# Place centrale (2x2)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var sy = _find_surface_y(cx + dx, cz + dz)
				if sy > 0:
					_path_blocks.append(Vector3i(cx + dx, sy, cz + dz))
		_path_index = 0
		print("VillageManager: chemin planifié — %d blocs" % _path_blocks.size())

	# Vérifier qu'on a assez de cobblestone
	var remaining = _path_blocks.size() - _path_index
	if remaining <= 0:
		_path_built = true
		return
	var cobble_count = get_resource_count(25)
	if cobble_count < 3:
		return  # Pas assez, on attend

	_add_task({
		"type": "build_path",
		"priority": 12,
		"required_profession": VProfession.Profession.BATISSEUR,
	})

# ============================================================
# MINAGE VILLAGEOIS
# ============================================================

func get_mine_time(block_type: int) -> float:
	var hardness = BlockRegistry.get_block_hardness(block_type as BlockRegistry.BlockType)
	var mult = TOOL_TIER_MULTIPLIER.get(village_tool_tier, 1.0)
	return maxf(0.5, hardness * 2.0 / mult)

func break_block(pos: Vector3i):
	if world_manager:
		world_manager.break_block_at_position(Vector3(pos.x, pos.y, pos.z))
		# Ne PAS invalider le cache ici — le cache expire naturellement (SCAN_CACHE_DURATION)
		# L'invalidation à chaque bloc causait des rescans de 2M+ itérations en continu

func place_block(pos: Vector3i, block_type: int):
	if world_manager:
		world_manager.place_block_at_position(Vector3(pos.x, pos.y, pos.z), block_type as BlockRegistry.BlockType)

func get_next_path_block() -> Vector3i:
	# Retourne le prochain bloc du chemin à poser
	if _path_index >= _path_blocks.size():
		_path_built = true
		return INVALID_POS_CONST
	var pos = _path_blocks[_path_index]
	_path_index += 1
	return pos

func mark_path_complete():
	if _path_index >= _path_blocks.size():
		_path_built = true
		print("VillageManager: chemin terminé !")

const INVALID_POS_CONST = Vector3i(-9999, -9999, -9999)

# ============================================================
# ENREGISTREMENT DES VILLAGEOIS
# ============================================================

func register_villager(npc):
	if npc not in villagers:
		villagers.append(npc)

func unregister_villager(npc):
	villagers.erase(npc)

# ============================================================
# BLUEPRINTS
# ============================================================

func _init_blueprints():
	# Cabane simple 5x4x5 (murs planches, toit planches, porte)
	var cabin_blocks = []
	var BT_PLANKS = 11
	var BT_GLASS = 61

	# Sol (y=0)
	for x in range(5):
		for z in range(5):
			cabin_blocks.append([x, 0, z, BT_PLANKS])

	# Murs (y=1 à y=3)
	for y in range(1, 4):
		for x in range(5):
			for z in range(5):
				# Murs extérieurs seulement
				if x == 0 or x == 4 or z == 0 or z == 4:
					# Porte : ouverture 1 bloc large à y=1-2, z=2, x=0
					if x == 0 and z == 2 and y <= 2:
						continue
					# Fenêtres : verre à y=2 sur les côtés
					if y == 2 and ((x == 2 and (z == 0 or z == 4)) or (z == 2 and x == 4)):
						cabin_blocks.append([x, y, z, BT_GLASS])
					else:
						cabin_blocks.append([x, y, z, BT_PLANKS])

	# Toit (y=4)
	for x in range(5):
		for z in range(5):
			cabin_blocks.append([x, 4, z, BT_PLANKS])

	BLUEPRINTS.append({
		"name": "Cabane",
		"size": Vector3i(5, 5, 5),
		"materials": { BT_PLANKS: 68, BT_GLASS: 3 },
		"block_list": cabin_blocks,
	})

	# Atelier 7x5x5
	var workshop_blocks = []
	var BT_COBBLE = 25

	# Sol
	for x in range(7):
		for z in range(5):
			workshop_blocks.append([x, 0, z, BT_COBBLE])

	# Murs (y=1-3)
	for y in range(1, 4):
		for x in range(7):
			for z in range(5):
				if x == 0 or x == 6 or z == 0 or z == 4:
					if x == 3 and z == 0 and y <= 2:
						continue  # Porte
					if y == 2 and ((z == 0 and (x == 1 or x == 5)) or (z == 4 and (x == 1 or x == 5))):
						workshop_blocks.append([x, y, z, BT_GLASS])
					else:
						workshop_blocks.append([x, y, z, BT_PLANKS])

	# Toit
	for x in range(7):
		for z in range(5):
			workshop_blocks.append([x, 4, z, BT_PLANKS])

	BLUEPRINTS.append({
		"name": "Atelier",
		"size": Vector3i(7, 5, 5),
		"materials": { BT_PLANKS: 62, BT_COBBLE: 35, BT_GLASS: 4 },
		"block_list": workshop_blocks,
	})

	# Tour de guet 3x8x3
	var tower_blocks = []

	# Sol
	for x in range(3):
		for z in range(3):
			tower_blocks.append([x, 0, z, BT_COBBLE])

	# Piliers (coins, y=1-6)
	for y in range(1, 7):
		tower_blocks.append([0, y, 0, BT_COBBLE])
		tower_blocks.append([2, y, 0, BT_COBBLE])
		tower_blocks.append([0, y, 2, BT_COBBLE])
		tower_blocks.append([2, y, 2, BT_COBBLE])

	# Plateforme (y=7)
	for x in range(3):
		for z in range(3):
			tower_blocks.append([x, 7, z, BT_PLANKS])

	BLUEPRINTS.append({
		"name": "Tour de guet",
		"size": Vector3i(3, 8, 3),
		"materials": { BT_COBBLE: 33, BT_PLANKS: 9 },
		"block_list": tower_blocks,
	})

# ============================================================
# DEBUG
# ============================================================

func get_status_text() -> String:
	var phase_names = ["Bootstrap", "Âge du Bois", "Âge de la Pierre", "Âge du Fer"]
	var status = "Village: %s (Phase %d)\n" % [phase_names[village_phase], village_phase]
	status += "Outils: tier %d (x%.1f)\n" % [village_tool_tier, TOOL_TIER_MULTIPLIER.get(village_tool_tier, 1.0)]
	status += "Tâches: %d en attente\n" % task_queue.size()
	status += "Villageois: %d\n" % villagers.size()
	status += "Stockpile:\n"
	for bt in stockpile:
		if stockpile[bt] > 0:
			status += "  %s: %d\n" % [BlockRegistry.get_block_name(bt as BlockRegistry.BlockType), stockpile[bt]]
	return status
