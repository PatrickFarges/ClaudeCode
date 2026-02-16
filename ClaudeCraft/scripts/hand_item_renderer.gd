extends Node3D

## Rendu du bras et de l'item en main du joueur (vue FPS)
## Attaché comme enfant de Camera3D

const ARM_COLOR = Color(0.9, 0.75, 0.65)
const BLOCK_SIZE = 0.28
const ARM_SIZE = Vector3(0.15, 0.55, 0.15)
const BASE_POSITION = Vector3(0.55, -0.35, -0.55)
const SPRINT_OFFSET = Vector3(-0.1, 0.0, -0.05)

const TEXTURE_PATH = "res://TexturesPack/Aurore Stone/assets/minecraft/textures/block/"

# Noeuds
var hand_pivot: Node3D
var arm_mesh: MeshInstance3D
var item_holder: Node3D
var current_item_node: Node3D = null

# Animations
var bob_time: float = 0.0
var is_swinging: bool = false
var swing_tween: Tween = null

# Référence
var player: CharacterBody3D = null

# Cache textures chargées
var _texture_cache: Dictionary = {}

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_build_hierarchy()

func _build_hierarchy():
	# HandPivot — point de pivot pour bobbing/swing
	hand_pivot = Node3D.new()
	hand_pivot.name = "HandPivot"
	hand_pivot.position = BASE_POSITION
	add_child(hand_pivot)

	# Bras — BoxMesh couleur peau, décalé vers le bas pour dépasser sous l'item
	arm_mesh = MeshInstance3D.new()
	arm_mesh.name = "Arm"
	var arm_box = BoxMesh.new()
	arm_box.size = ARM_SIZE
	arm_mesh.mesh = arm_box
	var arm_mat = StandardMaterial3D.new()
	arm_mat.albedo_color = ARM_COLOR
	arm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arm_mesh.material_override = arm_mat
	arm_mesh.layers = 2  # Layer de rendu dédié
	arm_mesh.position = Vector3(0, -0.08, 0)
	hand_pivot.add_child(arm_mesh)

	# ItemHolder — point d'attache de l'item, bas du bras (position « main »)
	item_holder = Node3D.new()
	item_holder.name = "ItemHolder"
	item_holder.position = Vector3(0.0, 0.05, 0.0)
	hand_pivot.add_child(item_holder)

func _process(delta: float):
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return

	_update_bobbing(delta)

var _sprint_blend: float = 0.0

func _update_bobbing(delta: float):
	if not player or not hand_pivot:
		return

	var on_floor = player.is_on_floor()
	var moving = player.velocity.length() > 0.5 and on_floor

	# Sprint blend (transition douce)
	var sprint_target = 1.0 if player.is_sprinting else 0.0
	_sprint_blend = lerpf(_sprint_blend, sprint_target, delta * 6.0)

	if moving:
		var speed_mult = 1.3 if player.is_sprinting else 1.0
		var swing_amp = 20.0 if player.is_sprinting else 12.0  # degrés
		bob_time += delta * speed_mult
		# Léger rebond vertical au rythme des pas
		var bob_y = abs(sin(bob_time * 14.0)) * 0.015
		hand_pivot.position = BASE_POSITION + Vector3(0, bob_y, 0.0) + SPRINT_OFFSET * _sprint_blend
		# Balancement avant/arrière (rotation X comme un pendule au niveau de l'épaule)
		hand_pivot.rotation_degrees.x = sin(bob_time * 7.0) * swing_amp
		hand_pivot.rotation_degrees.z = 0.0
	else:
		bob_time = 0.0
		var target_pos = BASE_POSITION + SPRINT_OFFSET * _sprint_blend
		hand_pivot.position = hand_pivot.position.lerp(target_pos, delta * 10.0)
		hand_pivot.rotation_degrees.x = lerpf(hand_pivot.rotation_degrees.x, 0.0, delta * 10.0)
		hand_pivot.rotation_degrees.z = 0.0

