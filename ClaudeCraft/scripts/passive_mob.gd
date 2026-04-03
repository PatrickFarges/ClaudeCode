extends CharacterBody3D
class_name PassiveMob

# === MOB SYSTEM v3.3.0 ===
# Charge les donnees depuis data/mob_database.json
# Comportements : passive (fuit), neutral (attaque si provoque), hostile (attaque)
# Systemes : faim, brulure soleil, predation, pack behavior

const GC = preload("res://scripts/game_config.gd")

enum Behavior { PASSIVE, NEUTRAL, HOSTILE }

# ── Base de donnees chargee depuis JSON ──
static var _mob_db: Dictionary = {}       # mob_id (String) -> data dict
static var _db_loaded: bool = false
static var _glb_cache: Dictionary = {}

# ── Tables de spawn precalculees (construites au chargement) ──
static var BIOME_DAY_MOBS: Dictionary = {}    # biome_id -> [mob_id, ...]
static var BIOME_NIGHT_MOBS: Dictionary = {}  # biome_id -> [mob_id, ...]

# ── Instance vars ──
var mob_id: String = "cow"
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO
var _data: Dictionary = {}  # reference directe dans _mob_db

var health: int = 10
var max_health: int = 10
var move_speed: float = 1.5
var attack_damage: int = 0
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null
var _model_root: Node3D = null
var _anim_player: AnimationPlayer = null  # Legacy
var _bedrock_anim: BedrockAnimPlayer = null  # Moteur d'animation Bedrock
var _current_anim: String = ""
var _total_distance_moved: float = 0.0
var _attack_anim_timer: float = -1.0
var _hurt_flash_timer: float = 0.0
var _is_glb_model: bool = false

# AI behavior
var _behavior: int = Behavior.PASSIVE
var _is_provoked: bool = false
var _flee_timer: float = 0.0
var _target_player: CharacterBody3D = null
var _target_prey: Node3D = null  # for predators
var _attack_cooldown: float = 0.0
var _aggro_range: float = 16.0
var _flee_speed_mult: float = 1.5
var _despawn_timer: float = 0.0
var _chase_persistence: float = 0.0  # Timer pour ne pas lâcher le joueur

# Head tracking
var _head_bone_idx: int = -1
var _head_base_transform: Transform3D = Transform3D.IDENTITY
var _head_track_angle: float = 0.0
var _head_random_target: float = 0.0   # Angle aléatoire quand pas de joueur
var _head_random_timer: float = 0.0    # Timer pour changer d'angle aléatoire

# Hunger system
var _hunger: float = 100.0
var _hunger_max: float = 100.0
var _hunger_drain: float = 0.0
var _hunger_timer: float = 0.0
var _eat_cooldown: float = 0.0
var _is_eating: bool = false
var _eat_progress: float = 0.0

# Sunburn
var _burns_in_sun: bool = false
var _sun_damage_timer: float = 0.0

# Pack attack — nearby same-type mobs also aggro
var _pack_behavior: bool = false
var _needs_water: bool = false

# Predator
var _prey_mobs: Array = []
var _hunt_timer: float = 0.0

# Special flags
var _neutral_day: bool = false
var _special_tags: Array = []

# Creeper explosion
var _is_creeper: bool = false
var _creeper_fuse_timer: float = -1.0  # -1 = not fusing
var _creeper_fuse_started: bool = false
var _creeper_flash_timer: float = 0.0
const CREEPER_FUSE_TIME = 1.5       # seconds before explosion
const CREEPER_FUSE_RANGE = 2.5      # start fuse at this distance
const CREEPER_CANCEL_RANGE = 5.0    # cancel fuse if player escapes
const CREEPER_BLAST_RADIUS = 3      # blocks in each direction (7x7x7)
const CREEPER_DAMAGE_RADIUS = 4.0   # damage range in blocks
const CREEPER_DAMAGE = 16           # max damage at center

# Skeleton archer
var _is_skeleton: bool = false
var _skeleton_shoot_timer: float = 0.0
var _skeleton_bow_node: Node3D = null
const SKELETON_SHOOT_INTERVAL = 2.5  # seconds between shots
const SKELETON_SHOOT_RANGE = 16.0    # max range
const SKELETON_MIN_RANGE = 4.0       # backs off if player too close

# Wall detection / stuck prevention
var _stuck_timer: float = 0.0
var _wall_jump_count: int = 0
var _last_xz_pos: Vector3 = Vector3.ZERO
var _consecutive_wanders: int = 0  # how many wander cycles without a rest
var _consecutive_stuck: int = 0    # compteur de stuck consécutifs → IDLE total après 3
var _truly_stuck: bool = false     # mob coincé sans issue → idle total jusqu'à despawn
var _mob_radius: float = 0.45     # demi-largeur collision, pour adapter la détection de mur
var _mob_height: float = 1.0      # hauteur collision

# Cached references (évite get_tree().get_first_node_in_group() chaque frame)
var _cached_player: Node = null
var _cached_dnc: Node = null
var _cached_skeleton: Skeleton3D = null

# Throttle
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.2
const ATTACK_RANGE = 2.0
const ATTACK_COOLDOWN_TIME = 1.0
const FLEE_DURATION = 5.0
const DESPAWN_DISTANCE = 64.0  # Despawn plus tôt pour libérer le cap
const DESPAWN_CHECK_INTERVAL = 5.0
const HUNGER_CHECK_INTERVAL = 2.0
const SUN_DAMAGE_INTERVAL = 1.0
const SUN_DAMAGE = 1
const HUNT_CHECK_INTERVAL = 3.0
const HUNT_RANGE = 16.0
const EAT_DURATION = 2.0
const STUCK_THRESHOLD = 0.15  # if moved less than this in 1s, we're stuck
const REST_MIN_DURATION = 4.0  # minimum idle rest between movement
const REST_MAX_DURATION = 12.0  # maximum idle rest between movement
const WANDER_CYCLES_BEFORE_REST = 2  # rest every N wander cycles

# ============================================================
#  DATABASE LOADING
# ============================================================

static func load_database():
	if _db_loaded:
		return
	_db_loaded = true
	var path = "res://data/mob_database.json"
	if not FileAccess.file_exists(path):
		push_error("mob_database.json not found!")
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		push_error("mob_database.json parse error: " + json.get_error_message())
		return
	var root = json.data
	if not root.has("mobs"):
		push_error("mob_database.json: missing 'mobs' key")
		return
	_mob_db = root["mobs"]
	_build_spawn_tables()
	#print("[MobSystem] Loaded %d mobs from database" % _mob_db.size())

