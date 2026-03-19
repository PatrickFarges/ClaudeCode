extends CharacterBody3D
class_name PassiveMob

# === MOB SYSTEM v2.0.0 ===
# Supporte 15 mobs Minecraft Bedrock (GLB convertis par mob_converter.py)
# 3 comportements : passive (fuit), neutral (attaque si provoqué), hostile (attaque de nuit)

enum MobType {
	COW, PIG, SHEEP, CHICKEN, RABBIT, FOX, CAT, BAT,  # Passive
	WOLF, POLAR_BEAR, ENDERMAN,                         # Neutral
	ZOMBIE, SKELETON, CREEPER, SPIDER,                   # Hostile
}

enum Behavior { PASSIVE, NEUTRAL, HOSTILE }

# ── Données par mob ──
const MOB_DATA = {
	MobType.COW: {
		"name": "Vache", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.9, 1.4, 0.9),
		"health": 10, "meat_name": "Boeuf", "meat_count": 3,
		"glb_path": "res://assets/Mobs/Bedrock/cow.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.5, "attack_damage": 0,
		"biomes": [0, 1, 3],  # desert, forest, plains
	},
	MobType.PIG: {
		"name": "Cochon", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.9, 0.9, 0.9),
		"health": 10, "meat_name": "Porc", "meat_count": 3,
		"glb_path": "res://assets/Mobs/Bedrock/pig.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.5, "attack_damage": 0,
		"biomes": [1, 3],  # forest, plains
	},
	MobType.SHEEP: {
		"name": "Mouton", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.9, 1.3, 0.9),
		"health": 8, "meat_name": "Mouton", "meat_count": 2,
		"glb_path": "res://assets/Mobs/Bedrock/sheep.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.3, "attack_damage": 0,
		"biomes": [3],  # plains
	},
	MobType.CHICKEN: {
		"name": "Poulet", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.5, 0.7, 0.5),
		"health": 4, "meat_name": "Poulet", "meat_count": 1,
		"glb_path": "res://assets/Mobs/Bedrock/chicken.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.2, "attack_damage": 0,
		"biomes": [1, 3],  # forest, plains
	},
	MobType.RABBIT: {
		"name": "Lapin", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.4, 0.5, 0.4),
		"health": 3, "meat_name": "Lapin", "meat_count": 1,
		"glb_path": "res://assets/Mobs/Bedrock/rabbit.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 2.0, "attack_damage": 0,
		"biomes": [0, 3],  # desert, plains
	},
	MobType.FOX: {
		"name": "Renard", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.6, 0.7, 0.6),
		"health": 10, "meat_name": "Renard", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/fox.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.8, "attack_damage": 0,
		"biomes": [1],  # forest
	},
	MobType.CAT: {
		"name": "Chat", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.6, 0.7, 0.6),
		"health": 10, "meat_name": "Chat", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/cat.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.6, "attack_damage": 0,
		"biomes": [1, 3],  # forest, plains
	},
	MobType.BAT: {
		"name": "Chauve-souris", "behavior": Behavior.PASSIVE,
		"collision_size": Vector3(0.5, 0.5, 0.5),
		"health": 3, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/bat.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 2.5, "attack_damage": 0,
		"biomes": [0, 1, 2, 3],  # all biomes (caves)
		"night_only": true,
	},
	# ── Neutral ──
	MobType.WOLF: {
		"name": "Loup", "behavior": Behavior.NEUTRAL,
		"collision_size": Vector3(0.6, 0.85, 0.6),
		"health": 8, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/wolf.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 2.0, "attack_damage": 4,
		"biomes": [1],  # forest
	},
	MobType.POLAR_BEAR: {
		"name": "Ours polaire", "behavior": Behavior.NEUTRAL,
		"collision_size": Vector3(1.3, 1.4, 1.3),
		"health": 30, "meat_name": "Ours", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/polar_bear.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.8, "attack_damage": 6,
		"biomes": [2],  # mountain (cold)
		"day_spawn": true,  # Spawne de jour !
		"max_per_biome": 2,
	},
	MobType.ENDERMAN: {
		"name": "Enderman", "behavior": Behavior.NEUTRAL,
		"collision_size": Vector3(0.6, 2.9, 0.6),
		"health": 40, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/enderman.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 2.5, "attack_damage": 7,
		"biomes": [0, 1, 2, 3],  # all
	},
	# ── Hostile ──
	MobType.ZOMBIE: {
		"name": "Zombie", "behavior": Behavior.HOSTILE,
		"collision_size": Vector3(0.6, 1.95, 0.6),
		"health": 20, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/zombie.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.2, "attack_damage": 3,
		"biomes": [0, 1, 2, 3],  # all
	},
	MobType.SKELETON: {
		"name": "Squelette", "behavior": Behavior.HOSTILE,
		"collision_size": Vector3(0.6, 1.95, 0.6),
		"health": 20, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/skeleton.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.3, "attack_damage": 3,
		"biomes": [0, 1, 2, 3],  # all
	},
	MobType.CREEPER: {
		"name": "Creeper", "behavior": Behavior.HOSTILE,
		"collision_size": Vector3(0.6, 1.7, 0.6),
		"health": 20, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/creeper.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.0, "attack_damage": 8,  # explosion damage
		"biomes": [0, 1, 2, 3],  # all
	},
	MobType.SPIDER: {
		"name": "Araignee", "behavior": Behavior.HOSTILE,
		"collision_size": Vector3(1.4, 0.9, 1.4),
		"health": 16, "meat_name": "", "meat_count": 0,
		"glb_path": "res://assets/Mobs/Bedrock/spider.glb",
		"model_scale": Vector3(1.0, 1.0, 1.0),
		"move_speed": 1.6, "attack_damage": 2,
		"biomes": [0, 1, 2, 3],  # all
		"neutral_day": true,  # Hostile only at night, neutral during day
	},
}

