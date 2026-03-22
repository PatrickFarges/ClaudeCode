extends CharacterBody3D
class_name PassiveMob

# === MOB SYSTEM v3.0.0 ===
# Charge les donnees depuis data/mob_database.json
# Comportements : passive (fuit), neutral (attaque si provoque), hostile (attaque)
# Systemes : faim, brulure soleil, predation, pack behavior

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
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""
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

# Predator
var _prey_mobs: Array = []
var _hunt_timer: float = 0.0

# Special flags
var _neutral_day: bool = false
var _special_tags: Array = []

# Throttle
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.2
const ATTACK_RANGE = 2.0
const ATTACK_COOLDOWN_TIME = 1.0
const FLEE_DURATION = 5.0
const DESPAWN_DISTANCE = 80.0
const DESPAWN_CHECK_INTERVAL = 5.0
const HUNGER_CHECK_INTERVAL = 2.0
const SUN_DAMAGE_INTERVAL = 1.0
const SUN_DAMAGE = 1
const HUNT_CHECK_INTERVAL = 3.0
const HUNT_RANGE = 16.0
const EAT_DURATION = 2.0

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
	print("[MobSystem] Loaded %d mobs from database" % _mob_db.size())

static func _build_spawn_tables():
	"""Precalcule les tables de spawn par biome et heure."""
	BIOME_DAY_MOBS.clear()
	BIOME_NIGHT_MOBS.clear()
	for biome_id in range(4):  # 0=desert, 1=forest, 2=mountain, 3=plains
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
			if biome_id < 0 or biome_id > 3:
				continue
			if spawn_time == "day" or spawn_time == "both":
				if mob_id not in BIOME_DAY_MOBS[biome_id]:
					BIOME_DAY_MOBS[biome_id].append(mob_id)
			if spawn_time == "night" or spawn_time == "both":
				if mob_id not in BIOME_NIGHT_MOBS[biome_id]:
					BIOME_NIGHT_MOBS[biome_id].append(mob_id)

	# Debug print
	for b in range(4):
		var biome_names = ["desert", "forest", "mountain", "plains"]
		print("[MobSystem] %s — jour: %s | nuit: %s" % [
			biome_names[b],
			str(BIOME_DAY_MOBS[b]),
			str(BIOME_NIGHT_MOBS[b])
		])

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

	# Predator prey
	var hunger_prey = hunger_data.get("prey_mobs", [])
	_prey_mobs = hunger_prey if hunger_prey is Array else []

func _ready():
	position = _spawn_pos
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	add_to_group("passive_mobs")

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
			_anim_player = _find_animation_player(instance)
			if _anim_player:
				_play_anim("idle")
			return
	_create_colored_box()

static func _load_glb(path: String) -> PackedScene:
	if _glb_cache.has(path):
		return _glb_cache[path]
	var scene = load(path) as PackedScene
	if scene:
		_glb_cache[path] = scene
	return scene

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _play_anim(logical_name: String):
	if not _anim_player or _current_anim == logical_name:
		return
	if _anim_player.has_animation(logical_name):
		var anim = _anim_player.get_animation(logical_name)
		anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(logical_name)
		_current_anim = logical_name

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

	# Behavior-specific AI
	match _behavior:
		Behavior.PASSIVE:
			_ai_passive(delta)
		Behavior.NEUTRAL:
			_ai_neutral(delta)
		Behavior.HOSTILE:
			_ai_hostile(delta)

	move_and_slide()

# ── Sunburn ──

func _process_sunburn(delta):
	if not _is_daytime():
		return
	# Check if exposed to sky (no block above)
	if world_manager and _is_exposed_to_sky():
		_sun_damage_timer += delta
		if _sun_damage_timer >= SUN_DAMAGE_INTERVAL:
			_sun_damage_timer = 0.0
			health -= SUN_DAMAGE
			_flash_model_red()
			_hurt_flash_timer = 0.3
			# Visual: fire particles could be added here
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

	# Drain hunger
	_hunger -= _hunger_drain * HUNGER_CHECK_INTERVAL
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

	# Find and chase player
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group("player")

	if _target_player and is_instance_valid(_target_player):
		var dist = global_position.distance_to(_target_player.global_position)
		if dist < _aggro_range:
			_chase_player(delta)
			return

	_do_wander(delta)

func _do_wander(delta):
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving and is_on_floor():
		_nav_check_timer += delta
		if _nav_check_timer >= NAV_CHECK_INTERVAL:
			_nav_check_timer = 0.0
			if world_manager:
				var ahead_pos = global_position + wander_direction * 1.0
				var ahead_block = world_manager.get_block_at_position(ahead_pos.floor())
				var below_ahead = world_manager.get_block_at_position((ahead_pos - Vector3(0, 1, 0)).floor())
				if ahead_block == BlockRegistry.BlockType.WATER or below_ahead == BlockRegistry.BlockType.AIR:
					_pick_new_wander()
					is_moving = false

		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

		if wander_direction.length_squared() > 0.01:
			rotation.y = atan2(-wander_direction.x, -wander_direction.z)
		_play_anim("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		_play_anim("idle")

func _chase_player(delta):
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group("player")
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
		_play_anim("walk")

func _flee_from_player(delta):
	if not _target_player or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group("player")
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
	_play_anim("walk")

func _is_daytime() -> bool:
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		var hour = dnc.get_hour()
		return hour >= 6.0 and hour < 18.0
	return true

func _check_despawn():
	var player_node = get_tree().get_first_node_in_group("player")
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
	_target_player = get_tree().get_first_node_in_group("player")

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
	var player_node = get_tree().get_first_node_in_group("player")
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
	wander_timer = randf_range(2.0, 5.0)
	is_moving = randf() > 0.4
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
