extends CharacterBody3D
class_name PassiveMob

enum MobType { SHEEP, COW, CHICKEN }

const MOB_DATA = {
	MobType.SHEEP: {
		"size": Vector3(0.8, 0.7, 0.5),
		"color": Color(0.95, 0.95, 0.95, 1.0),
	},
	MobType.COW: {
		"size": Vector3(0.9, 0.8, 0.5),
		"color": Color(0.55, 0.35, 0.2, 1.0),
	},
	MobType.CHICKEN: {
		"size": Vector3(0.4, 0.4, 0.3),
		"color": Color(0.95, 0.9, 0.5, 1.0),
	},
}

var mob_type: MobType = MobType.SHEEP
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

var move_speed: float = 1.5
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null  # WorldManager (non typé pour éviter dépendance circulaire)

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos

func _ready():
	position = _spawn_pos
	_create_mesh()
	_create_collision()
	_pick_new_wander()
	world_manager = get_tree().get_first_node_in_group("world_manager")

func _create_mesh():
	var data = MOB_DATA[mob_type]
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = data["size"]
	mesh_instance.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = data["color"]
	mat.roughness = 0.8
	mesh_instance.material_override = mat
	mesh_instance.position.y = data["size"].y / 2.0
	add_child(mesh_instance)

func _create_collision():
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["size"]
	col.shape = shape
	col.position.y = data["size"].y / 2.0
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
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)

	move_and_slide()

func _pick_new_wander():
	wander_timer = randf_range(2.0, 5.0)
	is_moving = randf() > 0.4
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
