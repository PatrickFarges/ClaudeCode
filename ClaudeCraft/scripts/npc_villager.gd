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
	# Récupérer l'AnimationPlayer embarqué dans le modèle GLB
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

func _physics_process(delta):
	# Gravité
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# IA de déplacement
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving:
		# Auto-jump et évitement (seulement au sol)
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
			# Éviter les falaises (2+ blocs de vide devant)
			elif block_at_feet == BlockRegistry.BlockType.AIR and block_below_ahead == BlockRegistry.BlockType.AIR:
				_pick_new_wander()
				is_moving = false
			# Auto-jump : bloc solide devant aux pieds + espace libre au-dessus
			elif block_at_feet != BlockRegistry.BlockType.AIR and block_above == BlockRegistry.BlockType.AIR:
				velocity.y = _jump_velocity

		# Mouvement horizontal (au sol ET en l'air pour franchir les blocs)
		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

		# Rotation vers la direction de déplacement
		if wander_direction.length_squared() > 0.01:
			rotation.y = atan2(wander_direction.x, wander_direction.z)

		# Détection de blocage : si le PNJ n'avance pas, changer de direction
		_stuck_timer += delta
		if _stuck_timer >= 1.0:
			var moved_dist = global_position.distance_to(_last_pos)
			if moved_dist < 0.3:
				_pick_new_wander()
			_last_pos = global_position
			_stuck_timer = 0.0

		_play_anim("walk")
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		_stuck_timer = 0.0
		_play_anim("idle")

	move_and_slide()

func _pick_new_wander():
	wander_timer = randf_range(3.0, 8.0)
	is_moving = randf() > 0.5
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