# Mobs that spawn during day (passive + these specific ones)
const DAY_SPAWN_MOBS = [
	MobType.COW, MobType.PIG, MobType.SHEEP, MobType.CHICKEN,
	MobType.RABBIT, MobType.FOX, MobType.CAT, MobType.WOLF,
	MobType.POLAR_BEAR,
]

# Mobs per biome for spawning — biome IDs: 0=desert, 1=forest, 2=mountain, 3=plains
const BIOME_PASSIVE_MOBS = {
	0: [MobType.RABBIT],  # desert
	1: [MobType.COW, MobType.PIG, MobType.CHICKEN, MobType.FOX, MobType.CAT, MobType.WOLF],  # forest
	2: [MobType.SHEEP, MobType.POLAR_BEAR],  # mountain
	3: [MobType.COW, MobType.PIG, MobType.SHEEP, MobType.CHICKEN, MobType.RABBIT, MobType.CAT],  # plains
}

const BIOME_HOSTILE_MOBS = {
	0: [MobType.ZOMBIE, MobType.SKELETON, MobType.SPIDER, MobType.CREEPER, MobType.ENDERMAN],
	1: [MobType.ZOMBIE, MobType.SKELETON, MobType.SPIDER, MobType.CREEPER, MobType.ENDERMAN],
	2: [MobType.ZOMBIE, MobType.SKELETON, MobType.SPIDER, MobType.ENDERMAN],
	3: [MobType.ZOMBIE, MobType.SKELETON, MobType.SPIDER, MobType.CREEPER, MobType.ENDERMAN],
}

# ── GLB scene cache ──
static var _glb_cache: Dictionary = {}

# ── Instance vars ──
var mob_type: MobType = MobType.COW
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

var health: int = 10
var move_speed: float = 1.5
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
var _is_provoked: bool = false  # For neutral mobs
var _flee_timer: float = 0.0   # How long to flee after hit
var _target_player: CharacterBody3D = null
var _attack_cooldown: float = 0.0
var _aggro_range: float = 16.0  # Hostile detection range
var _flee_speed_mult: float = 1.5
var _despawn_timer: float = 0.0

# Throttle
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.2
const ATTACK_RANGE = 2.0
const ATTACK_COOLDOWN_TIME = 1.0
const FLEE_DURATION = 5.0
const DESPAWN_DISTANCE = 80.0
const DESPAWN_CHECK_INTERVAL = 5.0

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos
	var data = MOB_DATA[type]
	health = data["health"]
	move_speed = data["move_speed"]
	_behavior = data["behavior"]

