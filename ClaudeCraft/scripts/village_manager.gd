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
const MINE_PLAN_MAX_SIZE = 5000    # plafond du mine plan — empêche la croissance infinie
const MINE_STOCK_PAUSE_STONE = 200 # pause minage si pierre > seuil
const MINE_STOCK_PAUSE_COAL = 80   # pause minage si charbon > seuil
const MINE_STOCK_PAUSE_IRON = 30   # pause minage si fer > seuil

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

	# Croissance du blé
	_update_wheat_growth(delta)

	# Croissance du village (nouveaux villageois)
	_growth_timer += delta
	if _growth_timer >= GROWTH_CHECK_INTERVAL:
		_growth_timer = 0.0
		_try_grow_village()

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
	var total_stone = get_resource_count(3)  # STONE
	var total_cobble = get_resource_count(25)  # COBBLESTONE

	# === AGRICULTURE — le fermier commence dès la phase 1 ===
	_add_farming_tasks()

	# Crafter du pain si on a du blé
	var wheat_count = get_resource_count(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3:
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
	if total_wood >= 2 and total_planks < 200:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Commencer à miner — mineurs travaillent en continu
	if total_stone < 40:
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

	# Construire le chemin en croix si on a du cobblestone
	if not _path_built and get_resource_count(25) >= 5:  # COBBLESTONE
		_try_queue_path()

	# Construire les bâtiments de phase 1 (pas besoin du chemin pour commencer)
	_try_queue_builds_for_phase(1)

	# Forge : outils en pierre
	if get_resource_count(25) >= 4 and get_total_planks() >= 4 and village_tool_tier < 2:
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
	var total_stone = get_resource_count(3)
	var total_coal = get_resource_count(16)   # COAL_ORE
	var total_iron_ore = get_resource_count(17)  # IRON_ORE
	var total_iron = get_resource_count(19)   # IRON_INGOT

	# Agriculture
	_add_farming_tasks()
	var wheat_count = get_resource_count(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3:
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
	if total_wood >= 2 and total_planks < 200:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	# Miner en galerie — mineurs travaillent en continu
	if total_stone < 40 or total_coal < 15 or (total_iron_ore < 8 and total_iron < 8):
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
				print("VillageManager: Ajout tâche craft Table en pierre (stone=%d, planks=%d)" % [total_stone, get_total_planks()])
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

	# Chemin si pas encore fait
	if not _path_built and get_resource_count(25) >= 5:
		_try_queue_path()

	# Verre : récolter du sable si nécessaire, puis crafter
	var glass_count = get_resource_count(61)  # GLASS
	var sand_count = get_resource_count(4)    # SAND
	var coal_count = get_resource_count(16)   # COAL_ORE
	if glass_count < 10:
		# Pas assez de sable → envoyer le bâtisseur en récolter (1 seul à la fois)
		if sand_count < 2:
			_add_sand_harvest_tasks(1)
		# Crafter si on a les ingrédients
		if sand_count >= 1 and coal_count >= 1:
			if not _has_task_of_type("craft", "Verre"):
				_add_task({
					"type": "craft",
					"recipe_name": "Verre",
					"priority": 12,
					"required_profession": VProfession.Profession.FORGERON,
				})

	# Construire les bâtiments de phase 1 et 2
	_try_queue_builds_for_phase(2)

	# Forge : outils en fer
	if get_resource_count(19) >= 3 and get_total_planks() >= 3 and village_tool_tier < 3:
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
	var total_stone = get_resource_count(3)

	# Agriculture
	_add_farming_tasks()
	var wheat_count = get_resource_count(BlockRegistry.BlockType.WHEAT_ITEM)
	if wheat_count >= 3:
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
	if total_wood >= 2 and total_planks < 200:
		if not _has_task_of_type("craft", "Planches"):
			_add_task({
				"type": "craft",
				"recipe_name": "Planches",
				"priority": 15,
				"required_profession": VProfession.Profession.MENUISIER,
			})

	if total_stone < 40:
		_add_mine_gallery_tasks(2)

	# Verre : récolter du sable si nécessaire, puis crafter
	var glass_count_p3 = get_resource_count(61)
	var sand_count_p3 = get_resource_count(4)
	var coal_count_p3 = get_resource_count(16)
	if glass_count_p3 < 10:
		if sand_count_p3 < 2:
			_add_sand_harvest_tasks(1)
		if sand_count_p3 >= 1 and coal_count_p3 >= 1:
			if not _has_task_of_type("craft", "Verre"):
				_add_task({
					"type": "craft",
					"recipe_name": "Verre",
					"priority": 12,
					"required_profession": VProfession.Profession.FORGERON,
				})

	# Construire tous les bâtiments
	_try_queue_builds_for_phase(3)

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

func _add_sand_harvest_tasks(count: int):
	# Récolte de sable — max 1 tâche à la fois, assignée au BATISSEUR
	# (le bâtisseur attend souvent les matériaux, autant l'occuper)
	var max_sand_tasks = 1
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
		"priority": 25,  # basse priorité — ne pas bloquer les tâches importantes
		"required_profession": VProfession.Profession.BATISSEUR,
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
	var chunk_radius = mini(ceili(radius / CHUNK_SIZE) + 1, 3)  # max 3 chunks (élargi de 2 à 3)
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
	# Retourne true si les ressources minières sont au-dessus des seuils de pause
	# Permet aux mineurs de s'arrêter quand le stockpile est saturé
	var stone = get_resource_count(3) + get_resource_count(25)  # STONE + COBBLE
	var coal = get_resource_count(16)
	var iron = get_resource_count(17) + get_resource_count(19)  # IRON_ORE + IRON_INGOT
	return stone > MINE_STOCK_PAUSE_STONE and coal > MINE_STOCK_PAUSE_COAL and iron > MINE_STOCK_PAUSE_IRON

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

			# Forge : upgrade tool tier
			if recipe.has("_tool_tier"):
				village_tool_tier = recipe["_tool_tier"]
				print("VillageManager: outils améliorés au tier %d (%s)" % [village_tool_tier, TOOL_TIER_NAMES.get(village_tool_tier, "?")])
				return true

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
	# Trouver le Y de surface à une position monde — optimisé : commence depuis y_max du chunk
	var chunk_pos = Vector3i(floori(float(wx) / CHUNK_SIZE), 0, floori(float(wz) / CHUNK_SIZE))
	var start_y = 120  # par défaut raisonnable
	if world_manager.chunks.has(chunk_pos):
		start_y = mini(world_manager.chunks[chunk_pos].y_max + 1, CHUNK_HEIGHT - 1)
	for y in range(start_y, 0, -1):
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

func _try_queue_builds_for_phase(max_phase: int):
	# Construire tous les blueprints dont la phase est <= max_phase et pas encore construits
	var built_names: Dictionary = {}
	for built in built_structures:
		built_names[built["name"]] = true

	for i in range(BLUEPRINTS.size()):
		var bp = BLUEPRINTS[i]
		if built_names.has(bp["name"]):
			continue
		var bp_phase = bp.get("phase", 0)
		if bp_phase <= max_phase:
			_try_queue_build(i)
			return  # Un seul bâtiment à la fois

func _try_queue_build(blueprint_index: int):
	if blueprint_index >= BLUEPRINTS.size():
		return

	# Vérifier qu'on n'a pas déjà cette construction en queue
	for t in task_queue:
		if t["type"] == "build" and t.get("blueprint_index", -1) == blueprint_index:
			return

	# Vérifier qu'un villageois ne construit pas déjà ce blueprint
	for npc in villagers:
		if is_instance_valid(npc) and npc.current_task.get("type", "") == "build" \
			and npc.current_task.get("blueprint_index", -1) == blueprint_index:
			return

	var bp = BLUEPRINTS[blueprint_index]

	# Vérifier si on a assez de matériaux
	var can_build = true
	var missing_info = []
	for bt in bp["materials"]:
		var needed = bp["materials"][bt]
		var have = 0
		if bt == 11:  # PLANKS
			have = get_total_planks()
			if have < needed:
				can_build = false
				missing_info.append("planches %d/%d" % [have, needed])
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
			else:
				have = get_resource_count(bt)
			if have < needed:
				var deficit = needed - have
				if bt == 11:  # Planks -> récolter du bois (le menuisier craft en continu)
					_add_harvest_tasks(5, mini(ceili(float(deficit) / 4.0), 4))
				elif bt == 3 or bt == 25:  # Stone/Cobble -> mine en galerie
					_add_mine_gallery_tasks(2)
				elif bt == 61:  # Glass -> crafter du verre (sable + charbon → fourneau)
					if get_resource_count(4) >= 1 and get_resource_count(16) >= 1:  # SAND + COAL_ORE
						if not _has_task_of_type("craft", "Verre"):
							_add_task({
								"type": "craft",
								"recipe_name": "Verre",
								"priority": 10,
								"required_profession": VProfession.Profession.FORGERON,
							})
					else:
						# Pas de sable → envoyer le bâtisseur en récolter (1 seul)
						if get_resource_count(4) < deficit:
							_add_sand_harvest_tasks(1)
		return

	# Trouver un emplacement
	var origin = _find_build_site(bp)
	if origin == Vector3i(-9999, -9999, -9999):
		print("VillageManager: '%s' — pas de site valide trouvé" % bp["name"])
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
	# Trouver un terrain assez plat pour le bâtiment
	# Tolère un dénivelé de 2 blocs, et aplatit le terrain lors de la construction
	var size = blueprint["size"]
	var cx = int(village_center.x)
	var cz = int(village_center.z)

	var best_site = Vector3i(-9999, -9999, -9999)
	var best_path_dist = INF

	for attempt in range(60):
		var tx = cx + randi_range(-16, 16)
		var tz = cz + randi_range(-16, 16)

		# Vérifier que le terrain est ~plat sur toute la surface
		var first_y = _find_surface_y(tx, tz)
		if first_y < 0:
			continue

		var flat = true
		var max_y = first_y
		var min_y = first_y
		for bx in range(size.x):
			for bz in range(size.z):
				var sy = _find_surface_y(tx + bx, tz + bz)
				if sy < 0:
					flat = false
					break
				max_y = maxi(max_y, sy)
				min_y = mini(min_y, sy)
				if max_y - min_y > 3:
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
			if tx < bo.x + bs.x + 2 and tx + size.x > bo.x - 2 \
				and tz < bo.z + bs.z + 2 and tz + size.z > bo.z - 2:
				overlap = true
				break

		if overlap:
			continue

		# Utiliser le y le plus haut comme référence (les blocs en dessous seront comblés)
		var site = Vector3i(tx, max_y + 1, tz)
		var path_dist = INF
		for pb in _path_blocks:
			var d = abs(tx - pb.x) + abs(tz - pb.z)
			if d < path_dist:
				path_dist = d
		# Sans chemin, utiliser la distance au centre
		if path_dist == INF:
			path_dist = abs(tx - cx) + abs(tz - cz)
		if path_dist < best_path_dist:
			best_path_dist = path_dist
			best_site = site

	return best_site

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
					# Fenêtres ouvertes à y=2 sur les côtés (pas de verre en phase 1)
					if y == 2 and ((x == 2 and (z == 0 or z == 4)) or (z == 2 and x == 4)):
						continue  # Ouvertures pour les fenêtres
					else:
						cabin_blocks.append([x, y, z, BT_PLANKS])

	# Toit (y=4)
	for x in range(5):
		for z in range(5):
			cabin_blocks.append([x, 4, z, BT_PLANKS])

	BLUEPRINTS.append({
		"name": "Cabane",
		"size": Vector3i(5, 5, 5),
		"materials": { BT_PLANKS: 65 },
		"block_list": cabin_blocks,
		"phase": 1,
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
		"phase": 2,
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
		"phase": 3,
	})

	# === Ferme 6x4x6 (Phase 1) — tout en planches (pas besoin de pierre) ===
	var farm_blocks = []
	# Sol planches
	for x in range(6):
		for z in range(6):
			farm_blocks.append([x, 0, z, BT_PLANKS])
	# Murs bas (y=1-2) — planches, porte au centre x=0
	for y in range(1, 3):
		for x in range(6):
			for z in range(6):
				if x == 0 or x == 5 or z == 0 or z == 5:
					if x == 0 and z == 3 and y <= 2:
						continue  # Porte
					farm_blocks.append([x, y, z, BT_PLANKS])
	# Toit planches (y=3)
	for x in range(6):
		for z in range(6):
			farm_blocks.append([x, 3, z, BT_PLANKS])
	BLUEPRINTS.append({
		"name": "Ferme",
		"size": Vector3i(6, 4, 6),
		"materials": { BT_PLANKS: 78 },
		"block_list": farm_blocks,
		"phase": 1,
	})

	# === Forge 5x5x5 (Phase 2) ===
	var forge_blocks = []
	var BT_STONE = 3
	# Sol cobblestone
	for x in range(5):
		for z in range(5):
			forge_blocks.append([x, 0, z, BT_COBBLE])
	# Murs (y=1-3) — stone + cobblestone, cheminée
	for y in range(1, 4):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4:
					if x == 0 and z == 2 and y <= 2:
						continue  # Porte
					if y == 2 and ((x == 2 and z == 0) or (x == 2 and z == 4)):
						forge_blocks.append([x, y, z, BT_GLASS])
					else:
						forge_blocks.append([x, y, z, BT_STONE if y >= 2 else BT_COBBLE])
	# Toit (y=4)
	for x in range(5):
		for z in range(5):
			forge_blocks.append([x, 4, z, BT_COBBLE])
	BLUEPRINTS.append({
		"name": "Forge",
		"size": Vector3i(5, 5, 5),
		"materials": { BT_COBBLE: 45, BT_STONE: 16, BT_GLASS: 2 },
		"block_list": forge_blocks,
		"phase": 2,
	})

	# === Entrepôt 7x4x7 (Phase 2) ===
	var storage_blocks = []
	# Sol planches
	for x in range(7):
		for z in range(7):
			storage_blocks.append([x, 0, z, BT_PLANKS])
	# Murs (y=1-2)
	for y in range(1, 3):
		for x in range(7):
			for z in range(7):
				if x == 0 or x == 6 or z == 0 or z == 6:
					if x == 3 and z == 0 and y <= 2:
						continue  # Porte large
					if x == 4 and z == 0 and y <= 2:
						continue
					storage_blocks.append([x, y, z, BT_PLANKS])
	# Toit (y=3)
	for x in range(7):
		for z in range(7):
			storage_blocks.append([x, 3, z, BT_PLANKS])
	BLUEPRINTS.append({
		"name": "Entrepôt",
		"size": Vector3i(7, 4, 7),
		"materials": { BT_PLANKS: 98 },
		"block_list": storage_blocks,
		"phase": 2,
	})

	# === Maison 5x4x5 (Phase 2) ===
	var house_blocks = []
	# Sol planches
	for x in range(5):
		for z in range(5):
			house_blocks.append([x, 0, z, BT_PLANKS])
	# Murs (y=1-2) — planches, fenêtres verre
	for y in range(1, 3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4:
					if x == 0 and z == 2 and y <= 2:
						continue  # Porte
					if y == 2 and ((x == 2 and (z == 0 or z == 4)) or (z == 2 and x == 4)):
						house_blocks.append([x, y, z, BT_GLASS])
					else:
						house_blocks.append([x, y, z, BT_PLANKS])
	# Toit (y=3)
	for x in range(5):
		for z in range(5):
			house_blocks.append([x, 3, z, BT_PLANKS])
	BLUEPRINTS.append({
		"name": "Maison",
		"size": Vector3i(5, 4, 5),
		"materials": { BT_PLANKS: 56, BT_GLASS: 3 },
		"block_list": house_blocks,
		"phase": 2,
	})

	# === Entrée de mine 3x3x3 (Phase 1) — planches (pas besoin de pierre) ===
	var mine_entry_blocks = []
	# Piliers (y=0-2) aux 4 coins
	for y in range(3):
		mine_entry_blocks.append([0, y, 0, BT_PLANKS])
		mine_entry_blocks.append([2, y, 0, BT_PLANKS])
		mine_entry_blocks.append([0, y, 2, BT_PLANKS])
		mine_entry_blocks.append([2, y, 2, BT_PLANKS])
	# Linteau (y=2, milieu)
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
		var min_dist = [15, 8, 5][pass_num]
		var max_dist = [35, 45, 50][pass_num]

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
	if not has_resources(BlockRegistry.BlockType.BREAD, BREAD_PER_VILLAGER):
		return

	# Consommer le pain
	consume_resources(BlockRegistry.BlockType.BREAD, BREAD_PER_VILLAGER)

	# Choisir une profession selon les besoins
	var prof = _pick_needed_profession()

	# Trouver un spot de spawn
	var spawn_pos = _find_villager_spawn_pos()
	if spawn_pos == Vector3.ZERO:
		# Rembourser le pain si pas de spot
		add_resource(BlockRegistry.BlockType.BREAD, BREAD_PER_VILLAGER)
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

	# Priorités : un fermier de plus si peu de nourriture, bûcheron si peu de bois, etc.
	var needs: Array = [
		[VProfession.Profession.FERMIER, 1],
		[VProfession.Profession.BUCHERON, 2],
		[VProfession.Profession.MINEUR, 2],
		[VProfession.Profession.BATISSEUR, 1],
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
	var model_index = VProfession.get_model_for_profession(prof, villagers.size())
	var chunk_pos = Vector3i(
		floori(spawn_pos.x / CHUNK_SIZE),
		0,
		floori(spawn_pos.z / CHUNK_SIZE)
	)
	var NpcVillagerScript = preload("res://scripts/npc_villager.gd")
	var npc = NpcVillagerScript.new()
	npc.setup(model_index, spawn_pos, chunk_pos, prof)
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
