extends CharacterBody3D
class_name NpcVillager

const VProfession = preload("res://scripts/villager_profession.gd")

const INVALID_POS = Vector3i(-9999, -9999, -9999)

const MODEL_PATH = "res://BlockPNJ/Models/GLB format/"
const MODEL_NAMES: Array[String] = [
	"character-a", "character-b", "character-c", "character-d",
	"character-e", "character-f", "character-g", "character-h",
	"character-i", "character-j", "character-k", "character-l",
	"character-m", "character-n", "character-o", "character-p",
	"character-q", "character-r"
]
static var _model_scenes: Array[PackedScene] = []

static func _preload_models():
	if _model_scenes.size() > 0:
		return
	for model_name in MODEL_NAMES:
		var scene = load(MODEL_PATH + model_name + ".glb") as PackedScene
		if scene:
			_model_scenes.append(scene)

# === Identité ===
var mob_type_index: int = 0
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO
var profession: int = 0  # VProfession.Profession
var health: int = 20

# === Mouvement ===
var move_speed: float = 2.0
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _jump_velocity: float = 5.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO

# === Emploi du temps ===
var current_activity: int = 0  # VProfession.Activity
var home_position: Vector3 = Vector3.ZERO
var _schedule_timer: float = 0.0
var _day_night: Node = null

# === Navigation vers cible ===
var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false
var _arrived_at_target: bool = false
var _target_stuck_timer: float = 0.0
var _total_stuck_time: float = 0.0  # temps total bloqué (cumulé)
var _detour_timer: float = 0.0
var _detour_direction: Vector3 = Vector3.ZERO
var _detour_count: int = 0  # nombre de détours effectués

# === POI / Travail ===
var claimed_poi: Vector3i = Vector3i(-9999, -9999, -9999)
var poi_manager = null  # POIManager reference, passée par WorldManager

const INVALID_POI = Vector3i(-9999, -9999, -9999)

# === Village Manager ===
var village_manager = null
var current_task: Dictionary = {}
var _mine_timer: float = 0.0
var _mine_target: Vector3i = INVALID_POS
var _build_timer: float = 0.0
var _task_status: String = ""  # texte affiché

# === Label3D au-dessus de la tête ===
var _head_label: Label3D = null
var _label_update_timer: float = 0.0

# === Cooldown pour éviter les scans coûteux en boucle ===
var _search_cooldown: float = 0.0
const SEARCH_COOLDOWN_DURATION = 5.0  # secondes avant de retenter une recherche

func setup(model_index: int, pos: Vector3, chunk_pos: Vector3i, prof: int = 0):
	mob_type_index = model_index
	_spawn_pos = pos
	chunk_position = chunk_pos
	profession = prof
	home_position = pos

func _ready():
	position = _spawn_pos
	_preload_models()
	_create_model()
	_create_collision()
	_create_head_label()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	_day_night = get_tree().get_first_node_in_group("day_night_cycle")
	village_manager = get_node_or_null("/root/VillageManager")

func _create_model():
	if mob_type_index < 0 or mob_type_index >= _model_scenes.size():
		return
	var model_instance = _model_scenes[mob_type_index].instantiate()
	model_instance.scale = Vector3(0.7, 0.7, 0.7)
	add_child(model_instance)
	_anim_player = _find_animation_player(model_instance)
	if _anim_player:
		_play_anim("idle")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _play_anim(anim_name: String):
	if not _anim_player or _current_anim == anim_name:
		return
	if _anim_player.has_animation(anim_name):
		var anim = _anim_player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(anim_name)
		_current_anim = anim_name

func _create_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.6, 1.7, 0.6)
	col.shape = shape
	col.position.y = 0.85
	add_child(col)

func _create_head_label():
	_head_label = Label3D.new()
	_head_label.font_size = 24
	_head_label.outline_size = 6
	_head_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_head_label.outline_modulate = Color(0, 0, 0, 0.8)
	_head_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_head_label.no_depth_test = true
	_head_label.position = Vector3(0, 2.3, 0)
	_head_label.text = ""
	add_child(_head_label)

