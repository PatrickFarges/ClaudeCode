extends CharacterBody3D
class_name PassiveMob

# === PASSIVE MOB — version simplifiée ===
# Utilise des GLB animés natifs Godot (ou des box colorées en placeholder)
# Plus de Bedrock .geo.json, plus d'animation procédurale

enum MobType { SHEEP, COW, CHICKEN, PIG, WOLF, HORSE }

# Données par type de mob — Quaternius low-poly GLB (CC0)
# Animations FBX→GLB : préfixées "Armature|" ou "WolfArmature|"
const MOB_DATA = {
	MobType.SHEEP: {
		"collision_size": Vector3(0.9, 1.3, 0.9),
		"color": Color(0.92, 0.92, 0.88),
		"health": 8, "meat_name": "Mouton", "meat_count": 2,
		"glb_path": "res://assets/Animals/GLB/Sheep.glb",
		"model_scale": Vector3(0.30, 0.30, 0.30),  # natif H=4.36 → cible ~1.3
		"anim_idle": "Armature|Idle", "anim_walk": "Armature|Jump",
	},
	MobType.COW: {
		"collision_size": Vector3(0.9, 1.4, 0.9),
		"color": Color(0.55, 0.35, 0.2),
		"health": 10, "meat_name": "Boeuf", "meat_count": 3,
		"glb_path": "res://assets/Animals/GLB/Cow.glb",
		"model_scale": Vector3(0.15, 0.15, 0.15),  # natif H=9.17 → cible ~1.4
		"anim_idle": "Armature|Idle", "anim_walk": "Armature|Walk",
	},
	MobType.CHICKEN: {
		"collision_size": Vector3(0.5, 0.7, 0.5),
		"color": Color(0.95, 0.95, 0.85),
		"health": 4, "meat_name": "Poulet", "meat_count": 1,
		"glb_path": "res://assets/Animals/GLB/Chicken.glb",
		"model_scale": Vector3(0.26, 0.26, 0.26),  # natif H=2.67 → cible ~0.7
		"model_tint": Color(0.95, 0.90, 0.75),  # blanc-crème poulet (modèle sans couleur)
		"anim_idle": "", "anim_walk": "Armature|ArmatureAction.002",
	},
	MobType.PIG: {
		"collision_size": Vector3(0.9, 0.9, 0.9),
		"color": Color(0.9, 0.7, 0.65),
		"health": 10, "meat_name": "Porc", "meat_count": 3,
		"glb_path": "res://assets/Animals/GLB/Pig.glb",
		"model_scale": Vector3(0.09, 0.09, 0.09),  # natif H=9.78 → cible ~0.9
		"anim_idle": "Armature|Idle", "anim_walk": "Armature|Jump",
	},
	MobType.WOLF: {
		"collision_size": Vector3(0.6, 0.85, 0.6),
		"color": Color(0.7, 0.7, 0.7),
		"health": 8, "meat_name": "Loup", "meat_count": 0,
		"glb_path": "res://assets/Animals/GLB/Wolf.glb",
		"model_scale": Vector3(0.16, 0.16, 0.16),  # natif H=5.30 → cible ~0.85
		"model_tint": Color(0.55, 0.5, 0.45),  # gris-brun loup (modèle sans couleur)
		"anim_idle": "WolfArmature|Idle", "anim_walk": "WolfArmature|Walking",
	},
	MobType.HORSE: {
		"collision_size": Vector3(1.4, 1.6, 1.4),
		"color": Color(0.6, 0.4, 0.25),
		"health": 15, "meat_name": "Cheval", "meat_count": 0,
		"glb_path": "res://assets/Animals/GLB/Horse.glb",
		"model_scale": Vector3(0.24, 0.24, 0.24),  # natif H=9.24 → cible ~2.2 (cheval grand)
		"anim_idle": "Armature|Idle", "anim_walk": "Armature|Walk",
	},
}

# GLB scene cache (chargé une seule fois par type)
static var _glb_cache: Dictionary = {}

var mob_type: MobType = MobType.SHEEP
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

# Throttle: les mobs ne vérifient pas les obstacles chaque frame
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.2  # vérif toutes les 0.2s au lieu de chaque frame

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos
	health = MOB_DATA[type]["health"]

func _ready():
	position = _spawn_pos
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	add_to_group("passive_mobs")

# ============================================================
#  MODEL CREATION — GLB natif ou box colorée
# ============================================================