func play_swing():
	if is_swinging:
		return
	is_swinging = true

	if swing_tween and swing_tween.is_valid():
		swing_tween.kill()

	swing_tween = create_tween()
	swing_tween.tween_property(hand_pivot, "rotation_degrees:x", -30.0, 0.15)
	swing_tween.tween_property(hand_pivot, "rotation_degrees:x", 0.0, 0.15)
	swing_tween.tween_callback(func(): is_swinging = false)

func update_held_item(block_type: BlockRegistry.BlockType):
	# Supprimer l'ancien item
	if current_item_node:
		current_item_node.queue_free()
		current_item_node = null

	if block_type == BlockRegistry.BlockType.AIR:
		# Main vide — bras visible
		arm_mesh.visible = true
		return

	# Bloc en main — bras masqué, cube visible
	arm_mesh.visible = false
	current_item_node = _create_block_cube(block_type)
	if current_item_node:
		item_holder.add_child(current_item_node)

func update_held_tool_model(mesh: ArrayMesh):
	# Supprimer l'ancien item
	if current_item_node:
		current_item_node.queue_free()
		current_item_node = null

	arm_mesh.visible = false

	if mesh == null:
		arm_mesh.visible = true
		return

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.layers = 2
	# Échelle adaptée (les modèles MC JSON sont en unités 0-16)
	mesh_inst.scale = Vector3(0.025, 0.025, 0.025)
	mesh_inst.position = Vector3(0, 0.05, 0)
	current_item_node = mesh_inst
	item_holder.add_child(current_item_node)

func update_held_tool_node(node: Node3D, hand_rotation := Vector3(-25, -135, 45), hand_scale := 0.35):
	# Supprimer l'ancien item
	if current_item_node:
		current_item_node.queue_free()
		current_item_node = null

	arm_mesh.visible = false

	if node == null:
		arm_mesh.visible = true
		return

	# GLB : layers 1+2 (reçoit la lumière + visible par la caméra FPS)
	_apply_glb_render_settings(node)

	# Auto-scale basé sur l'AABB du modèle
	var aabb = _compute_model_aabb(node)
	var max_dim = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim > 0.001:
		var s = hand_scale / max_dim
		node.scale = Vector3(s, s, s)
		var center = aabb.get_center() * s
		node.position = Vector3(-center.x, -center.y, -center.z)
	else:
		node.scale = Vector3(0.03, 0.03, 0.03)
		node.position = Vector3.ZERO

	# Rotation par outil — tenu en main droite, diagonal (manche bas-droite, tête haut-gauche)
	node.rotation_degrees = hand_rotation
	current_item_node = node
	item_holder.add_child(current_item_node)

func _compute_model_aabb(root: Node3D) -> AABB:
	var points: Array = []
	_collect_mesh_points(root, root, points)
	if points.is_empty():
		return AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))
	var aabb = AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		aabb = aabb.expand(points[i])
	return aabb

func _collect_mesh_points(node: Node, root: Node3D, points: Array):
	if node is MeshInstance3D and node.mesh:
		var mesh_aabb = node.mesh.get_aabb()
		var xform = _get_relative_transform(node as Node3D, root)
		for i in range(8):
			points.append(xform * mesh_aabb.get_endpoint(i))
	for child in node.get_children():
		_collect_mesh_points(child, root, points)

func _get_relative_transform(from_node: Node3D, to_node: Node3D) -> Transform3D:
	if from_node == to_node:
		return Transform3D.IDENTITY
	var xform = from_node.transform
	var current = from_node.get_parent()
	while current != to_node and current != null:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _apply_render_settings(node: Node):
	if node is MeshInstance3D:
		node.layers = 2
		# Forcer UNSHADED sur chaque surface (pour JSON Blockbench / blocs)
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				var mat = mesh_inst.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for child in node.get_children():
		_apply_render_settings(child)