func _update_head_label():
	if not _head_label:
		return
	var text = ""
	match current_activity:
		VProfession.Activity.WORK:
			if _task_status != "":
				text = _task_status
			else:
				text = "Au travail"
		VProfession.Activity.SLEEP:
			text = "Zzz..."
		VProfession.Activity.GO_HOME:
			text = "Rentre"
		VProfession.Activity.GATHER:
			text = "Balade"
		VProfession.Activity.WANDER:
			text = "Explore"
	_head_label.text = text

	# Couleur selon l'activité
	match current_activity:
		VProfession.Activity.WORK:
			_head_label.modulate = Color(1.0, 0.9, 0.3, 0.9)  # jaune
		VProfession.Activity.SLEEP:
			_head_label.modulate = Color(0.5, 0.5, 1.0, 0.7)  # bleu
		_:
			_head_label.modulate = Color(1.0, 1.0, 1.0, 0.8)  # blanc

# ============================================================
# PHYSICS PROCESS — dispatch par activité
# ============================================================

func _physics_process(delta):
	# Gravité
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# Vérifier le schedule toutes les 2 secondes
	_schedule_timer += delta
	if _schedule_timer >= 2.0:
		_schedule_timer = 0.0
		_update_schedule()

	# Mettre à jour le label au-dessus de la tête (toutes les 0.5s)
	_label_update_timer += delta
	if _label_update_timer >= 0.5:
		_label_update_timer = 0.0
		_update_head_label()

	# Dispatcher selon l'activité courante
	match current_activity:
		VProfession.Activity.WANDER:
			_behavior_wander(delta)
		VProfession.Activity.WORK:
			_behavior_work(delta)
		VProfession.Activity.GATHER:
			_behavior_gather(delta)
		VProfession.Activity.GO_HOME:
			_behavior_go_home(delta)
		VProfession.Activity.SLEEP:
			_behavior_sleep(delta)
		_:
			_behavior_wander(delta)

	move_and_slide()

# ============================================================
# SCHEDULE
# ============================================================

func _update_schedule():
	if not _day_night:
		return
	var hour = _day_night.get_hour()
	var new_activity = VProfession.get_activity_for_hour(hour)
	if new_activity != current_activity:
		_on_activity_changed(current_activity, new_activity)
		current_activity = new_activity

func _on_activity_changed(old_activity: int, new_activity: int):
	# Libérer le POI si on quitte le travail
	if old_activity == VProfession.Activity.WORK:
		if poi_manager and claimed_poi != INVALID_POI:
			poi_manager.release_poi(claimed_poi)
			claimed_poi = INVALID_POI
		# Retourner la tâche village non terminée
		if village_manager and not current_task.is_empty():
			if _mine_target != INVALID_POS:
				village_manager.release_position(_mine_target)
				_mine_target = INVALID_POS
			village_manager.return_task(current_task)
			current_task = {}
		_task_status = ""

	# Reset navigation
	has_target = false
	_arrived_at_target = false
	_target_stuck_timer = 0.0
	_detour_timer = 0.0
	_mine_timer = 0.0
	_build_timer = 0.0

	# Reprendre le wander timer
	if new_activity == VProfession.Activity.WANDER or new_activity == VProfession.Activity.GATHER:
		_pick_new_wander()

# ============================================================
# COMPORTEMENTS
# ============================================================

func _behavior_wander(delta):
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving:
		_apply_movement(delta)
		_play_anim("walk")
	else:
		_decelerate()
		_play_anim("idle")

func _behavior_sleep(_delta):
	# Rester immobile
	is_moving = false
	_decelerate()
	_play_anim("idle")

func _behavior_gather(delta):
	# Errer mais rester dans un rayon de 15 blocs autour de home
	var dist_to_home = Vector3(global_position.x, 0, global_position.z).distance_to(
		Vector3(home_position.x, 0, home_position.z))

	if dist_to_home > 15.0:
		# Trop loin, retourner vers home
		if _walk_toward(home_position, delta):
			_pick_new_wander()
			has_target = false
	else:
		# Errer normalement
		wander_timer -= delta
		if wander_timer <= 0:
			_pick_new_wander()
		if is_moving:
			_apply_movement(delta)
			_play_anim("walk")
		else:
			_decelerate()
			_play_anim("idle")

func _behavior_go_home(delta):
	if _walk_toward(home_position, delta):
		# Arrivé à la maison
		is_moving = false
		_decelerate()
		_play_anim("idle")

