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

# === STOCKAGE BÂTIMENTS (coffres physiques) ===
var building_storage: Dictionary = {}  # { name: { "items": {bt:count}, "chests": [Vector3i] } }
var _storage_map: Dictionary = {}      # { building_name: [BlockType, ...] } — quels items chaque bâtiment stocke
var _item_to_building: Dictionary = {} # { BlockType: building_name } — reverse lookup
const CHEST_CAPACITY = 500             # items max par coffre

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

const TOOL_TIER_NAMES = { 0: "", 1: "Bois", 2: "Pierre", 3: "Fer" }

func get_tool_tier_label(base: String) -> String:
	var mat = TOOL_TIER_NAMES.get(village_tool_tier, "")
	return base if mat == "" else "%s %s" % [base, mat]

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
const SCAN_CACHE_DURATION = 15.0  # durée cache scan — 15s pour éviter les rescans massifs

# === MINE / GALERIE ===
var mine_plan: Array = []          # Array de Vector3i — blocs à creuser dans l'ordre (du haut vers le bas)
var mine_front_index: int = 0      # front de la mine — plus loin qu'un mineur a creusé
var mine_entrance: Vector3i = Vector3i(-9999, -9999, -9999)
var _mine_initialized: bool = false
var _mine_gallery_center: Vector3i = Vector3i.ZERO  # centre de la galerie actuelle
var _mine_gallery_y: int = 45      # profondeur galerie actuelle
var _mine_expansion_dir: int = 0   # direction de la prochaine expansion (0-3)
const MINE_MAX_EXPANSIONS = 200    # max d'extensions par cycle (reset auto quand épuisé)
const MINE_PLAN_MAX_SIZE = 5000    # plafond du mine plan — empêche la croissance infinie
const MINE_STOCK_PAUSE_STONE = 2000 # pause minage si pavé > seuil (200 trop bas — mine 417 blocs → 1346 pavés)
const MINE_STOCK_PAUSE_COAL = 200  # pause minage si charbon > seuil
const MINE_STOCK_PAUSE_IRON = 80   # pause minage si fer > seuil

# === AGRICULTURE ===
var farm_plots: Array = []  # Array de { "pos": Vector3i, "stage": int, "timer": float }
var _farm_initialized: bool = false
var _farm_center: Vector3i = Vector3i.ZERO
const WHEAT_GROWTH_TIME = 30.0  # secondes par stage
const WHEAT_MAX_STAGE = 3  # 0→3 = 4 stages
const FARM_SIZE = 5  # 5x5

# === CROISSANCE DU VILLAGE ===
var _growth_timer: float = 0.0
const GROWTH_CHECK_INTERVAL = 30.0
const BREAD_PER_VILLAGER = 5

# === TIMER ===
var _eval_timer: float = 0.0
const EVAL_INTERVAL = 8.0  # évaluation toutes les 8s (réduit la charge de scan)

# === REFS ===
var world_manager = null

# === BLUEPRINTS ===
# Bâtiments que le village peut construire
# Chaque blueprint: { name, size: Vector3i, materials: { BlockType->count }, block_list: [[x,y,z,BlockType], ...] }
var BLUEPRINTS: Array = []

# === BÂTIMENTS CONSTRUITS ===
var built_structures: Array = []  # Array de { "name": String, "origin": Vector3i }

# === APLANISSEMENT DU TERRAIN ===
var village_ref_y: int = -1          # altitude de référence (médiane)
var flatten_plan: Array = []         # [{pos: Vector3i, action: "break"/"place"}]
var flatten_index: int = 0           # progression
var _flatten_complete: bool = false   # flag
const VILLAGE_RADIUS = 45            # zone 91×91 (45+1+45) — rayon pour placer les bâtiments
const FLATTEN_RADIUS = 20            # zone 41×41 — rayon d'aplanissement (place + premiers bâtiments)

# === PLACE DU VILLAGE ===
var _path_built: bool = false  # true quand la place + chemins sont posés
var _path_blocks: Array = []   # blocs à poser [[Vector3i, block_type], ...]
var _path_index: int = 0       # progression dans la pose
var plaza_center: Vector3 = Vector3.ZERO  # centre de la place (pour les PNJ)
const PLAZA_RADIUS = 9                    # rayon de la place pavée

# === NETTOYAGE FEUILLES ===
var _leaf_cleanup_timer: float = 0.0
const LEAF_CLEANUP_INTERVAL = 30.0  # toutes les 30 secondes (temps réel)

func _ready():
	add_to_group("village_manager")
	_init_blueprints()
	_init_storage_map()
	print("VillageManager: initialisé")

func _init_storage_map():
	_storage_map = {
		"Moulin": [BlockRegistry.BlockType.BREAD, BlockRegistry.BlockType.WHEAT_ITEM],
		"Forge": [BlockRegistry.BlockType.IRON_INGOT, BlockRegistry.BlockType.GOLD_INGOT, BlockRegistry.BlockType.COPPER_INGOT],
		"Caserne": [BlockRegistry.BlockType.IRON_SWORD, BlockRegistry.BlockType.GOLD_SWORD, BlockRegistry.BlockType.SHIELD],
	}
	_item_to_building = {}
	for bn in _storage_map:
		for bt in _storage_map[bn]:
			_item_to_building[bt] = bn

func _get_game_speed() -> float:
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("get_speed_multiplier"):
		return dnc.get_speed_multiplier()
	return 1.0

func _process(delta):
	if not world_manager:
		world_manager = get_tree().get_first_node_in_group("world_manager")
		return

	var game_speed = _get_game_speed()

	# Attendre que tous les chunks de la zone village soient chargés
	if _waiting_for_chunks:
		if _are_village_chunks_loaded():
			_waiting_for_chunks = false
			_generate_flatten_plan()

	# Évaluation des besoins — temps RÉEL (pas accéléré, sinon scans massifs)
	_eval_timer += delta
	if _eval_timer >= EVAL_INTERVAL:
		_eval_timer = 0.0
		_evaluate_needs()

	# Croissance du blé — accélérée par la vitesse du jeu
	_update_wheat_growth(delta * game_speed)

	# Croissance du village — accélérée par la vitesse du jeu
	_growth_timer += delta * game_speed
	if _growth_timer >= GROWTH_CHECK_INTERVAL:
		_growth_timer = 0.0
		_try_grow_village()

	# Nettoyage périodique des feuilles orphelines dans la zone village
	_leaf_cleanup_timer += delta
	if _leaf_cleanup_timer >= LEAF_CLEANUP_INTERVAL:
		_leaf_cleanup_timer = 0.0
		_cleanup_orphan_leaves()

# ============================================================
# CENTRE DU VILLAGE
# ============================================================

func set_village_center(pos: Vector3):
	village_center = pos
	_center_set = true
	print("VillageManager: centre du village à %s" % str(pos))
	# On attend que tous les chunks de la zone village soient chargés
	_waiting_for_chunks = true

var _waiting_for_chunks: bool = false
var _flatten_pass: int = 0  # nombre de passes de flatten effectuées

func _are_village_chunks_loaded() -> bool:
	if not world_manager:
		return false
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	# Vérifier que tous les chunks couvrant la zone de flatten sont chargés
	var min_cx = floori(float(cx - FLATTEN_RADIUS) / CHUNK_SIZE)
	var max_cx = floori(float(cx + FLATTEN_RADIUS) / CHUNK_SIZE)
	var min_cz = floori(float(cz - FLATTEN_RADIUS) / CHUNK_SIZE)
	var max_cz = floori(float(cz + FLATTEN_RADIUS) / CHUNK_SIZE)
	for chunk_x in range(min_cx, max_cx + 1):
		for chunk_z in range(min_cz, max_cz + 1):
			var chunk_pos = Vector3i(chunk_x, 0, chunk_z)
			if not world_manager.chunks.has(chunk_pos):
				return false
	return true

func _find_ground_y(wx: int, wz: int) -> int:
	# Trouver le Y du SOL (bloc solide non-végétal) — ignore feuilles, troncs, herbe
	# Utilisé pour le flatten au lieu de _find_surface_y qui renvoie le sommet des arbres
	var leaf_set = { 6: true, 44: true, 45: true, 46: true, 47: true, 48: true, 49: true }
	var trunk_set = { 5: true, 32: true, 33: true, 34: true, 35: true, 36: true, 42: true }
	var flora_set = { 77: true, 78: true, 79: true, 80: true, 81: true, 82: true }  # Cross mesh vegetation
	var chunk_pos = Vector3i(floori(float(wx) / CHUNK_SIZE), 0, floori(float(wz) / CHUNK_SIZE))
	var start_y = 120
	if world_manager.chunks.has(chunk_pos):
		start_y = mini(world_manager.chunks[chunk_pos].y_max + 1, CHUNK_HEIGHT - 1)
	for y in range(start_y, 0, -1):
		var bt = world_manager.get_block_at_position(Vector3(wx, y, wz))
		if bt == BlockRegistry.BlockType.AIR or bt == BlockRegistry.BlockType.WATER:
			continue
		if leaf_set.has(bt) or trunk_set.has(bt) or flora_set.has(bt):
			continue
		return y
	return -1

func _generate_flatten_plan():
	# Génère une liste de colonnes (x,z) à visiter, triées par distance au centre.
	# Le bâtisseur marchera en berserker et nettoiera chaque colonne au-dessus de ref_y.
	# PAS de placement de pierre — juste du cassage.
	if not world_manager:
		return
	var cx = int(village_center.x)
	var cz = int(village_center.z)

	# Calculer la médiane seulement à la première passe
	if village_ref_y < 0:
		var surface_ys: Array = []
		for dx in range(-FLATTEN_RADIUS, FLATTEN_RADIUS + 1):
			for dz in range(-FLATTEN_RADIUS, FLATTEN_RADIUS + 1):
				var sy = _find_ground_y(cx + dx, cz + dz)
				if sy > 0:
					surface_ys.append(sy)
		if surface_ys.size() == 0:
			print("VillageManager: flatten — aucune surface trouvée")
			_flatten_complete = true
			return
		surface_ys.sort()
		village_ref_y = surface_ys[surface_ys.size() / 2]

	# Positions des workstations à protéger
	var ws_set: Dictionary = {}
	for ws_type in placed_workstations:
		var wp = placed_workstations[ws_type]
		ws_set[Vector2i(wp.x, wp.z)] = true

	# Générer les colonnes à nettoyer : chaque entrée = { pos: Vector3i(x, ref_y, z) }
	# Le bâtisseur nettoiera la colonne entière au-dessus de ref_y quand il arrive
	var columns: Array = []
	for dx in range(-FLATTEN_RADIUS, FLATTEN_RADIUS + 1):
		for dz in range(-FLATTEN_RADIUS, FLATTEN_RADIUS + 1):
			var wx = cx + dx
			var wz = cz + dz
			# Protéger les workstations
			if ws_set.has(Vector2i(wx, wz)):
				continue
			var surface_y = _find_surface_y(wx, wz)
			if surface_y > village_ref_y:
				var dist = abs(dx) + abs(dz)
				columns.append({"pos": Vector3i(wx, village_ref_y, wz), "dist": dist})

	# Trier par distance au centre (spirale sortante)
	columns.sort_custom(func(a, b): return a["dist"] < b["dist"])

	flatten_plan = []
	for col in columns:
		flatten_plan.append(col)
	flatten_index = 0

	if flatten_plan.size() == 0:
		_flatten_complete = true
		print("VillageManager: terrain déjà plat (ref_y=%d)" % village_ref_y)
	else:
		print("VillageManager: flatten plan — %d colonnes à nettoyer, ref_y=%d" % [flatten_plan.size(), village_ref_y])

func get_next_flatten_column() -> Dictionary:
	# Retourne la prochaine colonne à nettoyer { pos: Vector3i }
	if flatten_index >= flatten_plan.size():
		# Re-scanner pour vérifier s'il reste des colonnes
		if _flatten_pass < 3:
			_flatten_pass += 1
			_generate_flatten_plan()
			if flatten_plan.size() > 0:
				print("VillageManager: flatten passe %d — %d colonnes supplémentaires" % [_flatten_pass, flatten_plan.size()])
				var entry = flatten_plan[flatten_index]
				flatten_index += 1
				return entry
		_flatten_complete = true
		print("VillageManager: aplanissement terminé après %d passe(s)" % _flatten_pass)
		return {}
	var entry = flatten_plan[flatten_index]
	flatten_index += 1
	return entry

