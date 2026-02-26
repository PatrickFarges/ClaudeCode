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

# === Faim ===
var hunger: float = 100.0
const HUNGER_MAX = 100.0
const HUNGER_DRAIN_WORK = 0.0    # DÉSACTIVÉ — réactiver quand la ferme fonctionne (ancien: 0.06)
const HUNGER_DRAIN_REST = 0.0    # DÉSACTIVÉ — réactiver quand la ferme fonctionne (ancien: 0.01)
const HUNGER_THRESHOLD_EAT = 40.0
const HUNGER_THRESHOLD_SLOW = 20.0
const HUNGER_BREAD_RESTORE = 50.0
const HUNGER_WHEAT_RESTORE = 20.0
var _is_starving: bool = false  # à 0 de faim
var _base_move_speed: float = 2.0

# === Cooldown pour éviter les scans coûteux en boucle ===
var _search_cooldown: float = 0.0
const SEARCH_COOLDOWN_DURATION = 5.0  # secondes avant de retenter une recherche

# === Throttle navigation block lookups ===
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.15  # vérif obstacles toutes les 0.15s au lieu de chaque frame
var _cached_block_ahead: int = 0  # BlockType en cache
var _cached_block_below: int = 0
var _cached_block_above: int = 0
var _wall_impassable: bool = false  # mur 2+ blocs détecté devant

# === Retour surface mineur ===
var _mine_entry_pos: Vector3 = Vector3.ZERO
var _mine_resume_pos: Vector3 = Vector3.ZERO  # position sauvegardée pour reprendre le minage
var _returning_to_surface: bool = false
var _return_stuck_timer: float = 0.0

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
	_head_label.font_size = 20
	_head_label.outline_size = 5
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
	var prof_name = VProfession.get_profession_name(profession)
	var text = ""
	match current_activity:
		VProfession.Activity.WORK:
			if _task_status != "":
				text = prof_name + " - " + _task_status
			else:
				text = prof_name + " - Au travail"
		VProfession.Activity.SLEEP:
			text = prof_name + " - Zzz..."
		VProfession.Activity.GO_HOME:
			text = prof_name + " - Rentre"
		VProfession.Activity.GATHER:
			text = prof_name + " - Balade"
		VProfession.Activity.WANDER:
			text = prof_name + " - Explore"

	# Afficher la faim si critique
	if _is_starving:
		text = prof_name + " - Faim!"
	elif hunger < HUNGER_THRESHOLD_EAT:
		text += " (faim)"

	_head_label.text = text

	# Couleur selon l'activité + faim
	if _is_starving:
		_head_label.modulate = Color(1.0, 0.2, 0.2, 0.9)  # rouge
	elif hunger < HUNGER_THRESHOLD_EAT:
		_head_label.modulate = Color(1.0, 0.6, 0.2, 0.9)  # orange
	else:
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

	# === Retour surface mineur ===
	if _returning_to_surface:
		_behavior_return_to_surface(delta)
		move_and_slide()
		return

	# === Faim ===
	_update_hunger(delta)

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
# FAIM
# ============================================================

func _update_hunger(delta):
	# Drain de faim
	var drain = HUNGER_DRAIN_REST
	if current_activity == VProfession.Activity.WORK:
		drain = HUNGER_DRAIN_WORK
	hunger = maxf(0.0, hunger - drain * delta)

	# Ralentissement si très affamé
	if hunger < HUNGER_THRESHOLD_SLOW:
		move_speed = _base_move_speed * 0.5
	else:
		move_speed = _base_move_speed

	# Famine totale
	_is_starving = hunger <= 0.0

	# Tentative de manger pendant GATHER (12h-13h) ou quand la faim est basse
	if hunger < HUNGER_THRESHOLD_EAT and village_manager:
		_try_eat()