func _behavior_work(delta):
	# Si le VillageManager existe, utiliser le système de tâches village
	if village_manager:
		_behavior_village_work(delta)
		return

	# Fallback: ancien système POI
	if claimed_poi == INVALID_POI:
		if poi_manager:
			var nearest = poi_manager.find_nearest_unclaimed(profession, global_position)
			if nearest != INVALID_POI:
				if poi_manager.claim_poi(nearest, self):
					claimed_poi = nearest
					has_target = false
					_arrived_at_target = false
		if claimed_poi == INVALID_POI:
			_behavior_wander(delta)
			return

	var poi_world = Vector3(claimed_poi.x + 0.5, claimed_poi.y, claimed_poi.z + 0.5)

	if not _arrived_at_target:
		if _walk_toward(poi_world, delta):
			_arrived_at_target = true
		return

	var dir_to_poi = poi_world - global_position
	if dir_to_poi.length_squared() > 0.01:
		rotation.y = atan2(dir_to_poi.x, dir_to_poi.z)

	is_moving = false
	_decelerate()
	var work_anim = VProfession.get_work_anim(profession)
	_play_anim(work_anim)

# ============================================================
# VILLAGE WORK — exécution des tâches du VillageManager
# ============================================================

func _behavior_village_work(delta):
	# Cooldown après un scan qui n'a rien trouvé (évite les scans coûteux en boucle)
	if _search_cooldown > 0.0:
		_search_cooldown -= delta
		_behavior_wander(delta)
		return

	# Pas de tâche -> en demander une
	if current_task.is_empty():
		current_task = village_manager.get_next_task()
		if current_task.is_empty():
			_task_status = "Attend"
			_search_cooldown = 3.0  # attendre 3s avant de redemander
			_behavior_wander(delta)
			return
		# Log la prise de tâche
		var task_type = current_task.get("type", "?")
		print("PNJ[%d]: prend tâche '%s'" % [profession, task_type])
		# Reset navigation
		has_target = false
		_arrived_at_target = false
		_mine_timer = 0.0
		_mine_target = INVALID_POS

	# Dispatcher par type de tâche
	match current_task.get("type", ""):
		"harvest":
			_execute_harvest(delta)
		"mine":
			_execute_mine(delta)
		"mine_gallery":
			_execute_mine_gallery(delta)
		"craft":
			_execute_craft(delta)
		"place_workstation":
			_execute_place_workstation(delta)
		"build":
			_execute_build(delta)
		_:
			current_task = {}

func _execute_harvest(delta):
	# Trouver un arbre (avec zone d'exclusion pour disperser les villageois)
	if _mine_target == INVALID_POS:
		var block_type = current_task.get("target_block", 5)  # WOOD par défaut
		_mine_target = village_manager.find_nearest_block(block_type, global_position, 40.0, village_manager.HARVEST_EXCLUSION_RADIUS)
		if _mine_target == INVALID_POS:
			_task_status = "Cherche du bois..."
			village_manager.return_task(current_task)
			current_task = {}
			_search_cooldown = SEARCH_COOLDOWN_DURATION
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_mine_timer = 0.0

	# Marcher vers l'arbre
	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	_task_status = "[Hache] Bois"

	if not _arrived_at_target:
		var xz_dist = Vector2(global_position.x - target_world.x, global_position.z - target_world.z).length()
		if xz_dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	# Arrivé -> miner le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR:
		# Bloc déjà cassé
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		current_task = {}
		return

	_mine_timer += delta
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		# Casser le bloc
		village_manager.break_block(_mine_target)
		village_manager.add_resource(block_type)
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		print("PNJ[%d]: récolté bloc %d à %s" % [profession, block_type, str(_mine_target)])

		# Aussi casser les feuilles au-dessus (décorer l'arbre)
		_harvest_leaves_above(_mine_target)

		_mine_target = INVALID_POS
		_mine_timer = 0.0
		current_task = {}