func clear_column_above_ref_batched(wx: int, wz: int, affected_chunks: Dictionary):
	# Détruit tous les blocs au-dessus de ref_y dans la colonne (x,z)
	# BATCHED : modifie les blocs directement sans rebuild, collecte les chunks affectés
	var top_y = _find_surface_y(wx, wz)
	if top_y <= village_ref_y:
		return
	var cx = floori(float(wx) / CHUNK_SIZE)
	var cz = floori(float(wz) / CHUNK_SIZE)
	var chunk_key = Vector3i(cx, 0, cz)
	if not world_manager.chunks.has(chunk_key):
		return
	var chunk = world_manager.chunks[chunk_key]
	var lx = wx - cx * CHUNK_SIZE
	var lz = wz - cz * CHUNK_SIZE
	if lx < 0:
		lx += CHUNK_SIZE
	if lz < 0:
		lz += CHUNK_SIZE
	for y in range(top_y, village_ref_y, -1):
		var bt = chunk.blocks[lx * 4096 + lz * 256 + y]
		if bt != BlockRegistry.BlockType.AIR:
			if BlockRegistry.is_workstation(bt):
				continue
			chunk.blocks[lx * 4096 + lz * 256 + y] = 0  # AIR
			chunk.is_modified = true
			affected_chunks[chunk_key] = chunk
			# Pas de drop pendant le flatten — ça saturait le stock (4000+ pavés)
			# et bloquait les mineurs via is_mine_stock_full()

func flush_affected_chunks(affected_chunks: Dictionary):
	# Rebuild mesh UNE SEULE FOIS par chunk affecté
	for chunk in affected_chunks.values():
		chunk._rebuild_mesh()

func _cleanup_orphan_leaves():
	# Scan périodique : détruire les feuilles orphelines dans la zone village
	if not world_manager or not _center_set:
		return
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var leaf_set = { 6: true, 44: true, 45: true, 46: true, 47: true, 48: true, 49: true }
	var wood_set = { 5: true, 32: true, 33: true, 34: true, 35: true, 36: true, 42: true }
	var ref_y = village_ref_y if village_ref_y > 0 else int(village_center.y)

	# Échantillonnage : scanner un quadrant aléatoire pour ne pas tout scanner à chaque tick
	var qx = randi_range(0, 1)  # 0 ou 1
	var qz = randi_range(0, 1)
	var x_start = cx - VILLAGE_RADIUS if qx == 0 else cx
	var x_end = cx if qx == 0 else cx + VILLAGE_RADIUS
	var z_start = cz - VILLAGE_RADIUS if qz == 0 else cz
	var z_end = cz if qz == 0 else cz + VILLAGE_RADIUS

	var leaf_positions: Array = []
	var trunk_positions: Array = []

	# Scanner le quadrant pour feuilles et troncs (au-dessus de ref_y seulement)
	for x in range(x_start, x_end + 1, 2):  # échantillonnage 1/2
		for z in range(z_start, z_end + 1, 2):
			for y in range(ref_y, ref_y + 30):
				var bt = world_manager.get_block_at_position(Vector3(x, y, z))
				if bt == 0:
					continue
				if leaf_set.has(bt):
					leaf_positions.append(Vector3i(x, y, z))
				elif wood_set.has(bt):
					trunk_positions.append(Vector3i(x, y, z))

	if leaf_positions.is_empty():
		return

	# Identifier les feuilles orphelines (aucun tronc à distance Manhattan ≤ 4)
	var orphan_leaves: Array = []
	for leaf_pos in leaf_positions:
		var has_trunk = false
		for trunk_pos in trunk_positions:
			var dist = abs(leaf_pos.x - trunk_pos.x) + abs(leaf_pos.y - trunk_pos.y) + abs(leaf_pos.z - trunk_pos.z)
			if dist <= 4:
				has_trunk = true
				break
		if not has_trunk:
			orphan_leaves.append(leaf_pos)

	if orphan_leaves.is_empty():
		return

	# Détruire en batch
	var affected_chunks_cleanup: Dictionary = {}
	for leaf_pos in orphan_leaves:
		var chunk_cx = floori(float(leaf_pos.x) / CHUNK_SIZE)
		var chunk_cz = floori(float(leaf_pos.z) / CHUNK_SIZE)
		var chunk_key = Vector3i(chunk_cx, 0, chunk_cz)
		if world_manager.chunks.has(chunk_key):
			var chunk = world_manager.chunks[chunk_key]
			var lx = leaf_pos.x - chunk_cx * CHUNK_SIZE
			var lz = leaf_pos.z - chunk_cz * CHUNK_SIZE
			if lx < 0:
				lx += CHUNK_SIZE
			if lz < 0:
				lz += CHUNK_SIZE
			chunk.blocks[lx * 4096 + lz * 256 + leaf_pos.y] = 0
			chunk.is_modified = true
			affected_chunks_cleanup[chunk_key] = chunk

	flush_affected_chunks(affected_chunks_cleanup)

	if orphan_leaves.size() > 0:
		print("VillageManager: nettoyage feuilles orphelines — %d feuilles détruites" % orphan_leaves.size())

func _flatten_drop(bt: int) -> int:
	# Retourne le type de ressource obtenu en cassant un bloc pendant le flatten
	match bt:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.COBBLESTONE, \
		BlockRegistry.BlockType.ANDESITE, BlockRegistry.BlockType.GRANITE, \
		BlockRegistry.BlockType.DIORITE, BlockRegistry.BlockType.DEEPSLATE, \
		BlockRegistry.BlockType.SMOOTH_STONE:
			return BlockRegistry.BlockType.COBBLESTONE
		BlockRegistry.BlockType.COAL_ORE:
			return BlockRegistry.BlockType.COAL_ORE
		BlockRegistry.BlockType.IRON_ORE:
			return BlockRegistry.BlockType.IRON_ORE
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.SPRUCE_LOG, \
		BlockRegistry.BlockType.BIRCH_LOG, BlockRegistry.BlockType.JUNGLE_LOG, \
		BlockRegistry.BlockType.ACACIA_LOG, BlockRegistry.BlockType.DARK_OAK_LOG, \
		BlockRegistry.BlockType.CHERRY_LOG:
			return bt  # garder le type de bois
		BlockRegistry.BlockType.SAND:
			return BlockRegistry.BlockType.SAND
		_:
			return -1  # pas de drop (terre, herbe, feuilles...)

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
	# Compte tous les types de bûches (stockpile + coffres)
	var total = 0
	for bt in [5, 32, 33, 34, 35, 36, 42]:  # WOOD, SPRUCE_LOG, BIRCH_LOG, JUNGLE_LOG, ACACIA_LOG, DARK_OAK_LOG, CHERRY_LOG
		total += get_total_resource(bt)
	return total

func get_total_planks() -> int:
	var total = 0
	for bt in [11, 37, 38, 39, 40, 41, 43]:  # PLANKS + variantes
		total += get_total_resource(bt)
	return total

func get_total_stone() -> int:
	return get_total_resource(3) + get_total_resource(25)  # STONE + COBBLESTONE

func _consume_types_anywhere(types: Array, count: int) -> bool:
	var remaining = count
	# D'abord le stockpile virtuel
	for bt in types:
		var have = stockpile.get(bt, 0)
		if have > 0:
			var take = mini(have, remaining)
			stockpile[bt] = have - take
			if stockpile[bt] == 0:
				stockpile.erase(bt)
			remaining -= take
			if remaining <= 0:
				return true
	# Ensuite les coffres de bâtiments
	for bt in types:
		for bn in building_storage:
			var items = building_storage[bn]["items"]
			var have = items.get(bt, 0)
			if have > 0:
				var take = mini(have, remaining)
				items[bt] = have - take
				if items[bt] == 0:
					items.erase(bt)
				remaining -= take
				if remaining <= 0:
					return true
	return remaining <= 0

func consume_any_stone(count: int) -> bool:
	return _consume_types_anywhere([25, 3], count)  # COBBLESTONE d'abord, puis STONE

func consume_any_wood(count: int) -> bool:
	return _consume_types_anywhere([5, 32, 33, 34, 35, 36, 42], count)

func consume_any_planks(count: int) -> bool:
	return _consume_types_anywhere([11, 37, 38, 39, 40, 41, 43], count)

# ============================================================
# STOCKAGE BÂTIMENTS (coffres physiques)
# ============================================================

func get_total_resource(block_type: int) -> int:
	"""Compte un item dans le stockpile virtuel + tous les coffres de bâtiments."""
	var total = stockpile.get(block_type, 0)
	for bn in building_storage:
		total += building_storage[bn]["items"].get(block_type, 0)
	return total

func consume_resources_anywhere(block_type: int, count: int) -> bool:
	"""Consomme un item depuis le stockpile virtuel, puis depuis les coffres si besoin."""
	if get_total_resource(block_type) < count:
		return false
	var remaining = count
	# D'abord le stockpile virtuel
	var in_stock = stockpile.get(block_type, 0)
	if in_stock > 0:
		var take = mini(in_stock, remaining)
		stockpile[block_type] = in_stock - take
		if stockpile[block_type] == 0:
			stockpile.erase(block_type)
		remaining -= take
	# Puis les coffres de bâtiments
	if remaining > 0:
		for bn in building_storage:
			var items = building_storage[bn]["items"]
			var have = items.get(block_type, 0)
			if have > 0:
				var take = mini(have, remaining)
				items[block_type] = have - take
				if items[block_type] == 0:
					items.erase(block_type)
				remaining -= take
				if remaining <= 0:
					break
	return remaining <= 0

func _route_craft_output(block_type: int, count: int):
	"""Route l'output d'un craft vers le coffre du bâtiment approprié, sinon stockpile virtuel."""
	var building_name = _item_to_building.get(block_type, "")
	if building_name != "" and building_storage.has(building_name):
		var storage = building_storage[building_name]
		var total_items = _get_building_total_items(building_name)
		var capacity = storage["chests"].size() * CHEST_CAPACITY
		var space = capacity - total_items
		if space >= count:
			storage["items"][block_type] = storage["items"].get(block_type, 0) + count
			return
		elif space > 0:
			storage["items"][block_type] = storage["items"].get(block_type, 0) + space
			add_resource(block_type, count - space)
			return
	add_resource(block_type, count)

func _get_building_total_items(building_name: String) -> int:
	if not building_storage.has(building_name):
		return 0
	var total = 0
	for bt in building_storage[building_name]["items"]:
		total += building_storage[building_name]["items"][bt]
	return total

func _is_building_full(building_name: String) -> bool:
	"""Vérifie si le bâtiment a ses coffres pleins. Cap 200 en stockpile si bâtiment pas construit."""
	if not building_storage.has(building_name):
		# Pas de bâtiment → cap 200 items dans le stockpile virtuel
		if _storage_map.has(building_name):
			var total = 0
			for bt in _storage_map[building_name]:
				total += stockpile.get(bt, 0)
			return total >= 200
		return false
	var storage = building_storage[building_name]
	var total = _get_building_total_items(building_name)
	var capacity = storage["chests"].size() * CHEST_CAPACITY
	return total >= capacity

func _init_building_storage(building_name: String, chest_pos: Vector3i):
	if not building_storage.has(building_name):
		building_storage[building_name] = { "items": {}, "chests": [] }
	building_storage[building_name]["chests"].append(chest_pos)
	print("VillageManager: coffre placé dans '%s' à %s (capacité %d)" % [
		building_name, str(chest_pos),
		building_storage[building_name]["chests"].size() * CHEST_CAPACITY])

func _find_chest_spot_in_building(origin: Vector3i, size: Vector3i) -> Vector3i:
	"""Trouve un emplacement libre (air + sol solide) à l'intérieur d'un bâtiment."""
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)
	var margin = mini(2, mini(size.x, size.z) / 3)
	for y_off in range(1, mini(size.y, 5)):
		var check_y = origin.y + y_off
		for dx in range(margin, size.x - margin):
			for dz in range(margin, size.z - margin):
				var pos = Vector3i(origin.x + dx, check_y, origin.z + dz)
				var at = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
				var below = world_manager.get_block_at_position(Vector3(pos.x, pos.y - 1, pos.z))
				var above = world_manager.get_block_at_position(Vector3(pos.x, pos.y + 1, pos.z))
				if at == BlockRegistry.BlockType.AIR and above == BlockRegistry.BlockType.AIR and BlockRegistry.is_solid(below):
					return pos
	return Vector3i(-9999, -9999, -9999)

func get_building_storage_info() -> Dictionary:
	"""Pour l'UI : retourne les infos de stockage par bâtiment."""
	var info = {}
	for bn in building_storage:
		var total = _get_building_total_items(bn)
		var cap = building_storage[bn]["chests"].size() * CHEST_CAPACITY
		info[bn] = { "items": building_storage[bn]["items"].duplicate(), "capacity": cap, "used": total }
	return info

# ============================================================
# ÉVALUATION DES BESOINS (boucle principale)
# ============================================================

func _evaluate_needs():
	# Purger les tâches craft d'upgrade tier obsolètes
	# (ex: "Outils en pierre" si tier déjà >= 2, "Outils en fer" si tier >= 3)
	var tier_recipes = {"Outils en bois": 1, "Outils en pierre": 2, "Outils en fer": 3}
	task_queue = task_queue.filter(func(t):
		if t.get("type", "") == "craft":
			var rname = t.get("recipe_name", "")
			if tier_recipes.has(rname) and village_tool_tier >= tier_recipes[rname]:
				return false
		return true
	)

	# Nettoyer les tâches en excès : supprimer les doublons harvest/mine
	# pour laisser de la place aux tâches critiques (craft, build, farm)
	if task_queue.size() > 20:
		_trim_excess_tasks()

	match village_phase:
		0:
			_evaluate_phase_0()
		1:
			_evaluate_phase_1()
		2:
			_evaluate_phase_2()
		3:
			_evaluate_phase_3()
		4:
			_evaluate_phase_4()

