extends CharacterBody3D
class_name PassiveMob

enum MobType { SHEEP, COW, CHICKEN, PIG, WOLF, HORSE }

const MOB_DATA = {
	MobType.SHEEP: {
		"collision_size": Vector3(0.9, 1.3, 0.9),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_sheep.glb",
		"model_scale": Vector3(0.065, 0.065, 0.065),
		"model_y_offset": 0.98,  # raw min_y=-15 * 0.065
		"health": 8,
		"meat_name": "Mouton",
		"meat_count": 2,
	},
	MobType.COW: {
		"collision_size": Vector3(0.9, 1.4, 0.9),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_cow.glb",
		"model_scale": Vector3(0.065, 0.065, 0.065),
		"model_y_offset": 0.98,  # raw min_y=-15 * 0.065
		"health": 10,
		"meat_name": "Boeuf",
		"meat_count": 3,
	},
	MobType.CHICKEN: {
		"collision_size": Vector3(0.5, 0.7, 0.5),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_chicken.glb",
		"model_scale": Vector3(0.045, 0.045, 0.045),
		"model_y_offset": 0.36,  # raw min_y=-8 * 0.045
		"health": 4,
		"meat_name": "Poulet",
		"meat_count": 1,
	},
	MobType.PIG: {
		"collision_size": Vector3(0.9, 0.9, 0.9),
		"model_path": "res://assets/Mobs/Passive/minecraft_pig.glb",
		"model_scale": Vector3(0.9, 0.9, 0.9),  # Pig model is ~1 unit, not ~20
		"model_y_offset": 0.34,  # raw min_y=-0.375 * 0.9
		"health": 10,
		"meat_name": "Porc",
		"meat_count": 3,
	},
	MobType.WOLF: {
		"collision_size": Vector3(0.6, 0.85, 0.6),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_wolf.glb",
		"model_scale": Vector3(0.04, 0.04, 0.04),
		"model_y_offset": 0.66,  # raw min_y=-16.5 * 0.04
		"health": 8,
		"meat_name": "Loup",
		"meat_count": 0,
	},
	MobType.HORSE: {
		"collision_size": Vector3(1.4, 1.6, 1.4),
		"model_path": "res://assets/Mobs/Passive/minecraft_-_horse.glb",
		"model_scale": Vector3(0.055, 0.055, 0.055),
		"model_y_offset": 0.88,  # raw min_y=-16 * 0.055
		"health": 15,
		"meat_name": "Cheval",
		"meat_count": 0,
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

var health: int = 10
var move_speed: float = 1.5
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null
var _model_node: Node3D = null
var _hurt_flash_timer: float = 0.0
var _walk_time: float = 0.0  # Pour l'animation procédurale
var _leg_nodes: Array = []    # Pattes séparées (pig uniquement)

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos
	health = MOB_DATA[type]["health"]

func _ready():
	position = _spawn_pos
	_preload_models()
	_create_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	add_to_group("passive_mobs")

func _create_model():
	if not _model_scenes.has(mob_type):
		_create_fallback_mesh()
		return
	var model_instance = _model_scenes[mob_type].instantiate()
	var data = MOB_DATA[mob_type]
	model_instance.scale = data["model_scale"]
	# Remonter le modèle pour que les pieds touchent le sol
	model_instance.position.y = data["model_y_offset"]
	_model_node = model_instance
	add_child(model_instance)
	# Chercher les pattes séparées (pig: Object_14, 17, 20, 23)
	if mob_type == MobType.PIG:
		_find_leg_nodes(model_instance)

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
	_model_node = mesh_instance
	add_child(mesh_instance)

func _create_collision():
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["collision_size"]
	col.shape = shape
	col.position.y = data["collision_size"].y / 2.0
	add_child(col)

func _physics_process(delta):
	# Flash de dégâts
	if _hurt_flash_timer > 0:
		_hurt_flash_timer -= delta
		if _hurt_flash_timer <= 0:
			_reset_model_color()

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

		# Animation procédurale de marche
		_walk_time += delta
		_animate_walk(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		# Retour à la position neutre
		_animate_idle(delta)

	move_and_slide()

# ============================================================
# ANIMATION PROCEDURALE (pas de skeleton dans ces GLB)
# Les modèles Sketchfab sont des mesh statiques sans squelette.
# Seul le cochon (pig) a des pattes séparées (4 mesh individuels).
# Pour les autres : bobbing doux + léger balancement.
# ============================================================

func _find_leg_nodes(root: Node):
	var leg_names = ["Object_14", "Object_17", "Object_20", "Object_23"]
	_leg_nodes.clear()
	for lname in leg_names:
		var node = _find_node_by_name(root, lname)
		if node:
			_leg_nodes.append(node)

func _find_node_by_name(root: Node, target_name: String) -> Node3D:
	if root.name == target_name and root is Node3D:
		return root as Node3D
	for child in root.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

func _animate_walk(delta: float):
	if not _model_node:
		return
	var data = MOB_DATA[mob_type]
	var base_y = data["model_y_offset"]
	# Bobbing vertical doux
	var bob = abs(sin(_walk_time * 8.0)) * 0.06
	_model_node.position.y = base_y + bob
	# Léger balancement latéral
	var lean = sin(_walk_time * 8.0) * 3.0
	_model_node.rotation_degrees.z = lean
	# Légère inclinaison vers l'avant
	_model_node.rotation_degrees.x = lerpf(_model_node.rotation_degrees.x, -5.0, delta * 4.0)
	# Pattes du cochon (seul modèle avec mesh séparés)
	if _leg_nodes.size() == 4:
		var swing = sin(_walk_time * 8.0) * 25.0
		_leg_nodes[0].rotation_degrees.x = swing
		_leg_nodes[3].rotation_degrees.x = swing
		_leg_nodes[1].rotation_degrees.x = -swing
		_leg_nodes[2].rotation_degrees.x = -swing

func _animate_idle(delta: float):
	if not _model_node:
		return
	var data = MOB_DATA[mob_type]
	var base_y = data["model_y_offset"]
	# Respiration subtile
	var breath = sin(Time.get_ticks_msec() * 0.002) * 0.01
	_model_node.position.y = lerpf(_model_node.position.y, base_y + breath, delta * 4.0)
	# Retour à plat
	_model_node.rotation_degrees.x = lerpf(_model_node.rotation_degrees.x, 0.0, delta * 4.0)
	_model_node.rotation_degrees.z = lerpf(_model_node.rotation_degrees.z, 0.0, delta * 4.0)
	# Pattes au repos
	for leg in _leg_nodes:
		leg.rotation_degrees.x = lerpf(leg.rotation_degrees.x, 0.0, delta * 4.0)
	_walk_time = 0.0

# ============================================================
# DÉGÂTS ET MORT
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
	# Donner la viande directement au joueur (pas de système de drop au sol encore)
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("heal"):
		# Soigner le joueur (viande crue = 2 PV par morceau)
		var heal_amount = meat_count * 2
		player_node.heal(heal_amount)
		# Afficher un label flottant de loot
		_spawn_loot_label(data["meat_name"], meat_count)

func _spawn_loot_label(item_name: String, count: int):
	var label = Label3D.new()
	label.text = "+%d %s" % [count, item_name]
	label.font_size = 36
	label.outline_size = 6
	label.modulate = Color(0.3, 1.0, 0.3)  # Vert
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
	if _model_node:
		_apply_tint_recursive(_model_node, Color(2.0, 0.5, 0.5))

func _reset_model_color():
	if _model_node:
		_apply_tint_recursive(_model_node, Color(1, 1, 1))

func _apply_tint_recursive(node: Node, color: Color):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		# Créer un override qui teinte sans écraser la texture
		if mi.get_surface_override_material_count() > 0:
			for i in range(mi.get_surface_override_material_count()):
				var mat = mi.get_surface_override_material(i)
				if mat is StandardMaterial3D:
					mat.albedo_color = color
		elif mi.material_override and mi.material_override is StandardMaterial3D:
			mi.material_override.albedo_color = color
	for child in node.get_children():
		_apply_tint_recursive(child, color)

func _pick_new_wander():
	wander_timer = randf_range(2.0, 5.0)
	is_moving = randf() > 0.4
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