func _harvest_leaves_above(trunk_pos: Vector3i):
	# Casser les feuilles connectées au tronc (simple: colonne au-dessus)
	var leaf_types = [6, 44, 45, 46, 47, 48, 49]  # LEAVES + variantes
	for dy in range(1, 8):
		var check_pos = Vector3i(trunk_pos.x, trunk_pos.y + dy, trunk_pos.z)
		var bt = world_manager.get_block_at_position(Vector3(check_pos.x, check_pos.y, check_pos.z))
		if bt in leaf_types:
			village_manager.break_block(check_pos)
		elif bt == BlockRegistry.BlockType.AIR:
			continue
		else:
			break

func _execute_mine(delta):
	# Miner un type de bloc spécifique (sable, pierre en surface, etc.)
	# Utilise la même logique directe que mine_gallery
	if _mine_target == INVALID_POS:
		var block_type = current_task.get("target_block", 3)
		_mine_target = village_manager.find_nearest_surface_block(block_type, global_position, 20.0)
		if _mine_target == INVALID_POS:
			_task_status = "Cherche..."
			village_manager.return_task(current_task)
			current_task = {}
			_search_cooldown = SEARCH_COOLDOWN_DURATION
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_mine_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	_task_status = "[Pioche] Mine"

	if not _arrived_at_target:
		var dist = global_position.distance_to(target_world)
		if dist < 3.0:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR:
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		current_task = {}
		return

	_mine_timer += delta
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		village_manager.break_block(_mine_target)
		village_manager.add_resource(block_type)
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		print("PNJ[%d]: miné surface bloc %d à %s" % [profession, block_type, str(_mine_target)])
		_mine_target = INVALID_POS
		_mine_timer = 0.0
		current_task = {}

func _execute_mine_gallery(delta):
	# Minage DIRECT — le mineur creuse les blocs autour de lui, sans plan ni galerie
	# Cherche le bloc solide le plus proche dans un rayon de 3 blocs
	if _mine_target == INVALID_POS:
		_mine_target = _find_minable_block_nearby()
		if _mine_target == INVALID_POS:
			_task_status = "[Pioche] Cherche..."
			# Pas de bloc minable à proximité — marcher un peu et réessayer
			_behavior_wander(delta)
			_mine_timer += delta
			if _mine_timer > 5.0:
				_mine_timer = 0.0
				current_task = {}
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = true  # Le bloc est juste à côté, pas besoin de marcher
		_mine_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	_task_status = "[Pioche] Mine"

	# Vérifier qu'on est assez proche (le bloc est à max 3 blocs)
	var dist = global_position.distance_to(target_world)
	if dist > 4.0:
		# Trop loin (on a bougé) — relâcher et chercher un nouveau bloc proche
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR:
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		return

	_mine_timer += delta
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		village_manager.break_block(_mine_target)
		village_manager.add_resource(block_type)
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		print("PNJ[%d]: miné bloc %d à %s" % [profession, block_type, str(_mine_target)])
		_mine_target = INVALID_POS
		_mine_timer = 0.0
		# Ne pas terminer la tâche — enchaîner avec le prochain bloc nearby

func _find_minable_block_nearby() -> Vector3i:
	# Cherche un bloc solide minable dans un rayon de 3 blocs autour du PNJ
	# Priorité : blocs au même niveau ou en dessous (creuser vers le bas)
	if not world_manager:
		return INVALID_POS
	var my_pos = Vector3i(int(round(global_position.x)), int(global_position.y), int(round(global_position.z)))
	var best = INVALID_POS
	var best_score = 999.0
	# Blocs non-minables (on ne veut pas casser l'eau, l'air, le bois, les feuilles)
	var skip_types = [0, 5, 6, 15, 32, 33, 34, 35, 36, 42, 44, 45, 46, 47, 48, 49]  # AIR, bois, feuilles, eau
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for dy in range(-2, 2):  # 2 blocs en dessous, 1 au-dessus
				var pos = Vector3i(my_pos.x + dx, my_pos.y + dy, my_pos.z + dz)
				if village_manager.claimed_positions.has(pos):
					continue
				var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
				if bt == BlockRegistry.BlockType.AIR or bt in skip_types:
					continue
				# Score : préfère les blocs proches et en dessous
				var dist = Vector3(dx, dy, dz).length()
				var depth_bonus = -dy * 0.5  # bonus pour creuser vers le bas
				var score = dist - depth_bonus
				if score < best_score:
					best_score = score
					best = pos
	return best