func _try_eat():
	if not village_manager:
		return
	# Essayer de manger du pain d'abord
	if village_manager.has_resources(BlockRegistry.BlockType.BREAD, 1):
		village_manager.consume_resources(BlockRegistry.BlockType.BREAD, 1)
		hunger = minf(HUNGER_MAX, hunger + HUNGER_BREAD_RESTORE)
		_show_harvest_label("Miam! +Pain", Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))
		return
	# Sinon manger du blé brut
	if village_manager.has_resources(BlockRegistry.BlockType.WHEAT_ITEM, 1):
		village_manager.consume_resources(BlockRegistry.BlockType.WHEAT_ITEM, 1)
		hunger = minf(HUNGER_MAX, hunger + HUNGER_WHEAT_RESTORE)
		_show_harvest_label("Miam! +Blé", Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))

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
		# Mineur souterrain : remonter à la surface au lieu de téléporter
		if village_manager and not current_task.is_empty():
			var task_type = current_task.get("type", "")
			if task_type == "mine_gallery" and _mine_entry_pos != Vector3.ZERO:
				# Sauvegarder la position pour y revenir après la balade
				_mine_resume_pos = global_position
				# Rendre la tâche et les positions
				if _mine_target != INVALID_POS:
					village_manager.release_position(_mine_target)
					_mine_target = INVALID_POS
				village_manager.return_task(current_task)
				current_task = {}
				_returning_to_surface = true
				_return_stuck_timer = 0.0
				_task_status = "Remonte..."
				# Ne pas reset la navigation — on va marcher vers _mine_entry_pos
				return
			# Retourner la tâche village non terminée (cas normal)
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
	_total_stuck_time = 0.0
	_detour_timer = 0.0
	_detour_count = 0
	_wall_impassable = false
	_mine_timer = 0.0
	_build_timer = 0.0
	_at_mine_entrance = false

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
	# Pause déjeuner (12h-13h) — essayer de manger
	if hunger < HUNGER_MAX and village_manager:
		_try_eat()

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
	# Si famine totale → arrêter de travailler
	if _is_starving:
		_task_status = "Faim!"
		is_moving = false
		_decelerate()
		_play_anim("idle")
		return

	# Cooldown après un scan qui n'a rien trouvé (évite les scans coûteux en boucle)
	if _search_cooldown > 0.0:
		_search_cooldown -= delta
		_behavior_wander(delta)
		return

	# Pas de tâche -> en demander une correspondant à notre profession
	if current_task.is_empty():
		current_task = village_manager.get_next_task_for(profession)
		if current_task.is_empty():
			_task_status = "Attend"
			_search_cooldown = 3.0  # attendre 3s avant de redemander
			_behavior_wander(delta)
			return
		# Log la prise de tâche
		var task_type = current_task.get("type", "?")
		var prof_name = VProfession.get_profession_name(profession)
		print("%s: prend tâche '%s'" % [prof_name, task_type])
		# Reset navigation
		has_target = false
		_arrived_at_target = false
		_mine_timer = 0.0
		_mine_target = INVALID_POS
		_mine_entry_pos = Vector3.ZERO
		_at_mine_entrance = false

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
		"build_path":
			_execute_build_path(delta)
		"farm_create":
			_execute_farm_create(delta)
		"farm_harvest":
			_execute_farm_harvest(delta)
		_:
			current_task = {}

func _execute_harvest(delta):
	# Trouver un tronc d'arbre à couper
	if _mine_target == INVALID_POS:
		# Cooldown pour éviter les scans coûteux chaque frame
		if _search_cooldown > 0.0:
			_search_cooldown -= delta
			_task_status = "Cherche du bois..."
			_behavior_wander(delta)
			return
		# D'abord chercher un tronc PROCHE (rayon 4 blocs, sans exclusion)
		var nearby = _find_nearest_trunk_around(global_position, 4.0)
		if nearby != INVALID_POS:
			_mine_target = nearby
		else:
			# Rien de proche — chercher plus loin avec le scan village
			_mine_target = village_manager.find_nearest_block(5, global_position, 40.0, 0.0)
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
	_task_status = "[%s] Bois" % village_manager.get_tool_tier_label("Hache")

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
		# Bloc déjà cassé — chercher un autre tronc à proximité immédiate
		village_manager.release_position(_mine_target)
		var next_trunk = _find_nearest_trunk_around(Vector3(_mine_target.x, _mine_target.y, _mine_target.z), 3.0)
		if next_trunk != INVALID_POS:
			_mine_target = next_trunk
			village_manager.claim_position(_mine_target)
			_mine_timer = 0.0
		else:
			_mine_target = INVALID_POS
			_arrived_at_target = false
			_mine_timer = 0.0
		return

	_mine_timer += delta
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		# Casser le bloc
		var last_pos = _mine_target
		village_manager.break_block(_mine_target)
		village_manager.add_resource(block_type)
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)

		# Chercher le prochain tronc à proximité (même arbre ou arbre voisin)
		var next_trunk = _find_nearest_trunk_around(Vector3(last_pos.x, last_pos.y, last_pos.z), 3.0)
		if next_trunk != INVALID_POS:
			_mine_target = next_trunk
			village_manager.claim_position(_mine_target)
			_arrived_at_target = false  # remarcher vers le nouveau tronc
			_mine_timer = 0.0
		else:
			# Plus aucun tronc autour — casser les feuilles et chercher plus loin
			_harvest_leaves_around(last_pos)
			_mine_target = INVALID_POS
			_arrived_at_target = false
			_mine_timer = 0.0

