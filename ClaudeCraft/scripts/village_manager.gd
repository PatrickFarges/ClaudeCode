extends Node

# VillageManager — cerveau centralisé du village autonome
# Gère le stockpile partagé, la file de tâches, la progression technologique
# et les blueprints de bâtiments. Les villageois exécutent les tâches assignées.

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
const SCAN_CACHE_DURATION = 5.0

# === MINE / GALERIE ===
var mine_plan: Array = []          # Array de Vector3i — blocs à creuser dans l'ordre
var mine_plan_index: int = 0       # prochain bloc à assigner
var mine_entrance: Vector3i = Vector3i(-9999, -9999, -9999)
var _mine_initialized: bool = false

# === TIMER ===
var _eval_timer: float = 0.0
const EVAL_INTERVAL = 3.0

# === REFS ===
var world_manager = null

# === BLUEPRINTS ===
# Bâtiments que le village peut construire
# Chaque blueprint: { name, size: Vector3i, materials: { BlockType->count }, block_list: [[x,y,z,BlockType], ...] }
var BLUEPRINTS: Array = []

# === BÂTIMENTS CONSTRUITS ===
var built_structures: Array = []  # Array de { "name": String, "origin": Vector3i }

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

	# Besoin de 10 bois pour démarrer
	if total_wood < 10 and total_planks < 4:
		_add_harvest_tasks(5, 6)  # WOOD + LEAVES — on vise les troncs (WOOD=5)
		return

	# Crafter des planches si on a du bois
	if total_wood >= 1 and total_planks < 8:
		_add_task({
			"type": "craft",
			"recipe_name": "Planches",
			"priority": 10,
		})

	# Crafter la crafting table si on a 4 planches
	if total_planks >= 4 and not placed_workstations.has(12):  # CRAFTING_TABLE
		if not _has_task_of_type("craft", "Table de Craft"):
			_add_task({
				"type": "craft",
				"recipe_name": "Table de Craft",
				"priority": 5,
			})

	# Placer la crafting table si on en a une
	if get_resource_count(12) >= 1 and not placed_workstations.has(12):
		_add_task({
			"type": "place_workstation",
			"target_block": 12,  # CRAFTING_TABLE
			"priority": 3,
		})

	# Si crafting table placée -> phase 1
	if placed_workstations.has(12):
		village_phase = 1
		village_tool_tier = 1
		print("VillageManager: === PHASE 1 — ÂGE DU BOIS ===  (tier %s)" % village_tool_tier)