func _execute_craft(delta):
	var rname = current_task.get("recipe_name", "")
	_task_status = "[Craft] %s" % rname
	# Le craft est instantané (pas besoin de marcher)
	var recipe_name = current_task.get("recipe_name", "")
	if recipe_name == "":
		current_task = {}
		return

	# Animation brève de craft
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var success = village_manager.try_craft(recipe_name)
	if not success:
		# Pas assez de ressources, retourner la tâche
		village_manager.return_task(current_task)
	current_task = {}

func _execute_place_workstation(delta):
	var block_type = current_task.get("target_block", -1)
	if block_type < 0 or not village_manager.has_resources(block_type, 1):
		current_task = {}
		return

	_task_status = "[Place] Atelier"

	# Trouver un emplacement
	if not current_task.has("place_pos"):
		var spot = village_manager.find_flat_spot_near_center()
		if spot == INVALID_POS:
			village_manager.return_task(current_task)
			current_task = {}
			return
		current_task["place_pos"] = spot

	var place_pos = current_task["place_pos"]
	var target_world = Vector3(place_pos.x + 0.5, place_pos.y, place_pos.z + 0.5)

	# Marcher vers l'emplacement
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	# Placer le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	village_manager.consume_resources(block_type, 1)
	village_manager.place_workstation_at(block_type, place_pos)
	_show_harvest_label("Workstation!", place_pos)
	current_task = {}

func _execute_build(delta):
	_task_status = "[Marteau] Construction"
	var block_list = current_task.get("block_list", [])
	var block_index = current_task.get("block_index", 0)
	var origin = current_task.get("origin", Vector3i.ZERO)

	if block_index >= block_list.size():
		# Construction terminée
		var bp_index = current_task.get("blueprint_index", 0)
		if bp_index < village_manager.BLUEPRINTS.size():
			var bp = village_manager.BLUEPRINTS[bp_index]
			village_manager.register_built_structure(bp["name"], origin, bp["size"])
		current_task = {}
		return

	# Bloc courant à placer
	var block_data = block_list[block_index]
	var world_pos = Vector3i(
		origin.x + block_data[0],
		origin.y + block_data[1],
		origin.z + block_data[2]
	)
	var target_world = Vector3(world_pos.x + 0.5, world_pos.y, world_pos.z + 0.5)

	# Marcher vers la position de construction
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 3.0:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	# Placer le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta
	if _build_timer >= 0.8:
		_build_timer = 0.0
		village_manager.place_block(world_pos, block_data[3])
		current_task["block_index"] = block_index + 1
		_arrived_at_target = false  # Bouger vers le prochain bloc

func _face_target(target: Vector3):
	var dir = target - global_position
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z)