func _apply_glb_render_settings(node: Node):
	if node is MeshInstance3D:
		# Layers 1+2 : visible par la caméra FPS ET éclairé par la DirectionalLight
		node.layers = 3
	for child in node.get_children():
		_apply_glb_render_settings(child)

func _create_block_cube(block_type: BlockRegistry.BlockType) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.layers = 2

	var faces_data = BlockRegistry.BLOCK_DATA[block_type].get("faces", {})

	# Si le bloc a des textures par face, construire un cube texturé
	if faces_data.size() > 0 and _has_any_texture_file(faces_data):
		mesh_inst.mesh = _build_textured_cube(block_type, faces_data)
	else:
		# Fallback : simple cube coloré
		var box = BoxMesh.new()
		box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = BlockRegistry.get_block_color(block_type)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.material_override = mat

	# Rotation légère pour voir 3 faces (effet isométrique)
	mesh_inst.rotation_degrees = Vector3(-15, 30, 0)
	return mesh_inst

func _has_any_texture_file(faces: Dictionary) -> bool:
	for key in faces:
		var tex_name = faces[key]
		var path = TEXTURE_PATH + tex_name + ".png"
		var abs_path = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			return true
	return false

func _build_textured_cube(block_type: BlockRegistry.BlockType, faces: Dictionary) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var s = BLOCK_SIZE * 0.5  # demi-taille

	# Définition des 6 faces : [normal, vertices (4 coins), face_name]
	var face_defs = [
		["top",    [Vector3(-s,s,-s), Vector3(s,s,-s), Vector3(s,s,s), Vector3(-s,s,s)],    Vector3(0,1,0)],
		["bottom", [Vector3(-s,-s,s), Vector3(s,-s,s), Vector3(s,-s,-s), Vector3(-s,-s,-s)], Vector3(0,-1,0)],
		["front",  [Vector3(-s,-s,-s), Vector3(s,-s,-s), Vector3(s,s,-s), Vector3(-s,s,-s)], Vector3(0,0,-1)],
		["back",   [Vector3(s,-s,s), Vector3(-s,-s,s), Vector3(-s,s,s), Vector3(s,s,s)],     Vector3(0,0,1)],
		["right",  [Vector3(s,-s,-s), Vector3(s,-s,s), Vector3(s,s,s), Vector3(s,s,-s)],     Vector3(1,0,0)],
		["left",   [Vector3(-s,-s,s), Vector3(-s,-s,-s), Vector3(-s,s,-s), Vector3(-s,s,s)], Vector3(-1,0,0)],
	]

	var uvs = [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]

	for face_def in face_defs:
		var face_name: String = face_def[0]
		var verts: Array = face_def[1]
		var normal: Vector3 = face_def[2]

		var tex_name = BlockRegistry.get_face_texture(block_type, face_name)
		var tint = BlockRegistry.get_block_tint(block_type, face_name)
		var mat = _get_face_material(tex_name, tint, block_type)

		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)

		# Triangle 1 : 0-1-2
		for idx in [0, 1, 2]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
		# Triangle 2 : 0-2-3
		for idx in [0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])

		st.commit(mesh)

	return mesh

func _get_face_material(tex_name: String, tint: Color, _block_type: BlockRegistry.BlockType) -> StandardMaterial3D:
	var cache_key = tex_name + str(tint)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var path = TEXTURE_PATH + tex_name + ".png"
	var abs_path = ProjectSettings.globalize_path(path)

	if FileAccess.file_exists(abs_path):
		var img = Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			# Appliquer le tint
			if tint != Color(1,1,1,1):
				for y in range(img.get_height()):
					for x in range(img.get_width()):
						var c = img.get_pixel(x, y)
						img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
			var tex = ImageTexture.create_from_image(img)
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			_texture_cache[cache_key] = mat
			return mat

	# Fallback couleur
	mat.albedo_color = tint
	_texture_cache[cache_key] = mat
	return mat