func _evaluate_phase_1():
	# Phase 1: Récolter plus de bois + pierre, crafter furnace, construire
	var total_wood = get_total_wood()
	var total_stone = get_resource_count(3)  # STONE
	var total_cobble = get_resource_count(25)  # COBBLESTONE

	# Toujours maintenir du bois en stock
	if total_wood < 20:
		_add_harvest_tasks(5, 4)  # plus de bois

	# Commencer à miner (galerie souterraine)
	if total_stone < 20:
		_add_mine_gallery_tasks(4)

	# Crafter le fourneau (8 stone, recette wood_table -> en réalité on simplifie)
	if total_stone >= 8 and not placed_workstations.has(21):  # FURNACE
		if not _has_task_of_type("craft", "Fourneau"):
			_add_task({
				"type": "craft",
				"recipe_name": "Fourneau",
				"priority": 8,
			})

	# Placer le fourneau
	if get_resource_count(21) >= 1 and not placed_workstations.has(21):
		_add_task({
			"type": "place_workstation",
			"target_block": 21,  # FURNACE
			"priority": 5,
		})

	# Construire la première cabane si on a les matériaux
	if placed_workstations.has(21) and built_structures.size() == 0:
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
		_add_mine_gallery_tasks(4)

	# Fondre le fer (recette furnace: 1 iron_ore + 1 coal_ore -> 1 iron_ingot)
	if total_iron_ore >= 1 and total_coal >= 1 and total_iron < 4:
		if not _has_task_of_type("craft", "Lingot de fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Lingot de fer",
				"priority": 10,
			})

	# Crafter stone_table (4 stone + 4 planks, recette wood_table)
	if total_iron >= 4 and total_stone >= 4 and not placed_workstations.has(22):
		if not _has_task_of_type("craft", "Table en pierre"):
			_add_task({
				"type": "craft",
				"recipe_name": "Table en pierre",
				"priority": 8,
			})

	# Placer stone_table
	if get_resource_count(22) >= 1 and not placed_workstations.has(22):
		_add_task({
			"type": "place_workstation",
			"target_block": 22,  # STONE_TABLE
			"priority": 5,
		})

	# Construire plus de bâtiments
	if built_structures.size() < 2:
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
		_add_mine_gallery_tasks(4)

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
		})

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
	# Trouver un spot d'entrée près du village center
	if _mine_initialized:
		return
	if not world_manager:
		return

	var cx = int(village_center.x) + randi_range(8, 15)
	var cz = int(village_center.z) + randi_range(8, 15)
	var surface_y = _find_surface_y(cx, cz)
	if surface_y < 0:
		return

	mine_entrance = Vector3i(cx, surface_y, cz)
	_mine_initialized = true

	# Générer le plan de mine
	# Phase 1: Escalier descendant (2 blocs de haut, descend de 1 par pas)
	# Direction: +X (arbitraire, on creuse vers l'est)
	var stair_dir = Vector3i(1, 0, 0)
	var pos = mine_entrance
	mine_plan.clear()
	mine_plan_index = 0

	# Creuser l'escalier de la surface jusqu'à y=30 (zone des minerais)
	var target_y = 30
	var step = 0
	while pos.y > target_y:
		# Bloc au niveau des pieds
		mine_plan.append(Vector3i(pos.x, pos.y, pos.z))
		# Bloc au niveau de la tête
		mine_plan.append(Vector3i(pos.x, pos.y + 1, pos.z))
		# Descendre d'un cran
		pos = Vector3i(pos.x + stair_dir.x, pos.y - 1, pos.z + stair_dir.z)
		step += 1
		# Tous les 3 pas, ajouter un palier (2 blocs plats pour que les PNJ ne tombent pas)
		if step % 3 == 0:
			mine_plan.append(Vector3i(pos.x, pos.y + 1, pos.z))
			mine_plan.append(Vector3i(pos.x, pos.y + 2, pos.z))

	# Phase 2: Galeries horizontales en branches à y=30, y=20, y=10
	for gallery_y in [30, 20, 10]:
		# Le couloir principal continue à cette profondeur
		var gallery_start = Vector3i(pos.x, gallery_y, pos.z)
		if gallery_y != 30:
			# Escalier vers le prochain niveau
			var descent_pos = mine_plan[mine_plan.size() - 1] if mine_plan.size() > 0 else pos
			# On continue à descendre depuis la fin du plan actuel
			var cur = Vector3i(descent_pos.x + 1, descent_pos.y, descent_pos.z)
			while cur.y > gallery_y:
				mine_plan.append(Vector3i(cur.x, cur.y, cur.z))
				mine_plan.append(Vector3i(cur.x, cur.y + 1, cur.z))
				cur = Vector3i(cur.x + 1, cur.y - 1, cur.z)
			gallery_start = cur

		# Galerie principale: 20 blocs tout droit
		for i in range(20):
			var gx = gallery_start.x + i
			mine_plan.append(Vector3i(gx, gallery_y, gallery_start.z))
			mine_plan.append(Vector3i(gx, gallery_y + 1, gallery_start.z))

		# Branches perpendiculaires tous les 4 blocs
		for branch_i in range(5):
			var branch_x = gallery_start.x + branch_i * 4
			# Branche sud (10 blocs)
			for bz in range(1, 11):
				mine_plan.append(Vector3i(branch_x, gallery_y, gallery_start.z + bz))
				mine_plan.append(Vector3i(branch_x, gallery_y + 1, gallery_start.z + bz))
			# Branche nord (10 blocs)
			for bz in range(1, 11):
				mine_plan.append(Vector3i(branch_x, gallery_y, gallery_start.z - bz))
				mine_plan.append(Vector3i(branch_x, gallery_y + 1, gallery_start.z - bz))

	print("VillageManager: mine planifiée — %d blocs à creuser depuis %s" % [mine_plan.size(), str(mine_entrance)])

func get_next_mine_block() -> Vector3i:
	# Retourne le prochain bloc ACCESSIBLE à creuser (doit avoir de l'air adjacent)
	# Scan depuis le début pour trouver les blocs au front de la mine
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	for i in range(mine_plan.size()):
		var pos = mine_plan[i]
		if claimed_positions.has(pos):
			continue
		var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
		if bt == BlockRegistry.BlockType.AIR or bt == BlockRegistry.BlockType.WATER:
			continue
		# Vérifier que le bloc est accessible (au moins 1 face adjacente = AIR)
		if _is_block_accessible(pos):
			return pos
	return Vector3i(-9999, -9999, -9999)

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

func _add_mine_gallery_tasks(count: int):
	# Ajouter des tâches de minage en galerie
	if not _mine_initialized:
		_init_mine()
	if not _mine_initialized:
		return

	var existing = 0
	for t in task_queue:
		if t["type"] == "mine_gallery":
			existing += 1
	if existing >= count:
		return

	for i in range(count - existing):
		_add_task({
			"type": "mine_gallery",
			"priority": 22,
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
				elif bt == 3 or bt == 25:  # Stone/Cobble
					_add_mine_tasks(bt, deficit)
				elif bt == 61:  # Glass -> miner du sable
					_add_mine_tasks(4, deficit)  # SAND
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
# MINAGE VILLAGEOIS
# ============================================================

func get_mine_time(block_type: int) -> float:
	var hardness = BlockRegistry.get_block_hardness(block_type as BlockRegistry.BlockType)
	var mult = TOOL_TIER_MULTIPLIER.get(village_tool_tier, 1.0)
	return maxf(0.5, hardness * 2.0 / mult)

func break_block(pos: Vector3i):
	if world_manager:
		world_manager.break_block_at_position(Vector3(pos.x, pos.y, pos.z))
		invalidate_scan_cache()

func place_block(pos: Vector3i, block_type: int):
	if world_manager:
		world_manager.place_block_at_position(Vector3(pos.x, pos.y, pos.z), block_type as BlockRegistry.BlockType)

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