func _show_harvest_label(text: String, pos: Vector3i):
	var label = Label3D.new()
	label.text = text
	label.font_size = 32
	label.modulate = Color(0.2, 1.0, 0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(pos.x + 0.5, pos.y + 1.5, pos.z + 0.5)
	get_tree().current_scene.add_child(label)

	# Tween: monte et disparaît
	var tween = get_tree().create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.5, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ============================================================
# NAVIGATION VERS UNE CIBLE
# ============================================================

func _walk_toward(target: Vector3, delta: float) -> bool:
	var diff = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist = diff.length()

	# Arrivé
	if dist < 1.5:
		is_moving = false
		_total_stuck_time = 0.0
		_detour_count = 0
		return true

	# Téléportation de secours : bloqué depuis 12s+ → se téléporter près de la cible
	if _total_stuck_time > 12.0:
		var tp_pos = Vector3(target.x, target.y + 1, target.z)
		global_position = tp_pos
		_total_stuck_time = 0.0
		_detour_count = 0
		_detour_timer = 0.0
		is_moving = false
		return true

	# En détour (contournement d'obstacle)
	if _detour_timer > 0.0:
		_detour_timer -= delta
		wander_direction = _detour_direction
		is_moving = true
		_apply_movement(delta)
		_play_anim("walk")
		return false

	# Marcher vers la cible
	wander_direction = diff.normalized()
	is_moving = true
	_apply_movement(delta)
	_play_anim("walk")

	# Détection de blocage en mode cible
	_target_stuck_timer += delta
	if _target_stuck_timer >= 2.0:
		var moved_dist = global_position.distance_to(_last_pos)
		if moved_dist < 0.5:
			_total_stuck_time += 2.0
			_detour_count += 1
			# Détour perpendiculaire — alterne gauche/droite à chaque détour
			var perp = Vector3(-wander_direction.z, 0, wander_direction.x)
			if _detour_count % 2 == 0:
				perp = -perp
			_detour_direction = perp.normalized()
			_detour_timer = 1.5
		else:
			# On bouge — réduire le stuck time
			_total_stuck_time = maxf(0.0, _total_stuck_time - 1.0)
		_last_pos = global_position
		_target_stuck_timer = 0.0

	return false

# ============================================================
# MOUVEMENT COMMUN (auto-jump, évitement eau/falaises, stuck)
# ============================================================

func _apply_movement(delta):
	if is_on_floor() and world_manager:
		var feet_y = int(global_position.y)
		var ahead_pos = global_position + wander_direction * 0.8
		var ahead_feet = Vector3(ahead_pos.x, feet_y, ahead_pos.z)

		var block_at_feet = world_manager.get_block_at_position(ahead_feet.floor())
		var block_above = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y + 1, ahead_feet.z).floor())
		var block_below_ahead = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y - 1, ahead_feet.z).floor())

		# Éviter l'eau
		if block_at_feet == BlockRegistry.BlockType.WATER:
			_pick_new_wander()
			is_moving = false
			return
		# Éviter les falaises (2+ blocs de vide devant) — SEULEMENT en mode errance
		# En mode cible (travail), le villageois doit pouvoir descendre vers la mine/arbre
		elif not has_target and block_at_feet == BlockRegistry.BlockType.AIR and block_below_ahead == BlockRegistry.BlockType.AIR:
			_pick_new_wander()
			is_moving = false
			return
		# Auto-jump : bloc solide devant aux pieds + espace libre au-dessus
		elif block_at_feet != BlockRegistry.BlockType.AIR and block_above == BlockRegistry.BlockType.AIR:
			velocity.y = _jump_velocity

	# Mouvement horizontal
	velocity.x = wander_direction.x * move_speed
	velocity.z = wander_direction.z * move_speed

	# Rotation vers la direction de déplacement
	if wander_direction.length_squared() > 0.01:
		rotation.y = atan2(wander_direction.x, wander_direction.z)

	# Détection de blocage (wander classique, pas en mode cible)
	if not has_target:
		_stuck_timer += delta
		if _stuck_timer >= 1.0:
			var moved_dist = global_position.distance_to(_last_pos)
			if moved_dist < 0.3:
				_pick_new_wander()
			_last_pos = global_position
			_stuck_timer = 0.0

func _decelerate():
	velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
	velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
	_stuck_timer = 0.0

func _pick_new_wander():
	wander_timer = randf_range(3.0, 8.0)
	is_moving = randf() > 0.5
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()

# ============================================================
# INFO
# ============================================================

func take_hit(damage: int, knockback: Vector3 = Vector3.ZERO):
	health -= damage
	velocity += knockback
	if health <= 0:
		if claimed_poi != Vector3i(-9999, -9999, -9999) and poi_manager:
			poi_manager.release_poi(claimed_poi)
		if village_manager:
			if _mine_target != INVALID_POS:
				village_manager.release_position(_mine_target)
			if not current_task.is_empty():
				village_manager.return_task(current_task)
			village_manager.unregister_villager(self)
		queue_free()

func get_info_text() -> String:
	var prof_name = VProfession.get_profession_name(profession)
	# Si en mode village work, afficher la tâche en cours
	if village_manager and current_activity == VProfession.Activity.WORK and _task_status != "":
		return "%s - %s" % [prof_name, _task_status]
	var activity_names = {
		VProfession.Activity.WANDER: "Se promène",
		VProfession.Activity.WORK: "Au travail",
		VProfession.Activity.GATHER: "Socialise",
		VProfession.Activity.GO_HOME: "Rentre chez lui",
		VProfession.Activity.SLEEP: "Dort",
	}
	var activity_text = activity_names.get(current_activity, "")
	return "%s - %s" % [prof_name, activity_text]