func _harvest_leaves_around(center_pos: Vector3i):
	# Casser les feuilles proches du tronc abattu (rayon 2, hauteur 8)
	# BATCHED : on set les blocs à AIR sans rebuild, puis rebuild 1 seule fois par chunk
	var leaf_set = { 6: true, 44: true, 45: true, 46: true, 47: true, 48: true, 49: true }
	var broken = 0
	var affected_chunks: Dictionary = {}  # chunk_key -> chunk_ref
	for dy in range(0, 8):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if broken >= 50:
					break
				var check_pos = Vector3i(center_pos.x + dx, center_pos.y + dy, center_pos.z + dz)
				var bt = world_manager.get_block_at_position(Vector3(check_pos.x, check_pos.y, check_pos.z))
				if leaf_set.has(bt):
					# Set block à AIR directement dans le chunk SANS rebuild
					var cx = int(floor(float(check_pos.x) / 16.0))
					var cz = int(floor(float(check_pos.z) / 16.0))
					var chunk_key = Vector2i(cx, cz)
					if world_manager.chunks.has(chunk_key):
						var chunk = world_manager.chunks[chunk_key]
						var lx = check_pos.x - cx * 16
						var lz = check_pos.z - cz * 16
						chunk.blocks[lx * 4096 + lz * 256 + check_pos.y] = 0  # AIR
						chunk.is_modified = true
						affected_chunks[chunk_key] = chunk
					# Feuilles = pas de ressource, juste nettoyage visuel
					broken += 1
	# Rebuild mesh UNE SEULE FOIS par chunk affecté
	for chunk in affected_chunks.values():
		chunk._rebuild_mesh()

func _find_nearest_trunk_around(from: Vector3, radius: float) -> Vector3i:
	# Cherche le tronc d'arbre le plus proche dans un rayon 3D
	# Optimisé : Dict lookup pour les types, early exit si trouvé à dist <= 1
	if not world_manager:
		return INVALID_POS
	var wood_set = { 5: true, 32: true, 33: true, 34: true, 35: true, 36: true, 42: true }
	var r = int(ceil(radius))
	var center = Vector3i(int(round(from.x)), int(from.y), int(round(from.z)))
	var best = INVALID_POS
	var best_dist = INF

	# Scan en spirale : d'abord les blocs proches (dy=0 d'abord, puis vers le haut)
	for dy in range(-1, 10):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var pos = Vector3i(center.x + dx, center.y + dy, center.z + dz)
				var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
				if wood_set.has(bt):
					if village_manager and village_manager.claimed_positions.has(pos):
						continue
					var d = from.distance_to(Vector3(pos.x, pos.y, pos.z))
					if d < best_dist:
						best_dist = d
						best = pos
						if d <= 1.5:
							return best  # early exit — tronc juste à côté

	return best

const MIN_MINE_DISTANCE_FROM_VILLAGE = 30.0  # ne pas miner à moins de 30 blocs du village

func _execute_mine(delta):
	# Miner un type de bloc spécifique (sable, pierre en surface, etc.)
	if _mine_target == INVALID_POS:
		var block_type = current_task.get("target_block", 3)
		# Chercher à partir d'un point éloigné du village center
		var search_from = global_position
		if village_manager:
			var to_center = Vector3(global_position.x - village_manager.village_center.x, 0,
				global_position.z - village_manager.village_center.z)
			var dist_to_center = to_center.length()
			if dist_to_center < MIN_MINE_DISTANCE_FROM_VILLAGE:
				# Trop près du village — se projeter à 30 blocs du centre
				var dir_away = to_center.normalized() if to_center.length() > 0.1 else Vector3(1, 0, 0)
				search_from = village_manager.village_center + dir_away * MIN_MINE_DISTANCE_FROM_VILLAGE
				search_from.y = global_position.y
		_mine_target = village_manager.find_nearest_surface_block(block_type, search_from, 20.0)
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
	_task_status = "[%s] Mine" % village_manager.get_tool_tier_label("Pioche")

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

var _at_mine_entrance: bool = false  # le mineur est arrivé à l'entrée de mine

