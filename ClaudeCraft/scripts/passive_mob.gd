extends CharacterBody3D
class_name PassiveMob

enum MobType { SHEEP, COW, CHICKEN }

const MOB_DATA = {
	MobType.SHEEP: {
		"collision_size": Vector3(0.9, 1.0, 0.9),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_sheep.glb",
		"model_scale": Vector3(0.012, 0.012, 0.012),
	},
	MobType.COW: {
		"collision_size": Vector3(0.9, 1.1, 0.9),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_cow.glb",
		"model_scale": Vector3(0.012, 0.012, 0.012),
	},
	MobType.CHICKEN: {
		"collision_size": Vector3(0.5, 0.6, 0.5),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_chicken.glb",
		"model_scale": Vector3(0.008, 0.008, 0.008),
	},
}

static var _model_scenes: Dictionary = {}

static func _preload_models():
	if _model_scenes.size() > 0:
		return
	for mob_type_key in MOB_DATA:
		var path = MOB_DATA[mob_type_key]["model_path"]
		var scene = load(path) as PackedScene
		if scene:
			_model_scenes[mob_type_key] = scene
		else:
			push_warning("[PassiveMob] Impossible de charger: " + path)

var mob_type: MobType = MobType.SHEEP
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

var move_speed: float = 1.5
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null  # WorldManager (non typé pour éviter dépendance circulaire)
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos

func _ready():
	position = _spawn_pos
	_preload_models()
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")

func _create_model():
	if not _model_scenes.has(mob_type):
		# Fallback BoxMesh si le GLB n'a pas pu être chargé
		_create_fallback_mesh()
		return
	var model_instance = _model_scenes[mob_type].instantiate()
	var data = MOB_DATA[mob_type]
	model_instance.scale = data["model_scale"]
	add_child(model_instance)
	_anim_player = _find_animation_player(model_instance)
	if _anim_player:
		_play_anim("idle")

func _create_fallback_mesh():
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	var data = MOB_DATA[mob_type]
	box.size = data["collision_size"]
	mesh_instance.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8)
	mat.roughness = 0.8
	mesh_instance.material_override = mat
	mesh_instance.position.y = data["collision_size"].y / 2.0
	add_child(mesh_instance)

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
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["collision_size"]
	col.shape = shape
	col.position.y = data["collision_size"].y / 2.0
	add_child(col)

func _physics_process(delta):
	# Gravité
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# IA de déplacement
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving and is_on_floor():
		# Éviter l'eau et les falaises
		if world_manager:
			var ahead_pos = global_position + wander_direction * 1.0
			var ahead_block = world_manager.get_block_at_position(ahead_pos.floor())
			var below_ahead = world_manager.get_block_at_position((ahead_pos - Vector3(0, 1, 0)).floor())
			if ahead_block == BlockRegistry.BlockType.WATER or below_ahead == BlockRegistry.BlockType.AIR:
				_pick_new_wander()
				is_moving = false

		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

		# Rotation vers la direction de déplacement
		if wander_direction.length_squared() > 0.01:
			rotation.y = atan2(wander_direction.x, wander_direction.z)

		_play_anim("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		_play_anim("idle")

	move_and_slide()

func _pick_new_wander():
	wander_timer = randf_range(2.0, 5.0)
	is_moving = randf() > 0.4
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