func _trim_excess_tasks():
	# Supprimer les tâches de récolte/mine en surplus pour ne pas bloquer
	# les tâches critiques (craft, build, place_workstation, farm)
	var to_remove: Array = []
	var harvest_count = 0
	var mine_count = 0
	for i in range(task_queue.size()):
		var t = task_queue[i]
		match t["type"]:
			"harvest":
				harvest_count += 1
				if harvest_count > 4:
					to_remove.append(i)
			"mine_gallery":
				mine_count += 1
				if mine_count > 2:
					to_remove.append(i)
			"mine":
				mine_count += 1
				if mine_count > 3:
					to_remove.append(i)
	# Supprimer en ordre inverse pour ne pas décaler les index
	to_remove.reverse()
	for idx in to_remove:
		task_queue.remove_at(idx)

func _evaluate_phase_0():
	# Phase 0: Bootstrap — récolter bois, crafter planches, crafter crafting_table
	var total_wood = get_total_wood()
	var total_planks = get_total_planks()

	# Besoin de 10 bois pour démarrer — bûcherons ET fermier y participent
	if total_wood < 10 and total_planks < 4:
		if task_queue.size() == 0:
			print("VillageManager: Phase 0 — bois=%d planches=%d → ajout tâches récolte" % [total_wood, total_planks])
		_add_harvest_tasks(5, 4)  # Bûcherons uniquement — le fermier fait la ferme
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

	# Forge : outils en bois si on a assez de planches
	if get_total_planks() >= 6 and village_tool_tier < 1:
		if not _has_task_of_type("craft", "Outils en bois"):
			_add_task({
				"type": "craft",
				"recipe_name": "Outils en bois",
				"priority": 7,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Si crafting table placée -> phase 1
	if placed_workstations.has(12):
		village_phase = 1
		if village_tool_tier < 1:
			village_tool_tier = 1
		print("VillageManager: === PHASE 1 — ÂGE DU BOIS ===  (tier %s)" % village_tool_tier)

func _evaluate_phase_1():
	# Phase 1: Récolter plus de bois + pierre, crafter furnace, construire
	var total_wood = get_total_wood()
	var total_planks = get_total_planks()
	var total_stone = get_total_stone()  # STONE + COBBLESTONE

	# === AGRICULTURE — le fermier commence dès la phase 1 ===
	_add_farming_tasks()

	# Crafter du pain si on a du blé
	var wheat_count = get_total_resource(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3 and not _is_building_full("Moulin"):
		if not _has_task_of_type("craft", "Pain"):
			_add_task({
				"type": "craft",
				"recipe_name": "Pain",
				"priority": 12,
				"required_profession": VProfession.Profession.BOULANGER,
			})

	# Toujours maintenir du bois en stock — les bûcherons ne s'arrêtent jamais
	if total_wood < 50:
		_add_harvest_tasks(5, 4)  # un par bûcheron

	# Le menuisier transforme le bois en planches en continu
	if total_wood >= 2 and total_planks < 1000:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Crafter des torches si on a du charbon et des planches (1 coal + 1 plank = 4 torches)
	var torch_count = get_resource_count(BlockRegistry.BlockType.TORCH)
	var coal_for_torch = get_resource_count(16)  # COAL_ORE
	if coal_for_torch >= 1 and total_planks >= 1 and torch_count < 32:
		if not _has_task_of_type("craft", "Torche"):
			_add_task({
				"type": "craft",
				"recipe_name": "Torche",
				"priority": 10,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Commencer à miner — mineurs travaillent en continu (is_mine_stock_full les pause)
	_add_mine_gallery_tasks(2)

	# Crafter le fourneau (8 stone) — seulement si on n'en a pas déjà un dans le stockpile
	if total_stone >= 8 and not placed_workstations.has(21) and get_resource_count(21) == 0:
		if not _has_task_of_type("craft", "Fourneau"):
			_add_task({
				"type": "craft",
				"recipe_name": "Fourneau",
				"priority": 8,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Placer le fourneau — avec garde anti-doublon
	if get_resource_count(21) >= 1 and not placed_workstations.has(21):
		if not _has_task_of_type("place_workstation"):
			_add_task({
				"type": "place_workstation",
				"target_block": 21,  # FURNACE
				"priority": 5,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	# Aplanissement (en parallèle avec la construction si 2+ bâtisseurs)
	if not _flatten_complete and flatten_plan.size() > 0:
		# Un seul bâtisseur aplanit — l'autre est libre pour construire
		if _count_flatten_active() < 1:
			_add_task({
				"type": "flatten",
				"priority": 2,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	# Construire le chemin en croix si on a de la pierre
	if (_flatten_complete or _count_builders() >= 2) and not _path_built and get_total_stone() >= 5:
		_try_queue_path()
	# Construire les bâtiments de phase 1 (même pendant l'aplanissement si bâtisseurs dispo)
	if _flatten_complete or _count_builders() >= 2:
		_try_queue_builds_for_phase(1)

	# Forge : outils en pierre
	if get_total_stone() >= 4 and get_total_planks() >= 4 and village_tool_tier < 2:
		if not _has_task_of_type("craft", "Outils en pierre"):
			_add_task({
				"type": "craft",
				"recipe_name": "Outils en pierre",
				"priority": 7,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Si furnace placée -> phase 2
	if placed_workstations.has(21):
		village_phase = 2
		if village_tool_tier < 2:
			village_tool_tier = 2
		print("VillageManager: === PHASE 2 — ÂGE DE LA PIERRE === (tier %s)" % village_tool_tier)

func _evaluate_phase_2():
	# Phase 2: Miner charbon/fer, fondre, crafter stone_table
	var total_wood = get_total_wood()
	var total_stone = get_total_stone()
	var total_coal = get_resource_count(16)   # COAL_ORE
	var total_iron_ore = get_resource_count(17)  # IRON_ORE
	var total_iron = get_total_resource(19)   # IRON_INGOT (stockpile + coffre Forge)

	# Agriculture
	_add_farming_tasks()
	var wheat_count = get_total_resource(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3 and not _is_building_full("Moulin"):
		if not _has_task_of_type("craft", "Pain"):
			_add_task({
				"type": "craft",
				"recipe_name": "Pain",
				"priority": 12,
				"required_profession": VProfession.Profession.BOULANGER,
			})

	# Maintenir le stock — bûcherons travaillent en continu
	if total_wood < 50:
		_add_harvest_tasks(5, 4)

	# Le menuisier transforme le bois en planches en continu
	var total_planks = get_total_planks()
	if total_wood >= 2 and total_planks < 1000:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Crafter des torches
	var torch_count_p2 = get_resource_count(BlockRegistry.BlockType.TORCH)
	if total_coal >= 1 and total_planks >= 1 and torch_count_p2 < 32:
		if not _has_task_of_type("craft", "Torche"):
			_add_task({
				"type": "craft",
				"recipe_name": "Torche",
				"priority": 10,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Miner en galerie — mineurs travaillent en continu (is_mine_stock_full les pause)
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

	# Crafter stone_table (4 stone + 4 planks) — la recette ne demande PAS de fer
	if not placed_workstations.has(22) and get_resource_count(22) == 0:
		if total_stone >= 4 and get_total_planks() >= 4:
			if not _has_task_of_type("craft", "Table en pierre"):
				_add_task({
					"type": "craft",
					"recipe_name": "Table en pierre",
					"priority": 5,  # Haute priorité — bloque la progression !
					"required_profession": VProfession.Profession.FORGERON,
				})

	# Placer stone_table — avec garde anti-doublon
	if get_resource_count(22) >= 1 and not placed_workstations.has(22):
		if not _has_task_of_type("place_workstation"):
			_add_task({
				"type": "place_workstation",
				"target_block": 22,  # STONE_TABLE
				"priority": 5,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	# Aplanissement (en parallèle avec la construction si 2+ bâtisseurs)
	if not _flatten_complete and flatten_plan.size() > 0:
		# Un seul bâtisseur aplanit — l'autre est libre pour construire
		if _count_flatten_active() < 1:
			_add_task({
				"type": "flatten",
				"priority": 2,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	# Verre proactif + chemin + builds (même pendant l'aplanissement si bâtisseurs dispo)
	_craft_glass_for_builds(2)
	if (_flatten_complete or _count_builders() >= 2) and not _path_built and get_total_stone() >= 5:
		_try_queue_path()
	if _flatten_complete or _count_builders() >= 2:
		_try_queue_builds_for_phase(2)

	# Forge : outils en fer
	if get_total_resource(19) >= 3 and get_total_planks() >= 3 and village_tool_tier < 3:
		if not _has_task_of_type("craft", "Outils en fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Outils en fer",
				"priority": 7,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Si stone_table placée -> phase 3
	if placed_workstations.has(22):
		village_phase = 3
		if village_tool_tier < 3:
			village_tool_tier = 3
		print("VillageManager: === PHASE 3 — ÂGE DU FER === (tier %s)" % village_tool_tier)

func _evaluate_phase_3():
	# Phase 3: Expansion continue
	var total_wood = get_total_wood()
	var total_stone = get_total_stone()

	# Agriculture
	_add_farming_tasks()
	var wheat_count = get_total_resource(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3 and not _is_building_full("Moulin"):
		if not _has_task_of_type("craft", "Pain"):
			_add_task({
				"type": "craft",
				"recipe_name": "Pain",
				"priority": 12,
				"required_profession": VProfession.Profession.BOULANGER,
			})

	if total_wood < 50:
		_add_harvest_tasks(5, 4)

	# Le menuisier transforme le bois en planches en continu
	var total_planks = get_total_planks()
	if total_wood >= 2 and total_planks < 1000:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Crafter des torches
	var torch_count_p3 = get_resource_count(BlockRegistry.BlockType.TORCH)
	var coal_for_torch_p3 = get_resource_count(16)
	if coal_for_torch_p3 >= 1 and total_planks >= 1 and torch_count_p3 < 32:
		if not _has_task_of_type("craft", "Torche"):
			_add_task({
				"type": "craft",
				"recipe_name": "Torche",
				"priority": 10,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Mineurs en continu — is_mine_stock_full() les pause si stock saturé
	_add_mine_gallery_tasks(2)

	# Aplanissement (en parallèle avec la construction si 2+ bâtisseurs)
	if not _flatten_complete and flatten_plan.size() > 0:
		# Un seul bâtisseur aplanit — l'autre est libre pour construire
		if _count_flatten_active() < 1:
			_add_task({
				"type": "flatten",
				"priority": 2,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	# Verre proactif + fondre fer + chemin + builds (même pendant l'aplanissement)
	_craft_glass_for_builds(3)

	var coal_count_p3 = get_resource_count(16)
	var total_iron_ore_p3 = get_resource_count(17)
	if total_iron_ore_p3 >= 1 and coal_count_p3 >= 1:
		if not _has_task_of_type("craft", "Lingot de fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Lingot de fer",
				"priority": 14,
				"required_profession": VProfession.Profession.FORGERON,
			})

	if (_flatten_complete or _count_builders() >= 2) and not _path_built and get_total_stone() >= 5:
		_try_queue_path()
	if _flatten_complete or _count_builders() >= 2:
		_try_queue_builds_for_phase(3)

	# Transition Phase 3 → Phase 4 : château quand 5+ bâtiments et outils fer
	if built_structures.size() >= 5 and village_tool_tier >= 3:
		village_phase = 4
		print("VillageManager: === PHASE 4 — ÂGE MÉDIÉVAL === Construction du château !")
		# Spawner le village ennemi
		var wm = get_tree().get_first_node_in_group("world_manager")
		if wm and wm.has_method("_spawn_enemy_village"):
			wm._spawn_enemy_village(village_center)

func _evaluate_phase_4():
	# Phase 4: Âge Médiéval — château, armement, guerre
	var total_wood = get_total_wood()
	var total_stone = get_total_stone()
	var total_planks = get_total_planks()
	var total_iron = get_total_resource(19)  # IRON_INGOT (stockpile + Forge)
	var total_coal = get_resource_count(16)  # COAL_ORE
	var total_bread = get_total_resource(BlockRegistry.BlockType.BREAD)

	# === ÉCONOMIE DE BASE (continue comme Phase 3) ===
	_add_farming_tasks()

	# Pain
	var wheat_count = get_total_resource(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3 and not _is_building_full("Moulin"):
		if not _has_task_of_type("craft", "Pain"):
			_add_task({
				"type": "craft",
				"recipe_name": "Pain",
				"priority": 12,
				"required_profession": VProfession.Profession.BOULANGER,
			})

	# Bois
	if total_wood < 50:
		_add_harvest_tasks(5, 4)

	# Planches
	if total_wood >= 2 and total_planks < 1000:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Torches
	var torch_count = get_resource_count(BlockRegistry.BlockType.TORCH)
	if total_coal >= 1 and total_planks >= 1 and torch_count < 32:
		if not _has_task_of_type("craft", "Torche"):
			_add_task({
				"type": "craft",
				"recipe_name": "Torche",
				"priority": 10,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Minage continu
	_add_mine_gallery_tasks(2)

	# Fondre le fer
	var total_iron_ore = get_resource_count(17)
	if total_iron_ore >= 1 and total_coal >= 1:
		if not _has_task_of_type("craft", "Lingot de fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Lingot de fer",
				"priority": 14,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Verre proactif pour les bâtiments
	_craft_glass_for_builds(4)

	# === CONSTRUCTION CHÂTEAU ===
	# Aplanissement (en parallèle avec la construction si 2+ bâtisseurs)
	if not _flatten_complete and flatten_plan.size() > 0:
		# Un seul bâtisseur aplanit — l'autre est libre pour construire
		if _count_flatten_active() < 1:
			_add_task({
				"type": "flatten",
				"priority": 2,
				"required_profession": VProfession.Profession.BATISSEUR,
			})

	if (_flatten_complete or _count_builders() >= 2) and not _path_built and get_total_stone() >= 5:
		_try_queue_path()
	if _flatten_complete or _count_builders() >= 2:
		_try_queue_builds_for_phase(4)

	# === FORGE D'ARMES (prioritaire en Phase 4) ===
	var swords_count = get_total_resource(BlockRegistry.BlockType.IRON_SWORD)
	if total_iron >= 2 and total_planks >= 1 and swords_count < 10 and not _is_building_full("Caserne"):
		if not _has_task_of_type("craft", "Épée en fer"):
			_add_task({
				"type": "craft",
				"recipe_name": "Épée en fer",
				"priority": 8,
				"required_profession": VProfession.Profession.FORGERON,
			})

	# Boucliers
	var shields_count = get_total_resource(BlockRegistry.BlockType.SHIELD)
	if total_iron >= 1 and total_planks >= 2 and shields_count < 5 and not _is_building_full("Caserne"):
		if not _has_task_of_type("craft", "Bouclier"):
			_add_task({
				"type": "craft",
				"recipe_name": "Bouclier",
				"priority": 9,
				"required_profession": VProfession.Profession.FORGERON,
			})

# ============================================================
# GESTION DES TÂCHES
# ============================================================

func _add_task(task: Dictionary):
	task_queue.append(task)
	task_queue.sort_custom(func(a, b): return a.get("priority", 50) < b.get("priority", 50))

func _has_task_of_type(type: String, recipe_name: String = "") -> bool:
	# Vérifie la queue ET les tâches actives des villageois
	for t in task_queue:
		if t["type"] == type:
			if recipe_name != "" and t.get("recipe_name", "") != recipe_name:
				continue
			return true
	# Aussi vérifier les villageois en cours d'exécution
	for v in villagers:
		if is_instance_valid(v) and not v.current_task.is_empty():
			var ct = v.current_task
			if ct.get("type", "") == type:
				if recipe_name != "" and ct.get("recipe_name", "") != recipe_name:
					continue
				return true
	return false

func _craft_glass_for_builds(max_phase: int):
	# Calculer le besoin total en verre des bâtiments non construits de cette phase
	var built_names: Dictionary = {}
	for built in built_structures:
		built_names[built["name"]] = true
	var glass_needed = 0
	for bp in BLUEPRINTS:
		if built_names.has(bp["name"]):
			continue
		if bp.get("phase", 0) <= max_phase:
			glass_needed += bp["materials"].get(61, 0)  # GLASS
	# Crafter proactivement : seuil = besoin total des bâtiments non construits
	var glass_count = get_resource_count(61)
	var sand_count = get_resource_count(4)
	var coal_count = get_resource_count(16)
	if glass_count < glass_needed:
		if sand_count < 8 and get_total_stone() >= 2:
			if not _has_task_of_type("craft", "Sable"):
				_add_task({
					"type": "craft",
					"recipe_name": "Sable",
					"priority": 11,
					"required_profession": VProfession.Profession.FORGERON,
				})
		if sand_count >= 1 and coal_count >= 1:
			if not _has_task_of_type("craft", "Verre"):
				_add_task({
					"type": "craft",
					"recipe_name": "Verre",
					"priority": 12,
					"required_profession": VProfession.Profession.FORGERON,
				})

func _count_flatten_active() -> int:
	# Compte les tâches flatten en queue + en cours chez les villageois
	var count = 0
	for t in task_queue:
		if t["type"] == "flatten":
			count += 1
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") == "flatten":
			count += 1
	return count

func _count_active_builds() -> int:
	# Compte les tâches build en queue + en cours chez les villageois
	var count = 0
	for t in task_queue:
		if t["type"] == "build":
			count += 1
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") == "build":
			count += 1
	return count

func _count_builders() -> int:
	# Compte les bâtisseurs vivants
	var count = 0
	for v in villagers:
		if is_instance_valid(v) and v.profession == VProfession.Profession.BATISSEUR:
			count += 1
	return count

func _add_harvest_tasks(block_type: int, count: int):
	# Tous les types de bois sont acceptables
	var wood_types = [5, 32, 33, 34, 35, 36, 42]  # WOOD + toutes les essences
	var existing = 0
	for t in task_queue:
		if t["type"] == "harvest" and t.get("target_block", -1) in wood_types:
			existing += 1
	# Compter aussi les villageois déjà en train de récolter
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") == "harvest":
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

func _add_sand_harvest_tasks(count: int):
	# Récolte de sable — max 2 tâches à la fois, tout villageois libre
	var max_sand_tasks = 2
	var existing = 0
	for t in task_queue:
		if t["type"] == "mine" and t.get("target_block", -1) == 4:
			existing += 1
	# Aussi compter les villageois déjà en train de chercher du sable
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") == "mine" \
			and v.current_task.get("target_block", -1) == 4:
			existing += 1
	if existing >= max_sand_tasks:
		return
	_add_task({
		"type": "mine",
		"target_block": 4,  # SAND
		"priority": 15,  # priorité moyenne — le verre est critique pour les bâtiments
		# Pas de required_profession — tout villageois libre peut récolter du sable
	})

func _add_farming_tasks():
	# Le fermier crée les parcelles et récolte le blé
	var existing_farm = 0
	for t in task_queue:
		if t["type"] in ["farm_create", "farm_harvest"]:
			existing_farm += 1
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") in ["farm_create", "farm_harvest"]:
			existing_farm += 1
	if existing_farm >= 2:
		return

	# Priorité 1 : récolter le blé mature
	var mature_plot = get_mature_wheat_plot()
	if not mature_plot.is_empty():
		_add_task({
			"type": "farm_harvest",
			"priority": 10,
			"required_profession": VProfession.Profession.FERMIER,
		})
		return

	# Priorité 2 : créer de nouvelles parcelles
	if farm_plots.size() < FARM_SIZE * FARM_SIZE:
		_add_task({
			"type": "farm_create",
			"priority": 18,
			"required_profession": VProfession.Profession.FERMIER,
		})

func get_next_task_for(prof: int) -> Dictionary:
	# D'abord chercher une tâche spécifiquement pour cette profession (spécialiste d'abord)
	for i in range(task_queue.size()):
		var task = task_queue[i]
		var req = task.get("required_profession", -1)
		if req == prof:
			task_queue.remove_at(i)
			return task
	# Sinon prendre une tâche générique (sans required_profession)
	for i in range(task_queue.size()):
		var task = task_queue[i]
		var req = task.get("required_profession", -1)
		if req == -1:
			task_queue.remove_at(i)
			return task
	return {}

func get_next_task() -> Dictionary:
	if task_queue.size() == 0:
		return {}
	return task_queue.pop_front()

func return_task(task: Dictionary):
	# Remettre une tâche non terminée dans la queue (triée par priorité)
	task_queue.append(task)
	task_queue.sort_custom(func(a, b): return a.get("priority", 50) < b.get("priority", 50))

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

	# Check cache (durée augmentée pour réduire les rescans massifs)
	var now = Time.get_ticks_msec() / 1000.0
	var cache_key = block_type
	if _scan_cache.has(cache_key):
		var cached = _scan_cache[cache_key]
		if now - cached["time"] < SCAN_CACHE_DURATION:
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

	# === SCAN OPTIMISÉ ===
	# Rayon de chunk réduit (max 2 chunks = 32 blocs) au lieu de radius/16
	# + early exit dès qu'on trouve un résultat valide proche
	var results: Array = []
	var from_chunk = Vector3i(
		floori(from_pos.x / CHUNK_SIZE),
		0,
		floori(from_pos.z / CHUNK_SIZE)
	)
	# Limiter à 2 chunks de rayon max (5x5 = 25 chunks max au lieu de potentiellement 81+)
	var chunk_radius = mini(ceili(radius / CHUNK_SIZE) + 1, 2)

	# Set pour lookup rapide des types acceptables
	var acceptable_set: Dictionary = {}
	if block_type == 5:  # WOOD -> accepter toutes les essences
		for bt in [5, 32, 33, 34, 35, 36, 42]:
			acceptable_set[bt] = true
	else:
		acceptable_set[block_type] = true

	# Scan spirale depuis le chunk du joueur (chunks les plus proches en premier)
	var chunk_list: Array = []
	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var cp = Vector3i(cx, 0, cz)
			if world_manager.chunks.has(cp):
				chunk_list.append(cp)
	# Trier par distance au joueur
	chunk_list.sort_custom(func(a, b):
		var da = abs(a.x - from_chunk.x) + abs(a.z - from_chunk.z)
		var db = abs(b.x - from_chunk.x) + abs(b.z - from_chunk.z)
		return da < db)

	for chunk_pos in chunk_list:
		var chunk = world_manager.chunks[chunk_pos]
		var blocks = chunk.blocks
		var y_start = maxi(chunk.y_min, 1)
		var y_end = mini(chunk.y_max + 1, CHUNK_HEIGHT)

		# Échantillonnage : scanner 1 colonne sur 2 pour diviser le coût par 4
		for lx in range(0, CHUNK_SIZE, 2):
			var x_off = lx * CHUNK_SIZE * CHUNK_HEIGHT
			for lz in range(0, CHUNK_SIZE, 2):
				var xz_off = x_off + lz * CHUNK_HEIGHT
				for ly in range(y_start, y_end):
					var bt = blocks[xz_off + ly]
					if acceptable_set.has(bt):
						var world_pos = Vector3i(
							chunk_pos.x * CHUNK_SIZE + lx,
							ly,
							chunk_pos.z * CHUNK_SIZE + lz
						)
						var d = from_pos.distance_to(Vector3(world_pos.x, world_pos.y, world_pos.z))
						if d <= radius:
							results.append(world_pos)

		# Early exit : si on a déjà trouvé assez de résultats dans les chunks proches
		if results.size() >= 20:
			break

	# Mettre en cache
	_scan_cache[cache_key] = { "results": results, "time": now }

	# Trouver le plus proche non-claimé
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

func find_nearest_surface_block(block_type: int, from_pos: Vector3, radius: float = 32.0, ignore_village_dist: bool = false) -> Vector3i:
	# Comme find_nearest_block mais ne retourne que les blocs en surface (avec AIR au-dessus)
	# OPTIMISÉ : rayon de chunk limité + échantillonnage
	# ignore_village_dist: si true, pas de distance min du village (pour sable, etc.)
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	var from_chunk = Vector3i(
		floori(from_pos.x / CHUNK_SIZE),
		0,
		floori(from_pos.z / CHUNK_SIZE)
	)
	var chunk_radius = mini(ceili(radius / CHUNK_SIZE) + 1, 5)  # max 5 chunks (~80 blocs) pour trouver du sable lointain
	var best = Vector3i(-9999, -9999, -9999)
	var best_dist = INF

	var acceptable_set: Dictionary = {}
	if block_type == 5:
		for bt in [5, 32, 33, 34, 35, 36, 42]:
			acceptable_set[bt] = true
	else:
		acceptable_set[block_type] = true

	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var chunk_pos = Vector3i(cx, 0, cz)
			if not world_manager.chunks.has(chunk_pos):
				continue

			var chunk = world_manager.chunks[chunk_pos]
			var blocks_data = chunk.blocks
			var y_start = maxi(chunk.y_min, 1)
			var y_end = mini(chunk.y_max + 1, CHUNK_HEIGHT - 1)

			for lx in range(0, CHUNK_SIZE, 2):
				var x_off = lx * CHUNK_SIZE * CHUNK_HEIGHT
				for lz in range(0, CHUNK_SIZE, 2):
					var xz_off = x_off + lz * CHUNK_HEIGHT
					for ly in range(y_start, y_end):
						var bt = blocks_data[xz_off + ly]
						if acceptable_set.has(bt):
							if blocks_data[xz_off + ly + 1] == 0:  # AIR au-dessus
								var world_pos = Vector3i(
									cx * CHUNK_SIZE + lx,
									ly,
									cz * CHUNK_SIZE + lz
								)
								if claimed_positions.has(world_pos):
									continue
								# Ne pas miner trop près du village center (sauf si ignore)
								if not ignore_village_dist:
									var dist_to_village = Vector2(world_pos.x - village_center.x, world_pos.z - village_center.z).length()
									if dist_to_village < 30.0:
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
	# Trouver un spot d'entrée ÉLOIGNÉ du village center
	if _mine_initialized:
		return
	if not world_manager:
		return

	var center_y = int(village_center.y)
	var best_pos = Vector3i(-9999, -9999, -9999)
	var best_score = 999.0  # plus bas = meilleur

	# Passe 1: terrain plat, 15-45 blocs (tolérance 3 blocs de diff)
	# Passe 2: sans check plat, 10-50 blocs (fallback)
	for pass_num in range(2):
		for attempt in range(60):
			var dist = randi_range(15, 45) if pass_num == 0 else randi_range(10, 50)
			var angle = randf() * TAU
			var dx = int(cos(angle) * dist)
			var dz = int(sin(angle) * dist)
			var cx = int(village_center.x) + dx
			var cz = int(village_center.z) + dz
			var surface_y = _find_surface_y(cx, cz)
			if surface_y < 0:
				continue

			if pass_num == 0:
				# Vérifier terrain ~plat (tolérance 3 blocs)
				var flat = true
				for check_dx in range(-1, 2):
					for check_dz in range(-1, 2):
						var ny = _find_surface_y(cx + check_dx, cz + check_dz)
						if ny < 0 or abs(ny - surface_y) > 3:
							flat = false
							break
					if not flat:
						break
				if not flat:
					continue

			var y_diff = abs(surface_y - center_y)
			var score = y_diff + abs(dist - 30) * 0.1  # préfère ~30 blocs et même altitude
			if score < best_score:
				best_score = score
				best_pos = Vector3i(cx, surface_y, cz)

		if best_pos != Vector3i(-9999, -9999, -9999):
			break  # Trouvé en passe 1, pas besoin de fallback

	if best_pos == Vector3i(-9999, -9999, -9999):
		# Fallback ultime : juste à 15 blocs dans une direction cardinale
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cx = int(village_center.x) + dir.x * 15
			var cz = int(village_center.z) + dir.y * 15
			var sy = _find_surface_y(cx, cz)
			if sy >= 0:
				best_pos = Vector3i(cx, sy, cz)
				break

	if best_pos == Vector3i(-9999, -9999, -9999):
		print("VillageManager: ERREUR — impossible de trouver un spot de mine !")
		return

	mine_entrance = best_pos
	_mine_initialized = true

	# Générer le plan de mine — escalier descendant praticable par les PNJ
	#
	# GÉOMÉTRIE D'UNE MARCHE (vue latérale, → = direction) :
	#
	#   [H1][H2]         ← y+1 (blocs à miner pour la tête — 2 blocs de hauteur libre)
	#   [F1][F2]         ← y   (blocs à miner pour les pieds)
	#   [SOL SOL]        ← y-1 (sol sur lequel le PNJ marche — PAS miné)
	#            [H3][H4]     ← y   (marche suivante, tête)
	#            [F3][F4]     ← y-1 (marche suivante, pieds)
	#            [SOL SOL]    ← y-2 (nouveau sol)
	#
	# Le PNJ a 2 blocs libres (pieds + tête minés), marche sur le sol en dessous.
	# Descente de 1 bloc entre chaque palier → le PNJ tombe de 1 bloc (OK).
	# Remontée : le PNJ saute de 1 bloc (OK — auto-jump).
	# Palier de 2 blocs de large → le PNJ a de la place pour marcher.
	#
	# ORDRE DE MINAGE : séquentiel de haut en bas.
	# Le premier bloc de chaque marche est toujours accessible car :
	# - Marche 0 : le PNJ est à la surface, les blocs sont exposés
	# - Marches N+1 : les blocs de la marche N sont déjà minés (air)

	mine_plan.clear()
	mine_front_index = 0

	var target_y = maxi(center_y - 30, 20)
	_mine_gallery_y = target_y

	# Géométrie de l'escalier (identique à Minecraft, vue latérale) :
	#
	#   Chaque marche = 2 colonnes (avance) × 3 rangées (largeur) × 3 blocs (hauteur)
	#   Le PNJ marche sur le bloc y-1 (sol, NON miné).
	#   3 blocs d'air au-dessus (y, y+1, y+2) pour que le PNJ passe.
	#   On avance de 2 blocs horizontalement, puis on descend de 1.
	#   Mine = 3 blocs de large (z-1, z, z+1) pour que 2 mineurs travaillent côte à côte.
	#
	#   Vue de dessus (une marche) :
	#
	#          z-1   z   z+1
	#   x    : [M]  [M]  [M]
	#   x+dx : [M]  [M]  [M]
	#
	#   Ordre de minage par colonne : TOP-DOWN (y+2, y+1, y)

	var cur_y = best_pos.y  # Y de la surface à l'entrée
	var cur_x = best_pos.x
	var cur_z = best_pos.z
	var dir_x = 1   # direction horizontale
	var steps = 0

	while cur_y > target_y:
		# 2 colonnes (avance) × 3 rangées (largeur) × 3 hauteurs, top-down
		for col_x in [cur_x, cur_x + dir_x]:
			for dz in [-1, 0, 1]:
				mine_plan.append(Vector3i(col_x, cur_y + 2, cur_z + dz))
				mine_plan.append(Vector3i(col_x, cur_y + 1, cur_z + dz))
				mine_plan.append(Vector3i(col_x, cur_y, cur_z + dz))

		# Avancer de 2 blocs horizontalement et descendre de 1
		cur_x += dir_x * 2
		cur_y -= 1
		steps += 1

		# Zigzag tous les 5 paliers pour rester compact
		if steps % 5 == 0:
			dir_x = -dir_x
			cur_z += 2  # décalé de 2 pour éviter de chevaucher (largeur 3)

	# Galerie en étoile au fond — 4 branches de 8 blocs (3 large × 3 haut)
	_mine_gallery_center = Vector3i(cur_x, target_y, cur_z)
	var gc = _mine_gallery_center
	var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for dir in dirs:
		for i in range(1, 9):
			# Perpendiculaire à la direction de la branche pour la largeur
			var perp_x = dir[1]  # si dir=(1,0) → perp=(0,1), si dir=(0,1) → perp=(1,0)
			var perp_z = dir[0]
			for w in [-1, 0, 1]:
				var bx = gc.x + dir[0] * i + perp_x * w
				var bz = gc.z + dir[1] * i + perp_z * w
				mine_plan.append(Vector3i(bx, target_y + 2, bz))
				mine_plan.append(Vector3i(bx, target_y + 1, bz))
				mine_plan.append(Vector3i(bx, target_y, bz))

	_mine_expansion_dir = 0
	print("VillageManager: mine planifiée — %d blocs à creuser depuis %s (cible y=%d)" % [mine_plan.size(), str(mine_entrance), target_y])

func is_mine_stock_full() -> bool:
	# Retourne true si les ressources minières sont TOUTES au-dessus des seuils de pause
	# Seuils élevés : pavé 2000, charbon 200, fer 80 — le village consomme beaucoup
	var cobble = get_resource_count(25)  # COBBLESTONE (vrai drop du mineur)
	var coal = get_resource_count(16)
	var iron = get_resource_count(17) + get_total_resource(19)  # IRON_ORE + IRON_INGOT (lingots dans coffre Forge)
	return cobble > MINE_STOCK_PAUSE_STONE and coal > MINE_STOCK_PAUSE_COAL and iron > MINE_STOCK_PAUSE_IRON

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
		# Lookahead de 20 blocs solides — largement assez pour 2 mineurs
		var lookahead = 0
		for i in range(mine_front_index + 1, mine_plan.size()):
			var p = mine_plan[i]
			var b = world_manager.get_block_at_position(Vector3(p.x, p.y, p.z))
			if b == BlockRegistry.BlockType.AIR or b == BlockRegistry.BlockType.WATER:
				continue
			if not claimed_positions.has(p):
				return p
			lookahead += 1
			if lookahead >= 20:
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

	# Purger les blocs déjà minés pour libérer de la mémoire
	if mine_front_index > 500:
		mine_plan = mine_plan.slice(mine_front_index)
		mine_front_index = 0

	# Plafond : ne pas étendre si le plan est déjà trop gros
	if mine_plan.size() > MINE_PLAN_MAX_SIZE:
		return
	# Si cap d'expansions atteint mais mine épuisée → reset pour descendre plus profond
	if _mine_expansion_dir >= MINE_MAX_EXPANSIONS:
		if mine_front_index >= mine_plan.size() or mine_plan.size() == 0:
			# Mine entièrement minée — nouveau cycle d'expansions plus profond
			_mine_expansion_dir = 0
			_mine_gallery_y = maxi(_mine_gallery_y - 5, 15)
			mine_plan.clear()
			mine_front_index = 0
			print("VillageManager: mine réinitialisée — nouveau niveau y=%d" % _mine_gallery_y)
		else:
			return

	_mine_expansion_dir += 1
	var branch_len = 10
	var old_size = mine_plan.size()
	var y = _mine_gallery_y
	var gc = _mine_gallery_center

	if _mine_expansion_dir % 6 == 0 and _mine_gallery_y > 15:
		# Tous les 6 expansions : descendre de 5 blocs via un nouvel escalier
		var new_y = maxi(_mine_gallery_y - 5, 10)
		# Escalier avec paliers de 2 blocs
		var pos_x = gc.x
		var pos_y = gc.y
		var pos_z = gc.z
		var dx = 1
		while pos_y > new_y:
			# 2 colonnes × 3 rangées (largeur) × 3 blocs (hauteur), top-down
			for col_x in [pos_x, pos_x + dx]:
				for ddz in [-1, 0, 1]:
					mine_plan.append(Vector3i(col_x, pos_y + 2, pos_z + ddz))
					mine_plan.append(Vector3i(col_x, pos_y + 1, pos_z + ddz))
					mine_plan.append(Vector3i(col_x, pos_y, pos_z + ddz))
			pos_x += dx * 2
			pos_y -= 1
		_mine_gallery_y = new_y
		_mine_gallery_center = Vector3i(pos_x, new_y, pos_z)
		var pos = _mine_gallery_center
		# 4 branches depuis le nouveau centre (3 large × 3 haut)
		var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
		for dir in dirs:
			var p_x = dir[1]
			var p_z = dir[0]
			for i in range(1, branch_len + 1):
				for w in [-1, 0, 1]:
					var bx = pos.x + dir[0] * i + p_x * w
					var bz = pos.z + dir[1] * i + p_z * w
					mine_plan.append(Vector3i(bx, new_y + 2, bz))
					mine_plan.append(Vector3i(bx, new_y + 1, bz))
					mine_plan.append(Vector3i(bx, new_y, bz))
	else:
		# Nouvelle branche latérale au même niveau — décalée à chaque expansion
		var offset = _mine_expansion_dir * 2
		var dir_idx = _mine_expansion_dir % 4
		var dx = [1, -1, 0, 0][dir_idx]
		var dz = [0, 0, 1, -1][dir_idx]
		# Perpendiculaire pour décaler le départ et la largeur
		var perp_dx = -dz if dz != 0 else 0
		var perp_dz = dx if dx != 0 else 0
		# Branche CONNECTÉE : part du centre + offset perpendiculaire
		var start_x = gc.x + perp_dx * offset
		var start_z = gc.z + perp_dz * offset
		# Couloir de connexion (du centre vers le start) — 3 large
		var conn_len = abs(offset)
		if conn_len > 0:
			var conn_dx = 1 if start_x > gc.x else (-1 if start_x < gc.x else 0)
			var conn_dz = 1 if start_z > gc.z else (-1 if start_z < gc.z else 0)
			# Perpendiculaire au couloir de connexion
			var cp_dx = -conn_dz if conn_dz != 0 else 0
			var cp_dz = conn_dx if conn_dx != 0 else 0
			for i in range(1, conn_len + 1):
				for w in [-1, 0, 1]:
					var bx = gc.x + conn_dx * i + cp_dx * w
					var bz = gc.z + conn_dz * i + cp_dz * w
					mine_plan.append(Vector3i(bx, y + 2, bz))
					mine_plan.append(Vector3i(bx, y + 1, bz))
					mine_plan.append(Vector3i(bx, y, bz))
		# Branche elle-même — 3 large
		for i in range(branch_len):
			for w in [-1, 0, 1]:
				var bx = start_x + dx * i + perp_dx * w
				var bz = start_z + dz * i + perp_dz * w
				mine_plan.append(Vector3i(bx, y + 2, bz))
				mine_plan.append(Vector3i(bx, y + 1, bz))
				mine_plan.append(Vector3i(bx, y, bz))

	if _mine_expansion_dir % 5 == 0:
		print("VillageManager: mine étendue — total %d blocs, y=%d" % [mine_plan.size(), _mine_gallery_y])

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
	# Ne pas miner si le stockpile est saturé
	if is_mine_stock_full():
		return
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
		if is_instance_valid(v) and v.current_task.get("type", "") == "mine_gallery":
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
			# Forge : vérifier le tier AVANT de consommer les ressources
			if recipe.has("_tool_tier"):
				var new_tier = recipe["_tool_tier"]
				if new_tier <= village_tool_tier:
					return false  # Déjà au bon tier, ne pas gaspiller

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
				elif bt == 3 or bt == 25:  # STONE ou COBBLESTONE — interchangeables
					if get_total_stone() < needed:
						can = false
						break
				else:
					if get_total_resource(bt) < needed:
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
				elif bt == 3 or bt == 25:
					consume_any_stone(needed)
				else:
					consume_resources_anywhere(bt, needed)

			# Forge : upgrade tool tier
			if recipe.has("_tool_tier"):
				village_tool_tier = recipe["_tool_tier"]
				print("VillageManager: outils améliorés au tier %d (%s)" % [village_tool_tier, TOOL_TIER_NAMES.get(village_tool_tier, "?")])
				return true

			# Produire l'output → coffre du bâtiment si applicable, sinon stockpile virtuel
			_route_craft_output(recipe["output_type"], recipe["output_count"])
			print("VillageManager: crafté %s x%d" % [recipe_name, recipe["output_count"]])
			return true

	return false

# ============================================================
# PLACEMENT DE WORKSTATION
# ============================================================

func find_flat_spot_near_center(radius: float = 8.0) -> Vector3i:
	# Trouver un spot plat près du centre du village (utilise ref_y, pas surface_y)
	if not world_manager:
		return Vector3i(-9999, -9999, -9999)

	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var r = int(radius)
	var ry = village_ref_y if village_ref_y > 0 else int(village_center.y)

	for attempt in range(20):
		var tx = cx + randi_range(-r, r)
		var tz = cz + randi_range(-r, r)

		# Placer à ref_y + 1 (terrain aplani garanti)
		var pos = Vector3i(tx, ry + 1, tz)

		# Vérifier qu'il y a de l'air
		var block_at = world_manager.get_block_at_position(Vector3(tx, ry + 1, tz))
		var block_above = world_manager.get_block_at_position(Vector3(tx, ry + 2, tz))

		if block_at == BlockRegistry.BlockType.AIR and block_above == BlockRegistry.BlockType.AIR:
			if not claimed_positions.has(pos):
				return pos

	return Vector3i(-9999, -9999, -9999)

func _find_surface_y(wx: int, wz: int) -> int:
	# Trouver le Y de surface à une position monde — optimisé : commence depuis y_max du chunk
	var chunk_pos = Vector3i(floori(float(wx) / CHUNK_SIZE), 0, floori(float(wz) / CHUNK_SIZE))
	var start_y = 120  # par défaut raisonnable
	if world_manager.chunks.has(chunk_pos):
		start_y = mini(world_manager.chunks[chunk_pos].y_max + 1, CHUNK_HEIGHT - 1)
	for y in range(start_y, 0, -1):
		var bt = world_manager.get_block_at_position(Vector3(wx, y, wz))
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and not BlockRegistry.is_cross_mesh(bt):
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

func _try_queue_builds_for_phase(max_phase: int):
	# Construire autant de bâtiments que de bâtisseurs disponibles (en parallèle)
	var slots = _count_builders() - _count_active_builds()
	if slots <= 0:
		return

	var built_names: Dictionary = {}
	for built in built_structures:
		built_names[built["name"]] = true

	var queued = 0
	for i in range(BLUEPRINTS.size()):
		if queued >= slots:
			break
		var bp = BLUEPRINTS[i]
		if built_names.has(bp["name"]):
			continue
		var bp_phase = bp.get("phase", 0)
		if bp_phase <= max_phase:
			if _try_queue_build(i):
				queued += 1

func _try_queue_build(blueprint_index: int) -> bool:
	if blueprint_index >= BLUEPRINTS.size():
		return false

	# Vérifier qu'on n'a pas déjà cette construction en queue
	for t in task_queue:
		if t["type"] == "build" and t.get("blueprint_index", -1) == blueprint_index:
			return false

	# Vérifier qu'un villageois ne construit pas déjà ce blueprint
	for npc in villagers:
		if is_instance_valid(npc) and npc.current_task.get("type", "") == "build" \
			and npc.current_task.get("blueprint_index", -1) == blueprint_index:
			return false

	var bp = BLUEPRINTS[blueprint_index]

	# Vérifier si on a assez de matériaux
	var can_build = true
	var missing_info = []
	for bt in bp["materials"]:
		var needed = bp["materials"][bt]
		var have = 0
		if bt == 11:  # PLANKS
			have = get_total_planks()
		elif bt == 3 or bt == 25:  # STONE/COBBLESTONE interchangeables
			have = get_total_stone()
		else:
			have = get_resource_count(bt)
		if have < needed:
			can_build = false
			missing_info.append("bt%d %d/%d" % [bt, have, needed])

	if not can_build:
		# Ajouter des tâches de récolte pour les matériaux manquants (max 4 par type)
		for bt in bp["materials"]:
			var needed = bp["materials"][bt]
			var have = 0
			if bt == 11:
				have = get_total_planks()
			elif bt == 3 or bt == 25:
				have = get_total_stone()
			else:
				have = get_resource_count(bt)
			if have < needed:
				var deficit = needed - have
				if bt == 11:  # Planks -> récolter du bois (le menuisier craft en continu)
					_add_harvest_tasks(5, mini(ceili(float(deficit) / 4.0), 4))
				elif bt == 3 or bt == 25:  # Stone/Cobble -> mine en galerie
					_add_mine_gallery_tasks(2)
				elif bt == 61:  # Glass -> crafter du sable + verre (pavé → sable → verre)
					if get_resource_count(4) >= 1 and get_resource_count(16) >= 1:  # SAND + COAL_ORE
						if not _has_task_of_type("craft", "Verre"):
							_add_task({
								"type": "craft",
								"recipe_name": "Verre",
								"priority": 10,
								"required_profession": VProfession.Profession.FORGERON,
							})
					# Crafter du sable depuis le pavé
					if get_resource_count(4) < deficit and get_total_stone() >= 2:
						if not _has_task_of_type("craft", "Sable"):
							_add_task({
								"type": "craft",
								"recipe_name": "Sable",
								"priority": 9,
								"required_profession": VProfession.Profession.FORGERON,
							})
		return false

	# Trouver un emplacement
	var origin = _find_build_site(bp)
	if origin == Vector3i(-9999, -9999, -9999):
		print("VillageManager: '%s' — pas de site valide trouvé" % bp["name"])
		return false

	# Consommer les matériaux
	for bt in bp["materials"]:
		var needed = bp["materials"][bt]
		if bt == 11:
			consume_any_planks(needed)
		elif bt == 3 or bt == 25:
			consume_any_stone(needed)
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
	return true

func _find_build_site(blueprint: Dictionary) -> Vector3i:
	# Terrain aplani → origin.y = ref_y + 1 (garanti plat après flatten)
	var size = blueprint["size"]
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var ref_y = village_ref_y if village_ref_y > 0 else int(village_center.y)

	var best_site = Vector3i(-9999, -9999, -9999)
	var best_dist = INF

	# Plus de tentatives car les bâtiments sont plus grands
	for attempt in range(120):
		var tx = cx + randi_range(-VILLAGE_RADIUS + 1, VILLAGE_RADIUS - size.x)
		var tz = cz + randi_range(-VILLAGE_RADIUS + 1, VILLAGE_RADIUS - size.z)

		# Vérifier que le site est dans la zone village
		if tx < cx - VILLAGE_RADIUS or tx + size.x > cx + VILLAGE_RADIUS + 1:
			continue
		if tz < cz - VILLAGE_RADIUS or tz + size.z > cz + VILLAGE_RADIUS + 1:
			continue

		# Pas de chevauchement avec les constructions existantes (marge 4 pour vrais bâtiments)
		var overlap = false
		for built in built_structures:
			var bo = built["origin"]
			var bs = built["size"]
			if tx < bo.x + bs.x + 4 and tx + size.x > bo.x - 4 \
				and tz < bo.z + bs.z + 4 and tz + size.z > bo.z - 4:
				overlap = true
				break
		if overlap:
			continue

		# Pas de chevauchement avec les constructions en cours (queue + NPC actifs)
		var in_progress_overlap = false
		for t in task_queue:
			if t["type"] == "build" and t.has("origin"):
				var to = t["origin"]
				var bi = t.get("blueprint_index", -1)
				if bi >= 0 and bi < BLUEPRINTS.size():
					var ts = BLUEPRINTS[bi]["size"]
					if tx < to.x + ts.x + 4 and tx + size.x > to.x - 4 \
						and tz < to.z + ts.z + 4 and tz + size.z > to.z - 4:
						in_progress_overlap = true
						break
		if not in_progress_overlap:
			for v in villagers:
				if is_instance_valid(v) and v.current_task.get("type", "") == "build":
					var ct = v.current_task
					if ct.has("origin"):
						var to = ct["origin"]
						var bi = ct.get("blueprint_index", -1)
						if bi >= 0 and bi < BLUEPRINTS.size():
							var ts = BLUEPRINTS[bi]["size"]
							if tx < to.x + ts.x + 4 and tx + size.x > to.x - 4 \
								and tz < to.z + ts.z + 4 and tz + size.z > to.z - 4:
								in_progress_overlap = true
								break
		if in_progress_overlap:
			continue

		# Pas de chevauchement avec les workstations
		var ws_overlap = false
		for ws_type in placed_workstations:
			var ws_pos = placed_workstations[ws_type]
			if tx <= ws_pos.x + 2 and tx + size.x > ws_pos.x - 2 \
				and tz <= ws_pos.z + 2 and tz + size.z > ws_pos.z - 2:
				ws_overlap = true
				break
		if ws_overlap:
			continue

		# Si flatten en cours, vérifier que la zone est à peu près plate
		# Tolérance +4 blocs car le flatten va nettoyer le reste en parallèle
		if not _flatten_complete:
			var is_ok = true
			var sample_points = [
				Vector2i(tx, tz), Vector2i(tx + size.x - 1, tz),
				Vector2i(tx, tz + size.z - 1), Vector2i(tx + size.x - 1, tz + size.z - 1),
				Vector2i(tx + size.x / 2, tz + size.z / 2)
			]
			for sp in sample_points:
				var sy = _find_surface_y(sp.x, sp.y)
				if sy > ref_y + 4:
					is_ok = false
					break
			if not is_ok:
				continue

		# origin.y = ref_y + 1 (terrain plat garanti ou vérifié)
		var site = Vector3i(tx, ref_y + 1, tz)
		var dist = abs(tx + size.x / 2 - cx) + abs(tz + size.z / 2 - cz)
		if dist < best_dist:
			best_dist = dist
			best_site = site

	return best_site

func register_built_structure(name: String, origin: Vector3i, size: Vector3i):
	built_structures.append({ "name": name, "origin": origin, "size": size })
	print("VillageManager: structure '%s' terminée à %s" % [name, str(origin)])
	# Placer un coffre si le bâtiment stocke des items
	if _storage_map.has(name):
		var chest_pos = _find_chest_spot_in_building(origin, size)
		if chest_pos != Vector3i(-9999, -9999, -9999):
			world_manager.place_block_at_position(Vector3(chest_pos.x, chest_pos.y, chest_pos.z), BlockRegistry.BlockType.CHEST)
			_init_building_storage(name, chest_pos)
		else:
			# Pas de spot trouvé — init storage sans coffre physique (fallback)
			_init_building_storage(name, origin + Vector3i(size.x / 2, 1, size.z / 2))
			print("VillageManager: WARNING — pas de spot pour coffre dans '%s'" % name)
	# Générer un chemin de 3 blocs de large entre le bâtiment et la plaza
	_generate_road_to_plaza(origin, size, name)
	# Relancer la construction des chemins si nécessaire
	_path_built = false

func _generate_road_to_plaza(origin: Vector3i, size: Vector3i, building_name: String):
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var ref_y = village_ref_y if village_ref_y > 0 else int(village_center.y)
	var sy = ref_y

	var BT_COBBLE = BlockRegistry.BlockType.COBBLESTONE

	# Centre du bâtiment
	var bx = origin.x + size.x / 2
	var bz = origin.z + size.z / 2

	# Direction vers la plaza (axe principal)
	var dx_total = cx - bx
	var dz_total = cz - bz

	# Déterminer le point de départ (bord du bâtiment côté plaza)
	var start_x = bx
	var start_z = bz
	if abs(dx_total) >= abs(dz_total):
		# Chemin horizontal (axe X)
		start_x = origin.x if dx_total < 0 else origin.x + size.x - 1
	else:
		# Chemin vertical (axe Z)
		start_z = origin.z if dz_total < 0 else origin.z + size.z - 1

	# Tracer le chemin en L : d'abord X puis Z (3 blocs de large)
	var road_width = 3  # 3 blocs de large minimum
	var half_w = road_width / 2

	# Si la chapelle, place de 7 blocs autour
	if building_name == "Chapelle":
		_generate_chapel_plaza(origin, size, sy)

	var BT_TORCH = BlockRegistry.BlockType.TORCH
	var blocks_added = 0

	# Segment X (horizontal)
	var x_start = mini(start_x, cx)
	var x_end = maxi(start_x, cx)
	for x in range(x_start, x_end + 1):
		for w in range(-half_w, half_w + 1):
			var pos = Vector3i(x, sy, start_z + w)
			_path_blocks.append([pos, BT_COBBLE])
			blocks_added += 1
		# Torche tous les 6 blocs sur le bord du chemin
		if (x - x_start) % 6 == 3 and x != x_start and x != x_end:
			_path_blocks.append([Vector3i(x, sy + 1, start_z + half_w + 1), BT_TORCH])
			blocks_added += 1

	# Segment Z (vertical)
	var z_start = mini(start_z, cz)
	var z_end = maxi(start_z, cz)
	for z in range(z_start, z_end + 1):
		for w in range(-half_w, half_w + 1):
			var pos = Vector3i(cx + w, sy, z)
			_path_blocks.append([pos, BT_COBBLE])
			blocks_added += 1
		# Torche tous les 6 blocs sur le bord du chemin
		if (z - z_start) % 6 == 3 and z != z_start and z != z_end:
			_path_blocks.append([Vector3i(cx + half_w + 1, sy + 1, z), BT_TORCH])
			blocks_added += 1

	print("VillageManager: chemin vers '%s' planifié — %d blocs (3 large, torches)" % [building_name, blocks_added])

func _generate_chapel_plaza(origin: Vector3i, size: Vector3i, sy: int):
	var BT_COBBLE = BlockRegistry.BlockType.COBBLESTONE
	var BT_TORCH = BlockRegistry.BlockType.TORCH
	var margin = 7  # 7 blocs de large autour
	var blocks_added = 0

	# Place en cobblestone autour de la chapelle
	for x in range(origin.x - margin, origin.x + size.x + margin):
		for z in range(origin.z - margin, origin.z + size.z + margin):
			# Seulement la bordure extérieure (pas sous le bâtiment)
			var inside_building = x >= origin.x and x < origin.x + size.x \
				and z >= origin.z and z < origin.z + size.z
			if not inside_building:
				_path_blocks.append([Vector3i(x, sy, z), BT_COBBLE])
				blocks_added += 1

	# Torches aux 4 coins de la place
	for corner in [
		[origin.x - margin + 1, origin.z - margin + 1],
		[origin.x - margin + 1, origin.z + size.z + margin - 2],
		[origin.x + size.x + margin - 2, origin.z - margin + 1],
		[origin.x + size.x + margin - 2, origin.z + size.z + margin - 2],
	]:
		_path_blocks.append([Vector3i(corner[0], sy + 1, corner[1]), BT_TORCH])
		blocks_added += 4

	print("VillageManager: place de la chapelle planifiée — %d blocs (marge %d)" % [blocks_added, margin])

# ============================================================
# PLACE DU VILLAGE (place pavée circulaire + puits + chemins)
# ============================================================

func _try_queue_path():
	if _path_built:
		return
	# Vérifier qu'il n'y a pas déjà une tâche de chemin
	for t in task_queue:
		if t["type"] == "build_path":
			return
	for v in villagers:
		if is_instance_valid(v) and v.current_task.get("type", "") == "build_path":
			return

	# Générer le plan de la place du village (une seule fois)
	if _path_blocks.size() == 0 or _path_index >= _path_blocks.size():
		_path_blocks.clear()
		_path_index = 0
		_generate_plaza_plan()

	# Vérifier qu'on a assez de pierre
	var remaining = _path_blocks.size() - _path_index
	if remaining <= 0:
		_path_built = true
		return
	var stone_count = get_total_stone()
	if stone_count < 3:
		return  # Pas assez, on attend

	_add_task({
		"type": "build_path",
		"priority": 12,
		"required_profession": VProfession.Profession.BATISSEUR,
	})

func _generate_plaza_plan():
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	var ref_y = village_ref_y if village_ref_y > 0 else int(village_center.y)
	var sy = ref_y  # terrain plat garanti après flatten
	plaza_center = Vector3(cx, sy, cz)

	var BT_COBBLE = BlockRegistry.BlockType.COBBLESTONE    # 25 — puits + chemins
	var BT_TORCH = BlockRegistry.BlockType.TORCH           # 72 — éclairage

	# --- 1) Puits central (5×5 base, murs 2 blocs de haut, poteaux, toit) ---
	# Base du puits en cobblestone (5×5)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			_path_blocks.append([Vector3i(cx + dx, sy, cz + dz), BT_COBBLE])
	# Murs du puits (anneau extérieur 5×5, 2 blocs de haut)
	for ring_y in range(1, 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if abs(dx) == 2 or abs(dz) == 2:
					_path_blocks.append([Vector3i(cx + dx, sy + ring_y, cz + dz), BT_COBBLE])
	# Poteaux aux 4 coins (3 blocs de haut)
	for corner in [[-2, -2], [-2, 2], [2, -2], [2, 2]]:
		_path_blocks.append([Vector3i(cx + corner[0], sy + 3, cz + corner[1]), BT_COBBLE])
	# Toit du puits (traverse en croix)
	for dx in range(-2, 3):
		_path_blocks.append([Vector3i(cx + dx, sy + 4, cz), BT_COBBLE])
	for dz in range(-2, 3):
		if dz != 0:
			_path_blocks.append([Vector3i(cx, sy + 4, cz + dz), BT_COBBLE])

	# --- 2) Torches autour du puits ---
	for off in [[-3, -3], [-3, 3], [3, -3], [3, 3]]:
		_path_blocks.append([Vector3i(cx + off[0], sy + 1, cz + off[1]), BT_TORCH])

	# --- 3) Quatre chemins en cobblestone (5 blocs de large, 15 blocs de long) ---
	var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for dir in dirs:
		for i in range(3, 18):  # depuis le bord du puits vers l'extérieur
			for w in range(-2, 3):  # 5 blocs de large (-2, -1, 0, 1, 2)
				var wx = cx + dir[0] * i + dir[1] * w
				var wz = cz + dir[1] * i + dir[0] * w
				if abs(wx - cx) <= FLATTEN_RADIUS and abs(wz - cz) <= FLATTEN_RADIUS:
					_path_blocks.append([Vector3i(wx, sy, wz), BT_COBBLE])

	_path_index = 0
	print("VillageManager: place du village planifiée — %d blocs (rayon %d)" % [_path_blocks.size(), PLAZA_RADIUS])

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

func get_next_path_block() -> Array:
	# Retourne [Vector3i, block_type] du prochain bloc à poser
	if _path_index >= _path_blocks.size():
		_path_built = true
		return []
	var entry = _path_blocks[_path_index]
	_path_index += 1
	return entry  # [Vector3i, int]

func mark_path_complete():
	if _path_index >= _path_blocks.size():
		_path_built = true
		print("VillageManager: place du village terminée !")

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
	# === Chargement des structures JSON converties depuis Minecraft ===
	# Les structures terrain (dirt, grass, leaves, logs naturels) sont filtrées
	# Seuls les blocs de construction sont gardés dans le blueprint

	# Blocs terrain à ignorer (pas des blocs de construction)
	var terrain_set: Dictionary = {}
	for bt in [0, 1, 2, 4, 6, 7, 8, 9, 10, 15, 44, 45, 46, 47, 48, 49, 56, 57, 58, 59, 60]:
		# AIR, GRASS, DIRT, SAND, LEAVES, SNOW, CACTUS, DARK_GRASS, GRAVEL, WATER,
		# SPRUCE_LEAVES..CHERRY_LEAVES, CLAY, PODZOL, ICE, PACKED_ICE, MOSS_BLOCK
		terrain_set[bt] = true

	# Phase 1 — Cabane en bois (Small Survival House)
	_load_structure_blueprint(
		"res://structures/small_(15x13)_survival_house___(mcbuild_org).json",
		"Cabane", 1, terrain_set)

	# Phase 1 — Ferme (Wood House — plus rustique, convient à une ferme)
	_load_structure_blueprint(
		"res://structures/wood_house___(mcbuild_org).json",
		"Ferme", 1, terrain_set)

	# Phase 1 — Entrée de mine (trop simple pour un JSON, on garde le hardcode)
	var BT_PLANKS = 11
	var mine_entry_blocks = []
	for y in range(3):
		mine_entry_blocks.append([0, y, 0, BT_PLANKS])
		mine_entry_blocks.append([2, y, 0, BT_PLANKS])
		mine_entry_blocks.append([0, y, 2, BT_PLANKS])
		mine_entry_blocks.append([2, y, 2, BT_PLANKS])
	mine_entry_blocks.append([1, 2, 0, BT_PLANKS])
	mine_entry_blocks.append([1, 2, 2, BT_PLANKS])
	mine_entry_blocks.append([0, 2, 1, BT_PLANKS])
	mine_entry_blocks.append([2, 2, 1, BT_PLANKS])
	mine_entry_blocks.append([1, 2, 1, BT_PLANKS])
	BLUEPRINTS.append({
		"name": "Entrée de mine",
		"size": Vector3i(3, 3, 3),
		"materials": { BT_PLANKS: 21 },
		"block_list": mine_entry_blocks,
		"phase": 1,
	})

	# Phase 2 — Forge (Fantasy Forge)
	_load_structure_blueprint(
		"res://structures/fantasy_forge___(mcbuild_org).json",
		"Forge", 2, terrain_set)

	# Phase 2 — Maison (Medieval Spruce Wood House 2)
	_load_structure_blueprint(
		"res://structures/medieval_spruce_wood_house_2___(mcbuild_org).json",
		"Maison", 2, terrain_set)

	# Phase 2 — Entrepôt (Medieval Guard Outpost — bâtiment trapu en pierre)
	_load_structure_blueprint(
		"res://structures/medieval_guard_outpost.json",
		"Entrepôt", 2, terrain_set)

	# Phase 2 — Taverne (Medieval Tavern Inn)
	_load_structure_blueprint(
		"res://structures/medieval_tavern_inn____(mcbuild_org).json",
		"Taverne", 2, terrain_set)

	# Phase 2 — Moulin (Windmill — boulangerie)
	_load_structure_blueprint(
		"res://structures/windmill___(mcbuild_org).json",
		"Moulin", 2, terrain_set)

	# Phase 2 — Chapelle (générée, pierre + clocher)
	_load_structure_blueprint(
		"res://structures/chapelle_village.json",
		"Chapelle", 2, terrain_set)

	# Phase 3 — Tour de guet (Tour Garde existante)
	_load_structure_blueprint(
		"res://structures/tour_garde.json",
		"Tour de guet", 3, terrain_set)

	# Phase 3 — Guilde (Medieval Spruce Wood House — grande bâtisse)
	_load_structure_blueprint(
		"res://structures/medieval_spruce_wood_house___(mcbuild_org).json",
		"Guilde", 3, terrain_set)

	# Phase 4 — Caserne (entraînement soldats)
	_load_structure_blueprint(
		"res://structures/caserne.json",
		"Caserne", 4, terrain_set)

	# Phase 4 — Donjon (bâtiment central du château)
	_load_structure_blueprint(
		"res://structures/donjon.json",
		"Donjon", 4, terrain_set)

	# Phase 4 — Rempart (segment de mur)
	_load_structure_blueprint(
		"res://structures/rempart.json",
		"Rempart", 4, terrain_set)

	# Phase 4 — Tour de défense (coins du château)
	_load_structure_blueprint(
		"res://structures/tour_defense.json",
		"Tour de défense", 4, terrain_set)

	print("VillageManager: %d blueprints chargés" % BLUEPRINTS.size())


func _load_structure_blueprint(path: String, bp_name: String, phase: int, terrain_set: Dictionary):
	"""Charge une structure JSON et la convertit en blueprint village."""
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("VillageManager: impossible de lire " + path)
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("VillageManager: JSON invalide " + path)
		return

	var data = json.data
	var sz = data["size"]  # [w, h, l] — ne pas utiliser data.size (conflit avec Dictionary.size())
	var w = int(sz[0])
	var h = int(sz[1])
	var l = int(sz[2])
	var palette_names: Array = data["palette"]

	# Résoudre la palette → BlockType IDs
	var palette: Array = []
	for pname in palette_names:
		if pname == "AIR":
			palette.append(0)
		elif pname == "KEEP":
			palette.append(-1)  # sera ignoré
		else:
			var resolved = -1
			for key in BlockRegistry.BlockType.keys():
				if key == pname:
					resolved = BlockRegistry.BlockType[key]
					break
			if resolved == -1:
				# Bloc inconnu → STONE comme fallback
				resolved = BlockRegistry.BlockType.STONE
			palette.append(resolved)

	# Décoder le RLE
	var rle: Array = data["blocks_rle"]
	var total = w * h * l
	var blocks: Array = []
	blocks.resize(total)
	blocks.fill(0)
	var pos = 0
	var i = 0
	while i + 1 < rle.size():
		var pidx = int(rle[i])
		var count = int(rle[i + 1])
		var bt = palette[pidx] if pidx < palette.size() else 0
		for j in range(count):
			if pos < total:
				blocks[pos] = bt
				pos += 1
		i += 2

	# Extraire les blocs de construction (ignorer AIR, terrain, KEEP)
	var block_list: Array = []
	var wood_count: int = 0
	var stone_count: int = 0
	var glass_count: int = 0

	# Sets pour classification des matériaux
	var wood_types: Dictionary = {}
	for bt in [5, 11, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 62, 64]:
		# WOOD, PLANKS, logs, planks variantes, BOOKSHELF, BARREL
		wood_types[bt] = true
	var stone_types: Dictionary = {}
	for bt in [3, 13, 25, 26, 27, 28, 29, 30, 31]:
		# STONE, BRICK, COBBLESTONE, MOSSY, ANDESITE, GRANITE, DIORITE, DEEPSLATE, SMOOTH
		stone_types[bt] = true

	# Trouver le bounding box des blocs de construction
	var min_x = w
	var max_x = 0
	var min_y = h
	var max_y = 0
	var min_z = l
	var max_z = 0

	for y in range(h):
		for z in range(l):
			for x in range(w):
				var idx = y * w * l + z * w + x
				var bt = blocks[idx]
				if bt <= 0:
					continue  # AIR ou KEEP
				if terrain_set.has(bt):
					continue  # Bloc terrain, ignorer
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				min_z = mini(min_z, z)
				max_z = maxi(max_z, z)

	if max_x < min_x:
		push_warning("VillageManager: aucun bloc de construction dans " + path)
		return

	# Recalculer les coordonnées relatives au bounding box
	for y in range(min_y, max_y + 1):
		for z in range(l):
			for x in range(w):
				var idx = y * w * l + z * w + x
				var bt = blocks[idx]
				if bt <= 0:
					continue
				if terrain_set.has(bt):
					continue
				block_list.append([x - min_x, y - min_y, z - min_z, bt])
				# Compter les matériaux
				if wood_types.has(bt):
					wood_count += 1
				elif stone_types.has(bt):
					stone_count += 1
				elif bt == 61:  # GLASS
					glass_count += 1

	var bp_size = Vector3i(max_x - min_x + 1, max_y - min_y + 1, max_z - min_z + 1)

	# Matériaux simplifiés : on ne demande que bois, pierre et verre
	# Les blocs décoratifs/spéciaux sont "offerts" par la structure
	var materials: Dictionary = {}
	if wood_count > 0:
		materials[11] = wood_count  # PLANKS (on accepte tout type de bois)
	if stone_count > 0:
		materials[25] = stone_count  # COBBLESTONE (on accepte tout type de pierre)
	if glass_count > 0:
		materials[61] = glass_count  # GLASS

	BLUEPRINTS.append({
		"name": bp_name,
		"size": bp_size,
		"materials": materials,
		"block_list": block_list,
		"phase": phase,
	})
	print("VillageManager: blueprint '%s' chargé — %dx%dx%d, %d blocs (W:%d S:%d G:%d)" % [
		bp_name, bp_size.x, bp_size.y, bp_size.z, block_list.size(),
		wood_count, stone_count, glass_count])

# ============================================================
# AGRICULTURE (Farming)
# ============================================================

func _update_wheat_growth(delta):
	if farm_plots.size() == 0:
		return
	for plot in farm_plots:
		if plot["stage"] >= WHEAT_MAX_STAGE:
			continue
		plot["timer"] += delta
		if plot["timer"] >= WHEAT_GROWTH_TIME:
			plot["timer"] = 0.0
			plot["stage"] += 1
			# Mettre à jour le bloc dans le monde
			var wheat_pos = Vector3i(plot["pos"].x, plot["pos"].y + 1, plot["pos"].z)
			var new_block = _wheat_stage_to_block(plot["stage"])
			place_block(wheat_pos, new_block)

func _wheat_stage_to_block(stage: int) -> int:
	match stage:
		0: return BlockRegistry.BlockType.WHEAT_STAGE_0
		1: return BlockRegistry.BlockType.WHEAT_STAGE_1
		2: return BlockRegistry.BlockType.WHEAT_STAGE_2
		3: return BlockRegistry.BlockType.WHEAT_STAGE_3
		_: return BlockRegistry.BlockType.WHEAT_STAGE_0

func init_farm():
	# Trouver un spot plat 5x5 pour la ferme
	if _farm_initialized:
		return
	if not world_manager:
		return

	var cx = int(village_center.x)
	var cz = int(village_center.z)

	# Passe 1: 15-35 blocs, terrain plat (tolérance 1)
	# Passe 2: 8-45 blocs, terrain plat (tolérance 2)
	# Passe 3: 5-50 blocs, pas de check plat (fallback)
	for pass_num in range(3):
		var tolerance = [1, 2, 999][pass_num]
		var min_dist = [30, 25, 22][pass_num]
		var max_dist = [50, 55, 60][pass_num]

		for attempt in range(60):
			var dist = randi_range(min_dist, max_dist)
			var angle = randf() * TAU
			var tx = cx + int(cos(angle) * dist)
			var tz = cz + int(sin(angle) * dist)

			var first_y = _find_surface_y(tx, tz)
			if first_y < 0:
				continue

			if tolerance < 999:
				var flat = true
				for fx in range(FARM_SIZE):
					for fz in range(FARM_SIZE):
						var sy = _find_surface_y(tx + fx, tz + fz)
						if sy < 0 or abs(sy - first_y) > tolerance:
							flat = false
							break
					if not flat:
						break
				if not flat:
					continue

			# Pas de chevauchement avec les constructions
			var overlap = false
			for built in built_structures:
				var bo = built["origin"]
				var bs = built["size"]
				if tx < bo.x + bs.x + 2 and tx + FARM_SIZE > bo.x - 2 \
					and tz < bo.z + bs.z + 2 and tz + FARM_SIZE > bo.z - 2:
					overlap = true
					break
			if overlap:
				continue

			_farm_center = Vector3i(tx, first_y, tz)
			_farm_initialized = true
			print("VillageManager: ferme planifiée à %s (passe %d)" % [str(_farm_center), pass_num + 1])
			return

	print("VillageManager: ERREUR — impossible de trouver un spot de ferme !")

func create_farm_plot(pos: Vector3i):
	# Convertir GRASS/DIRT en FARMLAND et planter du blé dessus
	place_block(pos, BlockRegistry.BlockType.FARMLAND)
	var wheat_pos = Vector3i(pos.x, pos.y + 1, pos.z)
	place_block(wheat_pos, BlockRegistry.BlockType.WHEAT_STAGE_0)
	farm_plots.append({
		"pos": pos,
		"stage": 0,
		"timer": 0.0,
	})

func get_next_farm_plot_to_create() -> Vector3i:
	# Retourne la prochaine position de la ferme à labourer
	if not _farm_initialized:
		init_farm()
	if not _farm_initialized:
		return INVALID_POS_CONST

	var created_set: Dictionary = {}
	for plot in farm_plots:
		created_set[plot["pos"]] = true

	for fx in range(FARM_SIZE):
		for fz in range(FARM_SIZE):
			var pos = Vector3i(_farm_center.x + fx, _farm_center.y, _farm_center.z + fz)
			if not created_set.has(pos):
				return pos

	return INVALID_POS_CONST  # Ferme complète

func get_mature_wheat_plot() -> Dictionary:
	# Retourne un plot de blé mature à récolter
	for plot in farm_plots:
		if plot["stage"] >= WHEAT_MAX_STAGE:
			var pos = plot["pos"]
			if not claimed_positions.has(pos):
				return plot
	return {}

func harvest_wheat(plot: Dictionary):
	# Récolter le blé mature : supprimer le bloc, ajouter WHEAT_ITEM, replanter
	var wheat_pos = Vector3i(plot["pos"].x, plot["pos"].y + 1, plot["pos"].z)
	place_block(wheat_pos, BlockRegistry.BlockType.WHEAT_STAGE_0)
	plot["stage"] = 0
	plot["timer"] = 0.0
	add_resource(BlockRegistry.BlockType.WHEAT_ITEM, 1)
	pass  # Log supprimé : trop fréquent

func get_farm_stats() -> Dictionary:
	var total = farm_plots.size()
	var mature = 0
	for plot in farm_plots:
		if plot["stage"] >= WHEAT_MAX_STAGE:
			mature += 1
	return { "total": total, "mature": mature, "max": FARM_SIZE * FARM_SIZE }

# ============================================================
# CROISSANCE DU VILLAGE
# ============================================================

func _try_grow_village():
	var pop = villagers.size()
	var cap = get_population_cap()
	if pop >= cap:
		return
	if get_total_resource(BlockRegistry.BlockType.BREAD) < BREAD_PER_VILLAGER:
		return

	# Consommer le pain (stockpile virtuel + coffres bâtiments)
	consume_resources_anywhere(BlockRegistry.BlockType.BREAD, BREAD_PER_VILLAGER)

	# Choisir une profession selon les besoins
	var prof = _pick_needed_profession()

	# Trouver un spot de spawn
	var spawn_pos = _find_villager_spawn_pos()
	if spawn_pos == Vector3.ZERO:
		# Rembourser le pain si pas de spot
		_route_craft_output(BlockRegistry.BlockType.BREAD, BREAD_PER_VILLAGER)
		return

	# Spawn le nouveau villageois
	_spawn_new_villager(spawn_pos, prof)
	print("VillageManager: nouveau villageois %s ! Population %d/%d" % [
		VProfession.get_profession_name(prof), pop + 1, cap])

func get_population_cap() -> int:
	var houses = 0
	for built in built_structures:
		if built["name"] in ["Cabane", "Maison"]:
			houses += 1
	return 9 + (2 * houses)

func _pick_needed_profession() -> int:
	# Compter les professions existantes
	var counts: Dictionary = {}
	for v in villagers:
		if is_instance_valid(v):
			counts[v.profession] = counts.get(v.profession, 0) + 1

	# Minimum de bâtisseurs selon la phase (plus de bâtiments à construire)
	var min_builders = 1
	if village_phase >= 3:
		min_builders = 3
	elif village_phase >= 2:
		min_builders = 2

	# Priorités : un fermier de plus si peu de nourriture, bûcheron si peu de bois, etc.
	var needs: Array = [
		[VProfession.Profession.FERMIER, 1],
		[VProfession.Profession.BUCHERON, 2],
		[VProfession.Profession.MINEUR, 2],
		[VProfession.Profession.BATISSEUR, min_builders],
		[VProfession.Profession.MENUISIER, 1],
		[VProfession.Profession.FORGERON, 1],
	]

	for need in needs:
		var prof = need[0]
		var min_count = need[1]
		if counts.get(prof, 0) < min_count:
			return prof

	# Sinon, la profession la moins représentée
	var min_prof = VProfession.Profession.BUCHERON
	var min_val = 999
	for need in needs:
		var prof = need[0]
		var c = counts.get(prof, 0)
		if c < min_val:
			min_val = c
			min_prof = prof
	return min_prof

func _find_villager_spawn_pos() -> Vector3:
	var cx = int(village_center.x)
	var cz = int(village_center.z)
	for attempt in range(15):
		var tx = cx + randi_range(-6, 6)
		var tz = cz + randi_range(-6, 6)
		var sy = _find_surface_y(tx, tz)
		if sy > 0:
			return Vector3(tx + 0.5, sy + 1, tz + 0.5)
	return Vector3.ZERO

func _spawn_new_villager(spawn_pos: Vector3, prof: int):
	if not world_manager:
		return
	var villager_index = villagers.size()
	var chunk_pos = Vector3i(
		floori(spawn_pos.x / CHUNK_SIZE),
		0,
		floori(spawn_pos.z / CHUNK_SIZE)
	)
	var NpcVillagerScript = preload("res://scripts/npc_villager.gd")
	var npc = NpcVillagerScript.new()
	npc.setup(villager_index, spawn_pos, chunk_pos, prof)
	if world_manager.poi_manager:
		npc.poi_manager = world_manager.poi_manager
	world_manager.get_parent().call_deferred("add_child", npc)
	world_manager.npcs.append({"npc": npc, "chunk_pos": chunk_pos})
	register_villager(npc)

# ============================================================
# DEBUG
# ============================================================

func get_status_text() -> String:
	var phase_names = ["Bootstrap", "Âge du Bois", "Âge de la Pierre", "Âge du Fer"]
	var status = "Village: %s (Phase %d)\n" % [phase_names[village_phase], village_phase]
	status += "Outils: tier %d (x%.1f)\n" % [village_tool_tier, TOOL_TIER_MULTIPLIER.get(village_tool_tier, 1.0)]
	status += "Population: %d/%d\n" % [villagers.size(), get_population_cap()]
	status += "Tâches: %d en attente\n" % task_queue.size()
	var fs = get_farm_stats()
	if fs["total"] > 0:
		status += "Ferme: %d parcelles (%d matures)\n" % [fs["total"], fs["mature"]]
	status += "Bâtiments: %d\n" % built_structures.size()
	status += "Stockpile:\n"
	for bt in stockpile:
		if stockpile[bt] > 0:
			status += "  %s: %d\n" % [BlockRegistry.get_block_name(bt as BlockRegistry.BlockType), stockpile[bt]]
	return status
