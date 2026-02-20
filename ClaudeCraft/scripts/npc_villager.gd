extends CharacterBody3D
class_name NpcVillager

const VProfession = preload("res://scripts/villager_profession.gd")

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
var _detour_timer: float = 0.0
var _detour_direction: Vector3 = Vector3.ZERO

# === POI / Travail ===
var claimed_poi: Vector3i = Vector3i(-9999, -9999, -9999)
var poi_manager = null  # POIManager reference, passée par WorldManager

const INVALID_POI = Vector3i(-9999, -9999, -9999)

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
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	_day_night = get_tree().get_first_node_in_group("day_night_cycle")

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

	# Reset navigation
	has_target = false
	_arrived_at_target = false
	_target_stuck_timer = 0.0
	_detour_timer = 0.0

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
	# 1. Pas de POI claimé -> en chercher un
	if claimed_poi == INVALID_POI:
		if poi_manager:
			var nearest = poi_manager.find_nearest_unclaimed(profession, global_position)
			if nearest != INVALID_POI:
				if poi_manager.claim_poi(nearest, self):
					claimed_poi = nearest
					has_target = false
					_arrived_at_target = false
		# Pas de POI trouvé -> fallback wander
		if claimed_poi == INVALID_POI:
			_behavior_wander(delta)
			return

	# 2. POI claimé mais pas arrivé -> marcher vers le POI
	var poi_world = Vector3(claimed_poi.x + 0.5, claimed_poi.y, claimed_poi.z + 0.5)

	if not _arrived_at_target:
		if _walk_toward(poi_world, delta):
			_arrived_at_target = true
		return

	# 3. Arrivé au POI -> travailler
	# Faire face au bloc
	var dir_to_poi = poi_world - global_position
	if dir_to_poi.length_squared() > 0.01:
		rotation.y = atan2(dir_to_poi.x, dir_to_poi.z)

	is_moving = false
	_decelerate()
	var work_anim = VProfession.get_work_anim(profession)
	_play_anim(work_anim)

# ============================================================
# NAVIGATION VERS UNE CIBLE
# ============================================================

func _walk_toward(target: Vector3, delta: float) -> bool:
	var diff = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist = diff.length()

	# Arrivé
	if dist < 1.5:
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
			# Bloqué -> dévier perpendiculairement pendant 2s
			var perp = Vector3(-wander_direction.z, 0, wander_direction.x)
			if randf() > 0.5:
				perp = -perp
			_detour_direction = perp.normalized()
			_detour_timer = 2.0
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
		# Éviter les falaises (2+ blocs de vide devant)
		elif block_at_feet == BlockRegistry.BlockType.AIR and block_below_ahead == BlockRegistry.BlockType.AIR:
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
		queue_free()

func get_info_text() -> String:
	var prof_name = VProfession.get_profession_name(profession)
	var activity_names = {
		VProfession.Activity.WANDER: "Se promène",
		VProfession.Activity.WORK: "Au travail",
		VProfession.Activity.GATHER: "Socialise",
		VProfession.Activity.GO_HOME: "Rentre chez lui",
		VProfession.Activity.SLEEP: "Dort",
	}
	var activity_text = activity_names.get(current_activity, "")
	return "%s - %s" % [prof_name, activity_text]