static func _build_spawn_tables():
	"""Precalcule les tables de spawn par biome et heure."""
	BIOME_DAY_MOBS.clear()
	BIOME_NIGHT_MOBS.clear()
	for biome_id in range(7):  # 0=desert, 1=forest, 2=mountain, 3=plains, 4=ocean, 5=beach, 6=river
		BIOME_DAY_MOBS[biome_id] = []
		BIOME_NIGHT_MOBS[biome_id] = []

	for mob_id in _mob_db:
		var data: Dictionary = _mob_db[mob_id]
		# Skip mobs without a converted GLB
		var status = data.get("conversion_status", "")
		if status != "converted":
			continue
		var glb_path = data.get("glb_path", "")
		if glb_path == "":
			continue

		var biomes: Array = data.get("biomes", [])
		var spawn_time: String = data.get("spawn_time", "day")
		var special: Array = data.get("special", [])

		# Skip dimension-locked mobs (nether, end)
		if "nether_only" in special or "end_only" in special:
			continue

		for biome_id_raw in biomes:
			var biome_id: int = int(biome_id_raw)
			if biome_id < 0 or biome_id > 6:
				continue
			if spawn_time == "day" or spawn_time == "both":
				if mob_id not in BIOME_DAY_MOBS[biome_id]:
					BIOME_DAY_MOBS[biome_id].append(mob_id)
			if spawn_time == "night" or spawn_time == "both":
				if mob_id not in BIOME_NIGHT_MOBS[biome_id]:
					BIOME_NIGHT_MOBS[biome_id].append(mob_id)

	# Debug print
	for b in range(7):
		var biome_names = ["desert", "forest", "mountain", "plains", "ocean", "beach", "river"]
		#print("[MobSystem] %s — jour: %s | nuit: %s" % [
		#	biome_names[b],
		#	str(BIOME_DAY_MOBS[b]),
		#	str(BIOME_NIGHT_MOBS[b])
		#])

static func get_mob_data(id: String) -> Dictionary:
	load_database()
	return _mob_db.get(id, {})

static func get_all_converted_mob_ids() -> Array:
	load_database()
	var result = []
	for mob_id in _mob_db:
		if _mob_db[mob_id].get("conversion_status", "") == "converted":
			result.append(mob_id)
	return result

# ============================================================
#  SETUP
# ============================================================

func setup_from_id(id: String, pos: Vector3, chunk_pos: Vector3i):
	load_database()
	mob_id = id
	_spawn_pos = pos
	chunk_position = chunk_pos
	_data = _mob_db.get(id, {})
	if _data.is_empty():
		push_error("Unknown mob id: " + id)
		return

	max_health = int(_data.get("health", 10))
	health = max_health
	move_speed = float(_data.get("move_speed", 1.5))
	attack_damage = int(_data.get("attack_damage", 0))

	# Behavior
	var beh: String = _data.get("behavior", "passive")
	match beh:
		"passive": _behavior = Behavior.PASSIVE
		"neutral": _behavior = Behavior.NEUTRAL
		"hostile", "boss": _behavior = Behavior.HOSTILE

	# Hostile mobs detect player from farther away
	if _behavior == Behavior.HOSTILE:
		_aggro_range = 24.0
	elif _behavior == Behavior.NEUTRAL:
		_aggro_range = 16.0

	# Hunger
	var hunger_data: Dictionary = _data.get("hunger", {})
	_hunger_max = float(hunger_data.get("max", 0))
	_hunger = _hunger_max
	_hunger_drain = float(hunger_data.get("drain_per_second", 0))

	# Sunburn
	_burns_in_sun = _data.get("burns_in_sunlight", false)

	# Special flags
	_special_tags = _data.get("special", [])
	_neutral_day = "neutral_day" in _special_tags or "hostile_night" in _special_tags
	_pack_behavior = "pack_behavior" in _special_tags or "attack_pack" == _data.get("when_hit", "")
	_needs_water = "needs_water" in _special_tags

	# Predator prey
	var hunger_prey = hunger_data.get("prey_mobs", [])
	_prey_mobs = hunger_prey if hunger_prey is Array else []

	# Creeper / Skeleton detection
	_is_creeper = (mob_id == "creeper")
	_is_skeleton = (mob_id == "skeleton" or mob_id == "stray" or mob_id == "bogged")

	# Collision size for pathfinding
	var cs = _data.get("collision_size", [0.9, 1.0, 0.9])
	_mob_radius = max(cs[0], cs[2]) / 2.0  # demi-largeur
	_mob_height = cs[1]

func _ready():
	position = _spawn_pos
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	_cached_player = get_tree().get_first_node_in_group("player")
	_cached_dnc = get_tree().get_first_node_in_group("day_night_cycle")
	add_to_group("passive_mobs")
	if _is_skeleton:
		_attach_skeleton_bow()
	_init_head_tracking()
	# S'assurer que _process tourne APRÈS l'AnimationPlayer (priorité haute = plus tard)
	process_priority = 100

# ============================================================
#  MODEL CREATION
# ============================================================

func _create_model():
	var glb_path: String = _data.get("glb_path", "")
	if glb_path != "" and ResourceLoader.exists(glb_path):
		var scene = _load_glb(glb_path)
		if scene:
			var instance = scene.instantiate()
			var sc_arr: Array = _data.get("model_scale", [1.0, 1.0, 1.0])
			instance.scale = Vector3(sc_arr[0], sc_arr[1], sc_arr[2])
			add_child(instance)
			_model_root = instance
			_is_glb_model = true
			# Désactiver AnimationPlayer legacy, setup Bedrock
			_anim_player = NodeUtils.find_animation_player(instance)
			if _anim_player:
				_anim_player.active = false
			var skel := NodeUtils.find_skeleton(instance)
			if skel:
				_bedrock_anim = BedrockAnimPlayer.new()
				_bedrock_anim.name = "BedrockAnimPlayer"
				add_child(_bedrock_anim)
				_bedrock_anim.setup(skel)
				BedrockEntityLoader.configure_entity(_bedrock_anim, mob_id)
			return
	_create_colored_box()

static func _load_glb(path: String) -> PackedScene:
	if _glb_cache.has(path):
		return _glb_cache[path]
	var scene = load(path) as PackedScene
	if scene:
		_glb_cache[path] = scene
	return scene

func _play_anim(logical_name: String):
	if _current_anim == logical_name:
		return
	_current_anim = logical_name
	match logical_name:
		"attack", "attack2":
			_attack_anim_timer = 0.4
		"walk", "idle", "eat":
			pass  # Géré automatiquement par le move controller Bedrock

func _create_colored_box():
	var cs_arr: Array = _data.get("collision_size", [0.9, 1.0, 0.9])
	var size = Vector3(cs_arr[0], cs_arr[1], cs_arr[2])
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size * 0.9
	mesh_instance.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.4)
	mat.roughness = 0.8
	mesh_instance.material_override = mat
	mesh_instance.position.y = size.y / 2.0
	_model_root = mesh_instance
	add_child(mesh_instance)

