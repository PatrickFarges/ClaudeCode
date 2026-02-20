extends Node3D

## Rendu du bras et de l'item en main du joueur (vue FPS)
## Blocs : cube texture par face depuis le pack actif
## Outils : flat sprite Minecraft-style depuis les textures d'items du pack

const ARM_COLOR = Color(0.9, 0.75, 0.65)
const BLOCK_SIZE = 0.28
const ARM_SIZE = Vector3(0.15, 0.55, 0.15)
const BASE_POSITION = Vector3(0.55, -0.35, -0.55)
const SPRINT_OFFSET = Vector3(-0.1, 0.0, -0.05)
const SPRITE_SIZE = 0.32

# Noeuds
var hand_pivot: Node3D
var arm_mesh: MeshInstance3D
var item_holder: Node3D
var current_item_node: Node3D = null

# Animations
var bob_time: float = 0.0
var is_swinging: bool = false
var swing_tween: Tween = null

# Reference
var player: CharacterBody3D = null

# Cache textures chargees
var _texture_cache: Dictionary = {}
var _sprite_cache: Dictionary = {}

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_build_hierarchy()

func _build_hierarchy():
	hand_pivot = Node3D.new()
	hand_pivot.name = "HandPivot"
	hand_pivot.position = BASE_POSITION
	add_child(hand_pivot)

	arm_mesh = MeshInstance3D.new()
	arm_mesh.name = "Arm"
	var arm_box = BoxMesh.new()
	arm_box.size = ARM_SIZE
	arm_mesh.mesh = arm_box
	var arm_mat = StandardMaterial3D.new()
	arm_mat.albedo_color = ARM_COLOR
	arm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arm_mesh.material_override = arm_mat
	arm_mesh.layers = 2
	arm_mesh.position = Vector3(0, -0.08, 0)
	hand_pivot.add_child(arm_mesh)

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

	var sprint_target = 1.0 if player.is_sprinting else 0.0
	_sprint_blend = lerpf(_sprint_blend, sprint_target, delta * 6.0)

	if moving:
		var speed_mult = 1.3 if player.is_sprinting else 1.0
		var swing_amp = 20.0 if player.is_sprinting else 12.0
		bob_time += delta * speed_mult
		var bob_y = abs(sin(bob_time * 14.0)) * 0.015
		hand_pivot.position = BASE_POSITION + Vector3(0, bob_y, 0.0) + SPRINT_OFFSET * _sprint_blend
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

# ============================================================
# AFFICHAGE BLOC EN MAIN
# ============================================================

func update_held_item(block_type: BlockRegistry.BlockType):
	_clear_held_item()

	if block_type == BlockRegistry.BlockType.AIR:
		arm_mesh.visible = true
		return

	arm_mesh.visible = false
	current_item_node = _create_block_cube(block_type)
	if current_item_node:
		item_holder.add_child(current_item_node)

# ============================================================
# AFFICHAGE OUTIL EN MAIN — FLAT SPRITE MINECRAFT-STYLE
# ============================================================

func update_held_item_sprite(tool_type: ToolRegistry.ToolType):
	_clear_held_item()
	arm_mesh.visible = false

	var tex_path = ToolRegistry.get_item_texture_path(tool_type)
	if tex_path.is_empty():
		arm_mesh.visible = true
		return

	var sprite_node = _create_item_sprite(tex_path)
	if sprite_node:
		current_item_node = sprite_node
		item_holder.add_child(current_item_node)
	else:
		arm_mesh.visible = true

# ============================================================
# AFFICHAGE NODE 3D ARBITRAIRE (pour food GLB etc.)
# ============================================================

func update_held_tool_node(node: Node3D, hand_rotation := Vector3(-25, -135, 45), hand_scale := 0.35):
	_clear_held_item()
	arm_mesh.visible = false

	if node == null:
		arm_mesh.visible = true
		return

	_apply_glb_render_settings(node)

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

	node.rotation_degrees = hand_rotation
	current_item_node = node
	item_holder.add_child(current_item_node)

func _clear_held_item():
	if current_item_node:
		current_item_node.queue_free()
		current_item_node = null

# ============================================================
# CREATION DU SPRITE PLAT (flat textured quad Minecraft-style)
# ============================================================

func _create_item_sprite(tex_path: String) -> MeshInstance3D:
	var abs_path = ProjectSettings.globalize_path(tex_path)

	if not FileAccess.file_exists(abs_path):
		push_warning("[HandItemRenderer] Texture introuvable: " + tex_path)
		return null

	var img = Image.new()
	if img.load(abs_path) != OK:
		return null

	img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img)

	# Construire un quad plat texture
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)

	var s = SPRITE_SIZE * 0.5
	var normal = Vector3(0, 0, 1)

	# Face avant
	var verts = [
		Vector3(-s, -s, 0), Vector3(s, -s, 0),
		Vector3(s, s, 0), Vector3(-s, s, 0)
	]
	var uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]

	for idx in [0, 1, 2]:
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])
	for idx in [0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])

	var mesh = ArrayMesh.new()
	st.commit(mesh)

	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	inst.layers = 2

	# Rotation Minecraft first-person : outil tenu en diagonale
	# Manche vers le bas-droite, tete vers le haut-gauche
	inst.rotation_degrees = Vector3(-10, -45, -20)
	inst.position = Vector3(0.0, 0.02, 0.0)

	return inst

# ============================================================
# CREATION DU CUBE BLOC TEXTURE
# ============================================================

func _create_block_cube(block_type: BlockRegistry.BlockType) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.layers = 2

	var faces_data = BlockRegistry.BLOCK_DATA[block_type].get("faces", {})

	if faces_data.size() > 0 and _has_any_texture_file(faces_data):
		mesh_inst.mesh = _build_textured_cube(block_type, faces_data)
	else:
		var box = BoxMesh.new()
		box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = BlockRegistry.get_block_color(block_type)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.material_override = mat

	mesh_inst.rotation_degrees = Vector3(-15, 30, 0)
	return mesh_inst

func _has_any_texture_file(faces: Dictionary) -> bool:
	var tex_path = GameConfig.get_block_texture_path()
	for key in faces:
		var tex_name = faces[key]
		var path = tex_path + tex_name + ".png"
		var abs_path = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			return true
	return false

func _build_textured_cube(block_type: BlockRegistry.BlockType, faces: Dictionary) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var s = BLOCK_SIZE * 0.5

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
		var mat = _get_face_material(tex_name, tint)

		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)

		for idx in [0, 1, 2]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
		for idx in [0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])

		st.commit(mesh)

	return mesh

func _get_face_material(tex_name: String, tint: Color) -> StandardMaterial3D:
	var cache_key = tex_name + str(tint)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var path = GameConfig.get_block_texture_path() + tex_name + ".png"
	var abs_path = ProjectSettings.globalize_path(path)

	if FileAccess.file_exists(abs_path):
		var img = Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
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

	mat.albedo_color = tint
	_texture_cache[cache_key] = mat
	return mat

# ============================================================
# HELPERS GLB (pour les rares modeles 3D restants — food etc.)
# ============================================================

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

func _apply_glb_render_settings(node: Node):
	if node is MeshInstance3D:
		node.layers = 3
	for child in node.get_children():
		_apply_glb_render_settings(child)