func _ready():
	position = _spawn_pos
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	add_to_group("passive_mobs")

# ============================================================
#  MODEL CREATION — GLB Bedrock
# ============================================================

func _create_model():
	var data: Dictionary = MOB_DATA[mob_type]
	var glb_path: String = data.get("glb_path", "")

	if glb_path != "" and ResourceLoader.exists(glb_path):
		var scene = _load_glb(glb_path)
		if scene:
			var instance = scene.instantiate()
			var sc: Vector3 = data.get("model_scale", Vector3.ONE)
			instance.scale = sc
			add_child(instance)
			_model_root = instance
			_is_glb_model = true
			_anim_player = _find_animation_player(instance)
			if _anim_player:
				_play_anim("idle")
			return

	# Fallback: box coloree
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
	# Bedrock GLB animations are named directly: walk, idle, eat, attack
	if _anim_player.has_animation(logical_name):
		var anim = _anim_player.get_animation(logical_name)
		anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(logical_name)
		_current_anim = logical_name

func _create_colored_box():
	var data = MOB_DATA[mob_type]
	var size: Vector3 = data["collision_size"]
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
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["collision_size"]
	col.shape = shape
	col.position.y = data["collision_size"].y / 2.0
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

	# Despawn check (far from player)
	_despawn_timer += delta
	if _despawn_timer >= DESPAWN_CHECK_INTERVAL:
		_despawn_timer = 0.0
		_check_despawn()

	# Behavior-specific AI
	match _behavior:
		Behavior.PASSIVE:
			_ai_passive(delta)
		Behavior.NEUTRAL:
			_ai_neutral(delta)
		Behavior.HOSTILE:
			_ai_hostile(delta)

	move_and_slide()

func _ai_passive(delta):
	# Flee if recently hit
	if _flee_timer > 0:
		_flee_timer -= delta
		_flee_from_player(delta)
		return

	# Normal wander
	_do_wander(delta)

func _ai_neutral(delta):
	# If provoked, chase and attack
	if _is_provoked:
		_flee_timer -= delta
		if _flee_timer <= 0:
			_is_provoked = false
		_chase_player(delta)
		return

	# Normal wander
	_do_wander(delta)

func _ai_hostile(delta):
	# Spider is neutral during day
	var data = MOB_DATA[mob_type]
	if data.get("neutral_day", false):
		if _is_daytime() and not _is_provoked:
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

	# No target — wander
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
		# Attack!
		velocity.x = 0
		velocity.z = 0
		_play_anim("attack")
		if _attack_cooldown <= 0:
			_attack_cooldown = ATTACK_COOLDOWN_TIME
			var data = MOB_DATA[mob_type]
			var dmg = data["attack_damage"]
			if _target_player.has_method("take_damage"):
				var kb = to_player.normalized() * 5.0
				kb.y = 3.0
				_target_player.take_damage(dmg, kb)
		# Face player
		rotation.y = atan2(-to_player.x, -to_player.z)
	else:
		# Move toward player
		var dir = Vector3(to_player.x, 0, to_player.z).normalized()
		var chase_speed = move_speed * 1.3
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
	health -= damage
	velocity += knockback
	_hurt_flash_timer = 0.3
	_flash_model_red()
	_target_player = get_tree().get_first_node_in_group("player")

	match _behavior:
		Behavior.PASSIVE:
			# Flee!
			_flee_timer = FLEE_DURATION
		Behavior.NEUTRAL:
			# Fight back!
			_is_provoked = true
			_flee_timer = 10.0  # Stay angry for 10s

	if health <= 0:
		_drop_loot()
		queue_free()

func _drop_loot():
	var data = MOB_DATA[mob_type]
	var meat_count = data["meat_count"]
	if meat_count <= 0:
		return
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("heal"):
		var heal_amount = meat_count * 2
		player_node.heal(heal_amount)
		_spawn_loot_label(data["meat_name"], meat_count)

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