func _create_collision():
	var cs_arr: Array = _data.get("collision_size", [0.9, 1.0, 0.9])
	var size = Vector3(cs_arr[0], cs_arr[1], cs_arr[2])
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y / 2.0
	add_child(col)

# ============================================================
#  PHYSICS + AI
# ============================================================

func _physics_process(delta):
	# ── Bedrock Animation Engine : feed movement data ──
	if _bedrock_anim:
		var horiz_vel := Vector3(velocity.x, 0, velocity.z)
		var horiz_speed := horiz_vel.length()
		_total_distance_moved += horiz_speed * delta
		_bedrock_anim.update_movement(delta, velocity, _total_distance_moved)
		if _attack_anim_timer >= 0.0:
			_attack_anim_timer -= delta
			var attack_progress := 1.0 - maxf(0.0, _attack_anim_timer) / 0.4
			_bedrock_anim.variables["attack_time"] = attack_progress * 0.7
		else:
			_bedrock_anim.variables["attack_time"] = -1.0
		_bedrock_anim.set_query("query.is_on_ground", 1.0 if is_on_floor() else 0.0)
		_bedrock_anim.set_query("query.modified_move_speed", horiz_speed)

	# Hurt flash
	if _hurt_flash_timer > 0:
		_hurt_flash_timer -= delta
		if _hurt_flash_timer <= 0:
			_reset_model_color()

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# Attack cooldown
	if _attack_cooldown > 0:
		_attack_cooldown -= delta

	# Despawn check
	_despawn_timer += delta
	if _despawn_timer >= DESPAWN_CHECK_INTERVAL:
		_despawn_timer = 0.0
		_check_despawn()

	# Sunburn
	if _burns_in_sun:
		_process_sunburn(delta)

	# Hunger
	if _hunger_max > 0:
		_process_hunger(delta)

	# Predator hunting
	if not _prey_mobs.is_empty() and _behavior != Behavior.HOSTILE:
		_process_hunting(delta)

	# Eating
	if _is_eating:
		_process_eating(delta)
		move_and_slide()
		return

	# Creeper fuse countdown (must tick even outside AI)
	if _is_creeper and _creeper_fuse_timer >= 0:
		_process_creeper_fuse(delta)

	# Behavior-specific AI
	match _behavior:
		Behavior.PASSIVE:
			_ai_passive(delta)
		Behavior.NEUTRAL:
			_ai_neutral(delta)
		Behavior.HOSTILE:
			_ai_hostile(delta)

	move_and_slide()

# Head tracking dans _process (s'exécute APRÈS les animations, sinon AnimationPlayer écrase la rotation)
func _process(delta):
	_update_head_tracking(delta)

# ── Sunburn ──

func _process_sunburn(delta):
	if not _is_daytime():
		return
	_sun_damage_timer += delta
	if _sun_damage_timer < SUN_DAMAGE_INTERVAL:
		return  # Throttle : check ciel seulement quand le dommage s'appliquerait
	_sun_damage_timer = 0.0
	# Check if exposed to sky (no block above)
	if world_manager and _is_exposed_to_sky():
		health -= SUN_DAMAGE
		_flash_model_red()
		_hurt_flash_timer = 0.3
		if health <= 0:
			_drop_loot()
			queue_free()

func _is_exposed_to_sky() -> bool:
	if not world_manager:
		return true
	var pos = global_position
	# Check a few blocks above for any solid block
	for dy in range(1, 15):
		var check_pos = Vector3(pos.x, pos.y + dy, pos.z).floor()
		var block = world_manager.get_block_at_position(check_pos)
		if block != 0 and block != BlockRegistry.BlockType.WATER:
			# Skip vegetation
			if block >= 98 and block <= 103:
				continue
			return false  # Under cover
	return true  # Open sky

# ── Hunger ──

func _process_hunger(delta):
	if _hunger_drain <= 0:
		return
	_hunger_timer += delta
	if _hunger_timer < HUNGER_CHECK_INTERVAL:
		return
	_hunger_timer = 0.0

	# Drain hunger — herbivores x30 pour manger ~1x/min, carnivores x1 (chassent rarement)
	var drain_mult = 30.0 if _prey_mobs.is_empty() else 1.0
	_hunger -= _hunger_drain * HUNGER_CHECK_INTERVAL * drain_mult
	_hunger = maxf(_hunger, 0.0)

	# Need to eat?
	if _hunger < _hunger_max * 0.3 and _eat_cooldown <= 0:
		_try_find_food()

	_eat_cooldown = maxf(_eat_cooldown - HUNGER_CHECK_INTERVAL, 0.0)

func _try_find_food():
	var hunger_data: Dictionary = _data.get("hunger", {})
	var food_source: String = hunger_data.get("food_source", "none")

	if food_source == "none":
		return

	if food_source == "prey":
		# Predators hunt — handled by _process_hunting
		return

	# Herbivores: look for food blocks nearby
	var food_blocks: Array = hunger_data.get("food_blocks", [])
	if food_blocks.is_empty():
		return

	if not world_manager:
		return

	# Scan nearby blocks for food
	var pos = global_position.floor()
	var best_food_pos: Vector3 = Vector3.ZERO
	var found = false
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for dy in range(-2, 3):
				var check = Vector3(pos.x + dx, pos.y + dy, pos.z + dz)
				var block = world_manager.get_block_at_position(check)
				if block == 0:
					continue
				if _is_food_block(block, food_blocks):
					best_food_pos = check + Vector3(0.5, 0, 0.5)
					found = true
					break
			if found:
				break
		if found:
			break

	if found:
		# Walk toward food
		var dir = (best_food_pos - global_position)
		dir.y = 0
		if dir.length() < 1.5:
			# Close enough — start eating
			_start_eating(best_food_pos)
		else:
			# Walk toward food
			wander_direction = dir.normalized()
			is_moving = true
			wander_timer = 3.0

func _is_food_block(block_type: int, food_blocks: Array) -> bool:
	"""Check if a block type matches a food block name from the database."""
	for fb_name in food_blocks:
		# Match block type enum names
		match fb_name:
			"GRASS_BLOCK":
				if block_type == BlockRegistry.BlockType.GRASS:
					return true
			"SHORT_GRASS":
				if block_type == BlockRegistry.BlockType.SHORT_GRASS:
					return true
			"FERN":
				if block_type == BlockRegistry.BlockType.FERN:
					return true
			"DANDELION":
				if block_type == BlockRegistry.BlockType.DANDELION:
					return true
			"POPPY":
				if block_type == BlockRegistry.BlockType.POPPY:
					return true
			"CORNFLOWER":
				if block_type == BlockRegistry.BlockType.CORNFLOWER:
					return true
			"WHEAT_STAGE_0":
				if block_type == BlockRegistry.BlockType.WHEAT_STAGE_0:
					return true
			"WHEAT_STAGE_3":
				if block_type == BlockRegistry.BlockType.WHEAT_STAGE_3:
					return true
			"FARMLAND":
				if block_type == BlockRegistry.BlockType.FARMLAND:
					return true
	return false