func _create_model():
	var data: Dictionary = MOB_DATA[mob_type]
	var glb_path: String = data.get("glb_path", "")

	# Essayer de charger le GLB s'il existe
	if glb_path != "" and ResourceLoader.exists(glb_path):
		var scene = _load_glb(glb_path)
		if scene:
			var instance = scene.instantiate()
			# Appliquer l'échelle du modèle + rotation 180° (modèles Quaternius orientés à l'envers)
			var sc: Vector3 = data.get("model_scale", Vector3.ONE)
			instance.scale = sc
			instance.rotation.y = PI
			add_child(instance)
			_model_root = instance
			_is_glb_model = true
			# Appliquer un tint si le modèle n'a pas de couleurs propres
			var tint: Color = data.get("model_tint", Color(-1, -1, -1))
			if tint.r >= 0:
				_apply_model_tint(instance, tint)
			_anim_player = _find_animation_player(instance)
			if _anim_player:
				_play_anim("idle")
			return

	# Fallback: box colorée simple
	_create_colored_box()

static func _load_glb(path: String) -> PackedScene:
	if _glb_cache.has(path):
		return _glb_cache[path]
	var scene = load(path) as PackedScene
	if scene:
		_glb_cache[path] = scene
	return scene

func _apply_model_tint(node: Node, tint: Color):
	# Colore les modèles GLB qui n'ont pas de couleurs propres (Wolf, Chicken)
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var base_mat = mi.mesh.surface_get_material(i)
			if base_mat and base_mat is StandardMaterial3D:
				var mat = base_mat.duplicate()
				mat.albedo_color = tint
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_model_tint(child, tint)

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
	# Résoudre le nom logique ("idle"/"walk") vers le nom réel dans le GLB
	var data: Dictionary = MOB_DATA[mob_type]
	var real_name: String = ""
	if logical_name == "idle":
		real_name = data.get("anim_idle", "")
	elif logical_name == "walk":
		real_name = data.get("anim_walk", "")
	if real_name == "":
		# Pas d'animation pour cet état — essayer le nom brut en fallback
		real_name = logical_name
	if _anim_player.has_animation(real_name):
		var anim = _anim_player.get_animation(real_name)
		anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play(real_name)
		_current_anim = logical_name

func _create_colored_box():
	var data = MOB_DATA[mob_type]
	var size: Vector3 = data["collision_size"]

	# Corps principal (box arrondie visuellement grâce à la couleur)
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size * 0.9  # légèrement plus petit que la collision
	mesh_instance.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = data["color"]
	mat.roughness = 0.8
	mesh_instance.material_override = mat
	mesh_instance.position.y = size.y / 2.0
	_model_root = mesh_instance
	add_child(mesh_instance)

	# Petite tête (pour distinguer l'avant)
	var head = MeshInstance3D.new()
	var head_box = BoxMesh.new()
	var head_size = size.x * 0.4
	head_box.size = Vector3(head_size, head_size, head_size)
	head.mesh = head_box
	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = data["color"].lightened(0.15)
	head_mat.roughness = 0.8
	head.material_override = head_mat
	head.position = Vector3(0, size.y * 0.7, -size.z * 0.4)
	_model_root.add_child(head)

func _create_collision():
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["collision_size"]
	col.shape = shape
	col.position.y = data["collision_size"].y / 2.0
	add_child(col)

# ============================================================
#  PHYSICS + AI — simplifié, throttled
# ============================================================

func _physics_process(delta):
	# Flash de dégâts
	if _hurt_flash_timer > 0:
		_hurt_flash_timer -= delta
		if _hurt_flash_timer <= 0:
			_reset_model_color()

	# Gravité
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# Wander timer
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving and is_on_floor():
		# Navigation throttlée : vérif obstacles toutes les 0.2s
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

	move_and_slide()

# ============================================================
#  DÉGÂTS ET MORT
# ============================================================

func take_hit(damage: int, knockback: Vector3 = Vector3.ZERO):
	health -= damage
	velocity += knockback
	_hurt_flash_timer = 0.3
	_flash_model_red()
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
		if _is_glb_model:
			_apply_glb_tint(_model_root, Color(3.0, 0.3, 0.3))
		else:
			_apply_tint_recursive(_model_root, Color(2.0, 0.5, 0.5))

func _reset_model_color():
	if _model_root:
		if _is_glb_model:
			_apply_glb_tint(_model_root, Color(1, 1, 1))
		else:
			var data = MOB_DATA[mob_type]
			_apply_tint_recursive(_model_root, data["color"])

func _apply_tint_recursive(node: Node, color: Color):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.material_override and mi.material_override is StandardMaterial3D:
			mi.material_override.albedo_color = color
	for child in node.get_children():
		_apply_tint_recursive(child, color)

func _apply_glb_tint(node: Node, color: Color):
	# Pour les GLB : on modifie l'émission pour le flash (pas les albedo du modèle)
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
