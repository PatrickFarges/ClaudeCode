extends CharacterBody3D
class_name NpcVillager

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

var mob_type_index: int = 0
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

var move_speed: float = 1.0
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null

func setup(model_index: int, pos: Vector3, chunk_pos: Vector3i):
	mob_type_index = model_index
	_spawn_pos = pos
	chunk_position = chunk_pos

func _ready():
	position = _spawn_pos
	_preload_models()
	_create_model()
	_create_collision()
	_pick_new_wander()
	# Rotation Y aléatoire initiale
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")

func _create_model():
	if mob_type_index < 0 or mob_type_index >= _model_scenes.size():
		return
	var model_instance = _model_scenes[mob_type_index].instantiate()
	model_instance.scale = Vector3(0.7, 0.7, 0.7)
	add_child(model_instance)

func _create_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.6, 1.7, 0.6)
	col.shape = shape
	col.position.y = 0.85
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
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)

	move_and_slide()

func _pick_new_wander():
	wander_timer = randf_range(3.0, 8.0)
	is_moving = randf() > 0.5
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