func _start_eating(food_pos: Vector3):
	_is_eating = true
	_eat_progress = 0.0
	velocity.x = 0
	velocity.z = 0
	# Face the food
	var dir = food_pos - global_position
	if dir.length_squared() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)
	# Play eat animation if available, otherwise idle
	if _anim_player and _anim_player.has_animation("eat"):
		_play_anim("eat")
	else:
		_play_anim("idle")

func _process_eating(delta):
	_eat_progress += delta
	if _eat_progress >= EAT_DURATION:
		_finish_eating()

func _finish_eating():
	_is_eating = false
	var hunger_data: Dictionary = _data.get("hunger", {})
	var satiation = float(hunger_data.get("satiation", 30))
	_hunger = minf(_hunger + satiation, _hunger_max)
	_eat_cooldown = 5.0  # Don't eat again for 5s

	# Remove the food block if eat_effect says so
	var eat_effect: String = hunger_data.get("eat_effect", "none")
	if eat_effect == "removes_block" and world_manager:
		var food_blocks: Array = hunger_data.get("food_blocks", [])
		# Find and remove the nearest food block
		var pos = global_position.floor()
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for dy in range(-1, 2):
					var check = Vector3(pos.x + dx, pos.y + dy, pos.z + dz)
					var block = world_manager.get_block_at_position(check)
					if block != 0 and _is_food_block(block, food_blocks):
						# Only eat vegetation (SHORT_GRASS, FERN, flowers), not GRASS_BLOCK
						if block >= 98 and block <= 103:
							world_manager.set_block_at_position(check, 0)
						elif block == BlockRegistry.BlockType.GRASS:
							# Turn grass block into dirt
							world_manager.set_block_at_position(check, BlockRegistry.BlockType.DIRT)
						return

# ── Predator Hunting ──

func _process_hunting(delta):
	_hunt_timer += delta
	if _hunt_timer < HUNT_CHECK_INTERVAL:
		return
	_hunt_timer = 0.0

	if _hunger > _hunger_max * 0.5:
		_target_prey = null
		return  # Not hungry enough to hunt

	# Find nearest prey mob
	if _target_prey and is_instance_valid(_target_prey):
		return  # Already hunting

	var nearest_dist = HUNT_RANGE
	var nearest_prey: Node3D = null
	for mob in get_tree().get_nodes_in_group("passive_mobs"):
		if mob == self or not is_instance_valid(mob):
			continue
		if mob is PassiveMob and mob.mob_id in _prey_mobs:
			var dist = global_position.distance_to(mob.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_prey = mob
	_target_prey = nearest_prey

# ── AI behaviors ──

func _ai_passive(delta):
	if _flee_timer > 0:
		_flee_timer -= delta
		_flee_from_player(delta)
		return
	_do_wander(delta)

func _ai_neutral(delta):
	if _is_provoked:
		_flee_timer -= delta
		if _flee_timer <= 0:
			_is_provoked = false
		_chase_player(delta)
		return

	# Hunting takes priority over wandering
	if _target_prey and is_instance_valid(_target_prey):
		_chase_prey(delta)
		return

	_do_wander(delta)

func _ai_hostile(delta):
	# Some hostile mobs are neutral during day (spider)
	if _neutral_day and _is_daytime() and not _is_provoked:
		_do_wander(delta)
		return

	# Find player
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = _cached_player

	if _target_player and is_instance_valid(_target_player):
		var dist = global_position.distance_to(_target_player.global_position)

		# Creeper: approach then explode
		if _is_creeper:
			_ai_creeper(delta, dist)
			return

		# Skeleton: ranged archer
		if _is_skeleton:
			_ai_skeleton(delta, dist)
			return

		if dist < _aggro_range:
			_chase_persistence = 30.0  # 30s de poursuite acharnée
			_chase_player(delta)
			return
		elif _chase_persistence > 0:
			# Hors de portée mais ne lâche pas encore
			_chase_persistence -= delta
			_chase_player(delta)
			return

	_do_wander(delta)

func _do_wander(delta):
	# Mobs aquatiques hors de l'eau → désespawn immédiat (comme MC)
	if _needs_water and world_manager:
		var feet_pos = Vector3(global_position.x, global_position.y - 0.5, global_position.z).floor()
		var block_at_feet = world_manager.get_block_at_position(feet_pos)
		if block_at_feet != BlockRegistry.BlockType.WATER:
			queue_free()
			return

	# Mob coincé sans issue → IDLE total (ne bouge plus, attend despawn faim)
	if _truly_stuck:
		velocity.x = 0
		velocity.z = 0
		_play_anim("idle")
		return

	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving and is_on_floor():
		# --- Stuck detection: if barely moved in 0.3s, we're against something ---
		_stuck_timer += delta
		if _stuck_timer >= 0.3:
			var moved_xz = Vector2(global_position.x - _last_xz_pos.x, global_position.z - _last_xz_pos.z).length()
			_last_xz_pos = global_position
			_stuck_timer = 0.0
			if moved_xz < STUCK_THRESHOLD:
				velocity.x = 0
				velocity.z = 0
				_consecutive_stuck += 1
				if _consecutive_stuck >= 4:
					# 4 stuck consécutifs → IDLE total, le mob est vraiment coincé
					_truly_stuck = true
					_play_anim("idle")
					return
				_force_idle_rest(1.0, 2.0)
				return
			else:
				# A bougé → reset du compteur stuck
				_consecutive_stuck = 0

		# --- Wall / cliff detection ahead ---
		_nav_check_timer += delta
		if _nav_check_timer >= NAV_CHECK_INTERVAL:
			_nav_check_timer = 0.0
			if world_manager and is_on_floor():
				# Adapter la distance de détection au rayon du mob
				var check_dist = max(_mob_radius + 0.5, 1.0)
				var ahead_pos = global_position + wander_direction * check_dist
				var feet_y = floori(global_position.y - 0.1)
				var b_at_feet = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y, ahead_pos.z).floor())
				var b_plus1 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 1, ahead_pos.z).floor())
				var b_plus2 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 2, ahead_pos.z).floor())
				var b_below = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y - 1, ahead_pos.z).floor())
				# Pour mobs hauts (cheval, etc.) vérifier aussi un bloc plus haut
				var b_plus3 = 0  # AIR
				if _mob_height > 1.5:
					b_plus3 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 3, ahead_pos.z).floor())

				# Eau devant → demi-tour
				if b_at_feet == BlockRegistry.BlockType.WATER:
					_force_idle_rest(2.0, 5.0)
					return

				# Falaise : pas de sol devant ni en dessous → demi-tour
				if _is_passable(b_at_feet) and _is_passable(b_below):
					_force_idle_rest(2.0, 5.0)
					return

				# Marche d'1 bloc : bloc solide à feet+1, espace libre au-dessus
				# Pour mobs grands, vérifier aussi b_plus3
				var can_step_up = _is_real_wall(b_plus1) and _is_passable(b_plus2)
				if can_step_up and _mob_height > 1.5:
					can_step_up = _is_passable(b_plus3)
				if can_step_up:
					global_position.y = feet_y + 1 + 1.05
					_wall_jump_count = 0
					_consecutive_stuck = 0  # A réussi à monter
				elif _is_real_wall(b_plus1):
					# Mur de 2+ blocs → demi-tour
					_wall_jump_count = 0
					_force_idle_rest(1.5, 3.0)
					return

		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

		if wander_direction.length_squared() > 0.01:
			rotation.y = atan2(-wander_direction.x, -wander_direction.z)
		_play_anim("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		_play_anim("idle")

func _is_vegetation(block: int) -> bool:
	"""Cross-mesh blocks that are not real walls."""
	return BlockRegistry.is_cross_mesh(block)

func _is_passable(block: int) -> bool:
	"""Blocks a mob can walk through (not real obstacles)."""
	if block == 0: return true  # AIR
	if block == BlockRegistry.BlockType.WATER: return true
	if BlockRegistry.is_cross_mesh(block): return true
	# Feuilles = traversables pour l'IA (pas de collision physique réelle pour les mobs)
	if block == BlockRegistry.BlockType.LEAVES: return true
	if block >= BlockRegistry.BlockType.SPRUCE_LEAVES and block <= BlockRegistry.BlockType.CHERRY_LEAVES: return true
	if block == BlockRegistry.BlockType.TORCH: return true
	if block == BlockRegistry.BlockType.LANTERN: return true
	return false

func _is_real_wall(block: int) -> bool:
	"""Block that is a real physical wall (not passable)."""
	return block != 0 and not _is_passable(block)

func _force_idle_rest(min_time: float, max_time: float):
	"""Stop moving, turn around away from obstacle, and rest idle."""
	is_moving = false
	velocity.x = 0
	velocity.z = 0
	# Demi-tour ~180° avec variance pour ne pas boucler
	var turn = PI + randf_range(-0.8, 0.8)
	rotation.y += turn
	wander_timer = randf_range(min_time, max_time)
	# Pré-charger la direction du prochain wander
	wander_direction = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	_stuck_timer = 0.0
	_last_xz_pos = global_position
	_play_anim("idle")

func _try_auto_jump(move_dir: Vector3):
	"""Step-up over 1-block walls when chasing/fleeing. Instant like MC."""
	if not is_on_floor() or not world_manager:
		return
	var check_dist = max(_mob_radius + 0.3, 0.8)
	var ahead_pos = global_position + move_dir * check_dist
	var feet_y = floori(global_position.y - 0.1)
	var b_plus1 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 1, ahead_pos.z).floor())
	var b_plus2 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 2, ahead_pos.z).floor())
	# Step-up instantané si mur d'1 bloc avec espace au-dessus
	var can_step = _is_real_wall(b_plus1) and _is_passable(b_plus2)
	# Mobs hauts : vérifier aussi b_plus3
	if can_step and _mob_height > 1.5:
		var b_plus3 = world_manager.get_block_at_position(Vector3(ahead_pos.x, feet_y + 3, ahead_pos.z).floor())
		can_step = _is_passable(b_plus3)
	if can_step:
		global_position.y = feet_y + 1 + 1.05