func _execute_mine_gallery(delta):
	# MINAGE SÉQUENTIEL — suit le mine_plan pré-calculé par VillageManager.
	#
	# Le mine_plan est un Array de Vector3i ordonné de haut en bas.
	# Chaque marche = 4 blocs (2 colonnes × 2 hauteurs), puis descente de 1.
	# Les blocs sont toujours adjacents au PNJ car il les mine dans l'ordre.
	#
	# Flow simple :
	#   1. Marcher vers l'entrée de mine (30 blocs du village)
	#   2. Demander le prochain bloc au plan séquentiel
	#   3. Si le bloc est à portée (< 6 blocs) → miner
	#      Si le bloc est trop loin → marcher vers lui (horizontalement)
	#   4. Boucler

	# Mémoriser l'entrée de mine pour le retour surface le soir
	if _mine_entry_pos == Vector3.ZERO:
		if village_manager.mine_entrance != INVALID_POS:
			_mine_entry_pos = Vector3(village_manager.mine_entrance.x + 0.5, village_manager.mine_entrance.y + 1, village_manager.mine_entrance.z + 0.5)
		else:
			_mine_entry_pos = global_position

	_task_status = "[%s] Mine" % village_manager.get_tool_tier_label("Pioche")

	# Phase 1: Se rendre à la mine (resume_pos si dispo, sinon entrée)
	if not _at_mine_entrance:
		var walk_target = _mine_entry_pos
		if _mine_resume_pos != Vector3.ZERO:
			walk_target = _mine_resume_pos
		var dx = global_position.x - walk_target.x
		var dz = global_position.z - walk_target.z
		var dist_h = sqrt(dx * dx + dz * dz)
		if dist_h < 3.0:
			_at_mine_entrance = true
			_mine_resume_pos = Vector3.ZERO  # consommé
		else:
			_task_status = "[%s] Vers mine..." % village_manager.get_tool_tier_label("Pioche")
			# Mode berserker : casser TOUT sur le chemin (0 détour)
			_berserker_walk_toward(walk_target, delta)
			return

	# Phase 2: Obtenir le prochain bloc du plan de mine
	if _mine_target == INVALID_POS:
		_mine_target = village_manager.get_next_mine_block()
		if _mine_target == INVALID_POS:
			# Pas de bloc dispo — attendre au lieu d'abandonner
			_mine_timer += delta
			_task_status = "[%s] Mine: attente..." % village_manager.get_tool_tier_label("Pioche")
			if _mine_timer > 10.0:
				# Après 10s d'attente, rendre la tâche
				_task_status = "Mine OK"
				current_task = {}
				_mine_timer = 0.0
			return
		village_manager.claim_position(_mine_target)
		_mine_timer = 0.0

	# Phase 3: Se rapprocher du bloc si nécessaire
	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	var dx = global_position.x - target_world.x
	var dz = global_position.z - target_world.z
	var dist_h = sqrt(dx * dx + dz * dz)
	var dy = global_position.y - target_world.y  # positif = mineur AU-DESSUS du bloc

	if dy > 6.0 and dist_h > 3.0:
		# Mineur très au-dessus du bloc cible — il est en surface ou en haut de l'escalier.
		# D'abord aller à l'entrée de mine, puis descendre l'escalier naturellement.
		var entry_dx = global_position.x - _mine_entry_pos.x
		var entry_dz = global_position.z - _mine_entry_pos.z
		var entry_dist = sqrt(entry_dx * entry_dx + entry_dz * entry_dz)
		if entry_dist > 3.0:
			# Pas encore à l'entrée — y aller d'abord
			_task_status = "[%s] Vers mine..." % village_manager.get_tool_tier_label("Pioche")
			_berserker_walk_toward(_mine_entry_pos, delta)
		else:
			# À l'entrée — descendre vers le bloc cible via l'escalier
			_task_status = "[%s] Descend..." % village_manager.get_tool_tier_label("Pioche")
			_berserker_walk_toward(target_world, delta)
		_mine_timer += delta
		if _mine_timer > 45.0:
			print("Mineur: skip bloc trop profond à %s (dy=%.1f)" % [str(_mine_target), dy])
			village_manager.release_position(_mine_target)
			_mine_target = INVALID_POS
			_mine_timer = 0.0
		return

	if dist_h > 5.0:
		# Bloc trop loin horizontalement — berserker pour y aller
		_berserker_walk_toward(target_world, delta)
		_mine_timer += delta
		if _mine_timer > 30.0:
			print("Mineur: skip bloc inaccessible à %s (dist_h=%.1f)" % [str(_mine_target), dist_h])
			village_manager.release_position(_mine_target)
			_mine_target = INVALID_POS
			_mine_timer = 0.0
		return

	# Phase 4: Miner le bloc
	# Le bloc est à portée — on peut le miner même s'il est sous nos pieds ou devant
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR or block_type == BlockRegistry.BlockType.WATER:
		# Bloc déjà vide — passer au suivant
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		_mine_timer = 0.0
		return

	_mine_timer += delta
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		village_manager.break_block(_mine_target)
		village_manager.add_resource(block_type)
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		var prof_name = VProfession.get_profession_name(profession)
		print("%s: miné bloc %d à %s (y=%d)" % [prof_name, block_type, str(_mine_target), _mine_target.y])
		_mine_target = INVALID_POS
		_mine_timer = 0.0


func _execute_craft(delta):
	var recipe_name = current_task.get("recipe_name", "")
	if recipe_name == "":
		current_task = {}
		return
	_task_status = "[Craft] %s" % recipe_name

	# Si un workstation est placé (furnace ou crafting_table), marcher vers lui d'abord
	if not _arrived_at_target:
		var ws_pos = Vector3.ZERO
		var found_ws = false
		# Chercher la workstation du forgeron
		for ws_type in [21, 12, 22, 23, 24]:  # FURNACE, CRAFTING_TABLE, STONE/IRON/GOLD
			if village_manager.placed_workstations.has(ws_type):
				var pos = village_manager.placed_workstations[ws_type]
				ws_pos = Vector3(pos.x + 0.5, pos.y, pos.z + 0.5)
				found_ws = true
				break

		if found_ws:
			var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
				Vector3(ws_pos.x, 0, ws_pos.z))
			if dist > 2.5:
				_walk_toward(ws_pos, delta)
				return
		_arrived_at_target = true

	# Arrivé au workstation → animation + craft
	is_moving = false
	_decelerate()
	_play_anim("attack")

	# Petit délai de craft (1s)
	_mine_timer += delta
	if _mine_timer < 1.0:
		return
	_mine_timer = 0.0

	var success = village_manager.try_craft(recipe_name)
	if success:
		_show_harvest_label("[Craft] " + recipe_name, Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))
	else:
		village_manager.return_task(current_task)
	current_task = {}
	_arrived_at_target = false

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
	_task_status = "[%s] Construction" % village_manager.get_tool_tier_label("Marteau")
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