func _chase_player(delta):
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = _cached_player
		if not _target_player:
			_do_wander(delta)
			return

	var to_player = _target_player.global_position - global_position
	var dist = to_player.length()

	if dist < ATTACK_RANGE:
		velocity.x = 0
		velocity.z = 0
		_play_anim("attack")
		if _attack_cooldown <= 0:
			_attack_cooldown = ATTACK_COOLDOWN_TIME
			if _target_player.has_method("take_damage"):
				var kb = to_player.normalized() * 5.0
				kb.y = 3.0
				_target_player.take_damage(attack_damage, kb)
		rotation.y = atan2(-to_player.x, -to_player.z)
	else:
		var dir = Vector3(to_player.x, 0, to_player.z).normalized()
		var chase_speed = move_speed * 1.3
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		rotation.y = atan2(-dir.x, -dir.z)
		_try_auto_jump(dir)
		_play_anim("walk")

func _chase_prey(delta):
	"""Predator chasing prey mob."""
	if not _target_prey or not is_instance_valid(_target_prey):
		_target_prey = null
		return

	var to_prey = _target_prey.global_position - global_position
	var dist = to_prey.length()

	if dist > HUNT_RANGE * 1.5:
		_target_prey = null  # Too far, give up
		return

	if dist < ATTACK_RANGE:
		velocity.x = 0
		velocity.z = 0
		_play_anim("attack")
		if _attack_cooldown <= 0:
			_attack_cooldown = ATTACK_COOLDOWN_TIME
			if _target_prey is PassiveMob:
				_target_prey.take_hit(attack_damage if attack_damage > 0 else 4, to_prey.normalized() * 3.0)
				if not is_instance_valid(_target_prey) or _target_prey.health <= 0:
					# Prey killed — feed
					var hunger_data: Dictionary = _data.get("hunger", {})
					var satiation = float(hunger_data.get("satiation", 50))
					_hunger = minf(_hunger + satiation, _hunger_max)
					_target_prey = null
		rotation.y = atan2(-to_prey.x, -to_prey.z)
	else:
		var dir = Vector3(to_prey.x, 0, to_prey.z).normalized()
		var chase_speed = move_speed * 1.4
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		rotation.y = atan2(-dir.x, -dir.z)
		_try_auto_jump(dir)
		_play_anim("walk")

# ============================================================
#  CREEPER — Fuse + Explosion
# ============================================================
func _ai_creeper(delta, dist_to_player: float):
	if _creeper_fuse_timer >= 0:
		# Fusing: stop moving, face player
		velocity.x = 0; velocity.z = 0
		var to_p = _target_player.global_position - global_position
		rotation.y = atan2(-to_p.x, -to_p.z)
		# Cancel if player escaped
		if dist_to_player > CREEPER_CANCEL_RANGE:
			_creeper_fuse_timer = -1.0
			_creeper_fuse_started = false
			_reset_model_color()
		return

	# Approach player silently
	if dist_to_player < CREEPER_FUSE_RANGE:
		# Start fuse!
		_creeper_fuse_timer = 0.0
		_creeper_fuse_started = true
		velocity.x = 0; velocity.z = 0
		_play_fuse_sound()
	elif dist_to_player < _aggro_range:
		_chase_player(delta)
	else:
		_do_wander(delta)

func _process_creeper_fuse(delta):
	_creeper_fuse_timer += delta
	# Flash white increasingly fast
	_creeper_flash_timer += delta
	var flash_rate = lerpf(0.5, 0.1, _creeper_fuse_timer / CREEPER_FUSE_TIME)
	if _creeper_flash_timer >= flash_rate:
		_creeper_flash_timer = 0.0
		_flash_model_white()
		get_tree().create_timer(flash_rate * 0.5).timeout.connect(_reset_model_color)
	# Swell: scale up slightly
	if _model_root:
		var swell = lerpf(1.0, 1.3, _creeper_fuse_timer / CREEPER_FUSE_TIME)
		_model_root.scale = Vector3(swell, swell, swell)
	# BOOM
	if _creeper_fuse_timer >= CREEPER_FUSE_TIME:
		_creeper_explode()

func _creeper_explode():
	var center = global_position + Vector3(0, 1, 0)
	var wm = world_manager
	# Destroy blocks in 7x7x7 sphere
	if wm:
		var cx = floori(center.x); var cy = floori(center.y); var cz = floori(center.z)
		for bx in range(cx - CREEPER_BLAST_RADIUS, cx + CREEPER_BLAST_RADIUS + 1):
			for by in range(cy - CREEPER_BLAST_RADIUS, cy + CREEPER_BLAST_RADIUS + 1):
				for bz in range(cz - CREEPER_BLAST_RADIUS, cz + CREEPER_BLAST_RADIUS + 1):
					var dist_sq = (bx - cx) ** 2 + (by - cy) ** 2 + (bz - cz) ** 2
					if dist_sq > (CREEPER_BLAST_RADIUS + 0.5) ** 2:
						continue  # sphérique, pas cubique
					var pos = Vector3(bx, by, bz)
					var bt = wm.get_block_at_position(pos)
					if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and by > 1:
						wm.break_block_at_position(pos)
	# Damage entities
	_creeper_damage_entities(center)
	# Sound + particles
	_play_explosion_sound(center)
	_spawn_explosion_particles(center)
	# Die
	queue_free()

func _creeper_damage_entities(center: Vector3):
	# Damage player
	var player = _cached_player
	if player and is_instance_valid(player):
		var dist = player.global_position.distance_to(center)
		if dist < CREEPER_DAMAGE_RADIUS and player.has_method("take_damage"):
			var dmg_factor = 1.0 - (dist / CREEPER_DAMAGE_RADIUS)
			var dmg = ceili(CREEPER_DAMAGE * dmg_factor)
			var kb = (player.global_position - center).normalized() * 10.0
			kb.y = 5.0
			player.take_damage(dmg, kb)
	# Damage NPCs
	for npc in get_tree().get_nodes_in_group("npc_villagers"):
		if not is_instance_valid(npc): continue
		var dist = npc.global_position.distance_to(center)
		if dist < CREEPER_DAMAGE_RADIUS and npc.has_method("take_hit"):
			var dmg_factor = 1.0 - (dist / CREEPER_DAMAGE_RADIUS)
			npc.take_hit(ceili(CREEPER_DAMAGE * dmg_factor), (npc.global_position - center).normalized() * 8.0)
	# Damage other mobs
	for mob in get_tree().get_nodes_in_group("passive_mobs"):
		if mob == self or not is_instance_valid(mob): continue
		var dist = mob.global_position.distance_to(center)
		if dist < CREEPER_DAMAGE_RADIUS and mob.has_method("take_hit"):
			var dmg_factor = 1.0 - (dist / CREEPER_DAMAGE_RADIUS)
			mob.take_hit(ceili(CREEPER_DAMAGE * dmg_factor), (mob.global_position - center).normalized() * 8.0)

func _flash_model_white():
	if not _model_root: return
	for child in _model_root.get_children():
		if child is MeshInstance3D:
			var mi = child as MeshInstance3D
			for i in range(mi.get_surface_override_material_count()):
				var mat = mi.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					mat.albedo_color = Color(2, 2, 2, 1)

func _play_fuse_sound():
	var path = "res://assets/Audio/Minecraft/random/fuse.mp3"
	if FileAccess.file_exists(path):
		var stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		var asp = AudioStreamPlayer3D.new()
		asp.stream = stream; asp.max_distance = 32.0; asp.bus = "Master"
		add_child(asp); asp.play()
		asp.finished.connect(asp.queue_free)

func _play_explosion_sound(pos: Vector3):
	var idx = randi_range(1, 4)
	var path = "res://assets/Audio/Minecraft/random/explode%d.mp3" % idx
	if FileAccess.file_exists(path):
		var stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		var asp = AudioStreamPlayer3D.new()
		asp.stream = stream; asp.max_distance = 64.0; asp.bus = "Master"
		asp.position = pos
		get_tree().root.add_child(asp); asp.play()
		asp.finished.connect(asp.queue_free)

func _spawn_explosion_particles(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.amount = 60; particles.lifetime = 1.2; particles.one_shot = true
	particles.emitting = true
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0
	mat.direction = Vector3(0, 1, 0); mat.spread = 180.0
	mat.initial_velocity_min = 4.0; mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.3; mat.scale_max = 0.8
	mat.color = Color(1.0, 0.6, 0.2)
	particles.process_material = mat
	var mesh = SphereMesh.new(); mesh.radius = 0.15; mesh.height = 0.3
	particles.draw_pass_1 = mesh
	particles.position = pos
	get_tree().root.add_child(particles)
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)

# ============================================================
#  SKELETON — Ranged Bow Attack
# ============================================================
func _ai_skeleton(delta, dist_to_player: float):
	_skeleton_shoot_timer += delta

	if dist_to_player > _aggro_range:
		_do_wander(delta)
		return

	# Face the player
	var to_player = _target_player.global_position - global_position
	rotation.y = atan2(-to_player.x, -to_player.z)

	# Too close: back away while shooting
	if dist_to_player < SKELETON_MIN_RANGE:
		var away = -Vector3(to_player.x, 0, to_player.z).normalized()
		velocity.x = away.x * move_speed
		velocity.z = away.z * move_speed
		_play_anim("walk")
	elif dist_to_player <= SKELETON_SHOOT_RANGE:
		# In range: stop and shoot
		velocity.x = 0; velocity.z = 0
		_play_anim("attack")
	else:
		# Approach to get in range
		var dir = Vector3(to_player.x, 0, to_player.z).normalized()
		velocity.x = dir.x * move_speed * 1.2
		velocity.z = dir.z * move_speed * 1.2
		_try_auto_jump(dir)
		_play_anim("walk")
		return

	# Shoot if ready and in range
	if dist_to_player <= SKELETON_SHOOT_RANGE and _skeleton_shoot_timer >= SKELETON_SHOOT_INTERVAL:
		if _has_line_of_sight():
			_skeleton_shoot()
			_skeleton_shoot_timer = 0.0