func _execute_build_path(delta):
	_task_status = "[%s] Construction" % village_manager.get_tool_tier_label("Marteau")

	# Récupérer le prochain bloc du chemin à poser
	if _mine_target == INVALID_POS:
		_mine_target = village_manager.get_next_path_block()
		if _mine_target == INVALID_POS:
			# Chemin terminé
			village_manager.mark_path_complete()
			current_task = {}
			return
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	# Marcher vers la position
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta
	if _build_timer >= 0.5:
		_build_timer = 0.0
		# Remplacer le bloc de surface par du cobblestone
		var BT_COBBLE = 25
		if village_manager.has_resources(BT_COBBLE, 1):
			village_manager.consume_resources(BT_COBBLE, 1)
			village_manager.place_block(_mine_target, BT_COBBLE)
			_show_harvest_label("Chemin", _mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		# Vérifier s'il reste des blocs
		if village_manager._path_index >= village_manager._path_blocks.size():
			village_manager.mark_path_complete()
			current_task = {}

func _execute_farm_create(delta):
	_task_status = "[%s] Laboure" % village_manager.get_tool_tier_label("Houe")

	# Trouver la prochaine parcelle à créer
	if _mine_target == INVALID_POS:
		_mine_target = village_manager.get_next_farm_plot_to_create()
		if _mine_target == INVALID_POS:
			# Ferme complète
			current_task = {}
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta
	if _build_timer >= 1.0:
		_build_timer = 0.0
		village_manager.create_farm_plot(_mine_target)
		village_manager.release_position(_mine_target)
		_show_harvest_label("Labouré", _mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		# Enchaîner avec la parcelle suivante
		var next = village_manager.get_next_farm_plot_to_create()
		if next == INVALID_POS:
			current_task = {}

func _execute_farm_harvest(delta):
	_task_status = "[Faucille] Récolte"

	if _mine_target == INVALID_POS:
		var plot = village_manager.get_mature_wheat_plot()
		if plot.is_empty():
			current_task = {}
			return
		_mine_target = plot["pos"]
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta
	if _build_timer >= 0.8:
		_build_timer = 0.0
		# Trouver le plot correspondant et le récolter
		for plot in village_manager.farm_plots:
			if plot["pos"] == _mine_target and plot["stage"] >= village_manager.WHEAT_MAX_STAGE:
				village_manager.harvest_wheat(plot)
				_show_harvest_label("+1 Blé", _mine_target)
				break
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		# Chercher un autre blé mature
		var next_plot = village_manager.get_mature_wheat_plot()
		if next_plot.is_empty():
			current_task = {}

func _behavior_return_to_surface(delta):
	_task_status = "Remonte..."
	_label_update_timer += delta
	if _label_update_timer >= 0.5:
		_label_update_timer = 0.0
		_update_head_label()

	# Marcher vers l'entrée de la mine (berserker — casse tout sur le passage)
	if _berserker_walk_toward(_mine_entry_pos, delta):
		# Arrivé en surface
		_returning_to_surface = false
		_mine_entry_pos = Vector3.ZERO
		_return_stuck_timer = 0.0
		_task_status = ""
		has_target = false
		_arrived_at_target = false
		_target_stuck_timer = 0.0
		_total_stuck_time = 0.0
		_detour_count = 0
		_pick_new_wander()
		return

	# Safety timeout : si bloqué > 8s → téléporter en surface
	_return_stuck_timer += delta
	if _return_stuck_timer > 8.0:
		global_position = _mine_entry_pos + Vector3(0, 1, 0)
		_returning_to_surface = false
		_mine_entry_pos = Vector3.ZERO
		_return_stuck_timer = 0.0
		_task_status = ""
		has_target = false
		_total_stuck_time = 0.0
		_detour_count = 0
		_pick_new_wander()

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
		_wall_impassable = false
		return true

	# Téléportation de secours : seuil relevé à 25s (dernier recours)
	if _total_stuck_time > 25.0:
		var tp_pos = Vector3(target.x, target.y + 1, target.z)
		global_position = tp_pos
		_total_stuck_time = 0.0
		_detour_count = 0
		_detour_timer = 0.0
		_wall_impassable = false
		is_moving = false
		return true

	# Après 7 détours sur harvest/mine : abandonner la cible
	if _detour_count >= 7 and not current_task.is_empty():
		var task_type = current_task.get("type", "")
		if task_type in ["harvest", "mine"]:
			_abandon_current_target()
			return false

	# Après 2 détours : casser le bloc devant pour passer (mode berserker)
	if _detour_count >= 2 and _detour_timer <= 0.0:
		if _try_break_path_block(diff.normalized()):
			_detour_count = 0
			_wall_impassable = false
			_detour_timer = 0.0

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

	# Détection immédiate de mur infranchissable → détour sans attendre
	if _wall_impassable:
		_total_stuck_time += delta * 3.0  # compte plus vite quand bloqué par un mur
		_start_smart_detour(diff.normalized())
		return false

	# Détection de blocage en mode cible
	_target_stuck_timer += delta
	if _target_stuck_timer >= 2.0:
		var moved_dist = global_position.distance_to(_last_pos)
		if moved_dist < 0.5:
			_total_stuck_time += 2.0
			_start_smart_detour(diff.normalized())
		else:
			# On bouge — réduire le stuck time et redonner du crédit
			_total_stuck_time = maxf(0.0, _total_stuck_time - 1.0)
			if moved_dist >= 0.5:
				_detour_count = maxi(0, _detour_count - 1)
		_last_pos = global_position
		_target_stuck_timer = 0.0

	return false

func _berserker_walk_toward(target: Vector3, delta: float) -> bool:
	# Walk vers la cible en mode berserker : casse IMMÉDIATEMENT tout bloc sur le chemin
	# Pas de détour, pas de patience — on fonce et on casse.
	var diff = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist = diff.length()

	if dist < 1.5:
		is_moving = false
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		return true

	# Téléportation de secours après 20s
	if _total_stuck_time > 20.0:
		global_position = Vector3(target.x, target.y + 1, target.z)
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		is_moving = false
		return true

	# Forcer le passage : casser les blocs devant immédiatement
	var toward = diff.normalized()
	_try_break_path_block(toward)

	# Marcher
	wander_direction = toward
	is_moving = true
	has_target = true
	_apply_movement(delta)
	_play_anim("walk")

	# Détection de blocage
	_target_stuck_timer += delta
	if _target_stuck_timer >= 1.5:
		var moved_dist = global_position.distance_to(_last_pos)
		if moved_dist < 0.3:
			_total_stuck_time += 1.5
			# Casser dans toutes les directions proches
			_try_break_path_block(toward)
			_try_break_path_block(Vector3(toward.z, 0, -toward.x))  # perpendiculaire
			_try_break_path_block(Vector3(-toward.z, 0, toward.x))
		else:
			_total_stuck_time = maxf(0.0, _total_stuck_time - 1.0)
		_last_pos = global_position
		_target_stuck_timer = 0.0

	return false

# ============================================================
# SMART DETOUR — contournement intelligent d'obstacles
# ============================================================

func _start_smart_detour(toward_target: Vector3):
	_wall_impassable = false
	_detour_count += 1
	var forward = toward_target.normalized()
	var perp_left = Vector3(-forward.z, 0, forward.x)
	var perp_right = Vector3(forward.z, 0, -forward.x)
	var back = -forward

	match _detour_count:
		1:
			_detour_direction = perp_left
			_detour_timer = 2.0
		2:
			_detour_direction = perp_right
			_detour_timer = 2.5
		3:
			_detour_direction = (perp_left + back).normalized()
			_detour_timer = 3.0
		4:
			_detour_direction = (perp_right + back).normalized()
			_detour_timer = 3.0
		5:
			_detour_direction = back
			_detour_timer = 3.5
		_:
			# Détour 6+ : direction aléatoire
			var angle = randf() * TAU
			_detour_direction = Vector3(cos(angle), 0, sin(angle))
			_detour_timer = 3.0

func _abandon_current_target():
	# Libérer la cible claimée
	if _mine_target != INVALID_POS and village_manager:
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS

	# Retourner la tâche dans la queue
	if not current_task.is_empty() and village_manager:
		village_manager.return_task(current_task)
		current_task = {}

	# Reset navigation
	has_target = false
	_arrived_at_target = false
	_target_stuck_timer = 0.0
	_total_stuck_time = 0.0
	_detour_timer = 0.0
	_detour_count = 0
	_wall_impassable = false
	_mine_timer = 0.0

	# Cooldown pour éviter de reprendre la même cible
	_search_cooldown = SEARCH_COOLDOWN_DURATION

	var prof_name = VProfession.get_profession_name(profession)
	print("%s: abandonne la cible (trop de détours)" % prof_name)

func _try_break_path_block(toward: Vector3) -> bool:
	# Casse les blocs devant le PNJ pour se frayer un passage
	# Ne casse PAS les blocs dans le périmètre des structures du village
	if not world_manager or not village_manager:
		return false

	var feet_y = int(global_position.y)
	var ahead_pos = global_position + toward * 1.0
	var block_pos_feet = Vector3i(int(round(ahead_pos.x)), feet_y, int(round(ahead_pos.z)))
	var block_pos_head = Vector3i(block_pos_feet.x, feet_y + 1, block_pos_feet.z)

	var broke_any = false

	# Casser le bloc aux pieds (si pas protégé)
	var bt_feet = world_manager.get_block_at_position(Vector3(block_pos_feet.x, block_pos_feet.y, block_pos_feet.z))
	if bt_feet != BlockRegistry.BlockType.AIR and bt_feet != BlockRegistry.BlockType.WATER:
		if not _is_in_village_structure(block_pos_feet):
			village_manager.break_block(block_pos_feet)
			village_manager.add_resource(bt_feet)
			broke_any = true

	# Casser le bloc à la tête (si pas protégé)
	var bt_head = world_manager.get_block_at_position(Vector3(block_pos_head.x, block_pos_head.y, block_pos_head.z))
	if bt_head != BlockRegistry.BlockType.AIR and bt_head != BlockRegistry.BlockType.WATER:
		if not _is_in_village_structure(block_pos_head):
			village_manager.break_block(block_pos_head)
			village_manager.add_resource(bt_head)
			broke_any = true

	if broke_any:
		_show_harvest_label("+Passage!", block_pos_feet)
		var prof_name = VProfession.get_profession_name(profession)
		print("%s: casse des blocs pour passer à %s" % [prof_name, str(block_pos_feet)])

	return broke_any

const SOFT_BLOCK_HARDNESS = 0.5  # seuil : casser immédiatement les blocs <= cette dureté

func _try_break_soft_blocks_ahead() -> bool:
	# Casse les blocs mous (feuilles, herbe, neige...) directement devant le PNJ
	# pour éviter des détours inutiles. Ne casse PAS les structures du village.
	if not world_manager or not village_manager:
		return false

	var feet_y = int(global_position.y)
	var ahead_pos = global_position + wander_direction * 0.8
	var block_pos_feet = Vector3i(int(round(ahead_pos.x)), feet_y, int(round(ahead_pos.z)))
	var block_pos_head = Vector3i(block_pos_feet.x, feet_y + 1, block_pos_feet.z)

	var broke_any = false

	# Bloc aux pieds
	var bt_feet = world_manager.get_block_at_position(Vector3(block_pos_feet.x, block_pos_feet.y, block_pos_feet.z))
	if bt_feet != BlockRegistry.BlockType.AIR and bt_feet != BlockRegistry.BlockType.WATER:
		var hardness = BlockRegistry.get_block_hardness(bt_feet as BlockRegistry.BlockType)
		if hardness <= SOFT_BLOCK_HARDNESS and not _is_in_village_structure(block_pos_feet):
			village_manager.break_block(block_pos_feet)
			village_manager.add_resource(bt_feet)
			broke_any = true

	# Bloc à la tête
	var bt_head = world_manager.get_block_at_position(Vector3(block_pos_head.x, block_pos_head.y, block_pos_head.z))
	if bt_head != BlockRegistry.BlockType.AIR and bt_head != BlockRegistry.BlockType.WATER:
		var hardness = BlockRegistry.get_block_hardness(bt_head as BlockRegistry.BlockType)
		if hardness <= SOFT_BLOCK_HARDNESS and not _is_in_village_structure(block_pos_head):
			village_manager.break_block(block_pos_head)
			village_manager.add_resource(bt_head)
			broke_any = true

	return broke_any

func _is_in_village_structure(pos: Vector3i) -> bool:
	# Vérifie si une position est dans le périmètre d'une structure construite
	if not village_manager:
		return false
	for built in village_manager.built_structures:
		var bo = built["origin"]
		var bs = built["size"]
		# Marge de 1 bloc autour des structures
		if pos.x >= bo.x - 1 and pos.x < bo.x + bs.x + 1 \
			and pos.y >= bo.y - 1 and pos.y < bo.y + bs.y + 1 \
			and pos.z >= bo.z - 1 and pos.z < bo.z + bs.z + 1:
			return true
	# Aussi protéger les workstations placées
	for ws_type in village_manager.placed_workstations:
		var ws_pos = village_manager.placed_workstations[ws_type]
		if pos == ws_pos or pos == Vector3i(ws_pos.x, ws_pos.y + 1, ws_pos.z):
			return true
	return false

# ============================================================
# MOUVEMENT COMMUN (auto-jump, évitement eau/falaises, stuck)
# ============================================================

func _apply_movement(delta):
	if is_on_floor() and world_manager:
		# Throttle block lookups : toutes les 0.15s au lieu de chaque frame
		_nav_check_timer += delta
		if _nav_check_timer >= NAV_CHECK_INTERVAL:
			_nav_check_timer = 0.0
			_wall_impassable = false  # reset avant re-check
			var feet_y = int(global_position.y)
			var ahead_pos = global_position + wander_direction * 0.8
			var ahead_feet = Vector3(ahead_pos.x, feet_y, ahead_pos.z)
			_cached_block_ahead = world_manager.get_block_at_position(ahead_feet.floor())
			_cached_block_above = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y + 1, ahead_feet.z).floor())
			_cached_block_below = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y - 1, ahead_feet.z).floor())

		# Utiliser les valeurs en cache
		if _cached_block_ahead == BlockRegistry.BlockType.WATER:
			_pick_new_wander()
			is_moving = false
			return
		elif not has_target and _cached_block_ahead == BlockRegistry.BlockType.AIR and _cached_block_below == BlockRegistry.BlockType.AIR:
			_pick_new_wander()
			is_moving = false
			return
		elif _cached_block_ahead != BlockRegistry.BlockType.AIR:
			if _cached_block_above == BlockRegistry.BlockType.AIR:
				# Bloc simple devant — sauter par-dessus
				velocity.y = _jump_velocity
				_wall_impassable = false
			else:
				# Mur de 2+ blocs — casser pour passer (tout bloc, pas juste mous)
				if has_target and _try_break_path_block(wander_direction):
					_wall_impassable = false  # passage dégagé
				elif has_target and _try_break_soft_blocks_ahead():
					_wall_impassable = false
				else:
					_wall_impassable = true

	# Mouvement horizontal — arrêter si mur infranchissable
	if _wall_impassable:
		velocity.x = 0
		velocity.z = 0
	else:
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