func _has_line_of_sight() -> bool:
	if not world_manager or not _target_player: return false
	var from = global_position + Vector3(0, 1.5, 0)  # eye level
	var to = _target_player.global_position + Vector3(0, 1.0, 0)
	var dir = (to - from).normalized()
	var dist = from.distance_to(to)
	# Raywalk through blocks
	for i in range(int(dist * 2)):
		var t = i * 0.5
		if t > dist: break
		var check = from + dir * t
		var bt = world_manager.get_block_at_position(check)
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and not BlockRegistry.is_cross_mesh(bt):
			return false
	return true

func _skeleton_shoot():
	var ArrowScript = load("res://scripts/arrow_entity.gd")
	if not ArrowScript: return
	var arrow = ArrowScript.new()
	var from = global_position + Vector3(0, 1.4, 0)
	var target = _target_player.global_position + Vector3(0, 0.8, 0)  # chest height
	var to_target = target - from
	var dist = to_target.length()
	# Simple gravity compensation: slight upward aim proportional to distance
	var gravity_comp = dist * 0.04  # léger, pas excessif
	var aim_dir = (to_target + Vector3(0, gravity_comp, 0)).normalized()
	# Add slight inaccuracy
	aim_dir += Vector3(randf_range(-0.04, 0.04), randf_range(-0.02, 0.02), randf_range(-0.04, 0.04))
	aim_dir = aim_dir.normalized()
	get_tree().root.add_child(arrow)
	arrow.initialize(from, aim_dir, 0.8, self)  # 80% charge
	# Bow sound
	_play_bow_sound()
	# Animate bow pull (tween relative to base rotation)
	if _skeleton_bow_node:
		var base_rot = _skeleton_bow_node.rotation_degrees
		var tween = create_tween()
		tween.tween_property(_skeleton_bow_node, "rotation_degrees:x", base_rot.x - 25.0, 0.1)
		tween.tween_property(_skeleton_bow_node, "rotation_degrees:x", base_rot.x, 0.3)

func _play_bow_sound():
	var path = "res://assets/Audio/Minecraft/random/bow.mp3"
	if FileAccess.file_exists(path):
		var stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		var asp = AudioStreamPlayer3D.new()
		asp.stream = stream; asp.max_distance = 24.0; asp.bus = "Master"
		add_child(asp); asp.play()
		asp.finished.connect(asp.queue_free)

func _attach_skeleton_bow():
	if not _model_root: return
	var skeleton = NodeUtils.find_skeleton(_model_root)
	if not skeleton: return
	# Bedrock: bow attaches to leftItem bone (left hand holds the bow)
	var bone_name = "leftItem"
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		bone_name = "leftArm"
		bone_idx = skeleton.find_bone(bone_name)
	if bone_idx < 0: return
	var attachment = BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	# Build extruded bow mesh
	_skeleton_bow_node = Node3D.new()
	var bow_mesh = _build_bow_mesh()
	if bow_mesh:
		_skeleton_bow_node.add_child(bow_mesh)
		# Bedrock bow.geo.json: position [2, 1, -2] pixels, rotation [0, -135, 90]
		# Scale adapté à la résolution du pack (32x32 = 2x plus de pixels → diviser par 32)
		var tex_res = float(TextureManager.get_texture_resolution())
		_skeleton_bow_node.scale = Vector3(1.0, 1.0, 1.0) / tex_res
		# Position in bone-local space (Bedrock pixels -> blocks: /16, indépendant de la résolution)
		_skeleton_bow_node.position = Vector3(2.0, 1.0, -2.0) / 16.0
		# Bedrock rotation [0, -135, 90] = bow flat, angled diagonally in hand
		_skeleton_bow_node.rotation_degrees = Vector3(0, -135, 90)
	attachment.add_child(_skeleton_bow_node)

func _build_bow_mesh() -> MeshInstance3D:
	# Load bow texture and build extruded 3D mesh (vertex colors only, no texture tiling)
	var tex_path = GC.get_item_texture_path() + "bow_pulling_2.png"
	if not ResourceLoader.exists(tex_path) and not FileAccess.file_exists(tex_path):
		tex_path = GC.get_item_texture_path() + "bow.png"
	var img: Image = null
	# ResourceLoader pour compatibilité export
	var tex = ResourceLoader.load(tex_path) as Texture2D
	if tex:
		img = tex.get_image()
	else:
		img = Image.new()
		if img.load(tex_path) != OK: return null
	img.convert(Image.FORMAT_RGBA8)
	var w = img.get_width(); var h = img.get_height()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	# Pivot adapté à la résolution (Bedrock pivot [6,6] est pour 16x16)
	var scale_factor = float(w) / 16.0
	var pivot_x = 6.0 * scale_factor
	var pivot_y = 6.0 * scale_factor
	for py in range(h):
		for px in range(w):
			var c = img.get_pixel(px, py)
			if c.a < 0.5: continue
			var x0 = float(px) - pivot_x; var y0 = float(h - 1 - py) - pivot_y
			st.set_color(c)
			# Front face
			st.add_vertex(Vector3(x0, y0, 0.5))
			st.add_vertex(Vector3(x0 + 1, y0, 0.5))
			st.add_vertex(Vector3(x0 + 1, y0 + 1, 0.5))
			st.add_vertex(Vector3(x0, y0, 0.5))
			st.add_vertex(Vector3(x0 + 1, y0 + 1, 0.5))
			st.add_vertex(Vector3(x0, y0 + 1, 0.5))
			# Back face
			st.add_vertex(Vector3(x0 + 1, y0, -0.5))
			st.add_vertex(Vector3(x0, y0, -0.5))
			st.add_vertex(Vector3(x0, y0 + 1, -0.5))
			st.add_vertex(Vector3(x0 + 1, y0, -0.5))
			st.add_vertex(Vector3(x0, y0 + 1, -0.5))
			st.add_vertex(Vector3(x0 + 1, y0 + 1, -0.5))
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi

# ── Head Tracking ──
# Les mobs passifs/neutres tournent la tête vers le joueur quand il est proche

func _init_head_tracking():
	if not _model_root or not _is_glb_model:
		return
	_cached_skeleton = NodeUtils.find_skeleton(_model_root)
	var skel = _cached_skeleton
	if not skel:
		return
	# Essayer plusieurs noms de bone possibles
	for bone_name in ["head", "Head", "HEAD"]:
		_head_bone_idx = skel.find_bone(bone_name)
		if _head_bone_idx >= 0:
			_head_base_transform = skel.get_bone_pose(_head_bone_idx)
			return

func _update_head_tracking(delta: float):
	if _head_bone_idx < 0:
		return
	# Pas de head tracking pendant la fuite ou le combat
	if _flee_timer > 0 or _is_eating:
		return

	var skel = _cached_skeleton
	if not skel:
		return

	var target_angle: float = 0.0
	var tracking_player = false

	# Priorité 1 : regarder le joueur s'il est proche
	var player_node = _cached_player
	if player_node and is_instance_valid(player_node):
		var to_player = player_node.global_position - global_position
		var dist = to_player.length()
		if dist < 12.0 and dist > 1.0:
			var world_angle = atan2(-to_player.x, -to_player.z)
			var relative_angle = world_angle - rotation.y
			while relative_angle > PI: relative_angle -= TAU
			while relative_angle < -PI: relative_angle += TAU
			# ±20° max — subtil et naturel, pas l'Exorciste
			target_angle = clampf(relative_angle, -0.35, 0.35)
			tracking_player = true

	# Priorité 2 : mouvements aléatoires de la tête (curiosité naturelle)
	if not tracking_player:
		_head_random_timer -= delta
		if _head_random_timer <= 0:
			_head_random_timer = randf_range(2.0, 5.0)
			if randf() < 0.4:
				_head_random_target = 0.0
			else:
				_head_random_target = randf_range(-0.25, 0.25)  # ±15°
		target_angle = _head_random_target

	# Lerp doux vers l'angle cible (lent = naturel)
	_head_track_angle = lerp(_head_track_angle, target_angle, delta * 2.0)

	# Appliquer rotation depuis la pose de repos (pas la pose animée — évite accumulation)
	var rest_rot = _head_base_transform.basis
	if abs(_head_track_angle) > 0.005:
		var extra_rot = Basis(Vector3.UP, _head_track_angle)
		skel.set_bone_pose_rotation(_head_bone_idx, (rest_rot * extra_rot).get_rotation_quaternion())
	else:
		skel.set_bone_pose_rotation(_head_bone_idx, rest_rot.get_rotation_quaternion())

func _flee_from_player(delta):
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = _cached_player
	if not _target_player:
		_do_wander(delta)
		return

	var away_from = global_position - _target_player.global_position
	var dir = Vector3(away_from.x, 0, away_from.z).normalized()
	var flee_speed = move_speed * _flee_speed_mult

	velocity.x = dir.x * flee_speed
	velocity.z = dir.z * flee_speed
	if dir.length_squared() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)
	_try_auto_jump(dir)
	_play_anim("walk")

func _is_daytime() -> bool:
	if _cached_dnc:
		var hour = _cached_dnc.get_hour()
		return hour >= 6.0 and hour < 18.0
	return true

func _check_despawn():
	var player_node = _cached_player
	if player_node and is_instance_valid(player_node):
		var dist = global_position.distance_to(player_node.global_position)
		if dist > DESPAWN_DISTANCE:
			queue_free()

# ============================================================
#  DAMAGE & DEATH
# ============================================================

func take_hit(damage: int, knockback: Vector3 = Vector3.ZERO):
	# Weapon effectiveness multiplier
	# (simplified — full implementation would check player's held weapon)
	health -= damage
	velocity += knockback
	_hurt_flash_timer = 0.3
	_flash_model_red()
	_target_player = _cached_player

	var when_hit: String = _data.get("when_hit", "flee")
	match when_hit:
		"flee", "flee_ink":
			_flee_timer = FLEE_DURATION
		"attack", "attack_teleport":
			_is_provoked = true
			_flee_timer = 10.0
		"attack_pack", "attack_swarm":
			_is_provoked = true
			_flee_timer = 10.0
			_alert_pack()
		"attack_spit", "attack_ram":
			_is_provoked = true
			_flee_timer = 10.0

	if health <= 0:
		_drop_loot()
		queue_free()

func _alert_pack():
	"""Alert nearby same-type mobs to attack."""
	for mob in get_tree().get_nodes_in_group("passive_mobs"):
		if mob == self or not is_instance_valid(mob):
			continue
		if mob is PassiveMob and mob.mob_id == mob_id:
			var dist = global_position.distance_to(mob.global_position)
			if dist < 16.0:
				mob._is_provoked = true
				mob._flee_timer = 10.0
				mob._target_player = _target_player

func _drop_loot():
	var drops: Dictionary = _data.get("drops", {})
	if drops.is_empty():
		return
	# For now: heal player with first meat-like drop
	var player_node = _cached_player
	var total_food = 0
	var loot_name = ""
	for item_name in drops:
		var item = drops[item_name]
		var count = randi_range(int(item.get("min", 0)), int(item.get("max", 1)))
		if count > 0 and loot_name == "":
			loot_name = item_name
			total_food = count
	if total_food > 0:
		if player_node and player_node.has_method("heal"):
			player_node.heal(total_food * 2)
		_spawn_loot_label(_data.get("name_fr", mob_id), total_food)

func _spawn_loot_label(item_name: String, count: int):
	var label = Label3D.new()
	label.text = "+%d %s" % [count, item_name]
	label.font_size = 36
	label.outline_size = 6
	label.modulate = Color(0.3, 1.0, 0.3)
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	get_tree().root.add_child(label)
	label.global_position = global_position + Vector3(0, 2.0, 0)

	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", global_position + Vector3(0, 3.5, 0), 1.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.set_parallel(false)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)

func _flash_model_red():
	if _model_root:
		_apply_glb_tint(_model_root, Color(3.0, 0.3, 0.3))

func _reset_model_color():
	if _model_root:
		_apply_glb_tint(_model_root, Color(1, 1, 1))

func _apply_glb_tint(node: Node, color: Color):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat = mi.get_surface_override_material(i)
			if not mat:
				mat = mi.mesh.surface_get_material(i)
				if mat:
					mat = mat.duplicate()
					mi.set_surface_override_material(i, mat)
			if mat and mat is StandardMaterial3D:
				if color == Color(1, 1, 1):
					mat.emission_enabled = false
				else:
					mat.emission_enabled = true
					mat.emission = Color(1, 0, 0)
					mat.emission_energy_multiplier = 2.0
	for child in node.get_children():
		_apply_glb_tint(child, color)

func _pick_new_wander():
	_wall_jump_count = 0
	_consecutive_wanders += 1
	# Every few wander cycles, force a long rest (animals don't walk non-stop)
	if _consecutive_wanders >= WANDER_CYCLES_BEFORE_REST:
		_consecutive_wanders = 0
		is_moving = false
		wander_timer = randf_range(REST_MIN_DURATION, REST_MAX_DURATION)
		wander_direction = Vector3.ZERO
		_stuck_timer = 0.0
		_last_xz_pos = global_position
		return

	wander_timer = randf_range(3.0, 7.0)
	is_moving = randf() > 0.35
	if is_moving:
		# Si une direction a été pré-chargée par _force_idle_rest, l'utiliser
		if wander_direction.length_squared() > 0.5:
			pass  # Garder la direction du demi-tour
		else:
			var angle = randf() * TAU
			wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
		_last_xz_pos = global_position
		_stuck_timer = 0.0
	else:
		wander_direction = Vector3.ZERO
